-- Ensure a completed purchase receipt can still be retried idempotently.
--
-- The original receipt function checked the order's open status before its
-- idempotency record. That made a successful final receipt unretryable once
-- the order transitioned to `received`. Keep authorization and warehouse
-- checks ahead of replay, but resolve an existing operation before checking
-- whether a *new* receipt may be created.
do $migration$
declare
  definition text;
  old_block constant text := $old$
  if not found or order_record.status not in ('ordered', 'partially_received') then
    raise exception 'Purchase order is not open for receiving';
  end if;
  if not private.has_permission(order_record.business_id, 'purchases.manage') then
    raise exception 'You do not have permission to receive purchases';
  end if;
  if not private.can_access_warehouse(order_record.warehouse_id) then
    raise exception 'Warehouse is not accessible';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(received_items) as x(purchase_order_item_id uuid)
    left join public.purchase_order_items poi
      on poi.id = x.purchase_order_item_id
     and poi.purchase_order_id = target_purchase_order_id
    where poi.id is null
  ) then
    raise exception 'A received line does not belong to this purchase order';
  end if;

  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (
    order_record.business_id, operation_id, 'purchase.receive', caller_id
  )
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select result into existing_result
    from public.idempotency_records i
    where i.business_id = order_record.business_id
      and i.operation_id = receive_purchase_order.operation_id
      and i.operation_type = 'purchase.receive';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Receipt operation is already in progress';
  end if;
$old$;
  new_block constant text := $new$
  if not found then
    raise exception 'Purchase order is not open for receiving';
  end if;
  if not private.has_permission(order_record.business_id, 'purchases.manage') then
    raise exception 'You do not have permission to receive purchases';
  end if;
  if not private.can_access_warehouse(order_record.warehouse_id) then
    raise exception 'Warehouse is not accessible';
  end if;

  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (
    order_record.business_id, operation_id, 'purchase.receive', caller_id
  )
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select result into existing_result
    from public.idempotency_records i
    where i.business_id = order_record.business_id
      and i.operation_id = receive_purchase_order.operation_id
      and i.operation_type = 'purchase.receive';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Receipt operation is already in progress';
  end if;

  if order_record.status not in ('ordered', 'partially_received') then
    raise exception 'Purchase order is not open for receiving';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(received_items) as x(purchase_order_item_id uuid)
    left join public.purchase_order_items poi
      on poi.id = x.purchase_order_item_id
     and poi.purchase_order_id = target_purchase_order_id
    where poi.id is null
  ) then
    raise exception 'A received line does not belong to this purchase order';
  end if;
$new$;
begin
  select pg_get_functiondef(
    'public.receive_purchase_order(uuid, uuid, jsonb, text, text)'::regprocedure
  ) into definition;

  if position(old_block in definition) > 0 then
    execute replace(definition, old_block, new_block);
  elsif position(new_block in definition) = 0 then
    raise exception 'Unexpected receive_purchase_order definition; refusing to change it';
  end if;
end;
$migration$;
