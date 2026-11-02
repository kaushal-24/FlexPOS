-- Durable, in-app low-stock notification workflow.
-- The existing stock alert report remains the source of truth for thresholds;
-- this table records notification lifecycle only.

create table public.inventory_stock_alert_notifications (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  warehouse_id uuid not null,
  variant_id uuid not null,
  severity text not null check (severity in (
    'out_of_stock', 'below_safety_stock', 'reorder_point'
  )),
  status text not null default 'open' check (status in (
    'open', 'acknowledged', 'resolved'
  )),
  quantity_on_hand numeric(20,6) not null check (quantity_on_hand >= 0),
  quantity_reserved numeric(20,6) not null check (quantity_reserved >= 0),
  available_quantity numeric(20,6) not null,
  target_stock numeric(20,6) not null check (target_stock >= 0),
  suggested_order_quantity numeric(20,6) not null check (suggested_order_quantity >= 0),
  average_cost numeric(18,4) not null check (average_cost >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  acknowledged_at timestamptz,
  acknowledged_by uuid references auth.users(id) on delete set null,
  resolved_at timestamptz,
  unique (business_id, warehouse_id, variant_id),
  constraint inventory_stock_alert_notifications_warehouse_fkey
    foreign key (warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete cascade,
  constraint inventory_stock_alert_notifications_variant_fkey
    foreign key (variant_id, business_id)
    references public.product_variants(id, business_id) on delete cascade
);

create index inventory_stock_alert_notifications_inbox_idx
  on public.inventory_stock_alert_notifications (business_id, status, updated_at desc);
create index inventory_stock_alert_notifications_warehouse_idx
  on public.inventory_stock_alert_notifications (warehouse_id, business_id, status);
create index inventory_stock_alert_notifications_acknowledged_by_idx
  on public.inventory_stock_alert_notifications (acknowledged_by);

alter table public.inventory_stock_alert_notifications enable row level security;

create policy inventory_stock_alert_notifications_select
on public.inventory_stock_alert_notifications for select to authenticated
using (
  (select private.has_permission(business_id, 'reports.view'))
  and (select private.has_permission(business_id, 'inventory.view'))
  and (select private.can_access_warehouse(warehouse_id))
);

revoke all on public.inventory_stock_alert_notifications from anon;
grant select on public.inventory_stock_alert_notifications to authenticated;

create or replace function public.refresh_inventory_stock_alert_notifications(
  target_business_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $refresh_stock_alert_notifications$
declare
  inserted_count integer := 0;
  resolved_count integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not private.has_permission(target_business_id, 'inventory.manage') then
    raise exception 'Inventory management permission required';
  end if;

  with scoped_balances as (
    select ib.business_id, ib.warehouse_id, ib.variant_id,
      ib.quantity_on_hand, ib.quantity_reserved,
      ib.quantity_on_hand - ib.quantity_reserved as available_quantity,
      ib.safety_stock,
      greatest(ib.reorder_point, ib.safety_stock) as target_stock,
      ib.average_cost
    from public.inventory_balances ib
    join public.warehouses w
      on w.id = ib.warehouse_id and w.business_id = ib.business_id
    join public.product_variants pv
      on pv.id = ib.variant_id and pv.business_id = ib.business_id
    join public.products p
      on p.id = pv.product_id and p.business_id = pv.business_id
    where ib.business_id = target_business_id
      and w.is_active and p.track_inventory and p.is_active
      and p.archived_at is null and pv.is_active and pv.archived_at is null
      and private.has_branch_access(w.branch_id)
  ), alerts as (
    select scoped_balances.*,
      case when available_quantity <= 0 then 'out_of_stock'
           when safety_stock > 0 and available_quantity <= safety_stock
             then 'below_safety_stock'
           else 'reorder_point' end as severity,
      greatest(target_stock - available_quantity, 0) as suggested_order_quantity
    from scoped_balances
    where available_quantity <= target_stock
  ), upserted as (
    insert into public.inventory_stock_alert_notifications (
      business_id, warehouse_id, variant_id, severity, status,
      quantity_on_hand, quantity_reserved, available_quantity, target_stock,
      suggested_order_quantity, average_cost, updated_at, resolved_at
    )
    select business_id, warehouse_id, variant_id, severity, 'open',
      quantity_on_hand, quantity_reserved, available_quantity, target_stock,
      suggested_order_quantity, average_cost, now(), null
    from alerts
    on conflict (business_id, warehouse_id, variant_id) do update set
      severity = excluded.severity,
      quantity_on_hand = excluded.quantity_on_hand,
      quantity_reserved = excluded.quantity_reserved,
      available_quantity = excluded.available_quantity,
      target_stock = excluded.target_stock,
      suggested_order_quantity = excluded.suggested_order_quantity,
      average_cost = excluded.average_cost,
      updated_at = now(),
      resolved_at = null,
      status = case
        when public.inventory_stock_alert_notifications.status = 'resolved'
          then 'open'
        else public.inventory_stock_alert_notifications.status
      end
    returning 1
  )
  select count(*) into inserted_count from upserted;

  update public.inventory_stock_alert_notifications n
  set status = 'resolved', resolved_at = now(), updated_at = now()
  where n.business_id = target_business_id
    and n.status <> 'resolved'
    and not exists (
      select 1 from public.inventory_balances ib
      where ib.business_id = n.business_id
        and ib.warehouse_id = n.warehouse_id
        and ib.variant_id = n.variant_id
        and ib.quantity_on_hand - ib.quantity_reserved
            <= greatest(ib.reorder_point, ib.safety_stock)
    );
  get diagnostics resolved_count = row_count;

  perform private.write_tenant_audit(
    target_business_id, 'inventory_stock_alerts.refreshed',
    'inventory_stock_alert_notifications', target_business_id::text,
    jsonb_build_object('active_count', inserted_count, 'resolved_count', resolved_count)
  );

  return jsonb_build_object(
    'active_count', inserted_count,
    'resolved_count', resolved_count
  );
end;
$refresh_stock_alert_notifications$;

create or replace function public.get_inventory_stock_alert_notifications(
  target_business_id uuid,
  include_resolved boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $get_stock_alert_notifications$
declare result jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not private.has_permission(target_business_id, 'reports.view')
     or not private.has_permission(target_business_id, 'inventory.view') then
    raise exception 'Inventory report permission required';
  end if;

  select jsonb_build_object(
    'open_count', count(*) filter (where n.status = 'open'),
    'acknowledged_count', count(*) filter (where n.status = 'acknowledged'),
    'resolved_count', count(*) filter (where n.status = 'resolved'),
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'id', n.id, 'warehouse_id', n.warehouse_id, 'variant_id', n.variant_id,
      'warehouse_name', w.name, 'product_name', p.name, 'variant_name', pv.name,
      'sku', pv.sku, 'severity', n.severity, 'status', n.status,
      'available_quantity', n.available_quantity,
      'target_stock', n.target_stock,
      'suggested_order_quantity', n.suggested_order_quantity,
      'average_cost', n.average_cost, 'created_at', n.created_at,
      'updated_at', n.updated_at, 'acknowledged_at', n.acknowledged_at
    ) order by
      case n.status when 'open' then 1 when 'acknowledged' then 2 else 3 end,
      n.updated_at desc), '[]'::jsonb)
  ) into result
  from public.inventory_stock_alert_notifications n
  join public.warehouses w
    on w.id = n.warehouse_id and w.business_id = n.business_id
  join public.product_variants pv
    on pv.id = n.variant_id and pv.business_id = n.business_id
  join public.products p
    on p.id = pv.product_id and p.business_id = pv.business_id
  where n.business_id = target_business_id
    and private.can_access_warehouse(n.warehouse_id)
    and (include_resolved or n.status <> 'resolved');
  return result;
end;
$get_stock_alert_notifications$;

create or replace function public.acknowledge_inventory_stock_alert(
  target_notification_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $acknowledge_stock_alert$
declare updated_notification public.inventory_stock_alert_notifications;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select n.* into updated_notification
  from public.inventory_stock_alert_notifications n
  where n.id = target_notification_id;
  if not found then raise exception 'Stock alert notification not found'; end if;
  if not private.has_permission(updated_notification.business_id, 'inventory.manage') then
    raise exception 'Inventory management permission required';
  end if;
  if not private.can_access_warehouse(updated_notification.warehouse_id) then
    raise exception 'Warehouse access required';
  end if;
  if updated_notification.status = 'resolved' then
    return jsonb_build_object('id', updated_notification.id, 'status', 'resolved');
  end if;
  update public.inventory_stock_alert_notifications
  set status = 'acknowledged', acknowledged_at = now(), acknowledged_by = auth.uid(), updated_at = now()
  where id = target_notification_id
  returning * into updated_notification;
  perform private.write_tenant_audit(
    updated_notification.business_id, 'inventory_stock_alert.acknowledged',
    'inventory_stock_alert_notification', updated_notification.id::text,
    jsonb_build_object('status', updated_notification.status)
  );
  return jsonb_build_object('id', updated_notification.id, 'status', updated_notification.status);
end;
$acknowledge_stock_alert$;

revoke all on function public.refresh_inventory_stock_alert_notifications(uuid) from public, anon;
revoke all on function public.get_inventory_stock_alert_notifications(uuid, boolean) from public, anon;
revoke all on function public.acknowledge_inventory_stock_alert(uuid) from public, anon;
grant execute on function public.refresh_inventory_stock_alert_notifications(uuid) to authenticated;
grant execute on function public.get_inventory_stock_alert_notifications(uuid, boolean) to authenticated;
grant execute on function public.acknowledge_inventory_stock_alert(uuid) to authenticated;
