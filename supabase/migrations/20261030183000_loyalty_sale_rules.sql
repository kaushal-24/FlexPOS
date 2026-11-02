begin;

-- Business-configurable loyalty rules. A row is seeded for every new business;
-- existing businesses use the same safe defaults on first read.
create table public.business_loyalty_settings (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  enabled boolean not null default true,
  earn_points_per_currency numeric(20,4) not null default 1
    check (earn_points_per_currency >= 0),
  redeem_points_per_currency numeric(20,4) not null default 100
    check (redeem_points_per_currency > 0),
  max_redeem_percent numeric(5,2) not null default 100
    check (max_redeem_percent between 0 and 100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

create index business_loyalty_settings_updated_by_idx
  on public.business_loyalty_settings(updated_by);

alter table public.business_loyalty_settings enable row level security;
create policy business_loyalty_settings_select
on public.business_loyalty_settings for select to authenticated
using ((select private.has_permission(business_id, 'business.view')));
create policy business_loyalty_settings_insert
on public.business_loyalty_settings for insert to authenticated
with check ((select private.has_permission(business_id, 'business.manage')));
create policy business_loyalty_settings_update
on public.business_loyalty_settings for update to authenticated
using ((select private.has_permission(business_id, 'business.manage')))
with check ((select private.has_permission(business_id, 'business.manage')));
create policy business_loyalty_settings_delete
on public.business_loyalty_settings for delete to authenticated
using ((select private.has_permission(business_id, 'business.manage')));

revoke all on public.business_loyalty_settings from anon, authenticated;
grant select on public.business_loyalty_settings to authenticated;

insert into public.business_loyalty_settings (business_id)
select b.id from public.businesses b
where not exists (
  select 1 from public.business_loyalty_settings existing
  where existing.business_id = b.id
);

create or replace function private.seed_business_loyalty_settings()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.business_loyalty_settings (business_id)
  values (new.id)
  on conflict (business_id) do nothing;
  return new;
end;
$$;

drop trigger if exists businesses_seed_loyalty_settings on public.businesses;
create trigger businesses_seed_loyalty_settings
after insert on public.businesses
for each row execute function private.seed_business_loyalty_settings();

create or replace function public.set_business_loyalty_settings(
  target_business_id uuid,
  target_enabled boolean,
  target_earn_points_per_currency numeric,
  target_redeem_points_per_currency numeric,
  target_max_redeem_percent numeric
)
returns public.business_loyalty_settings
language plpgsql
security definer
set search_path = public
as $$
declare
  saved public.business_loyalty_settings;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not private.has_permission(target_business_id, 'business.manage') then
    raise exception 'Business management permission required';
  end if;
  if target_earn_points_per_currency is null or target_earn_points_per_currency < 0
     or target_redeem_points_per_currency is null or target_redeem_points_per_currency <= 0
     or target_max_redeem_percent is null or target_max_redeem_percent < 0
     or target_max_redeem_percent > 100 then
    raise exception 'Invalid loyalty rule values';
  end if;

  insert into public.business_loyalty_settings (
    business_id, enabled, earn_points_per_currency,
    redeem_points_per_currency, max_redeem_percent, updated_by
  ) values (
    target_business_id, coalesce(target_enabled, false),
    target_earn_points_per_currency, target_redeem_points_per_currency,
    target_max_redeem_percent, auth.uid()
  )
  on conflict (business_id) do update set
    enabled = excluded.enabled,
    earn_points_per_currency = excluded.earn_points_per_currency,
    redeem_points_per_currency = excluded.redeem_points_per_currency,
    max_redeem_percent = excluded.max_redeem_percent,
    updated_by = auth.uid(),
    updated_at = now()
  returning * into saved;
  perform private.write_tenant_audit(
    target_business_id, 'business.loyalty_settings.updated',
    'business_loyalty_settings', target_business_id::text,
    jsonb_build_object('enabled', saved.enabled,
      'earn_points_per_currency', saved.earn_points_per_currency,
      'redeem_points_per_currency', saved.redeem_points_per_currency,
      'max_redeem_percent', saved.max_redeem_percent)
  );
  return saved;
end;
$$;

revoke all on function public.set_business_loyalty_settings(uuid, boolean, numeric, numeric, numeric)
  from public, anon;
grant execute on function public.set_business_loyalty_settings(uuid, boolean, numeric, numeric, numeric)
  to authenticated;

create or replace function private.apply_loyalty_delta(
  target_business_id uuid,
  target_customer_id uuid,
  target_branch_id uuid,
  target_operation_id uuid,
  target_points_delta numeric,
  target_transaction_type text,
  target_transaction_note text,
  target_actor_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_record public.customer_loyalty_transactions%rowtype;
  customer_record public.customers%rowtype;
  next_balance numeric(20,4);
  transaction_id uuid := gen_random_uuid();
  actor_id uuid := coalesce(auth.uid(), target_actor_user_id);
begin
  if actor_id is null then raise exception 'Actor is required'; end if;
  if target_operation_id is null or target_points_delta is null or target_points_delta = 0 then
    raise exception 'A non-zero idempotent loyalty operation is required';
  end if;
  if target_transaction_type not in ('earn', 'redeem', 'adjust', 'refund') then
    raise exception 'Invalid loyalty transaction type';
  end if;
  if target_transaction_type = 'earn' and target_points_delta <= 0 then
    raise exception 'Earn transactions must add points';
  end if;
  if target_transaction_type in ('redeem', 'refund') and target_points_delta >= 0 then
    raise exception 'Redeem and refund transactions must subtract points';
  end if;

  select * into existing_record
  from public.customer_loyalty_transactions
  where business_id = target_business_id and operation_id = target_operation_id;
  if found then
    return jsonb_build_object('transaction_id', existing_record.id,
      'customer_id', existing_record.customer_id,
      'points_delta', existing_record.points_delta,
      'balance_after', existing_record.balance_after, 'idempotent', true);
  end if;

  select * into customer_record
  from public.customers c
  where c.id = target_customer_id and c.business_id = target_business_id
    and c.is_active and c.archived_at is null
  for update;
  if not found then raise exception 'Customer not found'; end if;

  if target_branch_id is not null and not exists (
    select 1 from public.branches b
    where b.id = target_branch_id and b.business_id = target_business_id
      and b.is_active and b.archived_at is null
  ) then raise exception 'Invalid loyalty branch'; end if;

  next_balance := round(customer_record.loyalty_points + target_points_delta, 4);
  if next_balance < 0 then raise exception 'Insufficient loyalty points'; end if;
  update public.customers set loyalty_points = next_balance, updated_at = now()
  where id = target_customer_id and business_id = target_business_id;
  insert into public.customer_loyalty_transactions (
    id, business_id, customer_id, branch_id, transaction_type,
    points_delta, balance_after, note, operation_id, created_by
  ) values (
    transaction_id, target_business_id, target_customer_id, target_branch_id,
    target_transaction_type, round(target_points_delta, 4), next_balance,
    nullif(btrim(target_transaction_note), ''), target_operation_id, actor_id
  );
  perform private.write_tenant_audit(
    target_business_id, 'customer.loyalty.' || target_transaction_type,
    'customer', target_customer_id::text,
    jsonb_build_object('points_delta', round(target_points_delta, 4),
      'balance_after', next_balance, 'source_operation_id', target_operation_id)
  );
  return jsonb_build_object('transaction_id', transaction_id,
    'customer_id', target_customer_id,
    'points_delta', round(target_points_delta, 4),
    'balance_after', next_balance, 'idempotent', false);
end;
$$;

revoke all on function private.apply_loyalty_delta(uuid, uuid, uuid, uuid, numeric, text, text, uuid)
  from public, anon, authenticated;

create or replace function public.redeem_customer_loyalty_points(
  target_business_id uuid,
  target_customer_id uuid,
  target_branch_id uuid,
  target_operation_id uuid,
  target_points numeric,
  target_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  settings public.business_loyalty_settings;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not (private.has_permission(target_business_id, 'sales.create')
          or private.has_permission(target_business_id, 'customers.manage')) then
    raise exception 'Sales or customer management permission required';
  end if;
  if target_points is null or target_points <= 0 then
    raise exception 'Redeemed points must be greater than zero';
  end if;
  select * into settings from public.business_loyalty_settings
  where business_id = target_business_id;
  if not found or not settings.enabled then raise exception 'Loyalty is disabled'; end if;
  if target_points < settings.redeem_points_per_currency then
    raise exception 'Redeemed points do not meet the minimum value';
  end if;
  return private.apply_loyalty_delta(
    target_business_id, target_customer_id, target_branch_id,
    target_operation_id, -target_points, 'redeem', target_note, auth.uid()
  );
end;
$$;

revoke all on function public.redeem_customer_loyalty_points(uuid, uuid, uuid, uuid, numeric, text)
  from public, anon;
grant execute on function public.redeem_customer_loyalty_points(uuid, uuid, uuid, uuid, numeric, text)
  to authenticated;

create or replace function private.award_sale_loyalty_points()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  settings public.business_loyalty_settings;
  points numeric(20,4);
begin
  if new.status <> 'completed' or new.customer_id is null
     or new.payment_status not in ('paid', 'partially_paid') then
    return new;
  end if;
  select * into settings from public.business_loyalty_settings
  where business_id = new.business_id;
  if not found then
    settings.enabled := true;
    settings.earn_points_per_currency := 1;
  end if;
  if not settings.enabled or settings.earn_points_per_currency <= 0 then return new; end if;
  points := round(new.grand_total * settings.earn_points_per_currency, 4);
  if points > 0 then
    perform private.apply_loyalty_delta(
      new.business_id, new.customer_id, new.branch_id, new.operation_id,
      points, 'earn', 'Automatic points from sale ' || new.invoice_number,
      new.completed_by
    );
  end if;
  return new;
end;
$$;

revoke all on function private.award_sale_loyalty_points() from public, anon, authenticated;
drop trigger if exists sales_award_loyalty_points on public.sales;
create trigger sales_award_loyalty_points
after insert on public.sales
for each row execute function private.award_sale_loyalty_points();

commit;
