-- Reconstruct opening and closing quantities from the immutable movement
-- ledger, then calculate the standard turnover ratio:
-- net COGS / average(beginning inventory value, ending inventory value).

create index if not exists inventory_movements_turnover_position_idx
  on public.inventory_movements(
    business_id,
    warehouse_id,
    variant_id,
    created_at desc
  );

create or replace function public.get_inventory_turnover_report(
  target_business_id uuid,
  period_start timestamptz,
  period_end timestamptz
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $inventory_turnover$
declare
  result jsonb;
  period_days integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not private.has_permission(target_business_id, 'reports.view') then
    raise exception 'Report viewing permission required';
  end if;
  if not private.has_permission(target_business_id, 'reports.profit') then
    raise exception 'Profit report permission required';
  end if;
  if not private.has_permission(target_business_id, 'inventory.view') then
    raise exception 'Inventory viewing permission required';
  end if;
  if period_start is null or period_end is null or period_end <= period_start then
    raise exception 'Invalid report period';
  end if;
  if period_end - period_start > interval '366 days' then
    raise exception 'Inventory turnover period cannot exceed 366 days';
  end if;

  period_days := greatest(ceil(extract(epoch from period_end - period_start) / 86400), 1);

  with accessible_balances as materialized (
    select
      ib.business_id,
      ib.warehouse_id,
      ib.variant_id,
      ib.quantity_on_hand,
      ib.average_cost
    from public.inventory_balances ib
    join public.warehouses w
      on w.id = ib.warehouse_id
     and w.business_id = ib.business_id
    where ib.business_id = target_business_id
      and private.has_branch_access(w.branch_id)
  ),
  movement_deltas as (
    select
      balance.warehouse_id,
      balance.variant_id,
      coalesce(sum(movement.quantity_delta) filter (
        where movement.created_at >= period_start
      ), 0) as delta_since_start,
      coalesce(sum(movement.quantity_delta) filter (
        where movement.created_at >= period_end
      ), 0) as delta_since_end
    from accessible_balances balance
    left join public.inventory_movements movement
      on movement.business_id = balance.business_id
     and movement.warehouse_id = balance.warehouse_id
     and movement.variant_id = balance.variant_id
     and movement.created_at >= period_start
    group by balance.warehouse_id, balance.variant_id
  ),
  inventory_positions as (
    select
      balance.variant_id,
      greatest(
        balance.quantity_on_hand - deltas.delta_since_start,
        0
      ) as beginning_quantity,
      greatest(
        balance.quantity_on_hand - deltas.delta_since_end,
        0
      ) as ending_quantity,
      greatest(
        balance.quantity_on_hand - deltas.delta_since_start,
        0
      ) * balance.average_cost as beginning_value,
      greatest(
        balance.quantity_on_hand - deltas.delta_since_end,
        0
      ) * balance.average_cost as ending_value
    from accessible_balances balance
    join movement_deltas deltas
      on deltas.warehouse_id = balance.warehouse_id
     and deltas.variant_id = balance.variant_id
  ),
  variant_inventory as (
    select
      variant_id,
      sum(beginning_quantity) as beginning_quantity,
      sum(ending_quantity) as ending_quantity,
      sum(beginning_value) as beginning_value,
      sum(ending_value) as ending_value
    from inventory_positions
    group by variant_id
  ),
  sales_activity as (
    select
      item.variant_id,
      item.quantity as net_units_sold,
      item.quantity * item.unit_cost as net_cogs
    from public.sale_items item
    join public.sales sale
      on sale.id = item.sale_id
     and sale.business_id = item.business_id
    where item.business_id = target_business_id
      and sale.status in ('completed', 'partially_refunded', 'refunded')
      and sale.completed_at >= period_start
      and sale.completed_at < period_end
      and private.has_branch_access(sale.branch_id)

    union all

    select
      return_item.variant_id,
      -return_item.quantity,
      -return_item.cost_total
    from public.sale_return_items return_item
    join public.sale_returns sale_return
      on sale_return.id = return_item.return_id
     and sale_return.business_id = return_item.business_id
    where return_item.business_id = target_business_id
      and sale_return.status = 'completed'
      and sale_return.returned_at >= period_start
      and sale_return.returned_at < period_end
      and private.has_branch_access(sale_return.branch_id)
  ),
  variant_sales as (
    select
      variant_id,
      sum(net_units_sold) as net_units_sold,
      sum(net_cogs) as net_cogs
    from sales_activity
    group by variant_id
  ),
  variant_metrics as materialized (
    select
      variant.id as variant_id,
      product.id as product_id,
      product.name as product_name,
      product.category_id,
      coalesce(category.name, 'Uncategorized') as category_name,
      coalesce(inventory.beginning_quantity, 0) as beginning_quantity,
      coalesce(inventory.ending_quantity, 0) as ending_quantity,
      coalesce(inventory.beginning_value, 0) as beginning_value,
      coalesce(inventory.ending_value, 0) as ending_value,
      (
        coalesce(inventory.beginning_value, 0)
        + coalesce(inventory.ending_value, 0)
      ) / 2 as average_inventory_value,
      coalesce(sales.net_units_sold, 0) as net_units_sold,
      coalesce(sales.net_cogs, 0) as net_cogs
    from (
      select variant_id from variant_inventory
      union
      select variant_id from variant_sales
    ) activity
    join public.product_variants variant
      on variant.id = activity.variant_id
     and variant.business_id = target_business_id
    join public.products product
      on product.id = variant.product_id
     and product.business_id = variant.business_id
    left join public.categories category
      on category.id = product.category_id
     and category.business_id = product.business_id
    left join variant_inventory inventory
      on inventory.variant_id = activity.variant_id
    left join variant_sales sales
      on sales.variant_id = activity.variant_id
  ),
  product_base as (
    select
      product_id as id,
      product_name as name,
      category_id,
      category_name,
      sum(beginning_quantity) as beginning_quantity,
      sum(ending_quantity) as ending_quantity,
      sum(beginning_value) as beginning_value,
      sum(ending_value) as ending_value,
      sum(average_inventory_value) as average_inventory_value,
      sum(net_units_sold) as net_units_sold,
      sum(net_cogs) as net_cogs
    from variant_metrics
    group by product_id, product_name, category_id, category_name
  ),
  product_metrics as (
    select
      product_base.*,
      case when average_inventory_value > 0
        then net_cogs / average_inventory_value
        else null
      end as turnover_ratio,
      case when net_cogs > 0 and average_inventory_value > 0
        then period_days::numeric / (net_cogs / average_inventory_value)
        else null
      end as days_on_hand
    from product_base
  ),
  category_base as (
    select
      category_id as id,
      category_name as name,
      sum(beginning_quantity) as beginning_quantity,
      sum(ending_quantity) as ending_quantity,
      sum(beginning_value) as beginning_value,
      sum(ending_value) as ending_value,
      sum(average_inventory_value) as average_inventory_value,
      sum(net_units_sold) as net_units_sold,
      sum(net_cogs) as net_cogs
    from variant_metrics
    group by category_id, category_name
  ),
  category_metrics as (
    select
      category_base.*,
      case when average_inventory_value > 0
        then net_cogs / average_inventory_value
        else null
      end as turnover_ratio,
      case when net_cogs > 0 and average_inventory_value > 0
        then period_days::numeric / (net_cogs / average_inventory_value)
        else null
      end as days_on_hand
    from category_base
  ),
  summary as (
    select
      coalesce(sum(beginning_value), 0) as beginning_inventory_value,
      coalesce(sum(ending_value), 0) as ending_inventory_value,
      coalesce(sum(average_inventory_value), 0) as average_inventory_value,
      coalesce(sum(net_units_sold), 0) as net_units_sold,
      coalesce(sum(net_cogs), 0) as net_cogs
    from variant_metrics
  )
  select jsonb_build_object(
    'period_start', period_start,
    'period_end', period_end,
    'period_days', period_days,
    'method', 'two_point_current_average_cost',
    'net_cogs', summary.net_cogs,
    'net_units_sold', summary.net_units_sold,
    'beginning_inventory_value', summary.beginning_inventory_value,
    'ending_inventory_value', summary.ending_inventory_value,
    'average_inventory_value', summary.average_inventory_value,
    'turnover_ratio', case when summary.average_inventory_value > 0
      then summary.net_cogs / summary.average_inventory_value
      else null
    end,
    'days_on_hand', case
      when summary.net_cogs > 0 and summary.average_inventory_value > 0
      then period_days::numeric
        / (summary.net_cogs / summary.average_inventory_value)
      else null
    end,
    'by_product', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', ranked.id,
          'name', ranked.name,
          'beginning_quantity', ranked.beginning_quantity,
          'ending_quantity', ranked.ending_quantity,
          'beginning_inventory_value', ranked.beginning_value,
          'ending_inventory_value', ranked.ending_value,
          'average_inventory_value', ranked.average_inventory_value,
          'net_units_sold', ranked.net_units_sold,
          'net_cogs', ranked.net_cogs,
          'turnover_ratio', ranked.turnover_ratio,
          'days_on_hand', ranked.days_on_hand
        ) order by ranked.turnover_ratio desc nulls last, ranked.net_cogs desc, ranked.name
      )
      from (
        select * from product_metrics
        order by turnover_ratio desc nulls last, net_cogs desc, name
        limit 50
      ) ranked
    ), '[]'::jsonb),
    'by_category', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', category_metrics.id,
          'name', category_metrics.name,
          'beginning_quantity', category_metrics.beginning_quantity,
          'ending_quantity', category_metrics.ending_quantity,
          'beginning_inventory_value', category_metrics.beginning_value,
          'ending_inventory_value', category_metrics.ending_value,
          'average_inventory_value', category_metrics.average_inventory_value,
          'net_units_sold', category_metrics.net_units_sold,
          'net_cogs', category_metrics.net_cogs,
          'turnover_ratio', category_metrics.turnover_ratio,
          'days_on_hand', category_metrics.days_on_hand
        ) order by category_metrics.turnover_ratio desc nulls last,
                   category_metrics.net_cogs desc,
                   category_metrics.name
      )
      from category_metrics
    ), '[]'::jsonb)
  ) into result
  from summary;

  return result;
end;
$inventory_turnover$;

revoke all on function public.get_inventory_turnover_report(
  uuid, timestamptz, timestamptz
) from public, anon;
grant execute on function public.get_inventory_turnover_report(
  uuid, timestamptz, timestamptz
) to authenticated;
