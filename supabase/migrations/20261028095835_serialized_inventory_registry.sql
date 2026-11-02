-- Secure registry foundation for serial- and IMEI-tracked inventory.

alter table public.product_variants
add column tracking_mode text not null default 'none'
check (tracking_mode in ('none', 'serial', 'imei'));

create table public.serialized_inventory_units (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  warehouse_id uuid not null,
  variant_id uuid not null,
  tracking_mode text not null check (tracking_mode in ('serial', 'imei')),
  identifier text not null check (length(identifier) between 3 and 120),
  normalized_identifier text not null check (length(normalized_identifier) between 3 and 120),
  status text not null default 'in_stock'
    check (status in (
      'in_stock', 'reserved', 'sold', 'returned', 'damaged', 'wastage',
      'transferred'
    )),
  product_name text not null,
  variant_name text not null,
  sku text not null,
  registered_by uuid not null references auth.users(id) on delete restrict,
  registered_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, normalized_identifier),
  constraint serialized_inventory_units_warehouse_fkey
    foreign key (warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete restrict,
  constraint serialized_inventory_units_variant_fkey
    foreign key (variant_id, business_id)
    references public.product_variants(id, business_id) on delete restrict
);

create table public.serialized_inventory_unit_events (
  id bigint generated always as identity primary key,
  business_id uuid not null references public.businesses(id) on delete cascade,
  serialized_unit_id uuid not null,
  warehouse_id uuid not null,
  event_type text not null check (event_type in (
    'registered', 'reserved', 'sold', 'returned', 'damaged', 'wastage',
    'transferred'
  )),
  status_after text not null check (status_after in (
    'in_stock', 'reserved', 'sold', 'returned', 'damaged', 'wastage',
    'transferred'
  )),
  reference_type text,
  reference_id uuid,
  operation_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (business_id, operation_id, serialized_unit_id, event_type),
  constraint serialized_inventory_unit_events_unit_fkey
    foreign key (serialized_unit_id, business_id)
    references public.serialized_inventory_units(id, business_id) on delete restrict,
  constraint serialized_inventory_unit_events_warehouse_fkey
    foreign key (warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete restrict
);

create index serialized_inventory_units_business_status_idx
  on public.serialized_inventory_units(business_id, status, registered_at desc);
create index serialized_inventory_units_warehouse_business_fk_idx
  on public.serialized_inventory_units(warehouse_id, business_id);
create index serialized_inventory_units_variant_business_fk_idx
  on public.serialized_inventory_units(variant_id, business_id);
create index serialized_inventory_units_registered_by_idx
  on public.serialized_inventory_units(registered_by);
create index serialized_inventory_unit_events_unit_business_fk_idx
  on public.serialized_inventory_unit_events(serialized_unit_id, business_id);
create index serialized_inventory_unit_events_warehouse_business_fk_idx
  on public.serialized_inventory_unit_events(warehouse_id, business_id);
create index serialized_inventory_unit_events_created_by_idx
  on public.serialized_inventory_unit_events(created_by);

create trigger serialized_inventory_unit_events_immutable
before update or delete on public.serialized_inventory_unit_events
for each row execute function private.prevent_immutable_change();

alter table public.serialized_inventory_units enable row level security;
alter table public.serialized_inventory_unit_events enable row level security;

create policy serialized_inventory_units_select
on public.serialized_inventory_units for select to authenticated
using (
  (select private.has_permission(business_id, 'inventory.view'))
  and (select private.can_access_warehouse(warehouse_id))
);

create policy serialized_inventory_unit_events_select
on public.serialized_inventory_unit_events for select to authenticated
using (
  (select private.has_permission(business_id, 'inventory.view'))
  and (select private.can_access_warehouse(warehouse_id))
);

grant select on public.serialized_inventory_units to authenticated;
grant select on public.serialized_inventory_unit_events to authenticated;
revoke all on public.serialized_inventory_units from anon;
revoke all on public.serialized_inventory_unit_events from anon;

create or replace function public.register_serialized_inventory(
  target_business_id uuid,
  target_warehouse_id uuid,
  target_variant_id uuid,
  selected_tracking_mode text,
  identifiers text[],
  operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  variant_record record;
  balance_record public.inventory_balances%rowtype;
  normalized_identifiers text[] := array[]::text[];
  raw_identifier text;
  normalized_identifier text;
  display_identifier text;
  new_unit_id uuid;
  registered_count integer := 0;
  existing_count integer;
  inserted_count integer;
  existing_result jsonb;
begin
  if caller_id is null then
    raise exception 'Authentication required';
  end if;
  if operation_id is null then
    raise exception 'Operation ID is required';
  end if;
  if selected_tracking_mode is null
     or selected_tracking_mode not in ('serial', 'imei') then
    raise exception 'Tracking mode must be serial or IMEI';
  end if;
  if coalesce(array_length(identifiers, 1), 0) = 0 then
    raise exception 'At least one identifier is required';
  end if;
  if array_length(identifiers, 1) > 500 then
    raise exception 'No more than 500 identifiers can be registered at once';
  end if;
  if not private.has_permission(target_business_id, 'inventory.manage') then
    raise exception 'You do not have permission to register serialized inventory';
  end if;
  if not exists (
    select 1
    from public.warehouses w
    where w.id = target_warehouse_id
      and w.business_id = target_business_id
      and w.is_active
      and private.has_branch_access(w.branch_id)
  ) then
    raise exception 'Warehouse is not accessible';
  end if;

  select v.id, v.name as variant_name, v.sku, v.tracking_mode,
         p.name as product_name, p.allow_fractional_quantity
  into variant_record
  from public.product_variants v
  join public.products p
    on p.id = v.product_id and p.business_id = v.business_id
  where v.id = target_variant_id
    and v.business_id = target_business_id
    and v.is_active
    and v.archived_at is null
    and p.is_active
    and p.archived_at is null
    and p.track_inventory;
  if not found then
    raise exception 'Variant is not stock tracked or is inactive';
  end if;
  if variant_record.allow_fractional_quantity then
    raise exception 'Serialized tracking is not available for fractional SKU %',
      variant_record.sku;
  end if;
  if variant_record.tracking_mode <> 'none'
     and variant_record.tracking_mode <> selected_tracking_mode then
    raise exception 'SKU % already uses % tracking',
      variant_record.sku, upper(variant_record.tracking_mode);
  end if;

  foreach raw_identifier in array identifiers loop
    display_identifier := btrim(coalesce(raw_identifier, ''));
    normalized_identifier := case selected_tracking_mode
      when 'imei' then regexp_replace(display_identifier, '[^0-9]', '', 'g')
      else upper(display_identifier)
    end;
    if selected_tracking_mode = 'imei' then
      display_identifier := normalized_identifier;
      if normalized_identifier !~ '^[0-9]{15}$' then
        raise exception 'Every IMEI must contain exactly 15 digits';
      end if;
    elsif length(normalized_identifier) not between 3 and 120 then
      raise exception 'Every serial number must contain 3 to 120 characters';
    end if;
    if normalized_identifier = any(normalized_identifiers) then
      raise exception 'Duplicate identifier in request: %', display_identifier;
    end if;
    normalized_identifiers := array_append(
      normalized_identifiers,
      normalized_identifier
    );
  end loop;

  if exists (
    select 1
    from public.serialized_inventory_units u
    where u.business_id = target_business_id
      and u.normalized_identifier = any(normalized_identifiers)
  ) then
    raise exception 'One or more serial numbers or IMEIs are already registered';
  end if;

  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (
    target_business_id, operation_id, 'inventory.serial.register', caller_id
  )
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select result into existing_result
    from public.idempotency_records i
    where i.business_id = target_business_id
      and i.operation_id = register_serialized_inventory.operation_id
      and i.operation_type = 'inventory.serial.register';
    if existing_result <> '{}'::jsonb then
      return existing_result;
    end if;
    raise exception 'Serialized inventory registration is already in progress';
  end if;

  select * into balance_record
  from public.inventory_balances b
  where b.warehouse_id = target_warehouse_id
    and b.variant_id = target_variant_id
  for update;
  if not found then
    raise exception 'No inventory balance exists for SKU %', variant_record.sku;
  end if;
  if balance_record.quantity_on_hand <> trunc(balance_record.quantity_on_hand) then
    raise exception 'Serialized SKU % must have a whole-number stock balance',
      variant_record.sku;
  end if;
  select count(*) into existing_count
  from public.serialized_inventory_units u
  where u.business_id = target_business_id
    and u.warehouse_id = target_warehouse_id
    and u.variant_id = target_variant_id
    and u.status in ('in_stock', 'reserved');
  if existing_count + array_length(normalized_identifiers, 1)
     > balance_record.quantity_on_hand then
    raise exception 'Registration exceeds on-hand stock for SKU %',
      variant_record.sku;
  end if;

  update public.product_variants
  set tracking_mode = selected_tracking_mode,
      updated_at = now()
  where id = target_variant_id
    and business_id = target_business_id
    and tracking_mode = 'none';

  foreach normalized_identifier in array normalized_identifiers loop
    new_unit_id := gen_random_uuid();
    display_identifier := case selected_tracking_mode
      when 'imei' then normalized_identifier
      else (
        select btrim(value)
        from unnest(identifiers) as supplied(value)
        where upper(btrim(value)) = normalized_identifier
        limit 1
      )
    end;
    insert into public.serialized_inventory_units (
      id, business_id, warehouse_id, variant_id, tracking_mode, identifier,
      normalized_identifier, product_name, variant_name, sku, registered_by
    ) values (
      new_unit_id, target_business_id, target_warehouse_id, target_variant_id,
      selected_tracking_mode, display_identifier, normalized_identifier,
      variant_record.product_name, variant_record.variant_name,
      variant_record.sku, caller_id
    );
    insert into public.serialized_inventory_unit_events (
      business_id, serialized_unit_id, warehouse_id, event_type, status_after,
      reference_type, reference_id, operation_id, created_by
    ) values (
      target_business_id, new_unit_id, target_warehouse_id, 'registered',
      'in_stock', 'inventory_registration', null, operation_id, caller_id
    );
    registered_count := registered_count + 1;
  end loop;

  existing_result := jsonb_build_object(
    'tracking_mode', selected_tracking_mode,
    'variant_id', target_variant_id,
    'warehouse_id', target_warehouse_id,
    'identifiers_registered', registered_count
  );
  update public.idempotency_records
  set result = existing_result
  where business_id = target_business_id
    and idempotency_records.operation_id = register_serialized_inventory.operation_id
    and operation_type = 'inventory.serial.register';
  perform private.write_tenant_audit(
    target_business_id,
    'inventory.serialized_inventory_registered',
    'product_variant',
    target_variant_id::text,
    existing_result
  );
  return existing_result;
end;
$$;

revoke all on function public.register_serialized_inventory(
  uuid, uuid, uuid, text, text[], uuid
) from public, anon;
grant execute on function public.register_serialized_inventory(
  uuid, uuid, uuid, text, text[], uuid
) to authenticated;
