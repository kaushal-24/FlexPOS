-- Allocate selected serialized units as part of POS sale completion.

create or replace function public.complete_sale(
  target_business_id uuid,
  target_branch_id uuid,
  target_register_id uuid,
  target_shift_id uuid,
  target_customer_id uuid,
  operation_id uuid,
  line_items jsonb,
  payment_lines jsonb,
  order_discount numeric default 0,
  sale_notes text default null,
  serialized_unit_ids jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  result jsonb;
  sale_id uuid;
  item record;
  unit_id uuid;
  unit_record public.serialized_inventory_units%rowtype;
  sale_item_id uuid;
  tracking_mode text;
  identifiers jsonb;
  identifier_count integer;
  linked_count integer;
  seen_ids uuid[] := array[]::uuid[];
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if serialized_unit_ids is null then
    serialized_unit_ids := '{}'::jsonb;
  end if;
  if jsonb_typeof(serialized_unit_ids) <> 'object' then
    raise exception 'Serialized unit selections must be an object';
  end if;

  result := public.complete_sale(
    target_business_id, target_branch_id, target_register_id,
    target_shift_id, target_customer_id, operation_id, line_items,
    payment_lines, order_discount, sale_notes
  );
  sale_id := (result ->> 'sale_id')::uuid;

  for item in
    select x.variant_id, x.warehouse_id, x.quantity
    from jsonb_to_recordset(line_items) as x(
      variant_id uuid, warehouse_id uuid, quantity numeric
    )
  loop
    identifiers := serialized_unit_ids -> item.variant_id::text;
    select v.tracking_mode into tracking_mode
    from public.product_variants v
    where v.id = item.variant_id and v.business_id = target_business_id;
    if not found then raise exception 'Sale variant is unavailable'; end if;

    if identifiers is null then
      if tracking_mode <> 'none' then
        raise exception 'Serialized SKU requires selected inventory units';
      end if;
      continue;
    end if;
    if jsonb_typeof(identifiers) <> 'array' then
      raise exception 'Selected serialized units must be an array';
    end if;
    identifier_count := jsonb_array_length(identifiers);
    if tracking_mode = 'none' then
      if identifier_count > 0 then
        raise exception 'Non-serialized SKU cannot include inventory units';
      end if;
      continue;
    end if;
    if item.quantity <> trunc(item.quantity)
       or identifier_count <> item.quantity then
      raise exception 'Serialized SKU requires exactly one selected unit per item';
    end if;

    select count(*) into linked_count
    from public.sale_items si
    where si.sale_id = sale_id and si.variant_id = item.variant_id;
    if linked_count <> 1 then
      raise exception 'Serialized SKU must appear exactly once in a sale';
    end if;
    select si.id into sale_item_id
    from public.sale_items si
    where si.sale_id = sale_id and si.variant_id = item.variant_id;

    for unit_id in
      select value::uuid from jsonb_array_elements_text(identifiers)
    loop
      if unit_id = any(seen_ids) then
        raise exception 'A serialized inventory unit cannot be selected twice';
      end if;
      seen_ids := array_append(seen_ids, unit_id);

      select * into unit_record
      from public.serialized_inventory_units u
      where u.id = unit_id
        and u.business_id = target_business_id
      for update;
      if not found then raise exception 'Selected serialized unit was not found'; end if;
      if unit_record.variant_id <> item.variant_id
         or unit_record.warehouse_id <> item.warehouse_id then
        raise exception 'Selected serialized unit does not match the sale line';
      end if;
      if unit_record.tracking_mode <> tracking_mode then
        raise exception 'Selected serialized unit tracking mode does not match';
      end if;
      if unit_record.status <> 'in_stock' then
        raise exception 'Selected serialized unit is no longer in stock';
      end if;

      update public.serialized_inventory_units
      set status = 'sold'
      where id = unit_id and business_id = target_business_id;
      insert into public.sale_item_serialized_units (
        business_id, sale_item_id, serialized_unit_id
      ) values (target_business_id, sale_item_id, unit_id);
      insert into public.serialized_inventory_unit_events (
        business_id, serialized_unit_id, warehouse_id, event_type,
        status_after, reference_type, reference_id, operation_id, created_by
      ) values (
        target_business_id, unit_id, item.warehouse_id, 'sold', 'sold',
        'sale', sale_id, operation_id, caller_id
      );
    end loop;
  end loop;
  return result || jsonb_build_object('serialized_units_sold', cardinality(seen_ids));
end;
$$;

revoke all on function public.complete_sale(
  uuid, uuid, uuid, uuid, uuid, uuid, jsonb, jsonb, numeric, text, jsonb
) from public, anon;
grant execute on function public.complete_sale(
  uuid, uuid, uuid, uuid, uuid, uuid, jsonb, jsonb, numeric, text, jsonb
) to authenticated;
