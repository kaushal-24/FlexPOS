-- Fix ambiguous PL/pgSQL result variable references in staged transfer actions.
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
  outcome jsonb;
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
  outcome := jsonb_build_object('request_id', target_request_id,
    'request_number', request_record.request_number, 'status', 'approved');
  update public.idempotency_records i set result = outcome
  where i.business_id = target_business_id and i.operation_id = approve_inventory_transfer.operation_id
    and i.operation_type = 'inventory.transfer.approve';
  perform private.write_tenant_audit(target_business_id, 'inventory.transfer_approved',
    'inventory_transfer_request', target_request_id::text, outcome);
  return outcome;
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
  outcome jsonb;
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
  outcome := jsonb_build_object('request_id', target_request_id,
    'request_number', request_record.request_number, 'status', 'dispatched');
  update public.idempotency_records i set result = outcome
  where i.business_id = target_business_id and i.operation_id = dispatch_inventory_transfer.operation_id
    and i.operation_type = 'inventory.transfer.dispatch';
  perform private.write_tenant_audit(target_business_id, 'inventory.transfer_dispatched',
    'inventory_transfer_request', target_request_id::text, outcome);
  return outcome;
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
  outcome jsonb;
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
  outcome := jsonb_build_object('request_id', target_request_id,
    'request_number', request_record.request_number, 'status', 'received',
    'quantity', request_record.quantity,
    'source_quantity_after', source_after,
    'destination_quantity_after', destination_after);
  update public.idempotency_records i set result = outcome
  where i.business_id = target_business_id and i.operation_id = receive_inventory_transfer.operation_id
    and i.operation_type = 'inventory.transfer.receive';
  perform private.write_tenant_audit(target_business_id, 'inventory.transfer_received',
    'inventory_transfer_request', target_request_id::text, outcome);
  return outcome;
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
  outcome jsonb;
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
  outcome := jsonb_build_object('request_id', target_request_id,
    'request_number', request_record.request_number, 'status', 'cancelled');
  update public.idempotency_records i set result = outcome
  where i.business_id = target_business_id and i.operation_id = cancel_inventory_transfer.operation_id
    and i.operation_type = 'inventory.transfer.cancel';
  perform private.write_tenant_audit(target_business_id, 'inventory.transfer_cancelled',
    'inventory_transfer_request', target_request_id::text, outcome);
  return outcome;
end;
$$;


