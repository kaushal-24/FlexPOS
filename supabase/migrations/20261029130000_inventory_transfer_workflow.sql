-- Staged inventory transfer workflow.
-- Requests reserve source stock, approvals and dispatches change workflow state,
-- and receipt atomically moves stock to the destination warehouse.

alter table public.serialized_inventory_unit_events
  drop constraint serialized_inventory_unit_events_event_type_check;
alter table public.serialized_inventory_unit_events
  add constraint serialized_inventory_unit_events_event_type_check
  check (event_type in (
    'registered', 'reserved', 'released', 'sold', 'returned', 'damaged',
    'wastage', 'transferred'
  ));

create table public.inventory_transfer_requests (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  source_warehouse_id uuid not null,
  destination_warehouse_id uuid not null,
  variant_id uuid not null,
  request_number text not null,
  status text not null default 'requested'
    check (status in ('requested', 'approved', 'dispatched', 'received', 'cancelled')),
  quantity numeric(20,6) not null check (quantity > 0),
  reason text not null check (length(btrim(reason)) between 3 and 500),
  notes text,
  operation_id uuid not null,
  requested_by uuid not null references auth.users(id) on delete restrict,
  approved_by uuid references auth.users(id) on delete restrict,
  dispatched_by uuid references auth.users(id) on delete restrict,
  received_by uuid references auth.users(id) on delete restrict,
  requested_at timestamptz not null default now(),
  approved_at timestamptz,
  dispatched_at timestamptz,
  received_at timestamptz,
  created_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, request_number),
  unique (business_id, operation_id),
  constraint inventory_transfer_requests_source_fkey
    foreign key (source_warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete restrict,
  constraint inventory_transfer_requests_destination_fkey
    foreign key (destination_warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete restrict,
  constraint inventory_transfer_requests_variant_fkey
    foreign key (variant_id, business_id)
    references public.product_variants(id, business_id) on delete restrict,
  check (source_warehouse_id <> destination_warehouse_id),
  check ((status = 'requested' and approved_at is null and dispatched_at is null and received_at is null)
    or (status = 'approved' and approved_at is not null and dispatched_at is null and received_at is null)
    or (status = 'dispatched' and approved_at is not null and dispatched_at is not null and received_at is null)
    or (status = 'received' and approved_at is not null and dispatched_at is not null and received_at is not null)
    or (status = 'cancelled' and received_at is null))
);

create table public.inventory_transfer_request_serialized_units (
  business_id uuid not null references public.businesses(id) on delete cascade,
  request_id uuid not null,
  serialized_unit_id uuid not null,
  identifier text not null,
  source_warehouse_id uuid not null,
  destination_warehouse_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (request_id, serialized_unit_id),
  unique (business_id, request_id, identifier),
  constraint inventory_transfer_request_serialized_request_fkey
    foreign key (request_id, business_id)
    references public.inventory_transfer_requests(id, business_id) on delete cascade,
  constraint inventory_transfer_request_serialized_unit_fkey
    foreign key (serialized_unit_id, business_id)
    references public.serialized_inventory_units(id, business_id) on delete restrict,
  constraint inventory_transfer_request_serialized_source_fkey
    foreign key (source_warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete restrict,
  constraint inventory_transfer_request_serialized_destination_fkey
    foreign key (destination_warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete restrict
);

create index inventory_transfer_requests_business_created_idx
  on public.inventory_transfer_requests(business_id, created_at desc);
create index inventory_transfer_requests_status_idx
  on public.inventory_transfer_requests(business_id, status, created_at desc);
create index inventory_transfer_requests_source_idx
  on public.inventory_transfer_requests(source_warehouse_id, created_at desc);
create index inventory_transfer_requests_destination_idx
  on public.inventory_transfer_requests(destination_warehouse_id, created_at desc);
create index inventory_transfer_request_serialized_unit_idx
  on public.inventory_transfer_request_serialized_units(serialized_unit_id, created_at desc);

alter table public.inventory_transfer_requests enable row level security;
alter table public.inventory_transfer_request_serialized_units enable row level security;

create policy inventory_transfer_requests_select
on public.inventory_transfer_requests for select to authenticated
using (
  (select private.has_permission(business_id, 'inventory.view'))
  and (
    (select private.can_access_warehouse(source_warehouse_id))
    or (select private.can_access_warehouse(destination_warehouse_id))
  )
);

create policy inventory_transfer_request_serialized_units_select
on public.inventory_transfer_request_serialized_units for select to authenticated
using (
  exists (
    select 1
    from public.inventory_transfer_requests r
    where r.id = request_id
      and r.business_id = inventory_transfer_request_serialized_units.business_id
      and (select private.has_permission(r.business_id, 'inventory.view'))
      and (
        (select private.can_access_warehouse(r.source_warehouse_id))
        or (select private.can_access_warehouse(r.destination_warehouse_id))
      )
  )
);

grant select on public.inventory_transfer_requests,
  public.inventory_transfer_request_serialized_units to authenticated;
revoke all on public.inventory_transfer_requests,
  public.inventory_transfer_request_serialized_units from anon;

create or replace function public.request_inventory_transfer(
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
  selected_ids uuid[] := array[]::uuid[];
  selected_count integer := 0;
  normalized_quantity numeric(20,6);
  request_id uuid := gen_random_uuid();
  request_no text;
  existing_result jsonb;
  inserted_count integer;
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
    raise exception 'You do not have permission to request an inventory transfer';
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

  insert into public.idempotency_records (business_id, operation_id, operation_type, actor_user_id)
  values (target_business_id, operation_id, 'inventory.transfer.request', caller_id)
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select i.result into existing_result
    from public.idempotency_records i
    where i.business_id = target_business_id
      and i.operation_id = request_inventory_transfer.operation_id
      and i.operation_type = 'inventory.transfer.request';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Transfer request is already in progress';
  end if;

  select * into source_balance
  from public.inventory_balances b
  where b.warehouse_id = target_source_warehouse_id and b.variant_id = target_variant_id
  for update;
  if not found then raise exception 'No source inventory balance exists for SKU %', variant_record.sku; end if;
  if source_balance.quantity_on_hand - source_balance.quantity_reserved < normalized_quantity then
    raise exception 'Transfer exceeds available stock for SKU %', variant_record.sku;
  end if;

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

  request_no := 'TRQ-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS') || '-'
    || upper(substr(replace(request_id::text, '-', ''), 1, 8));
  insert into public.inventory_transfer_requests (
    id, business_id, source_warehouse_id, destination_warehouse_id, variant_id,
    request_number, quantity, reason, notes, operation_id, requested_by
  ) values (
    request_id, target_business_id, target_source_warehouse_id,
    target_destination_warehouse_id, target_variant_id, request_no,
    normalized_quantity, btrim(transfer_reason), nullif(btrim(transfer_notes), ''),
    operation_id, caller_id
  );

  update public.inventory_balances
  set quantity_reserved = quantity_reserved + normalized_quantity, updated_at = now()
  where warehouse_id = target_source_warehouse_id and variant_id = target_variant_id;

  if variant_record.tracking_mode in ('serial', 'imei') then
    insert into public.inventory_transfer_request_serialized_units (
      business_id, request_id, serialized_unit_id, identifier,
      source_warehouse_id, destination_warehouse_id
    )
    select target_business_id, request_id, u.id, u.identifier,
      target_source_warehouse_id, target_destination_warehouse_id
    from public.serialized_inventory_units u
    where u.id = any(selected_ids);
    update public.serialized_inventory_units
    set status = 'reserved'
    where id = any(selected_ids);
    insert into public.serialized_inventory_unit_events (
      business_id, serialized_unit_id, warehouse_id, event_type, status_after,
      reference_type, reference_id, operation_id, created_by
    )
    select target_business_id, u.id, target_source_warehouse_id,
      'reserved', 'reserved', 'inventory_transfer_request', request_id,
      operation_id, caller_id
    from public.serialized_inventory_units u
    where u.id = any(selected_ids);
  end if;

  existing_result := jsonb_build_object(
    'request_id', request_id,
    'request_number', request_no,
    'status', 'requested',
    'quantity', normalized_quantity,
    'serialized_units', selected_count
  );
  update public.idempotency_records i
  set result = existing_result
  where i.business_id = target_business_id
    and i.operation_id = request_inventory_transfer.operation_id
    and i.operation_type = 'inventory.transfer.request';
  perform private.write_tenant_audit(
    target_business_id, 'inventory.transfer_requested', 'inventory_transfer_request',
    request_id::text, existing_result || jsonb_build_object(
      'source_warehouse_id', target_source_warehouse_id,
      'destination_warehouse_id', target_destination_warehouse_id,
      'variant_id', target_variant_id,
      'reason', btrim(transfer_reason)
    )
  );
  return existing_result;
end;
$$;

create or replace function public.approve_inventory_transfer(
  target_business_id uuid,
  target_request_id uuid,
  operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  request_record public.inventory_transfer_requests%rowtype;
  existing_result jsonb;
  result jsonb;
  inserted_count integer;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if not private.has_permission(target_business_id, 'inventory.manage') then
    raise exception 'You do not have permission to approve inventory transfers';
  end if;
  insert into public.idempotency_records (business_id, operation_id, operation_type, actor_user_id)
  values (target_business_id, operation_id, 'inventory.transfer.approve', caller_id)
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select i.result into existing_result from public.idempotency_records i
    where i.business_id = target_business_id and i.operation_id = approve_inventory_transfer.operation_id
      and i.operation_type = 'inventory.transfer.approve';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Transfer approval is already in progress';
  end if;
  select * into request_record from public.inventory_transfer_requests r
  where r.id = target_request_id and r.business_id = target_business_id for update;
  if not found then raise exception 'Transfer request not found'; end if;
  if request_record.status <> 'requested' then
    raise exception 'Only requested transfers can be approved';
  end if;
  if not private.can_access_warehouse(request_record.source_warehouse_id)
     or not private.can_access_warehouse(request_record.destination_warehouse_id) then
    raise exception 'Transfer warehouses are not accessible';
  end if;
  update public.inventory_transfer_requests
  set status = 'approved', approved_by = caller_id, approved_at = now()
  where id = target_request_id and business_id = target_business_id;
  result := jsonb_build_object('request_id', target_request_id,
    'request_number', request_record.request_number, 'status', 'approved');
  update public.idempotency_records i set result = result
  where i.business_id = target_business_id and i.operation_id = approve_inventory_transfer.operation_id
    and i.operation_type = 'inventory.transfer.approve';
  perform private.write_tenant_audit(target_business_id, 'inventory.transfer_approved',
    'inventory_transfer_request', target_request_id::text, result);
  return result;
end;
$$;

create or replace function public.dispatch_inventory_transfer(
  target_business_id uuid,
  target_request_id uuid,
  operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  request_record public.inventory_transfer_requests%rowtype;
  existing_result jsonb;
  result jsonb;
  inserted_count integer;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if not private.has_permission(target_business_id, 'inventory.manage') then
    raise exception 'You do not have permission to dispatch inventory transfers';
  end if;
  insert into public.idempotency_records (business_id, operation_id, operation_type, actor_user_id)
  values (target_business_id, operation_id, 'inventory.transfer.dispatch', caller_id)
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select i.result into existing_result from public.idempotency_records i
    where i.business_id = target_business_id and i.operation_id = dispatch_inventory_transfer.operation_id
      and i.operation_type = 'inventory.transfer.dispatch';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Transfer dispatch is already in progress';
  end if;
  select * into request_record from public.inventory_transfer_requests r
  where r.id = target_request_id and r.business_id = target_business_id for update;
  if not found then raise exception 'Transfer request not found'; end if;
  if request_record.status <> 'approved' then
    raise exception 'Only approved transfers can be dispatched';
  end if;
  update public.inventory_transfer_requests
  set status = 'dispatched', dispatched_by = caller_id, dispatched_at = now()
  where id = target_request_id and business_id = target_business_id;
  result := jsonb_build_object('request_id', target_request_id,
    'request_number', request_record.request_number, 'status', 'dispatched');
  update public.idempotency_records i set result = result
  where i.business_id = target_business_id and i.operation_id = dispatch_inventory_transfer.operation_id
    and i.operation_type = 'inventory.transfer.dispatch';
  perform private.write_tenant_audit(target_business_id, 'inventory.transfer_dispatched',
    'inventory_transfer_request', target_request_id::text, result);
  return result;
end;
$$;

create or replace function public.receive_inventory_transfer(
  target_business_id uuid,
  target_request_id uuid,
  operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  request_record public.inventory_transfer_requests%rowtype;
  variant_record record;
  source_balance public.inventory_balances%rowtype;
  destination_balance public.inventory_balances%rowtype;
  source_after numeric(20,6);
  destination_after numeric(20,6);
  destination_cost numeric(18,4);
  source_cost numeric(18,4);
  result jsonb;
  existing_result jsonb;
  inserted_count integer;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if not private.has_permission(target_business_id, 'inventory.manage') then
    raise exception 'You do not have permission to receive inventory transfers';
  end if;
  insert into public.idempotency_records (business_id, operation_id, operation_type, actor_user_id)
  values (target_business_id, operation_id, 'inventory.transfer.receive', caller_id)
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select i.result into existing_result from public.idempotency_records i
    where i.business_id = target_business_id and i.operation_id = receive_inventory_transfer.operation_id
      and i.operation_type = 'inventory.transfer.receive';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Transfer receipt is already in progress';
  end if;
  select * into request_record from public.inventory_transfer_requests r
  where r.id = target_request_id and r.business_id = target_business_id for update;
  if not found then raise exception 'Transfer request not found'; end if;
  if request_record.status <> 'dispatched' then
    raise exception 'Only dispatched transfers can be received';
  end if;
  if not private.can_access_warehouse(request_record.destination_warehouse_id) then
    raise exception 'Destination warehouse is not accessible';
  end if;
  select v.tracking_mode, v.sku, p.allow_fractional_quantity
  into variant_record
  from public.product_variants v
  join public.products p on p.id = v.product_id and p.business_id = v.business_id
  where v.id = request_record.variant_id and v.business_id = target_business_id;
  select * into source_balance from public.inventory_balances b
  where b.warehouse_id = request_record.source_warehouse_id and b.variant_id = request_record.variant_id
  for update;
  if not found or source_balance.quantity_reserved < request_record.quantity
     or source_balance.quantity_on_hand < request_record.quantity then
    raise exception 'Reserved source stock is no longer available';
  end if;
  source_cost := source_balance.average_cost;
  insert into public.inventory_balances (business_id, warehouse_id, variant_id)
  values (target_business_id, request_record.destination_warehouse_id, request_record.variant_id)
  on conflict (warehouse_id, variant_id) do nothing;
  select * into destination_balance from public.inventory_balances b
  where b.warehouse_id = request_record.destination_warehouse_id and b.variant_id = request_record.variant_id
  for update;
  source_after := source_balance.quantity_on_hand - request_record.quantity;
  destination_after := destination_balance.quantity_on_hand + request_record.quantity;
  destination_cost := case when destination_after = 0 then source_cost else round((
    destination_balance.quantity_on_hand * destination_balance.average_cost
    + request_record.quantity * source_cost) / destination_after, 4) end;

  insert into public.inventory_movements (
    business_id, warehouse_id, variant_id, movement_type, quantity_delta,
    quantity_before, quantity_after, unit_cost, reference_type, reference_id,
    reason, operation_id, created_by
  ) values
    (target_business_id, request_record.source_warehouse_id, request_record.variant_id,
     'transfer_out', -request_record.quantity, source_balance.quantity_on_hand,
     source_after, source_cost, 'inventory_transfer_request', target_request_id,
     request_record.reason, operation_id, caller_id),
    (target_business_id, request_record.destination_warehouse_id, request_record.variant_id,
     'transfer_in', request_record.quantity, destination_balance.quantity_on_hand,
     destination_after, source_cost, 'inventory_transfer_request', target_request_id,
     request_record.reason, operation_id, caller_id);

  update public.inventory_balances
  set quantity_on_hand = source_after,
      quantity_reserved = quantity_reserved - request_record.quantity,
      updated_at = now()
  where warehouse_id = request_record.source_warehouse_id and variant_id = request_record.variant_id;
  update public.inventory_balances
  set quantity_on_hand = destination_after, average_cost = destination_cost, updated_at = now()
  where warehouse_id = request_record.destination_warehouse_id and variant_id = request_record.variant_id;

  if variant_record.tracking_mode in ('serial', 'imei') then
    if exists (
      select 1 from public.serialized_inventory_units u
      join public.inventory_transfer_request_serialized_units l
        on l.serialized_unit_id = u.id and l.business_id = u.business_id
      where l.request_id = target_request_id
        and (u.status <> 'reserved' or u.warehouse_id <> request_record.source_warehouse_id)
    ) then raise exception 'One or more serialized units are no longer reserved in the source warehouse'; end if;
    update public.serialized_inventory_units u
    set warehouse_id = request_record.destination_warehouse_id, status = 'in_stock'
    from public.inventory_transfer_request_serialized_units l
    where l.request_id = target_request_id and l.business_id = target_business_id
      and l.serialized_unit_id = u.id;
    insert into public.serialized_inventory_unit_events (
      business_id, serialized_unit_id, warehouse_id, event_type, status_after,
      reference_type, reference_id, operation_id, created_by
    )
    select target_business_id, l.serialized_unit_id, request_record.destination_warehouse_id,
      'transferred', 'in_stock', 'inventory_transfer_request', target_request_id,
      operation_id, caller_id
    from public.inventory_transfer_request_serialized_units l
    where l.request_id = target_request_id and l.business_id = target_business_id;
  end if;

  update public.inventory_transfer_requests
  set status = 'received', received_by = caller_id, received_at = now()
  where id = target_request_id and business_id = target_business_id;
  result := jsonb_build_object('request_id', target_request_id,
    'request_number', request_record.request_number, 'status', 'received',
    'quantity', request_record.quantity,
    'source_quantity_after', source_after,
    'destination_quantity_after', destination_after);
  update public.idempotency_records i set result = result
  where i.business_id = target_business_id and i.operation_id = receive_inventory_transfer.operation_id
    and i.operation_type = 'inventory.transfer.receive';
  perform private.write_tenant_audit(target_business_id, 'inventory.transfer_received',
    'inventory_transfer_request', target_request_id::text, result);
  return result;
end;
$$;

create or replace function public.cancel_inventory_transfer(
  target_business_id uuid,
  target_request_id uuid,
  operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  request_record public.inventory_transfer_requests%rowtype;
  variant_record record;
  result jsonb;
  existing_result jsonb;
  inserted_count integer;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if not private.has_permission(target_business_id, 'inventory.manage') then
    raise exception 'You do not have permission to cancel inventory transfers';
  end if;
  insert into public.idempotency_records (business_id, operation_id, operation_type, actor_user_id)
  values (target_business_id, operation_id, 'inventory.transfer.cancel', caller_id)
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select i.result into existing_result from public.idempotency_records i
    where i.business_id = target_business_id and i.operation_id = cancel_inventory_transfer.operation_id
      and i.operation_type = 'inventory.transfer.cancel';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Transfer cancellation is already in progress';
  end if;
  select * into request_record from public.inventory_transfer_requests r
  where r.id = target_request_id and r.business_id = target_business_id for update;
  if not found then raise exception 'Transfer request not found'; end if;
  if request_record.status not in ('requested', 'approved') then
    raise exception 'Only requested or approved transfers can be cancelled';
  end if;
  update public.inventory_balances
  set quantity_reserved = quantity_reserved - request_record.quantity, updated_at = now()
  where warehouse_id = request_record.source_warehouse_id and variant_id = request_record.variant_id;
  select v.tracking_mode into variant_record
  from public.product_variants v
  where v.id = request_record.variant_id and v.business_id = target_business_id;
  if variant_record.tracking_mode in ('serial', 'imei') then
    update public.serialized_inventory_units u
    set status = 'in_stock'
    from public.inventory_transfer_request_serialized_units l
    where l.request_id = target_request_id and l.business_id = target_business_id
      and l.serialized_unit_id = u.id;
    insert into public.serialized_inventory_unit_events (
      business_id, serialized_unit_id, warehouse_id, event_type, status_after,
      reference_type, reference_id, operation_id, created_by
    )
    select target_business_id, l.serialized_unit_id, request_record.source_warehouse_id,
      'released', 'in_stock', 'inventory_transfer_request', target_request_id,
      operation_id, caller_id
    from public.inventory_transfer_request_serialized_units l
    where l.request_id = target_request_id and l.business_id = target_business_id;
  end if;
  update public.inventory_transfer_requests
  set status = 'cancelled'
  where id = target_request_id and business_id = target_business_id;
  result := jsonb_build_object('request_id', target_request_id,
    'request_number', request_record.request_number, 'status', 'cancelled');
  update public.idempotency_records i set result = result
  where i.business_id = target_business_id and i.operation_id = cancel_inventory_transfer.operation_id
    and i.operation_type = 'inventory.transfer.cancel';
  perform private.write_tenant_audit(target_business_id, 'inventory.transfer_cancelled',
    'inventory_transfer_request', target_request_id::text, result);
  return result;
end;
$$;

revoke all on function public.request_inventory_transfer(
  uuid, uuid, uuid, uuid, numeric, text, uuid, text, jsonb
) from public, anon;
revoke all on function public.approve_inventory_transfer(uuid, uuid, uuid) from public, anon;
revoke all on function public.dispatch_inventory_transfer(uuid, uuid, uuid) from public, anon;
revoke all on function public.receive_inventory_transfer(uuid, uuid, uuid) from public, anon;
revoke all on function public.cancel_inventory_transfer(uuid, uuid, uuid) from public, anon;
grant execute on function public.request_inventory_transfer(
  uuid, uuid, uuid, uuid, numeric, text, uuid, text, jsonb
) to authenticated;
grant execute on function public.approve_inventory_transfer(uuid, uuid, uuid) to authenticated;
grant execute on function public.dispatch_inventory_transfer(uuid, uuid, uuid) to authenticated;
grant execute on function public.receive_inventory_transfer(uuid, uuid, uuid) to authenticated;
grant execute on function public.cancel_inventory_transfer(uuid, uuid, uuid) to authenticated;
