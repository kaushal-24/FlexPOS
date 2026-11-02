-- Link serialized units to sale returns and restore them atomically.

alter table public.sale_return_items
  add constraint sale_return_items_id_business_unique unique (id, business_id);

create table public.sale_return_item_serialized_units (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  return_item_id uuid not null,
  serialized_unit_id uuid not null,
  created_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, serialized_unit_id),
  unique (return_item_id, serialized_unit_id),
  constraint sale_return_item_serialized_units_return_item_fkey
    foreign key (return_item_id, business_id)
    references public.sale_return_items(id, business_id) on delete restrict,
  constraint sale_return_item_serialized_units_unit_fkey
    foreign key (serialized_unit_id, business_id)
    references public.serialized_inventory_units(id, business_id) on delete restrict
);

create index sale_return_item_serialized_units_return_item_idx
  on public.sale_return_item_serialized_units(return_item_id, business_id);
create index sale_return_item_serialized_units_unit_idx
  on public.sale_return_item_serialized_units(serialized_unit_id, business_id);

create trigger sale_return_item_serialized_units_immutable
before update or delete on public.sale_return_item_serialized_units
for each row execute function private.prevent_immutable_change();

alter table public.sale_return_item_serialized_units enable row level security;

create policy sale_return_item_serialized_units_select
on public.sale_return_item_serialized_units for select to authenticated
using (
  exists (
    select 1
    from public.sale_return_items sri
    join public.sale_returns sr
      on sr.id = sri.return_id
     and sr.business_id = sri.business_id
    where sri.id = sale_return_item_serialized_units.return_item_id
      and sri.business_id = sale_return_item_serialized_units.business_id
      and private.has_permission(sr.business_id, 'sales.view')
      and private.has_branch_access(sr.branch_id)
  )
);

grant select on public.sale_return_item_serialized_units to authenticated;
revoke all on public.sale_return_item_serialized_units from anon;

create or replace function public.process_sale_return(
  target_sale_id uuid,
  operation_id uuid,
  return_lines jsonb,
  serialized_unit_ids jsonb,
  refund_method text,
  return_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  sale_record public.sales%rowtype;
  sale_item_record record;
  variant_tracking_mode text;
  selected_units jsonb;
  unit_ids uuid[];
  item record;
  unit_id uuid;
  unit_count integer;
  linked_count integer;
  sold_count integer;
  already_returned_count integer;
  return_item_id uuid;
  return_result jsonb;
  v_return_id uuid;
  returned_count integer := 0;
  existing_result jsonb;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if serialized_unit_ids is null then
    serialized_unit_ids := '{}'::jsonb;
  end if;
  if jsonb_typeof(serialized_unit_ids) <> 'object' then
    raise exception 'Serialized unit selections must be an object';
  end if;

  select * into sale_record
  from public.sales
  where id = target_sale_id
  for update;
  if not found then raise exception 'Sale not found'; end if;

  select result into existing_result
  from public.idempotency_records
  where business_id = sale_record.business_id
    and idempotency_records.operation_id = process_sale_return.operation_id
    and operation_type = 'sale.return';
  if existing_result is not null and existing_result <> '{}'::jsonb then
    return existing_result;
  end if;

  if jsonb_typeof(return_lines) <> 'array' or jsonb_array_length(return_lines) = 0 then
    raise exception 'At least one return line is required';
  end if;

  if exists (
    select 1
    from jsonb_object_keys(serialized_unit_ids) as keys(key)
    where not exists (
      select 1
      from jsonb_to_recordset(return_lines) as lines(sale_item_id uuid, quantity numeric, restock boolean)
      where lines.sale_item_id::text = keys.key
    )
  ) then
    raise exception 'Serialized unit selection contains an item that is not being returned';
  end if;

  for item in
    select *
    from jsonb_to_recordset(return_lines) as x(
      sale_item_id uuid, quantity numeric, restock boolean
    )
    order by sale_item_id
  loop
    if item.sale_item_id is null or item.quantity is null or item.quantity <= 0 then
      raise exception 'Invalid return line';
    end if;

    select si.*
    into sale_item_record
    from public.sale_items si
    join public.product_variants pv
      on pv.id = si.variant_id
     and pv.business_id = sale_record.business_id
    where si.id = item.sale_item_id
      and si.sale_id = sale_record.id
      and si.business_id = sale_record.business_id;
    if not found then raise exception 'Sale item is not part of this sale'; end if;
    select pv.tracking_mode
    into variant_tracking_mode
    from public.product_variants pv
    where pv.id = sale_item_record.variant_id
      and pv.business_id = sale_record.business_id;

    if variant_tracking_mode in ('serial', 'imei') then
      if coalesce(item.restock, true) is not true then
        raise exception 'Serialized returns must be restocked';
      end if;
      if item.quantity <> trunc(item.quantity) then
        raise exception 'Serialized return quantity must be a whole number for SKU %', sale_item_record.sku;
      end if;
      selected_units := serialized_unit_ids -> item.sale_item_id::text;
      if jsonb_typeof(selected_units) <> 'array' then
        raise exception 'Select one serial number or IMEI for every returned unit of SKU %', sale_item_record.sku;
      end if;
      unit_count := jsonb_array_length(selected_units);
      if unit_count <> item.quantity::integer then
        raise exception 'Select exactly % serial number(s) or IMEI(s) for SKU %', item.quantity::integer, sale_item_record.sku;
      end if;
      select array_agg(value::uuid) into unit_ids
      from jsonb_array_elements_text(selected_units) as values(value);
      if unit_ids is null or array_length(unit_ids, 1) <> unit_count then
        raise exception 'Invalid serialized unit selection for SKU %', sale_item_record.sku;
      end if;
      select count(*) into linked_count
      from public.sale_item_serialized_units link
      where link.business_id = sale_record.business_id
        and link.sale_item_id = sale_item_record.id
        and link.serialized_unit_id = any(unit_ids);
      if linked_count <> unit_count then
        raise exception 'One or more selected serial numbers or IMEIs do not belong to this sale line';
      end if;
      select count(*) into sold_count
      from public.sale_item_serialized_units link
      join public.serialized_inventory_units unit_record
        on unit_record.id = link.serialized_unit_id
       and unit_record.business_id = link.business_id
      where link.business_id = sale_record.business_id
        and link.sale_item_id = sale_item_record.id
        and link.serialized_unit_id = any(unit_ids)
        and unit_record.status = 'sold';
      if sold_count <> unit_count then
        raise exception 'One or more selected serial numbers or IMEIs are not currently sold';
      end if;
      select count(*) into already_returned_count
      from public.sale_return_item_serialized_units returned_unit
      where returned_unit.business_id = sale_record.business_id
        and returned_unit.serialized_unit_id = any(unit_ids);
      if already_returned_count > 0 then
        raise exception 'One or more selected serial numbers or IMEIs were already returned';
      end if;
      perform 1
      from public.serialized_inventory_units unit_record
      where unit_record.business_id = sale_record.business_id
        and unit_record.id = any(unit_ids)
      order by unit_record.id
      for update;
    elsif serialized_unit_ids ? item.sale_item_id::text then
      raise exception 'Serialized unit selection supplied for a non-serialized SKU %', sale_item_record.sku;
    end if;
  end loop;

  return_result := public.process_sale_return(
    target_sale_id,
    operation_id,
    return_lines,
    refund_method,
    return_reason
  );
  v_return_id := (return_result ->> 'return_id')::uuid;

  for item in
    select *
    from jsonb_to_recordset(return_lines) as x(
      sale_item_id uuid, quantity numeric, restock boolean
    )
    order by sale_item_id
  loop
    selected_units := serialized_unit_ids -> item.sale_item_id::text;
    if jsonb_typeof(selected_units) <> 'array' then continue; end if;
    select array_agg(value::uuid) into unit_ids
    from jsonb_array_elements_text(selected_units) as values(value);
    select sri.id into return_item_id
    from public.sale_return_items sri
    where sri.return_id = v_return_id
      and sri.business_id = sale_record.business_id
      and sri.sale_item_id = item.sale_item_id;
    if return_item_id is null then
      raise exception 'Return line was not created for serialized sale item';
    end if;

    foreach unit_id in array unit_ids loop
      insert into public.sale_return_item_serialized_units (
        business_id, return_item_id, serialized_unit_id
      ) values (
        sale_record.business_id, return_item_id, unit_id
      );
      update public.serialized_inventory_units
      set status = 'in_stock'
      where id = unit_id
        and business_id = sale_record.business_id;
      insert into public.serialized_inventory_unit_events (
        business_id, serialized_unit_id, warehouse_id, event_type,
        status_after, reference_type, reference_id, operation_id, created_by
      )
      select sale_record.business_id, unit_id, unit_record.warehouse_id,
        'returned', 'in_stock', 'sale_return', v_return_id, operation_id, caller_id
      from public.serialized_inventory_units unit_record
      where unit_record.id = unit_id
        and unit_record.business_id = sale_record.business_id;
      returned_count := returned_count + 1;
    end loop;
  end loop;

  return_result := return_result || jsonb_build_object(
    'serialized_units_returned', returned_count
  );
  update public.idempotency_records
  set result = return_result
  where business_id = sale_record.business_id
    and idempotency_records.operation_id = process_sale_return.operation_id
    and operation_type = 'sale.return';
  return return_result;
end;
$$;

revoke all on function public.process_sale_return(uuid, uuid, jsonb, jsonb, text, text)
  from public, anon, authenticated;
grant execute on function public.process_sale_return(uuid, uuid, jsonb, jsonb, text, text)
  to authenticated;
