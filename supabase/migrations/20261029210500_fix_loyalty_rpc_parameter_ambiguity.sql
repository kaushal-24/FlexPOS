-- Keep loyalty RPC parameters distinct from ledger column names.

drop function if exists public.adjust_customer_loyalty_points(
  uuid, uuid, uuid, uuid, numeric, text, text
);

create or replace function public.adjust_customer_loyalty_points(
  target_business_id uuid,
  target_customer_id uuid,
  target_branch_id uuid,
  target_operation_id uuid,
  target_points_delta numeric,
  target_transaction_type text,
  target_transaction_note text default null
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
  if target_operation_id is null then raise exception 'Operation ID is required'; end if;
  if target_points_delta is null or target_points_delta = 0 then
    raise exception 'Points delta cannot be zero';
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
  where t.business_id = target_business_id
    and t.operation_id = target_operation_id;
  if found then
    return jsonb_build_object(
      'transaction_id', existing_record.id,
      'customer_id', existing_record.customer_id,
      'points_delta', existing_record.points_delta,
      'balance_after', existing_record.balance_after,
      'idempotent', true
    );
  end if;

  next_balance := round(customer_record.loyalty_points + target_points_delta, 4);
  if next_balance < 0 then raise exception 'Insufficient loyalty points'; end if;

  update public.customers
  set loyalty_points = next_balance, updated_at = now()
  where id = target_customer_id and business_id = target_business_id;

  insert into public.customer_loyalty_transactions (
    id, business_id, customer_id, branch_id, transaction_type,
    points_delta, balance_after, note, operation_id, created_by
  ) values (
    transaction_id, target_business_id, target_customer_id, target_branch_id,
    target_transaction_type, round(target_points_delta, 4), next_balance,
    nullif(btrim(target_transaction_note), ''), target_operation_id, caller_id
  );

  perform private.write_tenant_audit(
    target_business_id,
    'customer.loyalty.' || target_transaction_type,
    'customer',
    target_customer_id::text,
    jsonb_build_object(
      'points_delta', round(target_points_delta, 4),
      'balance_after', next_balance
    )
  );

  return jsonb_build_object(
    'transaction_id', transaction_id,
    'customer_id', target_customer_id,
    'points_delta', round(target_points_delta, 4),
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
