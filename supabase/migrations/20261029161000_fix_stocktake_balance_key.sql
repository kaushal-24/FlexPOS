-- inventory_balances is keyed by business, warehouse, and variant.

create or replace function public.finalize_inventory_stocktake(
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
  variant_record record;
  batch_record record;
  balance_record public.inventory_balances%rowtype;
  next_quantity numeric(20,6);
  variance_total numeric(20,6) := 0;
  movement_id bigint;
  existing_result jsonb;
  inserted_count integer;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  select * into stocktake_record
  from public.inventory_stocktakes s
  where s.id = target_stocktake_id
  for update;
  if not found then raise exception 'Stocktake not found'; end if;
  if not private.has_permission(stocktake_record.business_id, 'inventory.manage') then
    raise exception 'You do not have permission to finalize a stocktake';
  end if;
  if not private.can_access_warehouse(stocktake_record.warehouse_id) then
    raise exception 'Warehouse is not accessible';
  end if;
  if stocktake_record.status <> 'counting' then
    if stocktake_record.status = 'finalized' then
      select result into existing_result
      from public.idempotency_records
      where business_id = stocktake_record.business_id
        and operation_type = 'inventory.stocktake.finalize'
        and result ->> 'stocktake_id' = target_stocktake_id::text
      order by created_at desc limit 1;
      if existing_result is not null then return existing_result; end if;
    end if;
    raise exception 'Only an active stocktake can be finalized';
  end if;
  if exists (
    select 1 from public.inventory_stocktake_items i
    where i.stocktake_id = target_stocktake_id and i.counted_quantity is null
  ) then raise exception 'Every stocktake item must be counted before finalization'; end if;

  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (stocktake_record.business_id, operation_id, 'inventory.stocktake.finalize', caller_id)
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select result into existing_result
    from public.idempotency_records
    where business_id = stocktake_record.business_id
      and idempotency_records.operation_id = finalize_inventory_stocktake.operation_id
      and operation_type = 'inventory.stocktake.finalize';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Stocktake finalization is already in progress';
  end if;

  for variant_record in
    select i.variant_id,
           round(sum(i.counted_quantity - i.system_quantity), 6) as variance
    from public.inventory_stocktake_items i
    where i.stocktake_id = target_stocktake_id
    group by i.variant_id
    order by i.variant_id
  loop
    insert into public.inventory_balances (business_id, warehouse_id, variant_id)
    values (stocktake_record.business_id, stocktake_record.warehouse_id, variant_record.variant_id)
    on conflict (warehouse_id, variant_id) do nothing;
    select * into balance_record
    from public.inventory_balances b
    where b.business_id = stocktake_record.business_id
      and b.warehouse_id = stocktake_record.warehouse_id
      and b.variant_id = variant_record.variant_id
    for update;
    next_quantity := balance_record.quantity_on_hand + variant_record.variance;
    if next_quantity < balance_record.quantity_reserved or next_quantity < 0 then
      raise exception 'Stocktake would reduce stock below reserved quantity';
    end if;
    update public.inventory_balances
    set quantity_on_hand = next_quantity, updated_at = now()
    where business_id = stocktake_record.business_id
      and warehouse_id = stocktake_record.warehouse_id
      and variant_id = variant_record.variant_id;
    if variant_record.variance <> 0 then
      insert into public.inventory_movements (
        business_id, warehouse_id, variant_id, movement_type, quantity_delta,
        quantity_before, quantity_after, unit_cost, reference_type, reference_id,
        reason, operation_id, created_by
      ) values (
        stocktake_record.business_id, stocktake_record.warehouse_id,
        variant_record.variant_id, 'stocktake', variant_record.variance,
        balance_record.quantity_on_hand, next_quantity, balance_record.average_cost,
        'inventory_stocktake', target_stocktake_id, 'Physical stocktake', operation_id, caller_id
      ) returning id into movement_id;
      variance_total := variance_total + variant_record.variance;
    end if;
  end loop;

  for batch_record in
    select i.batch_id,
           round(sum(i.counted_quantity - i.system_quantity), 6) as variance
    from public.inventory_stocktake_items i
    where i.stocktake_id = target_stocktake_id and i.batch_id is not null
    group by i.batch_id
    order by i.batch_id
  loop
    update public.inventory_batches b
    set quantity_on_hand = b.quantity_on_hand + batch_record.variance,
        updated_at = now()
    where b.id = batch_record.batch_id
      and b.business_id = stocktake_record.business_id
      and b.quantity_on_hand + batch_record.variance >= b.quantity_reserved;
    if not found then raise exception 'Stocktake batch variance is invalid'; end if;
    if batch_record.variance <> 0 then
      insert into public.inventory_batch_movements (
        business_id, batch_id, warehouse_id, variant_id, movement_type,
        quantity_delta, quantity_before, quantity_after, unit_cost,
        reference_type, reference_id, operation_id, created_by
      )
      select stocktake_record.business_id, b.id, b.warehouse_id, b.variant_id,
             'stocktake', batch_record.variance, b.quantity_on_hand - batch_record.variance,
             b.quantity_on_hand, b.average_cost, 'inventory_stocktake',
             target_stocktake_id, operation_id, caller_id
      from public.inventory_batches b
      where b.id = batch_record.batch_id;
    end if;
  end loop;

  update public.inventory_stocktakes
  set status = 'finalized', completed_at = now(), finalized_by = caller_id
  where id = target_stocktake_id;
  existing_result := jsonb_build_object(
    'stocktake_id', target_stocktake_id,
    'stocktake_number', stocktake_record.stocktake_number,
    'status', 'finalized',
    'variance_total', variance_total
  );
  update public.idempotency_records set result = existing_result
  where business_id = stocktake_record.business_id
    and idempotency_records.operation_id = finalize_inventory_stocktake.operation_id
    and operation_type = 'inventory.stocktake.finalize';
  perform private.write_tenant_audit(
    stocktake_record.business_id, 'inventory.stocktake.finalized',
    'inventory_stocktake', target_stocktake_id::text, existing_result
  );
  return existing_result;
end;
$$;

revoke all on function public.finalize_inventory_stocktake(uuid, uuid)
from public, anon;
grant execute on function public.finalize_inventory_stocktake(uuid, uuid) to authenticated;
