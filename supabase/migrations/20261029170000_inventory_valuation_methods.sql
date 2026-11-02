-- Configurable inventory valuation for FlexPOS.
-- Weighted average remains the default. FIFO uses current batch layers when
-- available and falls back to the balance average cost for legacy unbatched stock.

create table public.inventory_valuation_settings (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  valuation_method text not null default 'weighted_average'
    check (valuation_method in ('weighted_average', 'fifo', 'standard_cost')),
  standard_cost numeric(18,4)
    check (standard_cost is null or standard_cost >= 0),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint inventory_valuation_standard_cost_required
    check (valuation_method <> 'standard_cost' or standard_cost is not null)
);

alter table public.inventory_valuation_settings enable row level security;

create policy inventory_valuation_settings_select
on public.inventory_valuation_settings for select to authenticated
using (
  (select private.has_permission(business_id, 'reports.view'))
  and (select private.has_permission(business_id, 'inventory.view'))
);

revoke all on public.inventory_valuation_settings from anon;
grant select on public.inventory_valuation_settings to authenticated;

create index inventory_valuation_settings_updated_by_idx
  on public.inventory_valuation_settings(updated_by);

create or replace function public.get_inventory_valuation_settings(
  target_business_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $inventory_valuation_settings$
declare
  result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not private.has_permission(target_business_id, 'reports.view')
     or not private.has_permission(target_business_id, 'inventory.view') then
    raise exception 'Inventory report permission required';
  end if;

  select jsonb_build_object(
    'valuation_method', coalesce(s.valuation_method, 'weighted_average'),
    'standard_cost', s.standard_cost,
    'updated_at', s.updated_at
  )
  into result
  from (select 1) as placeholder
  left join public.inventory_valuation_settings s
    on s.business_id = target_business_id;

  return result;
end;
$inventory_valuation_settings$;

create or replace function public.set_inventory_valuation_method(
  target_business_id uuid,
  selected_method text,
  target_standard_cost numeric default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $set_inventory_valuation_method$
declare
  saved public.inventory_valuation_settings;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not private.has_permission(target_business_id, 'inventory.manage') then
    raise exception 'Inventory management permission required';
  end if;
  if selected_method not in ('weighted_average', 'fifo', 'standard_cost') then
    raise exception 'Unsupported valuation method';
  end if;
  if target_standard_cost is not null and target_standard_cost < 0 then
    raise exception 'Standard cost cannot be negative';
  end if;
  if selected_method = 'standard_cost' and target_standard_cost is null then
    raise exception 'Standard cost is required for standard-cost valuation';
  end if;

  insert into public.inventory_valuation_settings (
    business_id, valuation_method, standard_cost, updated_by
  ) values (
    target_business_id,
    selected_method,
    case when selected_method = 'standard_cost' then target_standard_cost else null end,
    auth.uid()
  )
  on conflict (business_id) do update set
    valuation_method = excluded.valuation_method,
    standard_cost = excluded.standard_cost,
    updated_by = excluded.updated_by,
    updated_at = now()
  returning * into saved;

  perform private.write_tenant_audit(
    target_business_id,
    'inventory_valuation.updated',
    'inventory_valuation_settings',
    target_business_id::text,
    jsonb_build_object(
      'valuation_method', saved.valuation_method,
      'standard_cost', saved.standard_cost
    )
  );

  return jsonb_build_object(
    'valuation_method', saved.valuation_method,
    'standard_cost', saved.standard_cost,
    'updated_at', saved.updated_at
  );
end;
$set_inventory_valuation_method$;

revoke all on function public.get_inventory_valuation_settings(uuid)
  from public, anon;
revoke all on function public.set_inventory_valuation_method(uuid, text, numeric)
  from public, anon;
grant execute on function public.get_inventory_valuation_settings(uuid)
  to authenticated;
grant execute on function public.set_inventory_valuation_method(uuid, text, numeric)
  to authenticated;

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

  with settings as (
    select coalesce(s.valuation_method, 'weighted_average') as valuation_method,
           s.standard_cost
    from (select 1) as placeholder
    left join public.inventory_valuation_settings s
      on s.business_id = target_business_id
  ),
  base as (
    select ib.business_id, ib.warehouse_id, ib.variant_id, ib.quantity_on_hand,
           ib.quantity_reserved, ib.reorder_point, w.id as warehouse_group_id,
           w.name as warehouse_name, c.id as category_id,
           coalesce(c.name, 'Uncategorized') as category_name,
           settings.valuation_method, settings.standard_cost,
           case settings.valuation_method
             when 'standard_cost' then
               ib.quantity_on_hand * coalesce(settings.standard_cost, ib.average_cost)
             when 'fifo' then
               coalesce((
                 select sum(b.quantity_on_hand * b.average_cost)
                 from public.inventory_batches b
                 where b.business_id = ib.business_id
                   and b.warehouse_id = ib.warehouse_id
                   and b.variant_id = ib.variant_id
               ), 0)
               + greatest(
                   ib.quantity_on_hand - coalesce((
                     select sum(b.quantity_on_hand)
                     from public.inventory_batches b
                     where b.business_id = ib.business_id
                       and b.warehouse_id = ib.warehouse_id
                       and b.variant_id = ib.variant_id
                   ), 0),
                   0
                 ) * ib.average_cost
             else ib.quantity_on_hand * ib.average_cost
           end as total_value
    from public.inventory_balances ib
    join public.warehouses w
      on w.id = ib.warehouse_id and w.business_id = ib.business_id
    join public.product_variants pv
      on pv.id = ib.variant_id and pv.business_id = ib.business_id
    join public.products p
      on p.id = pv.product_id and p.business_id = pv.business_id
    left join public.categories c
      on c.id = p.category_id and c.business_id = p.business_id
    cross join settings
    where ib.business_id = target_business_id
      and private.has_branch_access(w.branch_id)
  )
  select jsonb_build_object(
    'method', coalesce(max(base.valuation_method), 'weighted_average'),
    'standard_cost', max(base.standard_cost),
    'total_value', coalesce(sum(base.total_value), 0),
    'on_hand_quantity', coalesce(sum(base.quantity_on_hand), 0),
    'reserved_quantity', coalesce(sum(base.quantity_reserved), 0),
    'available_quantity', coalesce(sum(base.quantity_on_hand - base.quantity_reserved), 0),
    'sku_count', count(distinct base.variant_id),
    'low_stock_count', count(*) filter (
      where base.quantity_on_hand - base.quantity_reserved <= base.reorder_point
    ),
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
        select warehouse_group_id as id, warehouse_name as name,
               sum(total_value) as total_value,
               sum(quantity_on_hand) as on_hand_quantity,
               sum(quantity_reserved) as reserved_quantity,
               sum(quantity_on_hand - quantity_reserved) as available_quantity,
               count(distinct variant_id) as sku_count,
               count(*) filter (
                 where quantity_on_hand - quantity_reserved <= reorder_point
               ) as low_stock_count
        from base
        group by warehouse_group_id, warehouse_name
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
        select category_id as id, category_name as name,
               sum(total_value) as total_value,
               sum(quantity_on_hand) as on_hand_quantity,
               sum(quantity_reserved) as reserved_quantity,
               sum(quantity_on_hand - quantity_reserved) as available_quantity,
               count(distinct variant_id) as sku_count,
               count(*) filter (
                 where quantity_on_hand - quantity_reserved <= reorder_point
               ) as low_stock_count
        from base
        group by category_id, category_name
      ) grouped
    ), '[]'::jsonb)
  ) into result
  from base;

  return result;
end;
$inventory_valuation$;

revoke all on function public.get_inventory_valuation_report(uuid)
  from public, anon;
grant execute on function public.get_inventory_valuation_report(uuid)
  to authenticated;
