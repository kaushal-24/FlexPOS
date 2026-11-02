-- Identify positive inventory positions with no sale movement during a
-- configurable inactivity window. The report remains branch scoped and keeps
-- never-sold stock explicit instead of assigning an artificial sale date.

create index if not exists inventory_movements_last_sale_position_idx
  on public.inventory_movements(
    business_id,
    warehouse_id,
    variant_id,
    created_at desc
  )
  where movement_type = 'sale' and quantity_delta < 0;

create or replace function public.get_dead_stock_report(
  target_business_id uuid,
  target_as_of_date date default current_date,
  inactivity_days integer default 90
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $dead_stock$
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
  if target_as_of_date is null then
    raise exception 'Dead-stock report date required';
  end if;
  if inactivity_days < 30 or inactivity_days > 730 then
    raise exception 'Inactivity days must be between 30 and 730';
  end if;

  with accessible_positions as materialized (
    select
      ib.business_id,
      ib.warehouse_id,
      warehouse.name as warehouse_name,
      ib.variant_id,
      product.id as product_id,
      product.name as product_name,
      variant.name as variant_name,
      variant.sku,
      product.category_id,
      coalesce(category.name, 'Uncategorized') as category_name,
      ib.quantity_on_hand,
      ib.quantity_reserved,
      greatest(ib.quantity_on_hand - ib.quantity_reserved, 0)
        as available_quantity,
      ib.average_cost,
      ib.quantity_on_hand * ib.average_cost as stock_value
    from public.inventory_balances ib
    join public.warehouses warehouse
      on warehouse.id = ib.warehouse_id
     and warehouse.business_id = ib.business_id
    join public.product_variants variant
      on variant.id = ib.variant_id
     and variant.business_id = ib.business_id
    join public.products product
      on product.id = variant.product_id
     and product.business_id = variant.business_id
    left join public.categories category
      on category.id = product.category_id
     and category.business_id = product.business_id
    where ib.business_id = target_business_id
      and ib.quantity_on_hand > 0
      and private.has_branch_access(warehouse.branch_id)
  ),
  last_sales as (
    select
      movement.warehouse_id,
      movement.variant_id,
      max(movement.created_at) as last_sale_at
    from public.inventory_movements movement
    join accessible_positions position
      on position.warehouse_id = movement.warehouse_id
     and position.variant_id = movement.variant_id
    where movement.business_id = target_business_id
      and movement.movement_type = 'sale'
      and movement.quantity_delta < 0
      and movement.created_at < (target_as_of_date + 1)::timestamptz
    group by movement.warehouse_id, movement.variant_id
  ),
  last_inbound as (
    select
      movement.warehouse_id,
      movement.variant_id,
      max(movement.created_at) as last_inbound_at
    from public.inventory_movements movement
    join accessible_positions position
      on position.warehouse_id = movement.warehouse_id
     and position.variant_id = movement.variant_id
    where movement.business_id = target_business_id
      and movement.quantity_delta > 0
      and movement.created_at < (target_as_of_date + 1)::timestamptz
    group by movement.warehouse_id, movement.variant_id
  ),
  position_metrics as materialized (
    select
      position.*,
      sales.last_sale_at,
      inbound.last_inbound_at,
      case when sales.last_sale_at is null then null
        else greatest(
          target_as_of_date - sales.last_sale_at::date,
          0
        )
      end as days_since_last_sale,
      case when inbound.last_inbound_at is null then null
        else greatest(
          target_as_of_date - inbound.last_inbound_at::date,
          0
        )
      end as days_since_inbound,
      sales.last_sale_at is null as never_sold,
      sales.last_sale_at is null
        or sales.last_sale_at::date <= target_as_of_date - inactivity_days
        as is_dead
    from accessible_positions position
    left join last_sales sales
      on sales.warehouse_id = position.warehouse_id
     and sales.variant_id = position.variant_id
    left join last_inbound inbound
      on inbound.warehouse_id = position.warehouse_id
     and inbound.variant_id = position.variant_id
  ),
  summary as (
    select
      count(*) as stock_position_count,
      count(distinct variant_id) as stocked_sku_count,
      count(*) filter (where is_dead) as dead_position_count,
      count(distinct variant_id) filter (where is_dead) as dead_sku_count,
      count(distinct variant_id) filter (where is_dead and never_sold)
        as never_sold_sku_count,
      coalesce(sum(quantity_on_hand), 0) as total_quantity,
      coalesce(sum(stock_value), 0) as total_value,
      coalesce(sum(quantity_on_hand) filter (where is_dead), 0)
        as dead_quantity,
      coalesce(sum(quantity_reserved) filter (where is_dead), 0)
        as dead_reserved_quantity,
      coalesce(sum(stock_value) filter (where is_dead), 0) as dead_value
    from position_metrics
  ),
  warehouse_totals as (
    select
      warehouse_id as id,
      warehouse_name as name,
      count(*) as position_count,
      count(distinct variant_id) as sku_count,
      count(distinct variant_id) filter (where never_sold)
        as never_sold_sku_count,
      sum(quantity_on_hand) as quantity,
      sum(stock_value) as total_value
    from position_metrics
    where is_dead
    group by warehouse_id, warehouse_name
  ),
  category_totals as (
    select
      category_id as id,
      category_name as name,
      count(*) as position_count,
      count(distinct variant_id) as sku_count,
      count(distinct variant_id) filter (where never_sold)
        as never_sold_sku_count,
      sum(quantity_on_hand) as quantity,
      sum(stock_value) as total_value
    from position_metrics
    where is_dead
    group by category_id, category_name
  )
  select jsonb_build_object(
    'as_of_date', target_as_of_date,
    'inactivity_days', inactivity_days,
    'stock_position_count', summary.stock_position_count,
    'stocked_sku_count', summary.stocked_sku_count,
    'dead_position_count', summary.dead_position_count,
    'dead_sku_count', summary.dead_sku_count,
    'never_sold_sku_count', summary.never_sold_sku_count,
    'total_quantity', summary.total_quantity,
    'total_value', summary.total_value,
    'dead_quantity', summary.dead_quantity,
    'dead_reserved_quantity', summary.dead_reserved_quantity,
    'dead_value', summary.dead_value,
    'dead_value_rate', case when summary.total_value > 0 then round(
      summary.dead_value / summary.total_value * 100,
      2
    ) else null end,
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'warehouse_id', ranked.warehouse_id,
          'warehouse_name', ranked.warehouse_name,
          'variant_id', ranked.variant_id,
          'product_name', ranked.product_name,
          'variant_name', ranked.variant_name,
          'sku', ranked.sku,
          'category_name', ranked.category_name,
          'quantity_on_hand', ranked.quantity_on_hand,
          'quantity_reserved', ranked.quantity_reserved,
          'available_quantity', ranked.available_quantity,
          'average_cost', ranked.average_cost,
          'stock_value', ranked.stock_value,
          'last_sale_at', ranked.last_sale_at,
          'days_since_last_sale', ranked.days_since_last_sale,
          'last_inbound_at', ranked.last_inbound_at,
          'days_since_inbound', ranked.days_since_inbound,
          'never_sold', ranked.never_sold
        ) order by ranked.stock_value desc, ranked.product_name,
                   ranked.variant_name, ranked.warehouse_name
      )
      from (
        select *
        from position_metrics
        where is_dead
        order by stock_value desc, product_name, variant_name, warehouse_name
        limit 100
      ) ranked
    ), '[]'::jsonb),
    'by_warehouse', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', warehouse_totals.id,
          'name', warehouse_totals.name,
          'position_count', warehouse_totals.position_count,
          'sku_count', warehouse_totals.sku_count,
          'never_sold_sku_count', warehouse_totals.never_sold_sku_count,
          'quantity', warehouse_totals.quantity,
          'total_value', warehouse_totals.total_value
        ) order by warehouse_totals.total_value desc, warehouse_totals.name
      )
      from warehouse_totals
    ), '[]'::jsonb),
    'by_category', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', category_totals.id,
          'name', category_totals.name,
          'position_count', category_totals.position_count,
          'sku_count', category_totals.sku_count,
          'never_sold_sku_count', category_totals.never_sold_sku_count,
          'quantity', category_totals.quantity,
          'total_value', category_totals.total_value
        ) order by category_totals.total_value desc, category_totals.name
      )
      from category_totals
    ), '[]'::jsonb)
  ) into result
  from summary;

  return result;
end;
$dead_stock$;

revoke all on function public.get_dead_stock_report(uuid, date, integer)
  from public, anon;
grant execute on function public.get_dead_stock_report(uuid, date, integer)
  to authenticated;
