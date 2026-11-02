-- Inventory, industry workflow, enterprise event, and hardware event history
-- for the two synthetic showcase businesses.

begin;
select set_config('request.jwt.claim.sub', '01331716-1fbd-4780-bc16-b4dba20a96aa', true);

do $$
declare
  b record;
  v_admin constant uuid := '01331716-1fbd-4780-bc16-b4dba20a96aa';
  v_manager constant uuid := '73558bcb-8f47-4e36-9c3e-2ff4f7f16d98';
begin
  for b in
    select * from (values
      ('7b000000-0000-4000-8000-000000000001'::uuid, 'Retail'),
      ('7b000000-0000-4000-8000-000000000002'::uuid, 'Cafe')
    ) as x(id, label)
  loop
    -- Make a serial-tracked showcase item and register its units.
    update public.product_variants
    set tracking_mode = 'serial', updated_at = now()
    where business_id = b.id
      and id = md5(b.id::text || '|variant|2')::uuid;

    insert into public.serialized_inventory_units (
      id, business_id, warehouse_id, variant_id, tracking_mode, identifier,
      normalized_identifier, status, product_name, variant_name, sku,
      registered_by, registered_at
    )
    select
      md5(b.id::text || '|serial-unit|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|warehouse|1')::uuid,
      md5(b.id::text || '|variant|2')::uuid,
      'serial',
      format('SN-%s-%06s', upper(left(b.label, 3)), i),
      lower(format('sn-%s-%06s', upper(left(b.label, 3)), i)),
      (array['in_stock','reserved','sold','returned','damaged','wastage','transferred'])[1 + ((i - 1) % 7)],
      format('%s Showcase Product 2', b.label), 'Standard pack',
      format('%s-%s', upper(left(b.label, 3)), lpad('2', 5, '0')),
      v_admin, now() - make_interval(days => i)
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set status = excluded.status;

    insert into public.serialized_inventory_unit_events (
      business_id, serialized_unit_id, warehouse_id, event_type,
      status_after, reference_type, reference_id, operation_id, created_by
    )
    select
      b.id,
      md5(b.id::text || '|serial-unit|' || i::text)::uuid,
      md5(b.id::text || '|warehouse|1')::uuid,
      'registered', 'in_stock', 'seed',
      md5(b.id::text || '|serial-unit|' || i::text)::uuid,
      md5(b.id::text || '|serial-event-op|' || i::text)::uuid,
      v_admin
    from generate_series(1, 8) as s(i)
    on conflict do nothing;

    -- Batch/lot inventory and its movement history.
    insert into public.inventory_batches (
      id, business_id, warehouse_id, variant_id, batch_number, lot_number,
      manufactured_on, expires_on, status, quantity_on_hand, quantity_reserved,
      average_cost, created_by
    )
    select
      md5(b.id::text || '|batch|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|warehouse|1')::uuid,
      md5(b.id::text || '|variant|' || (20 + i)::text)::uuid,
      format('%s-BATCH-%06s', upper(left(b.label, 3)), i),
      format('LOT-%s-%04s', upper(left(b.label, 3)), i),
      current_date - (120 + i),
      case when i % 5 = 0 then current_date - i else current_date + (90 + i) end,
      case when i % 7 = 0 then 'recalled' when i % 5 = 0 then 'expired' when i % 3 = 0 then 'blocked' else 'active' end,
      case when i % 5 = 0 then 0 else 40 + i end,
      0,
      35 + (i * 3),
      v_manager
    from generate_series(1, 16) as s(i)
    on conflict (id) do update set status = excluded.status, quantity_on_hand = excluded.quantity_on_hand;

    insert into public.inventory_batch_movements (
      business_id, batch_id, warehouse_id, variant_id, movement_type,
      quantity_delta, quantity_before, quantity_after, unit_cost,
      reference_type, reference_id, operation_id, created_by
    )
    select
      b.id,
      md5(b.id::text || '|batch|' || i::text)::uuid,
      md5(b.id::text || '|warehouse|1')::uuid,
      md5(b.id::text || '|variant|' || (20 + i)::text)::uuid,
      case when i % 2 = 0 then 'purchase' else 'adjustment' end,
      10, 30, 40, 35 + (i * 3), 'showcase',
      md5(b.id::text || '|purchase-order|' || i::text)::uuid,
      md5(b.id::text || '|batch-movement-op|' || i::text)::uuid,
      v_manager
    from generate_series(1, 16) as s(i)
    on conflict do nothing;

    -- Completed and staged warehouse transfers.
    insert into public.inventory_transfers (
      id, business_id, source_warehouse_id, destination_warehouse_id,
      variant_id, transfer_number, status, quantity, reason, notes,
      operation_id, created_by
    )
    select
      md5(b.id::text || '|transfer|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|warehouse|1')::uuid,
      md5(b.id::text || '|warehouse|2')::uuid,
      md5(b.id::text || '|variant|' || (40 + i)::text)::uuid,
      format('%s-TR-%06s', upper(left(b.label, 3)), i),
      'completed', 5 + i, 'Branch replenishment',
      'Synthetic completed transfer for inventory review.',
      md5(b.id::text || '|transfer-op|' || i::text)::uuid,
      v_manager
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set quantity = excluded.quantity;

    insert into public.inventory_transfer_requests (
      id, business_id, source_warehouse_id, destination_warehouse_id,
      variant_id, request_number, status, quantity, reason, notes,
      operation_id, requested_by, approved_by, dispatched_by, received_by,
      requested_at, approved_at, dispatched_at, received_at
    )
    select
      md5(b.id::text || '|transfer-request|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|warehouse|1')::uuid,
      md5(b.id::text || '|warehouse|2')::uuid,
      md5(b.id::text || '|variant|' || (50 + i)::text)::uuid,
      format('%s-TRQ-%06s', upper(left(b.label, 3)), i),
      case when i % 5 = 0 then 'cancelled' when i % 4 = 0 then 'received' when i % 3 = 0 then 'dispatched' when i % 2 = 0 then 'approved' else 'requested' end,
      4 + i, 'Demand balancing', 'Synthetic transfer request.',
      md5(b.id::text || '|transfer-request-op|' || i::text)::uuid,
      v_manager,
      case when i % 2 = 0 or i % 3 = 0 or i % 4 = 0 then v_admin else null end,
      case when i % 3 = 0 or i % 4 = 0 then v_manager else null end,
      case when i % 4 = 0 then v_manager else null end,
      now() - make_interval(days => i),
      case when i % 2 = 0 or i % 3 = 0 or i % 4 = 0 then now() - make_interval(days => i - 1) else null end,
      case when i % 3 = 0 or i % 4 = 0 then now() - make_interval(days => i - 2) else null end,
      case when i % 4 = 0 then now() - make_interval(days => i - 3) else null end
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set status = excluded.status;

    -- Cycle count examples.
    insert into public.inventory_stocktakes (
      id, business_id, warehouse_id, stocktake_number, status, reason,
      started_at, completed_at, created_by, finalized_by
    )
    select
      md5(b.id::text || '|stocktake|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|warehouse|1')::uuid,
      format('%s-ST-%06s', upper(left(b.label, 3)), i),
      case when i % 4 = 0 then 'cancelled' when i % 2 = 0 then 'finalized' else 'counting' end,
      'Synthetic cycle count for review.',
      now() - make_interval(days => i),
      case when i % 2 = 0 then now() - make_interval(days => i - 1) else null end,
      v_manager,
      case when i % 2 = 0 then v_manager else null end
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set status = excluded.status;

    insert into public.inventory_stocktake_items (
      id, business_id, stocktake_id, warehouse_id, variant_id, system_quantity,
      counted_quantity, note, counted_by, counted_at
    )
    select
      md5(b.id::text || '|stocktake-item|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|stocktake|' || i::text)::uuid,
      md5(b.id::text || '|warehouse|1')::uuid,
      md5(b.id::text || '|variant|' || (90 + i)::text)::uuid,
      40 + i, case when i % 3 = 0 then 39 + i else 40 + i end,
      'Synthetic counted quantity.', v_manager,
      now() - make_interval(days => i - 1)
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set counted_quantity = excluded.counted_quantity;

    -- Industry workflows, line items, and status-event history.
    insert into public.industry_workflow_lines (
      id, business_id, workflow_id, line_kind, product_id, description,
      quantity, unit_price, metadata, created_by
    )
    select
      md5(b.id::text || '|workflow-line|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|industry|' || i::text)::uuid,
      case when i % 3 = 0 then 'modifier' when i % 2 = 0 then 'component' else 'item' end,
      md5(b.id::text || '|product|' || i::text)::uuid,
      format('Workflow line item %s for %s.', i, b.label),
      1 + (i % 3), 100 + (i * 15),
      jsonb_build_object('showcase', true, 'line_index', i), v_manager
    from generate_series(1, 16) as s(i)
    on conflict (id) do update set description = excluded.description;

    insert into public.industry_workflow_events (
      business_id, workflow_id, from_status, to_status, note, metadata, actor_user_id
    )
    select
      b.id,
      md5(b.id::text || '|industry|' || i::text)::uuid,
      'planned', 'in_progress', 'Synthetic workflow status update.',
      jsonb_build_object('showcase', true, 'event_index', i), v_manager
    from generate_series(1, 16) as s(i)
    on conflict do nothing;

    insert into public.enterprise_record_events (
      business_id, record_id, from_status, to_status, note, metadata, actor_user_id
    )
    select
      b.id,
      md5(b.id::text || '|enterprise|' || i::text)::uuid,
      'draft', 'active', 'Synthetic enterprise record transition.',
      jsonb_build_object('showcase', true, 'event_index', i), v_admin
    from generate_series(1, 16) as s(i)
    on conflict do nothing;

    insert into public.hardware_device_events (
      business_id, device_id, event_type, status, error_message, metadata, actor_user_id
    )
    select
      b.id,
      md5(b.id::text || '|hardware|' || i::text)::uuid,
      case when i % 3 = 0 then 'status_changed' when i % 2 = 0 then 'connectivity_test' else 'registered' end,
      case when i % 5 = 0 then 'warning' else 'success' end,
      case when i % 5 = 0 then 'Synthetic intermittent connection warning.' else null end,
      jsonb_build_object('showcase', true, 'device_index', i), v_admin
    from generate_series(1, 8) as s(i)
    on conflict do nothing;

    insert into public.business_loyalty_settings (
      business_id, enabled, earn_points_per_currency, redeem_points_per_currency,
      max_redeem_percent, updated_by
    )
    values (b.id, true, 1, 0.01, 25, v_admin)
    on conflict (business_id) do update set enabled = true, updated_by = excluded.updated_by;
  end loop;
end $$;

commit;
