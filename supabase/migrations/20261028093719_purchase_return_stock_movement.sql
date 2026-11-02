-- Atomic supplier returns against received purchase-order quantities.

create table public.purchase_returns (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  purchase_order_id uuid not null,
  warehouse_id uuid not null,
  return_number text not null,
  status text not null default 'completed' check (status = 'completed'),
  total_cost numeric(18,2) not null check (total_cost >= 0),
  reason text not null check (length(btrim(reason)) between 1 and 500),
  notes text,
  operation_id uuid not null,
  returned_by uuid not null references auth.users(id) on delete restrict,
  returned_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, return_number),
  unique (business_id, operation_id),
  constraint purchase_returns_order_fkey
    foreign key (purchase_order_id, business_id)
    references public.purchase_orders(id, business_id) on delete restrict,
  constraint purchase_returns_warehouse_fkey
    foreign key (warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete restrict
);

create table public.purchase_return_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  purchase_return_id uuid not null,
  purchase_order_item_id uuid not null,
  variant_id uuid not null,
  quantity numeric(20,6) not null check (quantity > 0),
  unit_cost numeric(18,4) not null check (unit_cost >= 0),
  line_total numeric(18,2) not null check (line_total >= 0),
  created_at timestamptz not null default now(),
  unique (purchase_return_id, purchase_order_item_id),
  constraint purchase_return_items_return_fkey
    foreign key (purchase_return_id, business_id)
    references public.purchase_returns(id, business_id) on delete restrict,
  constraint purchase_return_items_order_item_fkey
    foreign key (purchase_order_item_id, business_id)
    references public.purchase_order_items(id, business_id) on delete restrict,
  constraint purchase_return_items_variant_fkey
    foreign key (variant_id, business_id)
    references public.product_variants(id, business_id) on delete restrict,
  check (line_total = round(quantity * unit_cost, 2))
);

create index purchase_returns_business_returned_idx
  on public.purchase_returns(business_id, returned_at desc);
create index purchase_returns_order_business_fk_idx
  on public.purchase_returns(purchase_order_id, business_id);
create index purchase_returns_warehouse_business_fk_idx
  on public.purchase_returns(warehouse_id, business_id);
create index purchase_returns_returned_by_idx
  on public.purchase_returns(returned_by);
create index purchase_return_items_business_id_idx
  on public.purchase_return_items(business_id);
create index purchase_return_items_return_business_fk_idx
  on public.purchase_return_items(purchase_return_id, business_id);
create index purchase_return_items_order_item_business_fk_idx
  on public.purchase_return_items(purchase_order_item_id, business_id);
create index purchase_return_items_variant_business_fk_idx
  on public.purchase_return_items(variant_id, business_id);

create trigger purchase_returns_immutable
before update or delete on public.purchase_returns
for each row execute function private.prevent_immutable_change();

create trigger purchase_return_items_immutable
before update or delete on public.purchase_return_items
for each row execute function private.prevent_immutable_change();

alter table public.purchase_returns enable row level security;
alter table public.purchase_return_items enable row level security;

create policy purchase_returns_select
on public.purchase_returns for select to authenticated
using (
  (select private.has_permission(business_id, 'purchases.view'))
  and (select private.can_access_warehouse(warehouse_id))
);

create policy purchase_return_items_select
on public.purchase_return_items for select to authenticated
using (
  exists (
    select 1
    from public.purchase_returns pr
    where pr.id = purchase_return_id
      and (select private.has_permission(pr.business_id, 'purchases.view'))
      and (select private.can_access_warehouse(pr.warehouse_id))
  )
);

grant select on public.purchase_returns, public.purchase_return_items
to authenticated;
revoke all on public.purchase_returns, public.purchase_return_items
from anon;

create or replace function public.return_purchase_order(
  target_purchase_order_id uuid,
  operation_id uuid,
  returned_items jsonb,
  return_reason text,
  return_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  order_record public.purchase_orders%rowtype;
  order_item public.purchase_order_items%rowtype;
  balance_record public.inventory_balances%rowtype;
  item record;
  return_id uuid := gen_random_uuid();
  return_no text;
  return_total numeric(18,2);
  already_returned numeric(20,6);
  returnable_quantity numeric(20,6);
  next_quantity numeric(20,6);
  next_average_cost numeric(18,4);
  existing_result jsonb;
  inserted_count integer;
begin
  if caller_id is null then
    raise exception 'Authentication required';
  end if;
  if operation_id is null then
    raise exception 'Operation ID is required';
  end if;
  if nullif(btrim(return_reason), '') is null then
    raise exception 'A return reason is required';
  end if;
  if jsonb_typeof(returned_items) <> 'array'
     or jsonb_array_length(returned_items) = 0 then
    raise exception 'At least one returned item is required';
  end if;
  if (
    select count(*) <> count(distinct x.purchase_order_item_id)
    from jsonb_to_recordset(returned_items)
      as x(purchase_order_item_id uuid)
  ) then
    raise exception 'Each purchase line may appear only once';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(returned_items)
      as x(purchase_order_item_id uuid, quantity numeric)
    where x.purchase_order_item_id is null
      or x.quantity is null
      or x.quantity <= 0
  ) then
    raise exception 'Returned quantities must be positive';
  end if;

  select * into order_record
  from public.purchase_orders
  where id = target_purchase_order_id
  for update;
  if not found
     or order_record.status not in ('partially_received', 'received') then
    raise exception 'Purchase order has no received stock available to return';
  end if;
  if not private.has_permission(order_record.business_id, 'purchases.manage') then
    raise exception 'You do not have permission to return purchases';
  end if;
  if not private.can_access_warehouse(order_record.warehouse_id) then
    raise exception 'Warehouse is not accessible';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(returned_items)
      as x(purchase_order_item_id uuid)
    left join public.purchase_order_items poi
      on poi.id = x.purchase_order_item_id
     and poi.purchase_order_id = target_purchase_order_id
    where poi.id is null
  ) then
    raise exception 'A returned line does not belong to this purchase order';
  end if;

  select coalesce(sum(round(x.quantity * poi.unit_cost, 2)), 0)
  into return_total
  from jsonb_to_recordset(returned_items)
    as x(purchase_order_item_id uuid, quantity numeric)
  join public.purchase_order_items poi
    on poi.id = x.purchase_order_item_id
   and poi.purchase_order_id = target_purchase_order_id;

  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (
    order_record.business_id, operation_id, 'purchase.return', caller_id
  )
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select result into existing_result
    from public.idempotency_records i
    where i.business_id = order_record.business_id
      and i.operation_id = return_purchase_order.operation_id
      and i.operation_type = 'purchase.return';
    if existing_result <> '{}'::jsonb then
      return existing_result;
    end if;
    raise exception 'Purchase return operation is already in progress';
  end if;

  return_no := 'PRN-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS') || '-'
    || upper(substr(replace(return_id::text, '-', ''), 1, 8));
  insert into public.purchase_returns (
    id, business_id, purchase_order_id, warehouse_id, return_number,
    total_cost, reason, notes, operation_id, returned_by
  ) values (
    return_id, order_record.business_id, order_record.id,
    order_record.warehouse_id, return_no, return_total, btrim(return_reason),
    nullif(btrim(return_notes), ''), operation_id, caller_id
  );

  for item in
    select x.purchase_order_item_id, round(x.quantity, 6) as quantity,
           poi.variant_id
    from jsonb_to_recordset(returned_items)
      as x(purchase_order_item_id uuid, quantity numeric)
    join public.purchase_order_items poi
      on poi.id = x.purchase_order_item_id
     and poi.purchase_order_id = target_purchase_order_id
    order by poi.variant_id, poi.id
  loop
    select * into order_item
    from public.purchase_order_items
    where id = item.purchase_order_item_id
      and purchase_order_id = target_purchase_order_id
    for update;
    if not found then
      raise exception 'Purchase order line not found';
    end if;
    if item.quantity <> trunc(item.quantity) and not exists (
      select 1
      from public.product_variants v
      join public.products p
        on p.id = v.product_id and p.business_id = v.business_id
      where v.id = order_item.variant_id
        and p.allow_fractional_quantity
    ) then
      raise exception 'Fractional quantity is not allowed for SKU %', order_item.sku;
    end if;

    select coalesce(sum(pri.quantity), 0)
    into already_returned
    from public.purchase_return_items pri
    where pri.purchase_order_item_id = order_item.id;
    returnable_quantity := order_item.received_quantity - already_returned;
    if item.quantity > returnable_quantity then
      raise exception 'Returned quantity exceeds received stock for SKU %', order_item.sku;
    end if;

    select * into balance_record
    from public.inventory_balances b
    where b.warehouse_id = order_record.warehouse_id
      and b.variant_id = order_item.variant_id
    for update;
    if not found then
      raise exception 'Inventory balance not found for SKU %', order_item.sku;
    end if;
    next_quantity := balance_record.quantity_on_hand - item.quantity;
    if next_quantity < 0
       or next_quantity < balance_record.quantity_reserved then
      raise exception 'Not enough unreserved stock to return SKU %', order_item.sku;
    end if;
    next_average_cost := case
      when next_quantity = 0 then 0
      else greatest(
        0,
        round(
          (
            (balance_record.quantity_on_hand * balance_record.average_cost)
            - (item.quantity * order_item.unit_cost)
          ) / next_quantity,
          4
        )
      )
    end;

    update public.inventory_balances
    set quantity_on_hand = next_quantity,
        average_cost = next_average_cost,
        updated_at = now()
    where warehouse_id = order_record.warehouse_id
      and variant_id = order_item.variant_id;

    insert into public.purchase_return_items (
      business_id, purchase_return_id, purchase_order_item_id, variant_id,
      quantity, unit_cost, line_total
    ) values (
      order_record.business_id, return_id, order_item.id,
      order_item.variant_id, item.quantity, order_item.unit_cost,
      round(item.quantity * order_item.unit_cost, 2)
    );

    insert into public.inventory_movements (
      business_id, warehouse_id, variant_id, movement_type, quantity_delta,
      quantity_before, quantity_after, unit_cost, reference_type, reference_id,
      reason, operation_id, created_by
    ) values (
      order_record.business_id, order_record.warehouse_id,
      order_item.variant_id, 'purchase_return', -item.quantity,
      balance_record.quantity_on_hand, next_quantity, order_item.unit_cost,
      'purchase_return', return_id, btrim(return_reason), operation_id, caller_id
    );
  end loop;

  existing_result := jsonb_build_object(
    'purchase_return_id', return_id,
    'return_number', return_no,
    'returned_total', return_total,
    'status', 'completed'
  );
  update public.idempotency_records
  set result = existing_result
  where business_id = order_record.business_id
    and idempotency_records.operation_id = return_purchase_order.operation_id
    and operation_type = 'purchase.return';
  perform private.write_tenant_audit(
    order_record.business_id,
    'purchase_order.returned',
    'purchase_return',
    return_id::text,
    existing_result || jsonb_build_object('purchase_order_id', order_record.id)
  );
  return existing_result;
end;
$$;

revoke all on function public.return_purchase_order(
  uuid, uuid, jsonb, text, text
) from public, anon;
grant execute on function public.return_purchase_order(
  uuid, uuid, jsonb, text, text
) to authenticated;
