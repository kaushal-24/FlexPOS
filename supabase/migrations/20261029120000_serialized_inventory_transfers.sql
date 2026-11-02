-- Atomic warehouse transfers for quantity and serialized/IMEI inventory.
-- A transfer is completed in one transaction; serialized units keep their
-- immutable transfer event while moving to the destination warehouse.

create table public.inventory_transfers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  source_warehouse_id uuid not null,
  destination_warehouse_id uuid not null,
  variant_id uuid not null,
  transfer_number text not null,
  status text not null default 'completed' check (status = 'completed'),
  quantity numeric(20,6) not null check (quantity > 0),
  reason text not null check (length(btrim(reason)) between 3 and 500),
  notes text,
  operation_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, transfer_number),
  unique (business_id, operation_id),
  constraint inventory_transfers_source_fkey foreign key (source_warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete restrict,
  constraint inventory_transfers_destination_fkey foreign key (destination_warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete restrict,
  constraint inventory_transfers_variant_fkey foreign key (variant_id, business_id)
    references public.product_variants(id, business_id) on delete restrict,
  check (source_warehouse_id <> destination_warehouse_id)
);

create table public.inventory_transfer_serialized_units (
  business_id uuid not null references public.businesses(id) on delete cascade,
  transfer_id uuid not null,
  serialized_unit_id uuid not null,
  identifier text not null,
  source_warehouse_id uuid not null,
  destination_warehouse_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (transfer_id, serialized_unit_id),
  unique (business_id, transfer_id, identifier),
  constraint inventory_transfer_serialized_transfer_fkey
    foreign key (transfer_id, business_id)
    references public.inventory_transfers(id, business_id) on delete cascade,
  constraint inventory_transfer_serialized_unit_fkey
    foreign key (serialized_unit_id, business_id)
    references public.serialized_inventory_units(id, business_id) on delete restrict,
  constraint inventory_transfer_serialized_source_fkey
    foreign key (source_warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete restrict,
  constraint inventory_transfer_serialized_destination_fkey
    foreign key (destination_warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete restrict
);

create index inventory_transfers_business_created_idx
  on public.inventory_transfers(business_id, created_at desc);
create index inventory_transfers_source_created_idx
  on public.inventory_transfers(source_warehouse_id, created_at desc);
create index inventory_transfers_destination_created_idx
  on public.inventory_transfers(destination_warehouse_id, created_at desc);
create index inventory_transfer_serialized_units_unit_idx
  on public.inventory_transfer_serialized_units(serialized_unit_id, created_at desc);

create trigger inventory_transfers_immutable
before update or delete on public.inventory_transfers
for each row execute function private.prevent_immutable_change();

create trigger inventory_transfer_serialized_units_immutable
before update or delete on public.inventory_transfer_serialized_units
for each row execute function private.prevent_immutable_change();

alter table public.inventory_transfers enable row level security;
alter table public.inventory_transfer_serialized_units enable row level security;

create policy inventory_transfers_select
on public.inventory_transfers for select to authenticated
using (
  (select private.has_permission(business_id, 'inventory.view'))
  and (
    (select private.can_access_warehouse(source_warehouse_id))
    or (select private.can_access_warehouse(destination_warehouse_id))
  )
);

create policy inventory_transfer_serialized_units_select
on public.inventory_transfer_serialized_units for select to authenticated
using (
  exists (
    select 1
    from public.inventory_transfers t
    where t.id = transfer_id
      and t.business_id = inventory_transfer_serialized_units.business_id
      and (select private.has_permission(t.business_id, 'inventory.view'))
      and (
        (select private.can_access_warehouse(t.source_warehouse_id))
        or (select private.can_access_warehouse(t.destination_warehouse_id))
      )
  )
);

grant select on public.inventory_transfers,
  public.inventory_transfer_serialized_units to authenticated;
revoke all on public.inventory_transfers,
  public.inventory_transfer_serialized_units from anon;

create or replace function public.execute_inventory_transfer(
  target_business_id uuid,
  target_source_warehouse_id uuid,
  target_destination_warehouse_id uuid,
  target_variant_id uuid,
  transfer_quantity numeric,
  transfer_reason text,
  operation_id uuid,
  transfer_notes text default null,
  serialized_unit_ids jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  variant_record record;
  source_balance public.inventory_balances%rowtype;
  destination_balance public.inventory_balances%rowtype;
  selected_ids uuid[] := array[]::uuid[];
  selected_count integer := 0;
  normalized_quantity numeric(20,6);
  source_after numeric(20,6);
  destination_after numeric(20,6);
  transfer_id uuid := gen_random_uuid();
  transfer_no text;
  existing_result jsonb;
  inserted_count integer;
  source_cost numeric(18,4);
  destination_cost numeric(18,4);
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if target_source_warehouse_id = target_destination_warehouse_id then
    raise exception 'Source and destination warehouses must be different';
  end if;
  if transfer_quantity is null or transfer_quantity <= 0 then
    raise exception 'Transfer quantity must be positive';
  end if;
  if length(btrim(coalesce(transfer_reason, ''))) < 3 then
    raise exception 'A meaningful transfer reason is required';
  end if;
  if length(btrim(transfer_reason)) > 500 then
    raise exception 'Transfer reason cannot exceed 500 characters';
  end if;
  if serialized_unit_ids is null or jsonb_typeof(serialized_unit_ids) <> 'array' then
    raise exception 'Serialized unit IDs must be a JSON array';
  end if;
  if not private.has_permission(target_business_id, 'inventory.manage') then
    raise exception 'You do not have permission to transfer inventory';
  end if;
  if not exists (
    select 1 from public.warehouses w
    where w.id = target_source_warehouse_id and w.business_id = target_business_id
      and w.is_active and private.has_branch_access(w.branch_id)
  ) then raise exception 'Source warehouse is not accessible'; end if;
  if not exists (
    select 1 from public.warehouses w
    where w.id = target_destination_warehouse_id and w.business_id = target_business_id
      and w.is_active and private.has_branch_access(w.branch_id)
  ) then raise exception 'Destination warehouse is not accessible'; end if;

  select v.id, v.name as variant_name, v.sku, v.tracking_mode,
         p.name as product_name, p.allow_fractional_quantity
  into variant_record
  from public.product_variants v
  join public.products p on p.id = v.product_id and p.business_id = v.business_id
  where v.id = target_variant_id and v.business_id = target_business_id
    and v.is_active and v.archived_at is null
    and p.is_active and p.archived_at is null and p.track_inventory;
  if not found then raise exception 'Variant is not stock tracked or is inactive'; end if;

  normalized_quantity := round(transfer_quantity, 6);
  if not variant_record.allow_fractional_quantity
     and normalized_quantity <> trunc(normalized_quantity) then
    raise exception 'Fractional quantity is not allowed for SKU %', variant_record.sku;
  end if;

  if jsonb_array_length(serialized_unit_ids) > 0 then
    select coalesce(array_agg(value::uuid), array[]::uuid[])
    into selected_ids
    from jsonb_array_elements_text(serialized_unit_ids) as values(value);
  end if;
  select coalesce(array_length(selected_ids, 1), 0) into selected_count;
  if variant_record.tracking_mode in ('serial', 'imei') then
    if normalized_quantity <> trunc(normalized_quantity) then
      raise exception 'Serialized transfer quantity must be a whole number';
    end if;
    if selected_count <> normalized_quantity::integer then
      raise exception 'Select exactly % serialized unit(s)', normalized_quantity::integer;
    end if;
  elsif selected_count > 0 then
    raise exception 'Serialized unit IDs are only valid for serial or IMEI SKUs';
  end if;

  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (
    target_business_id, operation_id, 'inventory.transfer', caller_id
  ) on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select i.result into existing_result
    from public.idempotency_records i
    where i.business_id = target_business_id
      and i.operation_id = execute_inventory_transfer.operation_id
      and i.operation_type = 'inventory.transfer';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Inventory transfer is already in progress';
  end if;

  select * into source_balance
  from public.inventory_balances b
  where b.warehouse_id = target_source_warehouse_id and b.variant_id = target_variant_id
  for update;
  if not found then raise exception 'No source inventory balance exists for SKU %', variant_record.sku; end if;
  if source_balance.quantity_on_hand - source_balance.quantity_reserved < normalized_quantity then
    raise exception 'Transfer exceeds available stock for SKU %', variant_record.sku;
  end if;
  source_cost := source_balance.average_cost;

  insert into public.inventory_balances (business_id, warehouse_id, variant_id)
  values (target_business_id, target_destination_warehouse_id, target_variant_id)
  on conflict (warehouse_id, variant_id) do nothing;
  select * into destination_balance
  from public.inventory_balances b
  where b.warehouse_id = target_destination_warehouse_id and b.variant_id = target_variant_id
  for update;
  destination_after := destination_balance.quantity_on_hand + normalized_quantity;
  destination_cost := case
    when destination_after = 0 then source_cost
    else round((destination_balance.quantity_on_hand * destination_balance.average_cost
      + normalized_quantity * source_cost) / destination_after, 4)
  end;
  source_after := source_balance.quantity_on_hand - normalized_quantity;

  if variant_record.tracking_mode in ('serial', 'imei') then
    if exists (
      select 1 from public.serialized_inventory_units u
      where u.id = any(selected_ids)
        and (u.business_id <> target_business_id
          or u.variant_id <> target_variant_id
          or u.warehouse_id <> target_source_warehouse_id
          or u.tracking_mode <> variant_record.tracking_mode
          or u.status <> 'in_stock')
    ) or (select count(*) from public.serialized_inventory_units u where u.id = any(selected_ids)) <> selected_count then
      raise exception 'One or more selected serialized units are not available in the source warehouse';
    end if;
    perform 1 from public.serialized_inventory_units u where u.id = any(selected_ids) for update;
  end if;

  transfer_no := 'TRF-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS') || '-'
    || upper(substr(replace(transfer_id::text, '-', ''), 1, 8));
  insert into public.inventory_transfers (
    id, business_id, source_warehouse_id, destination_warehouse_id, variant_id,
    transfer_number, quantity, reason, notes, operation_id, created_by
  ) values (
    transfer_id, target_business_id, target_source_warehouse_id,
    target_destination_warehouse_id, target_variant_id, transfer_no,
    normalized_quantity, btrim(transfer_reason), nullif(btrim(transfer_notes), ''),
    operation_id, caller_id
  );

  insert into public.inventory_movements (
    business_id, warehouse_id, variant_id, movement_type, quantity_delta,
    quantity_before, quantity_after, unit_cost, reference_type, reference_id,
    reason, operation_id, created_by
  ) values
    (target_business_id, target_source_warehouse_id, target_variant_id, 'transfer_out',
     -normalized_quantity, source_balance.quantity_on_hand, source_after, source_cost,
     'inventory_transfer', transfer_id, btrim(transfer_reason), operation_id, caller_id),
    (target_business_id, target_destination_warehouse_id, target_variant_id, 'transfer_in',
     normalized_quantity, destination_balance.quantity_on_hand, destination_after,
     source_cost, 'inventory_transfer', transfer_id, btrim(transfer_reason), operation_id, caller_id);

  update public.inventory_balances
  set quantity_on_hand = source_after, updated_at = now()
  where warehouse_id = target_source_warehouse_id and variant_id = target_variant_id;
  update public.inventory_balances
  set quantity_on_hand = destination_after, average_cost = destination_cost, updated_at = now()
  where warehouse_id = target_destination_warehouse_id and variant_id = target_variant_id;

  if variant_record.tracking_mode in ('serial', 'imei') then
    insert into public.inventory_transfer_serialized_units (
      business_id, transfer_id, serialized_unit_id, identifier,
      source_warehouse_id, destination_warehouse_id
    )
    select target_business_id, transfer_id, u.id, u.identifier,
      target_source_warehouse_id, target_destination_warehouse_id
    from public.serialized_inventory_units u
    where u.id = any(selected_ids);
    update public.serialized_inventory_units
    set warehouse_id = target_destination_warehouse_id, status = 'in_stock'
    where id = any(selected_ids);
    insert into public.serialized_inventory_unit_events (
      business_id, serialized_unit_id, warehouse_id, event_type, status_after,
      reference_type, reference_id, operation_id, created_by
    )
    select target_business_id, u.id, target_destination_warehouse_id,
      'transferred', 'in_stock', 'inventory_transfer', transfer_id,
      operation_id, caller_id
    from public.serialized_inventory_units u
    where u.id = any(selected_ids);
  end if;

  existing_result := jsonb_build_object(
    'transfer_id', transfer_id,
    'transfer_number', transfer_no,
    'quantity', normalized_quantity,
    'serialized_units_transferred', selected_count,
    'source_quantity_after', source_after,
    'destination_quantity_after', destination_after
  );
  update public.idempotency_records i
  set result = existing_result
  where i.business_id = target_business_id
    and i.operation_id = execute_inventory_transfer.operation_id
    and i.operation_type = 'inventory.transfer';
  perform private.write_tenant_audit(
    target_business_id, 'inventory.transferred', 'inventory_transfer', transfer_id::text,
    existing_result || jsonb_build_object(
      'source_warehouse_id', target_source_warehouse_id,
      'destination_warehouse_id', target_destination_warehouse_id,
      'variant_id', target_variant_id,
      'reason', btrim(transfer_reason)
    )
  );
  return existing_result;
end;
$$;

revoke all on function public.execute_inventory_transfer(
  uuid, uuid, uuid, uuid, numeric, text, uuid, text, jsonb
) from public, anon;
grant execute on function public.execute_inventory_transfer(
  uuid, uuid, uuid, uuid, numeric, text, uuid, text, jsonb
) to authenticated;
