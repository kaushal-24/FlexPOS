-- Current inventory valuation using the weighted average cost stored for each
-- warehouse balance. The RPC deliberately applies both permission and branch
-- access checks because SECURITY DEFINER bypasses table RLS.

create or replace function public.get_inventory_valuation_report(
  target_business_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $inventory_valuation$
declare
  result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not private.has_permission(target_business_id, 'reports.view') then
    raise exception 'Report viewing permission required';
  end if;
  if not private.has_permission(target_business_id, 'inventory.view') then
    raise exception 'Inventory viewing permission required';
  end if;

  select jsonb_build_object(
    'total_value', coalesce((
      select sum(ib.quantity_on_hand * ib.average_cost)
      from public.inventory_balances ib
      join public.warehouses w
        on w.id = ib.warehouse_id and w.business_id = ib.business_id
      where ib.business_id = target_business_id
        and private.has_branch_access(w.branch_id)
    ), 0),
    'on_hand_quantity', coalesce((
      select sum(ib.quantity_on_hand)
      from public.inventory_balances ib
      join public.warehouses w
        on w.id = ib.warehouse_id and w.business_id = ib.business_id
      where ib.business_id = target_business_id
        and private.has_branch_access(w.branch_id)
    ), 0),
    'reserved_quantity', coalesce((
      select sum(ib.quantity_reserved)
      from public.inventory_balances ib
      join public.warehouses w
        on w.id = ib.warehouse_id and w.business_id = ib.business_id
      where ib.business_id = target_business_id
        and private.has_branch_access(w.branch_id)
    ), 0),
    'available_quantity', coalesce((
      select sum(ib.quantity_on_hand - ib.quantity_reserved)
      from public.inventory_balances ib
      join public.warehouses w
        on w.id = ib.warehouse_id and w.business_id = ib.business_id
      where ib.business_id = target_business_id
        and private.has_branch_access(w.branch_id)
    ), 0),
    'sku_count', coalesce((
      select count(distinct ib.variant_id)
      from public.inventory_balances ib
      join public.warehouses w
        on w.id = ib.warehouse_id and w.business_id = ib.business_id
      where ib.business_id = target_business_id
        and private.has_branch_access(w.branch_id)
    ), 0),
    'low_stock_count', coalesce((
      select count(*)
      from public.inventory_balances ib
      join public.warehouses w
        on w.id = ib.warehouse_id and w.business_id = ib.business_id
      where ib.business_id = target_business_id
        and ib.quantity_on_hand - ib.quantity_reserved <= ib.reorder_point
        and private.has_branch_access(w.branch_id)
    ), 0),
    'by_warehouse', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', grouped.id,
          'name', grouped.name,
          'total_value', grouped.total_value,
          'on_hand_quantity', grouped.on_hand_quantity,
          'reserved_quantity', grouped.reserved_quantity,
          'available_quantity', grouped.available_quantity,
          'sku_count', grouped.sku_count,
          'low_stock_count', grouped.low_stock_count
        ) order by grouped.total_value desc, grouped.name
      )
      from (
        select
          w.id,
          w.name,
          sum(ib.quantity_on_hand * ib.average_cost) as total_value,
          sum(ib.quantity_on_hand) as on_hand_quantity,
          sum(ib.quantity_reserved) as reserved_quantity,
          sum(ib.quantity_on_hand - ib.quantity_reserved) as available_quantity,
          count(distinct ib.variant_id) as sku_count,
          count(*) filter (
            where ib.quantity_on_hand - ib.quantity_reserved <= ib.reorder_point
          ) as low_stock_count
        from public.inventory_balances ib
        join public.warehouses w
          on w.id = ib.warehouse_id and w.business_id = ib.business_id
        where ib.business_id = target_business_id
          and private.has_branch_access(w.branch_id)
        group by w.id, w.name
      ) grouped
    ), '[]'::jsonb),
    'by_category', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', grouped.id,
          'name', grouped.name,
          'total_value', grouped.total_value,
          'on_hand_quantity', grouped.on_hand_quantity,
          'reserved_quantity', grouped.reserved_quantity,
          'available_quantity', grouped.available_quantity,
          'sku_count', grouped.sku_count,
          'low_stock_count', grouped.low_stock_count
        ) order by grouped.total_value desc, grouped.name
      )
      from (
        select
          c.id,
          coalesce(c.name, 'Uncategorized') as name,
          sum(ib.quantity_on_hand * ib.average_cost) as total_value,
          sum(ib.quantity_on_hand) as on_hand_quantity,
          sum(ib.quantity_reserved) as reserved_quantity,
          sum(ib.quantity_on_hand - ib.quantity_reserved) as available_quantity,
          count(distinct ib.variant_id) as sku_count,
          count(*) filter (
            where ib.quantity_on_hand - ib.quantity_reserved <= ib.reorder_point
          ) as low_stock_count
        from public.inventory_balances ib
        join public.warehouses w
          on w.id = ib.warehouse_id and w.business_id = ib.business_id
        join public.product_variants pv
          on pv.id = ib.variant_id and pv.business_id = ib.business_id
        join public.products p
          on p.id = pv.product_id and p.business_id = pv.business_id
        left join public.categories c
          on c.id = p.category_id and c.business_id = p.business_id
        where ib.business_id = target_business_id
          and private.has_branch_access(w.branch_id)
        group by c.id, c.name
      ) grouped
    ), '[]'::jsonb)
  ) into result;

  return result;
end;
$inventory_valuation$;

revoke all on function public.get_inventory_valuation_report(uuid)
  from public, anon;
grant execute on function public.get_inventory_valuation_report(uuid)
  to authenticated;
