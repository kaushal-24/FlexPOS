-- Branch sales targets plus current-versus-prior equivalent-period reporting.
-- Target ranges use explicit local business dates while sales calculations use
-- the same UTC boundaries already used by the business dashboard.

insert into public.permissions (code, category, description) values
  ('sales_targets.manage', 'Reports', 'Create and update branch sales targets')
on conflict (code) do update set
  category = excluded.category,
  description = excluded.description;

insert into public.role_permissions (role_id, permission_code)
select role.id, 'sales_targets.manage'
from public.roles role
where role.name in ('Owner', 'Administrator', 'Branch Manager')
on conflict do nothing;

create or replace function private.seed_sales_target_role_permission()
returns trigger
language plpgsql
security definer
set search_path = ''
as $seed_sales_target_permission$
begin
  if new.name in ('Owner', 'Administrator', 'Branch Manager') then
    insert into public.role_permissions (role_id, permission_code)
    values (new.id, 'sales_targets.manage')
    on conflict do nothing;
  end if;
  return new;
end;
$seed_sales_target_permission$;

create trigger roles_seed_sales_target_permission
after insert on public.roles
for each row execute function private.seed_sales_target_role_permission();

create table public.sales_targets (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  starts_on date not null,
  ends_on date not null,
  target_amount numeric(18,2) not null check (target_amount > 0),
  notes text check (notes is null or length(btrim(notes)) between 1 and 500),
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, branch_id, starts_on, ends_on),
  constraint sales_targets_branch_fkey foreign key (branch_id, business_id)
    references public.branches(id, business_id) on delete restrict,
  check (ends_on >= starts_on),
  check (ends_on - starts_on <= 365)
);

create index sales_targets_branch_business_fk_idx
  on public.sales_targets (branch_id, business_id);
create index sales_targets_business_period_idx
  on public.sales_targets (business_id, starts_on, ends_on, branch_id)
  include (target_amount);

create trigger sales_targets_set_updated_at
before update on public.sales_targets
for each row execute function private.set_updated_at();

alter table public.sales_targets enable row level security;

create policy sales_targets_select on public.sales_targets
for select to authenticated
using (
  (select private.has_permission(business_id, 'reports.view'))
  and (select private.has_branch_access(branch_id))
);

revoke all on public.sales_targets from anon, authenticated;
grant select on public.sales_targets to authenticated;

create or replace function public.upsert_sales_target(
  target_business_id uuid,
  target_branch_id uuid,
  target_starts_on date,
  target_ends_on date,
  target_amount numeric,
  target_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $upsert_sales_target$
declare
  caller_id uuid := auth.uid();
  target_record public.sales_targets;
begin
  if caller_id is null then
    raise exception 'Authentication required';
  end if;
  if not private.has_permission(target_business_id, 'sales_targets.manage') then
    raise exception 'Sales target management permission required';
  end if;
  if not private.has_branch_access(target_branch_id) then
    raise exception 'Branch access required';
  end if;
  if target_starts_on is null or target_ends_on is null
     or target_ends_on < target_starts_on
     or target_ends_on - target_starts_on > 365 then
    raise exception 'Invalid sales target period';
  end if;
  if target_amount is null or round(target_amount, 2) <= 0 then
    raise exception 'Sales target amount must be greater than zero';
  end if;
  if target_notes is not null and length(btrim(target_notes)) > 500 then
    raise exception 'Sales target notes cannot exceed 500 characters';
  end if;
  if not exists (
    select 1
    from public.branches branch
    where branch.id = target_branch_id
      and branch.business_id = target_business_id
      and branch.is_active
      and branch.archived_at is null
  ) then
    raise exception 'Active branch not found';
  end if;

  insert into public.sales_targets (
    business_id,
    branch_id,
    starts_on,
    ends_on,
    target_amount,
    notes,
    created_by,
    updated_by
  ) values (
    target_business_id,
    target_branch_id,
    target_starts_on,
    target_ends_on,
    round(target_amount, 2),
    nullif(btrim(target_notes), ''),
    caller_id,
    caller_id
  )
  on conflict (business_id, branch_id, starts_on, ends_on)
  do update set
    target_amount = excluded.target_amount,
    notes = excluded.notes,
    updated_by = excluded.updated_by
  returning * into target_record;

  perform private.write_tenant_audit(
    target_business_id,
    'sales_target.upserted',
    'sales_target',
    target_record.id::text,
    jsonb_build_object(
      'branch_id', target_branch_id,
      'starts_on', target_starts_on,
      'ends_on', target_ends_on,
      'target_amount', target_record.target_amount
    )
  );

  return jsonb_build_object(
    'id', target_record.id,
    'business_id', target_record.business_id,
    'branch_id', target_record.branch_id,
    'starts_on', target_record.starts_on,
    'ends_on', target_record.ends_on,
    'target_amount', target_record.target_amount,
    'notes', target_record.notes,
    'updated_at', target_record.updated_at
  );
end;
$upsert_sales_target$;

create or replace function public.get_sales_target_comparison_report(
  target_business_id uuid,
  period_start timestamptz,
  period_end timestamptz,
  target_starts_on date,
  target_ends_on date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $sales_target_comparison$
declare
  result jsonb;
  comparison_start timestamptz;
  period_duration interval;
  period_days integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not private.has_permission(target_business_id, 'reports.view') then
    raise exception 'Report viewing permission required';
  end if;
  if not private.has_permission(target_business_id, 'sales.view') then
    raise exception 'Sales viewing permission required';
  end if;
  if period_start is null or period_end is null or period_end <= period_start then
    raise exception 'Invalid report period';
  end if;
  if period_end - period_start > interval '366 days' then
    raise exception 'Sales comparison period cannot exceed 366 days';
  end if;
  if target_starts_on is null or target_ends_on is null
     or target_ends_on < target_starts_on
     or target_ends_on - target_starts_on > 365 then
    raise exception 'Invalid target date range';
  end if;

  period_duration := period_end - period_start;
  comparison_start := period_start - period_duration;
  period_days := target_ends_on - target_starts_on + 1;

  result := (
  with accessible_branches as materialized (
    select branch.id, branch.name
    from public.branches branch
    where branch.business_id = target_business_id
      and branch.is_active
      and branch.archived_at is null
      and private.has_branch_access(branch.id)
  ),
  sales_activity as materialized (
    select
      sale.branch_id,
      case when sale.completed_at >= period_start then 'current' else 'previous' end
        as period_key,
      sale.grand_total as amount,
      1::bigint as orders
    from public.sales sale
    join accessible_branches branch on branch.id = sale.branch_id
    where sale.business_id = target_business_id
      and sale.status in ('completed', 'partially_refunded', 'refunded')
      and sale.completed_at >= comparison_start
      and sale.completed_at < period_end
    union all
    select
      return_entry.branch_id,
      case when return_entry.returned_at >= period_start then 'current' else 'previous' end,
      -return_entry.refund_total,
      0::bigint
    from public.sale_returns return_entry
    join accessible_branches branch on branch.id = return_entry.branch_id
    where return_entry.business_id = target_business_id
      and return_entry.status = 'completed'
      and return_entry.returned_at >= comparison_start
      and return_entry.returned_at < period_end
  ),
  branch_actuals as materialized (
    select
      activity.branch_id,
      coalesce(sum(activity.amount) filter (
        where activity.period_key = 'current'
      ), 0) as current_sales,
      coalesce(sum(activity.amount) filter (
        where activity.period_key = 'previous'
      ), 0) as previous_sales,
      coalesce(sum(activity.orders) filter (
        where activity.period_key = 'current'
      ), 0) as current_orders,
      coalesce(sum(activity.orders) filter (
        where activity.period_key = 'previous'
      ), 0) as previous_orders
    from sales_activity activity
    group by activity.branch_id
  ),
  exact_targets as materialized (
    select target.branch_id, target.id, target.target_amount, target.notes
    from public.sales_targets target
    join accessible_branches branch on branch.id = target.branch_id
    where target.business_id = target_business_id
      and target.starts_on = target_starts_on
      and target.ends_on = target_ends_on
  ),
  branch_metrics as materialized (
    select
      branch.id,
      branch.name,
      target.id as target_id,
      target.target_amount,
      target.notes as target_notes,
      coalesce(actual.current_sales, 0) as current_sales,
      coalesce(actual.previous_sales, 0) as previous_sales,
      coalesce(actual.current_orders, 0) as current_orders,
      coalesce(actual.previous_orders, 0) as previous_orders
    from accessible_branches branch
    left join branch_actuals actual on actual.branch_id = branch.id
    left join exact_targets target on target.branch_id = branch.id
  ),
  totals as materialized (
    select
      sum(current_sales) as current_sales,
      sum(previous_sales) as previous_sales,
      sum(current_orders) as current_orders,
      sum(previous_orders) as previous_orders,
      sum(target_amount) as target_amount,
      count(target_id) as targeted_branch_count,
      count(*) as accessible_branch_count
    from branch_metrics
  )
  select jsonb_build_object(
    'period_start', target_starts_on,
    'period_end', target_ends_on,
    'period_days', period_days,
    'comparison_start', target_starts_on - period_days,
    'comparison_end', target_starts_on - 1,
    'current_sales', coalesce(total.current_sales, 0),
    'previous_sales', coalesce(total.previous_sales, 0),
    'sales_change', coalesce(total.current_sales, 0)
      - coalesce(total.previous_sales, 0),
    'sales_change_rate', case when total.previous_sales <> 0
      then round(
        (total.current_sales - total.previous_sales)
        / abs(total.previous_sales) * 100,
        2
      )
      else null
    end,
    'current_orders', coalesce(total.current_orders, 0),
    'previous_orders', coalesce(total.previous_orders, 0),
    'order_change_rate', case when total.previous_orders <> 0
      then round(
        (total.current_orders - total.previous_orders)::numeric
        / total.previous_orders * 100,
        2
      )
      else null
    end,
    'current_average_order_value', case when total.current_orders > 0
      then total.current_sales / total.current_orders
      else null
    end,
    'previous_average_order_value', case when total.previous_orders > 0
      then total.previous_sales / total.previous_orders
      else null
    end,
    'target_amount', total.target_amount,
    'target_gap', case when total.target_amount is not null
      then total.current_sales - total.target_amount
      else null
    end,
    'target_achievement_rate', case when total.target_amount > 0
      then round(total.current_sales / total.target_amount * 100, 2)
      else null
    end,
    'targeted_branch_count', total.targeted_branch_count,
    'accessible_branch_count', total.accessible_branch_count,
    'branches', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', branch.id,
          'name', branch.name,
          'target_id', branch.target_id,
          'target_amount', branch.target_amount,
          'target_notes', branch.target_notes,
          'current_sales', branch.current_sales,
          'previous_sales', branch.previous_sales,
          'sales_change', branch.current_sales - branch.previous_sales,
          'sales_change_rate', case when branch.previous_sales <> 0
            then round(
              (branch.current_sales - branch.previous_sales)
              / abs(branch.previous_sales) * 100,
              2
            )
            else null
          end,
          'current_orders', branch.current_orders,
          'previous_orders', branch.previous_orders,
          'target_gap', case when branch.target_amount is not null
            then branch.current_sales - branch.target_amount
            else null
          end,
          'target_achievement_rate', case when branch.target_amount > 0
            then round(branch.current_sales / branch.target_amount * 100, 2)
            else null
          end
        ) order by branch.current_sales desc, branch.name
      )
      from branch_metrics branch
    ), '[]'::jsonb)
  )
  from totals total
  );

  return result;
end;
$sales_target_comparison$;

comment on table public.sales_targets is
  'One exact sales target per business branch and inclusive local date range.';
comment on function public.get_sales_target_comparison_report(
  uuid, timestamptz, timestamptz, date, date
) is 'Returns branch-scoped target achievement and prior equivalent-period sales comparisons.';

revoke all on function private.seed_sales_target_role_permission()
  from public, anon, authenticated;
revoke all on function public.upsert_sales_target(
  uuid, uuid, date, date, numeric, text
) from public, anon, authenticated;
revoke all on function public.get_sales_target_comparison_report(
  uuid, timestamptz, timestamptz, date, date
) from public, anon, authenticated;

grant execute on function public.upsert_sales_target(
  uuid, uuid, date, date, numeric, text
) to authenticated;
grant execute on function public.get_sales_target_comparison_report(
  uuid, timestamptz, timestamptz, date, date
) to authenticated;
