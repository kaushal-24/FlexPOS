-- Aggregated register reconciliation and staff performance reporting.
-- All monetary activity is branch-scoped to the caller's accessible branches.

create index if not exists register_shifts_business_closed_report_idx
  on public.register_shifts(business_id, closed_at desc)
  include (register_id, opened_by, expected_cash, closing_cash, difference_amount)
  where status = 'closed';

create or replace function public.get_register_staff_performance_report(
  target_business_id uuid,
  period_start timestamptz,
  period_end timestamptz
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not private.has_permission(target_business_id, 'reports.view')
     or not private.has_permission(target_business_id, 'sales.view')
     or not private.has_permission(target_business_id, 'staff.view')
     or not private.has_permission(target_business_id, 'registers.manage') then
    raise exception 'Register and staff reporting permission required';
  end if;
  if period_start is null or period_end is null or period_end <= period_start then
    raise exception 'Invalid report period';
  end if;
  if period_end - period_start > interval '366 days' then
    raise exception 'Report period cannot exceed 366 days';
  end if;

  with accessible_registers as materialized (
    select r.id, r.name, r.code, r.branch_id, b.name as branch_name
    from public.registers r
    join public.branches b
      on b.id = r.branch_id and b.business_id = r.business_id
    where r.business_id = target_business_id
      and private.has_branch_access(r.branch_id)
  ),
  sale_activity as materialized (
    select activity.user_id,
           sum(activity.gross_sales) as gross_sales,
           sum(activity.returned_sales) as returned_sales,
           sum(activity.orders) as orders
    from (
      select s.completed_by as user_id,
             s.grand_total as gross_sales,
             0::numeric as returned_sales,
             1::bigint as orders
      from public.sales s
      where s.business_id = target_business_id
        and s.status in ('completed', 'partially_refunded', 'refunded')
        and s.completed_at >= period_start and s.completed_at < period_end
        and private.has_branch_access(s.branch_id)
      union all
      select s.completed_by,
             0::numeric,
             sr.refund_total,
             0::bigint
      from public.sale_returns sr
      join public.sales s
        on s.id = sr.sale_id and s.business_id = sr.business_id
      where sr.business_id = target_business_id
        and sr.status = 'completed'
        and sr.returned_at >= period_start and sr.returned_at < period_end
        and private.has_branch_access(sr.branch_id)
    ) activity
    group by activity.user_id
  ),
  return_activity as materialized (
    select sr.returned_by as user_id,
           count(*) as returns_processed,
           sum(sr.refund_total) as returned_amount
    from public.sale_returns sr
    where sr.business_id = target_business_id
      and sr.status = 'completed'
      and sr.returned_at >= period_start and sr.returned_at < period_end
      and private.has_branch_access(sr.branch_id)
    group by sr.returned_by
  ),
  closed_shifts as materialized (
    select rs.id, rs.register_id, rs.opened_by,
           coalesce(rs.expected_cash, 0) as expected_cash,
           coalesce(rs.closing_cash, 0) as closing_cash,
           coalesce(rs.difference_amount, 0) as difference_amount
    from public.register_shifts rs
    join accessible_registers ar on ar.id = rs.register_id
    where rs.business_id = target_business_id
      and rs.status = 'closed'
      and rs.closed_at >= period_start and rs.closed_at < period_end
  ),
  shift_activity as materialized (
    select cs.opened_by as user_id,
           count(*) as shifts_closed,
           count(*) filter (where cs.difference_amount = 0) as balanced_shifts,
           count(*) filter (where cs.difference_amount > 0) as over_shifts,
           count(*) filter (where cs.difference_amount < 0) as short_shifts,
           sum(cs.expected_cash) as expected_cash,
           sum(cs.closing_cash) as closing_cash,
           sum(cs.difference_amount) as net_variance,
           sum(abs(cs.difference_amount)) as absolute_variance,
           sum(greatest(cs.difference_amount, 0)) as overage,
           sum(abs(least(cs.difference_amount, 0))) as shortage
    from closed_shifts cs
    group by cs.opened_by
  ),
  staff_rows as materialized (
    select m.user_id as id,
           coalesce(nullif(btrim(p.full_name), ''), p.email) as name,
           p.email,
           coalesce(sa.gross_sales, 0) as gross_sales,
           coalesce(sa.returned_sales, 0) as returned_sales,
           coalesce(sa.gross_sales, 0) - coalesce(sa.returned_sales, 0) as net_sales,
           coalesce(sa.orders, 0) as orders,
           coalesce(ra.returns_processed, 0) as returns_processed,
           coalesce(ra.returned_amount, 0) as returned_amount,
           coalesce(sha.shifts_closed, 0) as shifts_closed,
           coalesce(sha.balanced_shifts, 0) as balanced_shifts,
           coalesce(sha.over_shifts, 0) as over_shifts,
           coalesce(sha.short_shifts, 0) as short_shifts,
           coalesce(sha.expected_cash, 0) as expected_cash,
           coalesce(sha.closing_cash, 0) as closing_cash,
           coalesce(sha.net_variance, 0) as net_variance,
           coalesce(sha.absolute_variance, 0) as absolute_variance,
           coalesce(sha.overage, 0) as overage,
           coalesce(sha.shortage, 0) as shortage
    from public.memberships m
    join public.profiles p on p.id = m.user_id
    left join sale_activity sa on sa.user_id = m.user_id
    left join return_activity ra on ra.user_id = m.user_id
    left join shift_activity sha on sha.user_id = m.user_id
    where m.business_id = target_business_id
      and m.status = 'active'
      and m.archived_at is null
  ),
  register_rows as materialized (
    select ar.id, ar.name, ar.code, ar.branch_id, ar.branch_name,
           count(cs.id) as shifts_closed,
           count(cs.id) filter (where cs.difference_amount = 0) as balanced_shifts,
           count(cs.id) filter (where cs.difference_amount > 0) as over_shifts,
           count(cs.id) filter (where cs.difference_amount < 0) as short_shifts,
           coalesce(sum(cs.expected_cash), 0) as expected_cash,
           coalesce(sum(cs.closing_cash), 0) as closing_cash,
           coalesce(sum(cs.difference_amount), 0) as net_variance,
           coalesce(sum(abs(cs.difference_amount)), 0) as absolute_variance,
           coalesce(sum(greatest(cs.difference_amount, 0)), 0) as overage,
           coalesce(sum(abs(least(cs.difference_amount, 0))), 0) as shortage
    from accessible_registers ar
    left join closed_shifts cs on cs.register_id = ar.id
    group by ar.id, ar.name, ar.code, ar.branch_id, ar.branch_name
  ),
  totals as (
    select
      coalesce((select sum(sa.gross_sales) from sale_activity sa), 0) as gross_sales,
      coalesce((select sum(sa.returned_sales) from sale_activity sa), 0) as returned_sales,
      coalesce((select sum(sa.orders) from sale_activity sa), 0) as orders,
      coalesce((select sum(ra.returns_processed) from return_activity ra), 0) as returns_processed,
      coalesce((select count(*) from closed_shifts), 0) as shifts_closed,
      coalesce((select count(*) from closed_shifts cs where cs.difference_amount = 0), 0) as balanced_shifts,
      coalesce((select count(*) from closed_shifts cs where cs.difference_amount > 0), 0) as over_shifts,
      coalesce((select count(*) from closed_shifts cs where cs.difference_amount < 0), 0) as short_shifts,
      coalesce((select sum(cs.expected_cash) from closed_shifts cs), 0) as expected_cash,
      coalesce((select sum(cs.closing_cash) from closed_shifts cs), 0) as closing_cash,
      coalesce((select sum(cs.difference_amount) from closed_shifts cs), 0) as net_variance,
      coalesce((select sum(abs(cs.difference_amount)) from closed_shifts cs), 0) as absolute_variance,
      coalesce((select sum(greatest(cs.difference_amount, 0)) from closed_shifts cs), 0) as overage,
      coalesce((select sum(abs(least(cs.difference_amount, 0))) from closed_shifts cs), 0) as shortage
  )
  select jsonb_build_object(
    'period_start', period_start,
    'period_end', period_end,
    'gross_sales', round(t.gross_sales, 2),
    'returned_sales', round(t.returned_sales, 2),
    'net_sales', round(t.gross_sales - t.returned_sales, 2),
    'orders', t.orders,
    'average_order_value', case when t.orders > 0
      then round((t.gross_sales - t.returned_sales) / t.orders, 2)
      else null end,
    'returns_processed', t.returns_processed,
    'shifts_closed', t.shifts_closed,
    'balanced_shifts', t.balanced_shifts,
    'over_shifts', t.over_shifts,
    'short_shifts', t.short_shifts,
    'expected_cash', round(t.expected_cash, 2),
    'closing_cash', round(t.closing_cash, 2),
    'net_variance', round(t.net_variance, 2),
    'absolute_variance', round(t.absolute_variance, 2),
    'overage', round(t.overage, 2),
    'shortage', round(t.shortage, 2),
    'staff', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', sr.id,
        'name', sr.name,
        'email', sr.email,
        'gross_sales', round(sr.gross_sales, 2),
        'returned_sales', round(sr.returned_sales, 2),
        'net_sales', round(sr.net_sales, 2),
        'orders', sr.orders,
        'average_order_value', case when sr.orders > 0
          then round(sr.net_sales / sr.orders, 2) else null end,
        'returns_processed', sr.returns_processed,
        'returned_amount', round(sr.returned_amount, 2),
        'shifts_closed', sr.shifts_closed,
        'balanced_shifts', sr.balanced_shifts,
        'over_shifts', sr.over_shifts,
        'short_shifts', sr.short_shifts,
        'expected_cash', round(sr.expected_cash, 2),
        'closing_cash', round(sr.closing_cash, 2),
        'net_variance', round(sr.net_variance, 2),
        'absolute_variance', round(sr.absolute_variance, 2),
        'overage', round(sr.overage, 2),
        'shortage', round(sr.shortage, 2)
      ) order by sr.net_sales desc, sr.name)
      from staff_rows sr
    ), '[]'::jsonb),
    'registers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', rr.id,
        'name', rr.name,
        'code', rr.code,
        'branch_id', rr.branch_id,
        'branch_name', rr.branch_name,
        'shifts_closed', rr.shifts_closed,
        'balanced_shifts', rr.balanced_shifts,
        'over_shifts', rr.over_shifts,
        'short_shifts', rr.short_shifts,
        'expected_cash', round(rr.expected_cash, 2),
        'closing_cash', round(rr.closing_cash, 2),
        'net_variance', round(rr.net_variance, 2),
        'absolute_variance', round(rr.absolute_variance, 2),
        'overage', round(rr.overage, 2),
        'shortage', round(rr.shortage, 2)
      ) order by rr.absolute_variance desc, rr.branch_name, rr.name)
      from register_rows rr
    ), '[]'::jsonb)
  ) into result
  from totals t;

  return result;
end;
$$;

revoke all on function public.get_register_staff_performance_report(
  uuid, timestamptz, timestamptz
) from public, anon, authenticated;
grant execute on function public.get_register_staff_performance_report(
  uuid, timestamptz, timestamptz
) to authenticated;
