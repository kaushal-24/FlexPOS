-- Capture serial numbers and IMEIs atomically with purchase receipts.

create index serialized_inventory_unit_events_receipt_reference_idx
  on public.serialized_inventory_unit_events(business_id, reference_id)
  where reference_type = 'goods_receipt';

create or replace function public.receive_purchase_order(
  target_purchase_order_id uuid,
  operation_id uuid,
  received_items jsonb,
  supplier_document_reference text default null,
  receipt_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  order_record public.purchase_orders%rowtype;
  order_item public.purchase_order_items%rowtype;
  balance_record public.inventory_balances%rowtype;
  variant_record record;
  item record;
  receipt_id uuid := gen_random_uuid();
  receipt_no text;
  next_quantity numeric(20,6);
  next_average_cost numeric(18,4);
  receipt_total numeric(18,2) := 0;
  remaining_lines integer;
  existing_result jsonb;
  inserted_count integer;
  existing_serial_count integer;
  serialized_units_registered integer := 0;
  raw_identifier text;
  display_identifier text;
  normalized_identifier text;
  line_identifiers text[];
  request_identifiers text[] := array[]::text[];
  new_unit_id uuid;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if jsonb_typeof(received_items) <> 'array'
     or jsonb_array_length(received_items) = 0 then
    raise exception 'At least one received item is required';
  end if;
  if (
    select count(*) <> count(distinct x.purchase_order_item_id)
    from jsonb_to_recordset(received_items) as x(purchase_order_item_id uuid)
  ) then
    raise exception 'Each purchase line may appear only once';
  end if;

  select * into order_record
  from public.purchase_orders
  where id = target_purchase_order_id
  for update;
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

  receipt_no := 'GRN-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS') || '-'
    || upper(substr(replace(receipt_id::text, '-', ''), 1, 8));
  insert into public.goods_receipts (
    id, business_id, purchase_order_id, warehouse_id, receipt_number,
    supplier_document_number, operation_id, notes, received_by
  ) values (
    receipt_id, order_record.business_id, order_record.id,
    order_record.warehouse_id, receipt_no,
    nullif(btrim(supplier_document_reference), ''), operation_id,
    nullif(btrim(receipt_notes), ''), caller_id
  );

  for item in
    select x.purchase_order_item_id, x.quantity, x.identifiers, poi.variant_id
    from jsonb_to_recordset(received_items) as x(
      purchase_order_item_id uuid,
      quantity numeric,
      identifiers jsonb
    )
    join public.purchase_order_items poi
      on poi.id = x.purchase_order_item_id
     and poi.purchase_order_id = target_purchase_order_id
    order by poi.variant_id, poi.id
  loop
    if item.quantity is null or item.quantity <= 0 then
      raise exception 'Received quantity must be positive';
    end if;
    select * into order_item
    from public.purchase_order_items
    where id = item.purchase_order_item_id
      and purchase_order_id = target_purchase_order_id
    for update;
    if not found then raise exception 'Purchase order line not found'; end if;
    if order_item.received_quantity + item.quantity > order_item.ordered_quantity then
      raise exception 'Received quantity exceeds remaining quantity for SKU %',
        order_item.sku;
    end if;

    select v.tracking_mode, p.allow_fractional_quantity
    into variant_record
    from public.product_variants v
    join public.products p
      on p.id = v.product_id and p.business_id = v.business_id
    where v.id = order_item.variant_id
      and v.business_id = order_record.business_id;
    if not found then raise exception 'Product variant not found'; end if;
    if item.quantity <> trunc(item.quantity)
       and not variant_record.allow_fractional_quantity then
      raise exception 'Fractional quantity is not allowed for SKU %',
        order_item.sku;
    end if;

    line_identifiers := array[]::text[];
    if variant_record.tracking_mode = 'none' then
      if item.identifiers is not null
         and item.identifiers <> 'null'::jsonb then
        if jsonb_typeof(item.identifiers) <> 'array'
           or jsonb_array_length(item.identifiers) > 0 then
          raise exception 'SKU % does not use serial or IMEI tracking',
            order_item.sku;
        end if;
      end if;
    else
      if item.quantity <> trunc(item.quantity) then
        raise exception 'Serialized SKU % requires a whole-number quantity',
          order_item.sku;
      end if;
      if jsonb_typeof(item.identifiers) is distinct from 'array' then
        raise exception 'SKU % requires identifiers as an array',
          order_item.sku;
      end if;
      if jsonb_array_length(item.identifiers) <> item.quantity then
        raise exception 'SKU % requires exactly one % for every received unit',
          order_item.sku,
          case variant_record.tracking_mode
            when 'imei' then 'IMEI'
            else 'serial number'
          end;
      end if;
      for raw_identifier in
        select value from jsonb_array_elements_text(item.identifiers)
      loop
        display_identifier := btrim(coalesce(raw_identifier, ''));
        normalized_identifier := case variant_record.tracking_mode
          when 'imei' then regexp_replace(display_identifier, '[^0-9]', '', 'g')
          else upper(display_identifier)
        end;
        if variant_record.tracking_mode = 'imei' then
          display_identifier := normalized_identifier;
          if normalized_identifier !~ '^[0-9]{15}$' then
            raise exception 'Every IMEI must contain exactly 15 digits';
          end if;
        elsif length(normalized_identifier) not between 3 and 120 then
          raise exception 'Every serial number must contain 3 to 120 characters';
        end if;
        if normalized_identifier = any(line_identifiers)
           or normalized_identifier = any(request_identifiers) then
          raise exception 'Duplicate identifier in receipt: %',
            display_identifier;
        end if;
        line_identifiers := array_append(
          line_identifiers,
          normalized_identifier
        );
        request_identifiers := array_append(
          request_identifiers,
          normalized_identifier
        );
      end loop;
      if exists (
        select 1
        from public.serialized_inventory_units u
        where u.business_id = order_record.business_id
          and u.normalized_identifier = any(line_identifiers)
      ) then
        raise exception 'One or more serial numbers or IMEIs are already registered';
      end if;
    end if;

    insert into public.inventory_balances (
      business_id, warehouse_id, variant_id
    ) values (
      order_record.business_id, order_record.warehouse_id, order_item.variant_id
    )
    on conflict (warehouse_id, variant_id) do nothing;
    select * into balance_record
    from public.inventory_balances b
    where b.warehouse_id = order_record.warehouse_id
      and b.variant_id = order_item.variant_id
    for update;
    next_quantity := balance_record.quantity_on_hand + round(item.quantity, 6);
    next_average_cost := case
      when next_quantity = 0 then order_item.unit_cost
      else round(
        ((balance_record.quantity_on_hand * balance_record.average_cost)
          + (item.quantity * order_item.unit_cost)) / next_quantity,
        4
      )
    end;
    if variant_record.tracking_mode <> 'none' then
      select count(*) into existing_serial_count
      from public.serialized_inventory_units u
      where u.business_id = order_record.business_id
        and u.warehouse_id = order_record.warehouse_id
        and u.variant_id = order_item.variant_id
        and u.status in ('in_stock', 'reserved');
      if existing_serial_count + array_length(line_identifiers, 1)
         > next_quantity then
        raise exception 'Serialized units exceed on-hand stock for SKU %',
          order_item.sku;
      end if;
    end if;

    update public.inventory_balances
    set quantity_on_hand = next_quantity,
        average_cost = next_average_cost,
        updated_at = now()
    where warehouse_id = order_record.warehouse_id
      and variant_id = order_item.variant_id;
    update public.purchase_order_items
    set received_quantity = received_quantity + round(item.quantity, 6)
    where id = order_item.id;

    insert into public.goods_receipt_items (
      business_id, goods_receipt_id, purchase_order_item_id, variant_id,
      quantity, unit_cost, line_total
    ) values (
      order_record.business_id, receipt_id, order_item.id, order_item.variant_id,
      round(item.quantity, 6), order_item.unit_cost,
      round(item.quantity * order_item.unit_cost, 2)
    );
    insert into public.inventory_movements (
      business_id, warehouse_id, variant_id, movement_type, quantity_delta,
      quantity_before, quantity_after, unit_cost, reference_type, reference_id,
      reason, operation_id, created_by
    ) values (
      order_record.business_id, order_record.warehouse_id, order_item.variant_id,
      'purchase', round(item.quantity, 6), balance_record.quantity_on_hand,
      next_quantity, order_item.unit_cost, 'goods_receipt', receipt_id,
      'Purchase receipt', operation_id, caller_id
    );

    if variant_record.tracking_mode <> 'none' then
      for raw_identifier in
        select value from jsonb_array_elements_text(item.identifiers)
      loop
        display_identifier := btrim(raw_identifier);
        normalized_identifier := case variant_record.tracking_mode
          when 'imei' then regexp_replace(display_identifier, '[^0-9]', '', 'g')
          else upper(display_identifier)
        end;
        if variant_record.tracking_mode = 'imei' then
          display_identifier := normalized_identifier;
        end if;
        new_unit_id := gen_random_uuid();
        insert into public.serialized_inventory_units (
          id, business_id, warehouse_id, variant_id, tracking_mode, identifier,
          normalized_identifier, product_name, variant_name, sku, registered_by
        )
        select new_unit_id, order_record.business_id,
          order_record.warehouse_id, v.id, variant_record.tracking_mode,
          display_identifier, normalized_identifier, p.name, v.name, v.sku,
          caller_id
        from public.product_variants v
        join public.products p
          on p.id = v.product_id and p.business_id = v.business_id
        where v.id = order_item.variant_id
          and v.business_id = order_record.business_id;
        insert into public.serialized_inventory_unit_events (
          business_id, serialized_unit_id, warehouse_id, event_type,
          status_after, reference_type, reference_id, operation_id, created_by
        ) values (
          order_record.business_id, new_unit_id, order_record.warehouse_id,
          'registered', 'in_stock', 'goods_receipt', receipt_id, operation_id,
          caller_id
        );
        serialized_units_registered := serialized_units_registered + 1;
      end loop;
    end if;
    receipt_total := receipt_total + round(item.quantity * order_item.unit_cost, 2);
  end loop;

  if not exists (
    select 1
    from public.goods_receipt_items gri
    where gri.goods_receipt_id = receipt_id
  ) then
    raise exception 'No valid purchase order lines were supplied';
  end if;
  update public.goods_receipts
  set total_cost = receipt_total
  where id = receipt_id;
  select count(*) into remaining_lines
  from public.purchase_order_items poi
  where poi.purchase_order_id = order_record.id
    and poi.received_quantity < poi.ordered_quantity;
  update public.purchase_orders
  set status = case
        when remaining_lines = 0 then 'received'
        else 'partially_received'
      end,
      completed_at = case when remaining_lines = 0 then now() else null end
  where id = order_record.id;

  existing_result := jsonb_build_object(
    'goods_receipt_id', receipt_id,
    'receipt_number', receipt_no,
    'received_total', receipt_total,
    'serialized_units_registered', serialized_units_registered,
    'purchase_status', case
      when remaining_lines = 0 then 'received'
      else 'partially_received'
    end
  );
  update public.idempotency_records
  set result = existing_result
  where business_id = order_record.business_id
    and idempotency_records.operation_id = receive_purchase_order.operation_id
    and operation_type = 'purchase.receive';
  perform private.write_tenant_audit(
    order_record.business_id,
    'purchase_order.received',
    'goods_receipt',
    receipt_id::text,
    existing_result
  );
  return existing_result;
end;
$$;

revoke all on function public.receive_purchase_order(
  uuid, uuid, jsonb, text, text
) from public, anon;
grant execute on function public.receive_purchase_order(
  uuid, uuid, jsonb, text, text
) to authenticated;
