-- Per-warehouse low-stock thresholds for stock-tracked variants.
-- Quantities remain owned by the trusted inventory RPCs; this function only
-- changes reorder_point after validating tenant, warehouse, variant, and role.

create or replace function public.set_inventory_threshold(
  target_business_id uuid,
  target_warehouse_id uuid,
  target_variant_id uuid,
  target_reorder_point numeric
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  next_reorder_point numeric(20,6);
begin
  if caller_id is null then
    raise exception 'Authentication required';
  end if;
  if target_reorder_point is null or target_reorder_point < 0 then
    raise exception 'Low-stock threshold must be zero or greater';
  end if;
  if not private.has_permission(target_business_id, 'inventory.manage') then
    raise exception 'You do not have permission to update inventory thresholds';
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
  if not exists (
    select 1
    from public.product_variants v
    join public.products p
      on p.id = v.product_id
     and p.business_id = v.business_id
    where v.id = target_variant_id
      and v.business_id = target_business_id
      and v.is_active
      and v.archived_at is null
      and p.track_inventory
  ) then
    raise exception 'Variant is not stock tracked or is inactive';
  end if;

  next_reorder_point := round(target_reorder_point, 6);

  insert into public.inventory_balances (business_id, warehouse_id, variant_id)
  values (target_business_id, target_warehouse_id, target_variant_id)
  on conflict (warehouse_id, variant_id) do nothing;

  update public.inventory_balances
  set reorder_point = next_reorder_point,
      updated_at = now()
  where business_id = target_business_id
    and warehouse_id = target_warehouse_id
    and variant_id = target_variant_id;

  perform private.write_tenant_audit(
    target_business_id,
    'inventory.threshold_updated',
    'inventory_balance',
    target_variant_id::text,
    jsonb_build_object(
      'warehouse_id', target_warehouse_id,
      'reorder_point', next_reorder_point
    )
  );

  return jsonb_build_object(
    'business_id', target_business_id,
    'warehouse_id', target_warehouse_id,
    'variant_id', target_variant_id,
    'reorder_point', next_reorder_point
  );
end;
$$;

revoke all on function public.set_inventory_threshold(uuid, uuid, uuid, numeric)
from public, anon;
grant execute on function public.set_inventory_threshold(uuid, uuid, uuid, numeric)
to authenticated;
