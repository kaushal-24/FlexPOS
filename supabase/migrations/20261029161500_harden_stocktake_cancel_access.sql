-- Keep stocktake cancellation scoped to the caller's warehouse access.

create or replace function public.cancel_inventory_stocktake(
  target_stocktake_id uuid,
  operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  stocktake_record public.inventory_stocktakes%rowtype;
  existing_result jsonb;
  inserted_count integer;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  select * into stocktake_record from public.inventory_stocktakes s
  where s.id = target_stocktake_id for update;
  if not found then raise exception 'Stocktake not found'; end if;
  if not private.has_permission(stocktake_record.business_id, 'inventory.manage') then
    raise exception 'You do not have permission to cancel a stocktake';
  end if;
  if not private.can_access_warehouse(stocktake_record.warehouse_id) then
    raise exception 'Warehouse is not accessible';
  end if;
  if stocktake_record.status <> 'counting' then
    raise exception 'Only an active stocktake can be cancelled';
  end if;
  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (stocktake_record.business_id, operation_id, 'inventory.stocktake.cancel', caller_id)
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select result into existing_result from public.idempotency_records
    where business_id = stocktake_record.business_id
      and idempotency_records.operation_id = cancel_inventory_stocktake.operation_id
      and operation_type = 'inventory.stocktake.cancel';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Stocktake cancellation is already in progress';
  end if;
  update public.inventory_stocktakes set status = 'cancelled', completed_at = now()
  where id = target_stocktake_id;
  existing_result := jsonb_build_object(
    'stocktake_id', target_stocktake_id,
    'stocktake_number', stocktake_record.stocktake_number,
    'status', 'cancelled'
  );
  update public.idempotency_records set result = existing_result
  where business_id = stocktake_record.business_id
    and idempotency_records.operation_id = cancel_inventory_stocktake.operation_id
    and operation_type = 'inventory.stocktake.cancel';
  perform private.write_tenant_audit(
    stocktake_record.business_id, 'inventory.stocktake.cancelled',
    'inventory_stocktake', target_stocktake_id::text, existing_result
  );
  return existing_result;
end;
$$;

revoke all on function public.cancel_inventory_stocktake(uuid, uuid)
from public, anon;
grant execute on function public.cancel_inventory_stocktake(uuid, uuid) to authenticated;
