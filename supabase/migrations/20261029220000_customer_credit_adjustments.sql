-- Permission-controlled, auditable customer credit adjustments.

create or replace function public.create_customer_credit_adjustment(
  target_business_id uuid,
  target_branch_id uuid,
  target_customer_id uuid,
  target_operation_id uuid,
  target_adjustment_type text,
  target_amount numeric,
  target_description text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  existing_result jsonb;
  inserted_count integer;
  outstanding numeric(18,2);
  adjustment_id uuid := gen_random_uuid();
  entry_type text;
  direction text;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if target_operation_id is null then raise exception 'Operation ID is required'; end if;
  if not private.has_permission(target_business_id, 'customer_credit.manage') then
    raise exception 'Customer credit management permission required';
  end if;
  if not private.has_branch_access(target_branch_id) then
    raise exception 'Branch access required';
  end if;
  if target_adjustment_type not in ('debit', 'credit') then
    raise exception 'Adjustment type must be debit or credit';
  end if;
  if target_amount is null or round(target_amount, 2) <= 0 then
    raise exception 'Adjustment amount must be greater than zero';
  end if;
  if length(btrim(coalesce(target_description, ''))) < 3 then
    raise exception 'A meaningful adjustment description is required';
  end if;
  if not exists (
    select 1 from public.customers c
    where c.id = target_customer_id
      and c.business_id = target_business_id
      and c.is_active and c.archived_at is null
  ) then
    raise exception 'Active customer not found';
  end if;

  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (
    target_business_id, target_operation_id, 'customer.credit_adjustment', caller_id
  ) on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select ir.result into existing_result
    from public.idempotency_records ir
    where ir.business_id = target_business_id
      and ir.operation_id = target_operation_id
      and ir.operation_type = 'customer.credit_adjustment';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Adjustment operation is already in progress';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(target_customer_id::text, 0));
  select coalesce(sum(
    case when cle.direction = 'debit' then cle.amount else -cle.amount end
  ), 0)
  into outstanding
  from public.customer_ledger_entries cle
  where cle.business_id = target_business_id
    and cle.customer_id = target_customer_id
    and private.has_branch_access(cle.branch_id);

  if target_adjustment_type = 'credit'
     and round(target_amount, 2) > outstanding then
    raise exception 'Credit adjustment exceeds outstanding balance';
  end if;

  entry_type := target_adjustment_type || '_adjustment';
  direction := case when target_adjustment_type = 'debit' then 'debit' else 'credit' end;
  insert into public.customer_ledger_entries (
    id, business_id, branch_id, customer_id, entry_type, direction, amount,
    description, operation_id, created_by
  ) values (
    adjustment_id, target_business_id, target_branch_id, target_customer_id,
    entry_type, direction, round(target_amount, 2), btrim(target_description),
    target_operation_id, caller_id
  );

  existing_result := jsonb_build_object(
    'adjustment_id', adjustment_id,
    'customer_id', target_customer_id,
    'adjustment_type', target_adjustment_type,
    'amount', round(target_amount, 2),
    'outstanding_balance', case
      when target_adjustment_type = 'debit'
        then outstanding + round(target_amount, 2)
      else outstanding - round(target_amount, 2)
    end
  );
  update public.idempotency_records ir
  set result = existing_result
  where ir.business_id = target_business_id
    and ir.operation_id = target_operation_id
    and ir.operation_type = 'customer.credit_adjustment';
  perform private.write_tenant_audit(
    target_business_id,
    'customer.' || entry_type,
    'customer',
    target_customer_id::text,
    existing_result
  );
  return existing_result;
end;
$$;

revoke all on function public.create_customer_credit_adjustment(
  uuid, uuid, uuid, uuid, text, numeric, text
) from public, anon, authenticated;
grant execute on function public.create_customer_credit_adjustment(
  uuid, uuid, uuid, uuid, text, numeric, text
) to authenticated;
