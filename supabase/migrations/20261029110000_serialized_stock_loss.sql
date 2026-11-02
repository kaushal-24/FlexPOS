-- Integrate serial/IMEI units with atomic damage and wastage recording.

create or replace function public.record_stock_loss(
  target_business_id uuid,
  target_warehouse_id uuid,
  target_variant_id uuid,
  selected_loss_type text,
  loss_quantity numeric,
  loss_reason text,
  operation_id uuid,
  loss_notes text,
  serialized_unit_ids jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  existing_result jsonb;
  variant_tracking_mode text;
  selected_ids uuid[];
  selected_id uuid;
  selected_count integer;
  linked_count integer;
  valid_count integer;
  loss_event_id uuid;
  terminal_status text;
  result jsonb;
  serialized_units_lost integer := 0;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  select i.result into existing_result
  from public.idempotency_records i
  where business_id = target_business_id
    and idempotency_records.operation_id = record_stock_loss.operation_id
    and operation_type = 'inventory.loss';
  if existing_result is not null and existing_result <> '{}'::jsonb then
    return existing_result;
  end if;
  if serialized_unit_ids is null then
    serialized_unit_ids := '[]'::jsonb;
  end if;
  if jsonb_typeof(serialized_unit_ids) <> 'array' then
    raise exception 'Serialized unit selections must be an array';
  end if;
  select v.tracking_mode
  into variant_tracking_mode
  from public.product_variants v
  where v.id = target_variant_id
    and v.business_id = target_business_id;
  if not found then raise exception 'Variant is unavailable'; end if;

  selected_count := jsonb_array_length(serialized_unit_ids);
  if variant_tracking_mode in ('serial', 'imei') then
    if loss_quantity is null or loss_quantity <> trunc(loss_quantity) then
      raise exception 'Serialized loss quantity must be a whole number';
    end if;
    if selected_count <> loss_quantity::integer then
      raise exception 'Select exactly % serial number(s) or IMEI(s) for this loss',
        loss_quantity::integer;
    end if;
    select array_agg(value::uuid) into selected_ids
    from jsonb_array_elements_text(serialized_unit_ids) as values(value);
    if selected_ids is null or array_length(selected_ids, 1) <> selected_count then
      raise exception 'Invalid serialized unit selection';
    end if;
    select count(*) into linked_count
    from (
      select distinct id
      from public.serialized_inventory_units
      where id = any(selected_ids)
        and business_id = target_business_id
    ) matched;
    if linked_count <> selected_count then
      raise exception 'One or more selected serial numbers or IMEIs were not found';
    end if;
    select count(*) into valid_count
    from public.serialized_inventory_units unit_record
    where unit_record.id = any(selected_ids)
      and unit_record.business_id = target_business_id
      and unit_record.warehouse_id = target_warehouse_id
      and unit_record.variant_id = target_variant_id
      and unit_record.tracking_mode = variant_tracking_mode
      and unit_record.status = 'in_stock';
    if valid_count <> selected_count then
      raise exception 'One or more selected serial numbers or IMEIs are not in stock in this warehouse';
    end if;
    perform 1
    from public.serialized_inventory_units unit_record
    where unit_record.id = any(selected_ids)
      and unit_record.business_id = target_business_id
    order by unit_record.id
    for update;
  elsif selected_count > 0 then
    raise exception 'Serialized unit selection supplied for a non-serialized SKU';
  end if;

  result := public.record_stock_loss(
    target_business_id,
    target_warehouse_id,
    target_variant_id,
    selected_loss_type,
    loss_quantity,
    loss_reason,
    operation_id,
    loss_notes
  );
  loss_event_id := (result ->> 'stock_loss_event_id')::uuid;
  terminal_status := case selected_loss_type
    when 'damage' then 'damaged'
    else 'wastage'
  end;

  if selected_count > 0 then
    foreach selected_id in array selected_ids loop
      update public.serialized_inventory_units
      set status = terminal_status
      where id = selected_id
        and business_id = target_business_id;
      insert into public.serialized_inventory_unit_events (
        business_id, serialized_unit_id, warehouse_id, event_type,
        status_after, reference_type, reference_id, operation_id, created_by
      ) values (
        target_business_id, selected_id, target_warehouse_id,
        terminal_status, terminal_status, 'stock_loss_event',
        loss_event_id, operation_id, caller_id
      );
      serialized_units_lost := serialized_units_lost + 1;
    end loop;
  end if;

  result := result || jsonb_build_object(
    'serialized_units_lost', serialized_units_lost
  );
  existing_result := result;
  update public.idempotency_records
  set result = existing_result
  where business_id = target_business_id
    and idempotency_records.operation_id = record_stock_loss.operation_id
    and operation_type = 'inventory.loss';
  return result;
end;
$$;

revoke all on function public.record_stock_loss(
  uuid, uuid, uuid, text, numeric, text, uuid, text, jsonb
) from public, anon;
grant execute on function public.record_stock_loss(
  uuid, uuid, uuid, text, numeric, text, uuid, text, jsonb
) to authenticated;
