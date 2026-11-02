-- Auditable customer loyalty balance changes for FlexPOS.

create table public.customer_loyalty_transactions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  customer_id uuid not null,
  branch_id uuid,
  transaction_type text not null
    check (transaction_type in ('earn', 'redeem', 'adjust', 'refund')),
  points_delta numeric(20,4) not null check (points_delta <> 0),
  balance_after numeric(20,4) not null check (balance_after >= 0),
  note text,
  operation_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (business_id, operation_id),
  constraint customer_loyalty_customer_fkey
    foreign key (customer_id, business_id)
    references public.customers(id, business_id) on delete cascade,
  constraint customer_loyalty_branch_fkey
    foreign key (branch_id, business_id)
    references public.branches(id, business_id) on delete restrict,
  check (
    (transaction_type = 'earn' and points_delta > 0)
    or (transaction_type = 'refund' and points_delta < 0)
    or (transaction_type = 'redeem' and points_delta < 0)
    or transaction_type = 'adjust'
  )
);

create index customer_loyalty_transactions_customer_idx
  on public.customer_loyalty_transactions(business_id, customer_id, created_at desc);
create index customer_loyalty_transactions_branch_idx
  on public.customer_loyalty_transactions(business_id, branch_id, created_at desc)
  where branch_id is not null;

alter table public.customer_loyalty_transactions enable row level security;

create policy customer_loyalty_transactions_select
on public.customer_loyalty_transactions for select to authenticated
using ((select private.has_permission(business_id, 'customers.view')));

revoke all on public.customer_loyalty_transactions from anon;
grant select on public.customer_loyalty_transactions to authenticated;

create or replace function public.adjust_customer_loyalty_points(
  target_business_id uuid,
  target_customer_id uuid,
  target_branch_id uuid,
  operation_id uuid,
  points_delta numeric,
  transaction_type text,
  transaction_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  customer_record public.customers%rowtype;
  existing_record public.customer_loyalty_transactions%rowtype;
  next_balance numeric(20,4);
  transaction_id uuid := gen_random_uuid();
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if points_delta is null or points_delta = 0 then
    raise exception 'Points delta cannot be zero';
  end if;
  if transaction_type not in ('earn', 'redeem', 'adjust', 'refund') then
    raise exception 'Invalid loyalty transaction type';
  end if;
  if transaction_type = 'earn' and points_delta <= 0 then
    raise exception 'Earn transactions must add points';
  end if;
  if transaction_type in ('redeem', 'refund') and points_delta >= 0 then
    raise exception 'Redeem and refund transactions must subtract points';
  end if;
  if not private.has_permission(target_business_id, 'customers.manage') then
    raise exception 'Customer management permission required';
  end if;
  if target_branch_id is not null and not private.has_branch_access(target_branch_id) then
    raise exception 'Branch access required';
  end if;

  select * into customer_record
  from public.customers c
  where c.id = target_customer_id
    and c.business_id = target_business_id
    and c.is_active and c.archived_at is null
  for update;
  if not found then raise exception 'Customer not found'; end if;

  select * into existing_record
  from public.customer_loyalty_transactions t
  where t.business_id = target_business_id and t.operation_id = adjust_customer_loyalty_points.operation_id;
  if found then
    return jsonb_build_object(
      'transaction_id', existing_record.id,
      'customer_id', existing_record.customer_id,
      'points_delta', existing_record.points_delta,
      'balance_after', existing_record.balance_after,
      'idempotent', true
    );
  end if;

  next_balance := round(customer_record.loyalty_points + points_delta, 4);
  if next_balance < 0 then raise exception 'Insufficient loyalty points'; end if;

  update public.customers
  set loyalty_points = next_balance, updated_at = now()
  where id = target_customer_id and business_id = target_business_id;

  insert into public.customer_loyalty_transactions (
    id, business_id, customer_id, branch_id, transaction_type,
    points_delta, balance_after, note, operation_id, created_by
  ) values (
    transaction_id, target_business_id, target_customer_id, target_branch_id,
    transaction_type, round(points_delta, 4), next_balance,
    nullif(btrim(transaction_note), ''), operation_id, caller_id
  );

  perform private.write_tenant_audit(
    target_business_id,
    'customer.loyalty.' || transaction_type,
    'customer',
    target_customer_id::text,
    jsonb_build_object('points_delta', round(points_delta, 4), 'balance_after', next_balance)
  );

  return jsonb_build_object(
    'transaction_id', transaction_id,
    'customer_id', target_customer_id,
    'points_delta', round(points_delta, 4),
    'balance_after', next_balance,
    'idempotent', false
  );
end;
$$;

revoke all on function public.adjust_customer_loyalty_points(
  uuid, uuid, uuid, uuid, numeric, text, text
) from public, anon;
grant execute on function public.adjust_customer_loyalty_points(
  uuid, uuid, uuid, uuid, numeric, text, text
) to authenticated;

comment on table public.customer_loyalty_transactions is
  'Append-only, idempotent loyalty balance ledger; current balance is mirrored on customers.loyalty_points.';
