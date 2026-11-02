-- Allocate current positive stock against the newest inbound movement layers.
-- Under FIFO consumption the oldest stock is consumed first, so the remaining
-- on-hand quantity is represented by the newest layers. Quantities without a
-- matching inbound history remain explicit in an untracked bucket.

create index if not exists inventory_movements_ageing_inbound_idx
  on public.inventory_movements(
    business_id,
    warehouse_id,
    variant_id,
    created_at desc,
    id desc
  )
  where quantity_delta > 0;

create or replace function public.get_inventory_ageing_report(
  target_business_id uuid,
  target_as_of_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $inventory_ageing$
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
    raise exception 'Inventory ageing date required';
  end if;

  with accessible_balances as materialized (
    select
      ib.business_id,
      ib.warehouse_id,
      w.name as warehouse_name,
      ib.variant_id,
      p.category_id,
      coalesce(c.name, 'Uncategorized') as category_name,
      ib.quantity_on_hand,
      ib.average_cost
    from public.inventory_balances ib
    join public.warehouses w
      on w.id = ib.warehouse_id
     and w.business_id = ib.business_id
    join public.product_variants pv
      on pv.id = ib.variant_id
     and pv.business_id = ib.business_id
    join public.products p
      on p.id = pv.product_id
     and p.business_id = pv.business_id
    left join public.categories c
      on c.id = p.category_id
     and c.business_id = p.business_id
    where ib.business_id = target_business_id
      and ib.quantity_on_hand > 0
      and private.has_branch_access(w.branch_id)
  ),
  inbound_ranked as (
    select
      balance.*,
      movement.id as movement_id,
      movement.quantity_delta,
      movement.created_at,
      coalesce(sum(movement.quantity_delta) over (
        partition by movement.warehouse_id, movement.variant_id
        order by movement.created_at desc, movement.id desc
        rows between unbounded preceding and 1 preceding
      ), 0) as newer_quantity
    from accessible_balances balance
    join public.inventory_movements movement
      on movement.business_id = balance.business_id
     and movement.warehouse_id = balance.warehouse_id
     and movement.variant_id = balance.variant_id
     and movement.quantity_delta > 0
     and movement.created_at < (target_as_of_date + 1)::timestamptz
  ),
  tracked_layers as (
    select
      inbound_ranked.business_id,
      inbound_ranked.warehouse_id,
      inbound_ranked.warehouse_name,
      inbound_ranked.variant_id,
      inbound_ranked.category_id,
      inbound_ranked.category_name,
      greatest(
        least(
          inbound_ranked.quantity_delta,
          inbound_ranked.quantity_on_hand - inbound_ranked.newer_quantity
        ),
        0
      ) as layer_quantity,
      inbound_ranked.average_cost,
      greatest(target_as_of_date - inbound_ranked.created_at::date, 0)
        as age_days
    from inbound_ranked
  ),
  tracked_totals as (
    select
      warehouse_id,
      variant_id,
      sum(layer_quantity) as tracked_quantity
    from tracked_layers
    group by warehouse_id, variant_id
  ),
  untracked_layers as (
    select
      balance.business_id,
      balance.warehouse_id,
      balance.warehouse_name,
      balance.variant_id,
      balance.category_id,
      balance.category_name,
      greatest(
        balance.quantity_on_hand - coalesce(tracked.tracked_quantity, 0),
        0
      ) as layer_quantity,
      balance.average_cost,
      null::integer as age_days
    from accessible_balances balance
    left join tracked_totals tracked
      on tracked.warehouse_id = balance.warehouse_id
     and tracked.variant_id = balance.variant_id
  ),
  stock_layers as materialized (
    select * from tracked_layers where layer_quantity > 0
    union all
    select * from untracked_layers where layer_quantity > 0
  ),
  bucketed as (
    select
      case
        when age_days is null then 'untracked'
        when age_days <= 30 then '0_30'
        when age_days <= 60 then '31_60'
        when age_days <= 90 then '61_90'
        when age_days <= 180 then '91_180'
        else '181_plus'
      end as bucket_key,
      case
        when age_days is null then 'Untracked'
        when age_days <= 30 then '0-30 days'
        when age_days <= 60 then '31-60 days'
        when age_days <= 90 then '61-90 days'
        when age_days <= 180 then '91-180 days'
        else '181+ days'
      end as bucket_label,
      case
        when age_days <= 30 then 1
        when age_days <= 60 then 2
        when age_days <= 90 then 3
        when age_days <= 180 then 4
        when age_days > 180 then 5
        else 6
      end as bucket_order,
      stock_layers.*
    from stock_layers
  ),
  bucket_totals as (
    select
      bucket_key,
      bucket_label,
      bucket_order,
      sum(layer_quantity) as quantity,
      sum(layer_quantity * average_cost) as total_value,
      count(distinct variant_id) as sku_count
    from bucketed
    group by bucket_key, bucket_label, bucket_order
  ),
  warehouse_totals as (
    select
      warehouse_id as id,
      warehouse_name as name,
      sum(layer_quantity) as quantity,
      sum(layer_quantity * average_cost) as total_value,
      count(distinct variant_id) as sku_count,
      max(age_days) as oldest_age_days,
      coalesce(sum(layer_quantity) filter (where age_days > 90), 0)
        as older_than_90_quantity
    from stock_layers
    group by warehouse_id, warehouse_name
  ),
  category_totals as (
    select
      category_id as id,
      category_name as name,
      sum(layer_quantity) as quantity,
      sum(layer_quantity * average_cost) as total_value,
      count(distinct variant_id) as sku_count,
      max(age_days) as oldest_age_days,
      coalesce(sum(layer_quantity) filter (where age_days > 90), 0)
        as older_than_90_quantity
    from stock_layers
    group by category_id, category_name
  )
  select jsonb_build_object(
    'as_of_date', target_as_of_date,
    'method', 'fifo',
    'total_quantity', coalesce((
      select sum(layer_quantity) from stock_layers
    ), 0),
    'total_value', coalesce((
      select sum(layer_quantity * average_cost) from stock_layers
    ), 0),
    'tracked_quantity', coalesce((
      select sum(layer_quantity) from stock_layers where age_days is not null
    ), 0),
    'untracked_quantity', coalesce((
      select sum(layer_quantity) from stock_layers where age_days is null
    ), 0),
    'oldest_age_days', (
      select max(age_days) from stock_layers
    ),
    'buckets', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'key', bucket_totals.bucket_key,
          'label', bucket_totals.bucket_label,
          'quantity', bucket_totals.quantity,
          'total_value', bucket_totals.total_value,
          'sku_count', bucket_totals.sku_count
        ) order by bucket_totals.bucket_order
      )
      from bucket_totals
    ), '[]'::jsonb),
    'by_warehouse', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', warehouse_totals.id,
          'name', warehouse_totals.name,
          'quantity', warehouse_totals.quantity,
          'total_value', warehouse_totals.total_value,
          'sku_count', warehouse_totals.sku_count,
          'oldest_age_days', warehouse_totals.oldest_age_days,
          'older_than_90_quantity', warehouse_totals.older_than_90_quantity
        ) order by warehouse_totals.total_value desc, warehouse_totals.name
      )
      from warehouse_totals
    ), '[]'::jsonb),
    'by_category', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', category_totals.id,
          'name', category_totals.name,
          'quantity', category_totals.quantity,
          'total_value', category_totals.total_value,
          'sku_count', category_totals.sku_count,
          'oldest_age_days', category_totals.oldest_age_days,
          'older_than_90_quantity', category_totals.older_than_90_quantity
        ) order by category_totals.total_value desc, category_totals.name
      )
      from category_totals
    ), '[]'::jsonb)
  ) into result;

  return result;
end;
$inventory_ageing$;

revoke all on function public.get_inventory_ageing_report(uuid, date)
  from public, anon;
grant execute on function public.get_inventory_ageing_report(uuid, date)
  to authenticated;
