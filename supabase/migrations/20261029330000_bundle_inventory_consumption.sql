-- Consume non-serialized bundle components as part of the authoritative sale.
-- Bundles remain non-stock parent SKUs; their selected warehouse components are
-- decremented atomically after the sale header and lines are inserted.
begin;

create or replace function private.validate_product_bundle_component()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  bundle_type text;
  component_type text;
  component_tracks_inventory boolean;
  component_tracking_mode text;
begin
  select p.product_type into bundle_type
  from public.product_variants v
  join public.products p on p.id = v.product_id and p.business_id = v.business_id
  where v.id = new.bundle_variant_id and v.business_id = new.business_id
    and v.is_active and v.archived_at is null
    and p.is_active and p.archived_at is null;
  if bundle_type is distinct from 'bundle' then
    raise exception 'Bundle components require an active bundle product variant';
  end if;

  select p.product_type, p.track_inventory, v.tracking_mode
  into component_type, component_tracks_inventory, component_tracking_mode
  from public.product_variants v
  join public.products p on p.id = v.product_id and p.business_id = v.business_id
  where v.id = new.component_variant_id and v.business_id = new.business_id
    and v.is_active and v.archived_at is null
    and p.is_active and p.archived_at is null;
  if component_type is null then
    raise exception 'Bundle component variant is unavailable';
  end if;
  if component_type = 'bundle' then
    raise exception 'Nested bundles are not supported';
  end if;
  if not component_tracks_inventory or component_tracking_mode <> 'none' then
    raise exception 'Bundle components must be non-serialized inventory items';
  end if;
  return new;
end;
$$;

create or replace function private.consume_bundle_components()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  component record;
  batch_record public.inventory_batches%rowtype;
  balance_record public.inventory_balances%rowtype;
  remaining_quantity numeric(20,6);
  batch_take_quantity numeric(20,6);
  batch_available numeric(20,6);
  all_batch_available numeric(20,6);
  untracked_available numeric(20,6);
  next_quantity numeric(20,6);
  component_operation_id uuid;
  component_warehouse_id uuid;
begin
  if new.status <> 'completed' or new.sale_type <> 'invoice' then
    return new;
  end if;

  for component in
    select
      si.business_id,
      si.warehouse_id,
      pbc.component_variant_id,
      sum(si.quantity * pbc.quantity)::numeric(20,6) as quantity,
      cv.cost_price,
      cv.sku,
      cp.track_inventory,
      cv.tracking_mode
    from public.sale_items si
    join public.product_variants bv
      on bv.id = si.variant_id and bv.business_id = si.business_id
    join public.products bp
      on bp.id = bv.product_id and bp.business_id = bv.business_id
    join public.product_bundle_components pbc
      on pbc.bundle_variant_id = si.variant_id
     and pbc.business_id = si.business_id
    join public.product_variants cv
      on cv.id = pbc.component_variant_id and cv.business_id = pbc.business_id
    join public.products cp
      on cp.id = cv.product_id and cp.business_id = cv.business_id
    where si.sale_id = new.id
      and si.business_id = new.business_id
      and bp.product_type = 'bundle'
    group by si.business_id, si.warehouse_id, pbc.component_variant_id,
      cv.cost_price, cv.sku, cp.track_inventory, cv.tracking_mode
  loop
    if not component.track_inventory or component.tracking_mode <> 'none' then
      raise exception 'Bundle component SKU % must be non-serialized inventory', component.sku;
    end if;

    component_warehouse_id := component.warehouse_id;
    if component_warehouse_id is null then
      select w.id into component_warehouse_id
      from public.warehouses w
      where w.business_id = new.business_id
        and w.branch_id = new.branch_id
        and w.is_active
      order by w.is_default desc, w.created_at, w.id
      limit 1;
    end if;
    if component_warehouse_id is null or not exists (
      select 1 from public.warehouses w
      where w.id = component_warehouse_id
        and w.business_id = new.business_id
        and w.branch_id = new.branch_id
        and w.is_active
    ) then
      raise exception 'A valid warehouse is required to sell bundle component SKU %', component.sku;
    end if;

    insert into public.inventory_balances (business_id, warehouse_id, variant_id)
    values (new.business_id, component_warehouse_id, component.component_variant_id)
    on conflict (warehouse_id, variant_id) do nothing;
    select * into balance_record
    from public.inventory_balances b
    where b.warehouse_id = component_warehouse_id
      and b.variant_id = component.component_variant_id
    for update;
    next_quantity := balance_record.quantity_on_hand - round(component.quantity, 6);
    if next_quantity < balance_record.quantity_reserved or next_quantity < 0 then
      raise exception 'Insufficient available stock for bundle component SKU %', component.sku;
    end if;

    component_operation_id := gen_random_uuid();
    -- Keep batch balances and FEFO history in sync with the aggregate balance.
    remaining_quantity := round(component.quantity, 6);
    select coalesce(sum(greatest(b.quantity_on_hand - b.quantity_reserved, 0)), 0)
    into batch_available
    from public.inventory_batches b
    where b.business_id = new.business_id
      and b.warehouse_id = component_warehouse_id
      and b.variant_id = component.component_variant_id
      and b.status = 'active'
      and (b.expires_on is null or b.expires_on >= current_date);
    select coalesce(sum(greatest(b.quantity_on_hand - b.quantity_reserved, 0)), 0)
    into all_batch_available
    from public.inventory_batches b
    where b.business_id = new.business_id
      and b.warehouse_id = component_warehouse_id
      and b.variant_id = component.component_variant_id;
    untracked_available := greatest(
      balance_record.quantity_on_hand - balance_record.quantity_reserved
        - all_batch_available,
      0
    );
    if batch_available + untracked_available < remaining_quantity then
      raise exception 'Insufficient non-expired batch or untracked stock for bundle component SKU %', component.sku;
    end if;
    if batch_available > 0 then
      for batch_record in
        select b.*
        from public.inventory_batches b
        where b.business_id = new.business_id
          and b.warehouse_id = component_warehouse_id
          and b.variant_id = component.component_variant_id
          and b.status = 'active'
          and b.quantity_on_hand > b.quantity_reserved
          and (b.expires_on is null or b.expires_on >= current_date)
        order by b.expires_on nulls last, b.expires_on, b.created_at, b.id
        for update
      loop
        exit when remaining_quantity <= 0;
        batch_take_quantity := least(
          remaining_quantity,
          batch_record.quantity_on_hand - batch_record.quantity_reserved
        );
        if batch_take_quantity <= 0 then
          continue;
        end if;
        update public.inventory_batches
        set quantity_on_hand = quantity_on_hand - batch_take_quantity,
            updated_at = now()
        where id = batch_record.id and business_id = new.business_id;
        insert into public.inventory_batch_movements (
          business_id, batch_id, warehouse_id, variant_id, movement_type,
          quantity_delta, quantity_before, quantity_after, unit_cost,
          reference_type, reference_id, operation_id, created_by
        ) values (
          new.business_id, batch_record.id, component_warehouse_id,
          component.component_variant_id, 'sale', -batch_take_quantity,
          batch_record.quantity_on_hand,
          batch_record.quantity_on_hand - batch_take_quantity,
          batch_record.average_cost, 'sale', new.id, component_operation_id, new.completed_by
        );
        remaining_quantity := remaining_quantity - batch_take_quantity;
      end loop;
    end if;

    update public.inventory_balances
    set quantity_on_hand = next_quantity, updated_at = now()
    where warehouse_id = component_warehouse_id
      and variant_id = component.component_variant_id;
    insert into public.inventory_movements (
      business_id, warehouse_id, variant_id, movement_type, quantity_delta,
      quantity_before, quantity_after, unit_cost, reference_type, reference_id,
      reason, operation_id, created_by
    ) values (
      new.business_id, component_warehouse_id, component.component_variant_id,
      'sale', -round(component.quantity, 6), balance_record.quantity_on_hand,
      next_quantity, component.cost_price, 'sale', new.id,
      'Bundle component', component_operation_id, new.completed_by
    );
  end loop;
  return new;
end;
$$;

revoke all on function private.consume_bundle_components() from public, anon, authenticated, service_role;

drop trigger if exists sales_consume_bundle_components on public.sales;
create constraint trigger sales_consume_bundle_components
after insert on public.sales
deferrable initially deferred
for each row execute function private.consume_bundle_components();

commit;
