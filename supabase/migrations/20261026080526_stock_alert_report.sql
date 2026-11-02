-- Detailed stock alerts and minimum replenishment guidance. The report uses
-- available stock (on hand less reservations), applies branch access inside
-- the SECURITY DEFINER function, and does not create mutable alert records.

create index if not exists inventory_balances_stock_alert_idx
  on public.inventory_balances (
    business_id,
    warehouse_id,
    ((quantity_on_hand - quantity_reserved)),
    variant_id
  )
  where (quantity_on_hand - quantity_reserved)
    <= greatest(reorder_point, safety_stock);

create or replace function public.get_stock_alert_report(
  target_business_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $stock_alert_report$
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

  with scoped_balances as materialized (
    select
      ib.variant_id,
      pv.product_id,
      p.category_id,
      ib.warehouse_id,
      w.branch_id,
      p.name as product_name,
      pv.name as variant_name,
      pv.sku,
      w.name as warehouse_name,
      b.name as branch_name,
      coalesce(c.name, 'Uncategorized') as category_name,
      ib.quantity_on_hand,
      ib.quantity_reserved,
      ib.quantity_on_hand - ib.quantity_reserved as available_quantity,
      ib.reorder_point,
      ib.safety_stock,
      greatest(ib.reorder_point, ib.safety_stock) as target_stock,
      ib.average_cost,
      ib.updated_at
    from public.inventory_balances ib
    join public.warehouses w
      on w.id = ib.warehouse_id and w.business_id = ib.business_id
    join public.branches b
      on b.id = w.branch_id and b.business_id = w.business_id
    join public.product_variants pv
      on pv.id = ib.variant_id and pv.business_id = ib.business_id
    join public.products p
      on p.id = pv.product_id and p.business_id = pv.business_id
    left join public.categories c
      on c.id = p.category_id and c.business_id = p.business_id
    where ib.business_id = target_business_id
      and w.is_active
      and p.track_inventory
      and p.is_active
      and p.archived_at is null
      and pv.is_active
      and pv.archived_at is null
      and private.has_branch_access(w.branch_id)
  ),
  alerts as materialized (
    select
      scoped_balances.*,
      case
        when available_quantity <= 0 then 'out_of_stock'
        when safety_stock > 0 and available_quantity <= safety_stock
          then 'below_safety_stock'
        else 'reorder_point'
      end as severity,
      target_stock > 0 as threshold_configured,
      greatest(target_stock - available_quantity, 0)
        as suggested_order_quantity,
      greatest(target_stock - available_quantity, 0) * average_cost
        as suggested_order_cost
    from scoped_balances
    where available_quantity <= target_stock
  )
  select jsonb_build_object(
    'generated_at', statement_timestamp(),
    'alert_count', (select count(*) from alerts),
    'affected_sku_count', (
      select count(distinct variant_id) from alerts
    ),
    'out_of_stock_count', (
      select count(*) from alerts where severity = 'out_of_stock'
    ),
    'below_safety_stock_count', (
      select count(*) from alerts where severity = 'below_safety_stock'
    ),
    'reorder_point_count', (
      select count(*) from alerts where severity = 'reorder_point'
    ),
    'unconfigured_threshold_count', (
      select count(*) from alerts where not threshold_configured
    ),
    'suggested_order_quantity', coalesce((
      select sum(suggested_order_quantity) from alerts
    ), 0),
    'estimated_reorder_cost', coalesce((
      select sum(suggested_order_cost) from alerts
    ), 0),
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'variant_id', alert.variant_id,
          'product_id', alert.product_id,
          'category_id', alert.category_id,
          'warehouse_id', alert.warehouse_id,
          'branch_id', alert.branch_id,
          'product_name', alert.product_name,
          'variant_name', alert.variant_name,
          'sku', alert.sku,
          'warehouse_name', alert.warehouse_name,
          'branch_name', alert.branch_name,
          'category_name', alert.category_name,
          'severity', alert.severity,
          'quantity_on_hand', alert.quantity_on_hand,
          'quantity_reserved', alert.quantity_reserved,
          'available_quantity', alert.available_quantity,
          'reorder_point', alert.reorder_point,
          'safety_stock', alert.safety_stock,
          'target_stock', alert.target_stock,
          'threshold_configured', alert.threshold_configured,
          'suggested_order_quantity', alert.suggested_order_quantity,
          'average_cost', alert.average_cost,
          'suggested_order_cost', alert.suggested_order_cost,
          'updated_at', alert.updated_at
        ) order by
          case alert.severity
            when 'out_of_stock' then 1
            when 'below_safety_stock' then 2
            else 3
          end,
          alert.suggested_order_quantity desc,
          alert.product_name,
          alert.variant_name,
          alert.warehouse_name
      )
      from alerts alert
    ), '[]'::jsonb),
    'by_warehouse', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', grouped.id,
          'name', grouped.name,
          'alert_count', grouped.alert_count,
          'out_of_stock_count', grouped.out_of_stock_count,
          'below_safety_stock_count', grouped.below_safety_stock_count,
          'reorder_point_count', grouped.reorder_point_count,
          'suggested_order_quantity', grouped.suggested_order_quantity,
          'estimated_reorder_cost', grouped.estimated_reorder_cost
        ) order by grouped.alert_count desc, grouped.name
      )
      from (
        select
          warehouse_id as id,
          warehouse_name as name,
          count(*) as alert_count,
          count(*) filter (where severity = 'out_of_stock')
            as out_of_stock_count,
          count(*) filter (where severity = 'below_safety_stock')
            as below_safety_stock_count,
          count(*) filter (where severity = 'reorder_point')
            as reorder_point_count,
          sum(suggested_order_quantity) as suggested_order_quantity,
          sum(suggested_order_cost) as estimated_reorder_cost
        from alerts
        group by warehouse_id, warehouse_name
      ) grouped
    ), '[]'::jsonb),
    'by_category', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', grouped.id,
          'name', grouped.name,
          'alert_count', grouped.alert_count,
          'out_of_stock_count', grouped.out_of_stock_count,
          'below_safety_stock_count', grouped.below_safety_stock_count,
          'reorder_point_count', grouped.reorder_point_count,
          'suggested_order_quantity', grouped.suggested_order_quantity,
          'estimated_reorder_cost', grouped.estimated_reorder_cost
        ) order by grouped.alert_count desc, grouped.name
      )
      from (
        select
          category_id as id,
          category_name as name,
          count(*) as alert_count,
          count(*) filter (where severity = 'out_of_stock')
            as out_of_stock_count,
          count(*) filter (where severity = 'below_safety_stock')
            as below_safety_stock_count,
          count(*) filter (where severity = 'reorder_point')
            as reorder_point_count,
          sum(suggested_order_quantity) as suggested_order_quantity,
          sum(suggested_order_cost) as estimated_reorder_cost
        from alerts
        group by category_id, category_name
      ) grouped
    ), '[]'::jsonb)
  ) into result;

  return result;
end;
$stock_alert_report$;

comment on function public.get_stock_alert_report(uuid) is
  'Returns branch-scoped stock alerts and minimum replenishment guidance.';

revoke all on function public.get_stock_alert_report(uuid)
  from public, anon;
grant execute on function public.get_stock_alert_report(uuid)
  to authenticated;
