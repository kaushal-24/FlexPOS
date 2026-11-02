-- Classify products by cumulative contribution to return-adjusted sales value.
-- A covers products contributing through the first 80%, B the next 15%, and
-- C the remaining 5%. A boundary-crossing product stays in the class it starts.

create or replace function public.get_abc_inventory_report(
  target_business_id uuid,
  period_start timestamptz,
  period_end timestamptz
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $abc_inventory$
declare
  result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not private.has_permission(target_business_id, 'reports.view') then
    raise exception 'Report viewing permission required';
  end if;
  if not private.has_permission(target_business_id, 'sales.view') then
    raise exception 'Sales viewing permission required';
  end if;
  if not private.has_permission(target_business_id, 'inventory.view') then
    raise exception 'Inventory viewing permission required';
  end if;
  if period_start is null or period_end is null or period_end <= period_start then
    raise exception 'Invalid report period';
  end if;
  if period_end - period_start > interval '366 days' then
    raise exception 'ABC analysis period cannot exceed 366 days';
  end if;

  with sales_activity as (
    select
      item.variant_id,
      item.quantity as net_quantity,
      item.line_total as net_sales
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
      -return_item.line_total
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
  product_sales as materialized (
    select
      product.id as product_id,
      product.name as product_name,
      product.category_id,
      coalesce(category.name, 'Uncategorized') as category_name,
      sum(activity.net_quantity) as net_quantity,
      sum(activity.net_sales) as net_sales
    from sales_activity activity
    join public.product_variants variant
      on variant.id = activity.variant_id
     and variant.business_id = target_business_id
    join public.products product
      on product.id = variant.product_id
     and product.business_id = variant.business_id
    left join public.categories category
      on category.id = product.category_id
     and category.business_id = product.business_id
    group by product.id, product.name, product.category_id, category.name
  ),
  accessible_inventory as materialized (
    select
      product.id as product_id,
      sum(balance.quantity_on_hand) as inventory_quantity,
      sum(balance.quantity_on_hand * balance.average_cost) as inventory_value
    from public.inventory_balances balance
    join public.warehouses warehouse
      on warehouse.id = balance.warehouse_id
     and warehouse.business_id = balance.business_id
    join public.product_variants variant
      on variant.id = balance.variant_id
     and variant.business_id = balance.business_id
    join public.products product
      on product.id = variant.product_id
     and product.business_id = variant.business_id
    where balance.business_id = target_business_id
      and private.has_branch_access(warehouse.branch_id)
    group by product.id
  ),
  eligible_products as materialized (
    select
      sales.product_id,
      sales.product_name,
      sales.category_id,
      sales.category_name,
      sales.net_quantity,
      sales.net_sales,
      coalesce(inventory.inventory_quantity, 0) as inventory_quantity,
      coalesce(inventory.inventory_value, 0) as inventory_value
    from product_sales sales
    left join accessible_inventory inventory
      on inventory.product_id = sales.product_id
    where sales.net_sales > 0
  ),
  ranked_products as (
    select
      eligible.*,
      sum(eligible.net_sales) over () as total_net_sales,
      coalesce(sum(eligible.net_sales) over (
        order by eligible.net_sales desc, eligible.product_name,
                 eligible.product_id
        rows between unbounded preceding and 1 preceding
      ), 0) as cumulative_sales_before,
      sum(eligible.net_sales) over (
        order by eligible.net_sales desc, eligible.product_name,
                 eligible.product_id
        rows between unbounded preceding and current row
      ) as cumulative_sales
    from eligible_products eligible
  ),
  classified_products as materialized (
    select
      ranked.*,
      case
        when ranked.cumulative_sales_before / ranked.total_net_sales < 0.80
          then 'A'
        when ranked.cumulative_sales_before / ranked.total_net_sales < 0.95
          then 'B'
        else 'C'
      end as abc_class,
      round(ranked.net_sales / ranked.total_net_sales * 100, 2)
        as contribution_rate,
      round(ranked.cumulative_sales / ranked.total_net_sales * 100, 2)
        as cumulative_contribution_rate
    from ranked_products ranked
  ),
  class_totals as (
    select
      abc_class,
      count(*) as product_count,
      sum(net_quantity) as net_quantity,
      sum(net_sales) as net_sales,
      sum(inventory_quantity) as inventory_quantity,
      sum(inventory_value) as inventory_value,
      round(sum(net_sales) / max(total_net_sales) * 100, 2)
        as contribution_rate
    from classified_products
    group by abc_class
  ),
  summary as (
    select
      count(*) as product_count,
      coalesce(sum(net_quantity), 0) as net_quantity,
      coalesce(sum(net_sales), 0) as net_sales,
      coalesce(sum(inventory_quantity), 0) as inventory_quantity,
      coalesce(sum(inventory_value), 0) as inventory_value
    from classified_products
  )
  select jsonb_build_object(
    'period_start', period_start,
    'period_end', period_end,
    'method', 'cumulative_net_sales_value',
    'a_threshold', 80,
    'b_threshold', 95,
    'product_count', summary.product_count,
    'net_quantity', summary.net_quantity,
    'net_sales', summary.net_sales,
    'inventory_quantity', summary.inventory_quantity,
    'inventory_value', summary.inventory_value,
    'classes', (
      select jsonb_agg(
        jsonb_build_object(
          'class', definitions.abc_class,
          'label', definitions.label,
          'product_count', coalesce(totals.product_count, 0),
          'net_quantity', coalesce(totals.net_quantity, 0),
          'net_sales', coalesce(totals.net_sales, 0),
          'inventory_quantity', coalesce(totals.inventory_quantity, 0),
          'inventory_value', coalesce(totals.inventory_value, 0),
          'contribution_rate', coalesce(totals.contribution_rate, 0)
        ) order by definitions.sort_order
      )
      from (values
        ('A', 'A - highest contribution', 1),
        ('B', 'B - medium contribution', 2),
        ('C', 'C - lowest contribution', 3)
      ) as definitions(abc_class, label, sort_order)
      left join class_totals totals
        on totals.abc_class = definitions.abc_class
    ),
    'products', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'product_id', classified.product_id,
          'product_name', classified.product_name,
          'category_id', classified.category_id,
          'category_name', classified.category_name,
          'class', classified.abc_class,
          'net_quantity', classified.net_quantity,
          'net_sales', classified.net_sales,
          'contribution_rate', classified.contribution_rate,
          'cumulative_contribution_rate',
            classified.cumulative_contribution_rate,
          'inventory_quantity', classified.inventory_quantity,
          'inventory_value', classified.inventory_value
        ) order by classified.net_sales desc, classified.product_name
      )
      from classified_products classified
    ), '[]'::jsonb)
  ) into result
  from summary;

  return result;
end;
$abc_inventory$;

revoke all on function public.get_abc_inventory_report(
  uuid,
  timestamptz,
  timestamptz
) from public, anon;

grant execute on function public.get_abc_inventory_report(
  uuid,
  timestamptz,
  timestamptz
) to authenticated;
