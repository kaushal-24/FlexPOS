-- FlexPOS customers and purchasing: supplier masters, purchase orders,
-- immutable goods receipts, and atomic inventory updates.

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  code text,
  name text not null check (length(btrim(name)) between 1 and 180),
  contact_name text,
  phone text,
  email text,
  gstin text,
  billing_address jsonb not null default '{}'::jsonb
    check (jsonb_typeof(billing_address) = 'object'),
  credit_days integer not null default 0 check (credit_days between 0 and 3650),
  notes text,
  is_active boolean not null default true,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, code)
);

create table public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  warehouse_id uuid not null,
  supplier_id uuid not null,
  order_number text not null,
  supplier_reference text,
  status text not null default 'ordered'
    check (status in ('draft', 'ordered', 'partially_received', 'received', 'cancelled')),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  subtotal numeric(18,2) not null default 0 check (subtotal >= 0),
  tax_total numeric(18,2) not null default 0 check (tax_total >= 0),
  grand_total numeric(18,2) not null default 0 check (grand_total >= 0),
  expected_at timestamptz,
  notes text,
  operation_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  ordered_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, order_number),
  unique (business_id, operation_id),
  constraint purchase_orders_branch_fkey foreign key (branch_id, business_id)
    references public.branches(id, business_id) on delete restrict,
  constraint purchase_orders_warehouse_fkey foreign key (warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete restrict,
  constraint purchase_orders_supplier_fkey foreign key (supplier_id, business_id)
    references public.suppliers(id, business_id) on delete restrict,
  check (grand_total = round(subtotal + tax_total, 2)),
  check (
    (status = 'received' and completed_at is not null)
    or (status <> 'received' and completed_at is null)
  )
);

create table public.purchase_order_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  purchase_order_id uuid not null,
  variant_id uuid not null,
  product_name text not null,
  variant_name text not null,
  sku text not null,
  ordered_quantity numeric(20,6) not null check (ordered_quantity > 0),
  received_quantity numeric(20,6) not null default 0
    check (received_quantity >= 0 and received_quantity <= ordered_quantity),
  unit_cost numeric(18,4) not null check (unit_cost >= 0),
  tax_rate numeric(8,4) not null default 0 check (tax_rate between 0 and 100),
  tax_amount numeric(18,2) not null default 0 check (tax_amount >= 0),
  line_total numeric(18,2) not null check (line_total >= 0),
  created_at timestamptz not null default now(),
  unique (id, business_id),
  unique (purchase_order_id, variant_id),
  constraint purchase_order_items_order_fkey
    foreign key (purchase_order_id, business_id)
    references public.purchase_orders(id, business_id) on delete restrict,
  constraint purchase_order_items_variant_fkey
    foreign key (variant_id, business_id)
    references public.product_variants(id, business_id) on delete restrict,
  check (
    line_total = round(ordered_quantity * unit_cost + tax_amount, 2)
  )
);

create table public.goods_receipts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  purchase_order_id uuid not null,
  warehouse_id uuid not null,
  receipt_number text not null,
  supplier_document_number text,
  status text not null default 'completed' check (status = 'completed'),
  total_cost numeric(18,2) not null default 0 check (total_cost >= 0),
  operation_id uuid not null,
  notes text,
  received_by uuid not null references auth.users(id) on delete restrict,
  received_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, receipt_number),
  unique (business_id, operation_id),
  constraint goods_receipts_order_fkey
    foreign key (purchase_order_id, business_id)
    references public.purchase_orders(id, business_id) on delete restrict,
  constraint goods_receipts_warehouse_fkey
    foreign key (warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete restrict
);

create table public.goods_receipt_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  goods_receipt_id uuid not null,
  purchase_order_item_id uuid not null,
  variant_id uuid not null,
  quantity numeric(20,6) not null check (quantity > 0),
  unit_cost numeric(18,4) not null check (unit_cost >= 0),
  line_total numeric(18,2) not null check (line_total >= 0),
  created_at timestamptz not null default now(),
  unique (goods_receipt_id, purchase_order_item_id),
  constraint goods_receipt_items_receipt_fkey
    foreign key (goods_receipt_id, business_id)
    references public.goods_receipts(id, business_id) on delete restrict,
  constraint goods_receipt_items_order_item_fkey
    foreign key (purchase_order_item_id, business_id)
    references public.purchase_order_items(id, business_id) on delete restrict,
  constraint goods_receipt_items_variant_fkey
    foreign key (variant_id, business_id)
    references public.product_variants(id, business_id) on delete restrict,
  check (line_total = round(quantity * unit_cost, 2))
);

create index suppliers_business_name_idx
  on public.suppliers(business_id, name) where archived_at is null;
create index suppliers_business_phone_idx
  on public.suppliers(business_id, phone) where phone is not null;
create index purchase_orders_business_created_idx
  on public.purchase_orders(business_id, created_at desc);
create index purchase_orders_branch_id_idx on public.purchase_orders(branch_id);
create index purchase_orders_warehouse_id_idx on public.purchase_orders(warehouse_id);
create index purchase_orders_supplier_id_idx on public.purchase_orders(supplier_id);
create index purchase_orders_created_by_idx on public.purchase_orders(created_by);
create index purchase_order_items_order_id_idx
  on public.purchase_order_items(purchase_order_id);
create index purchase_order_items_variant_id_idx
  on public.purchase_order_items(variant_id);
create index goods_receipts_business_received_idx
  on public.goods_receipts(business_id, received_at desc);
create index goods_receipts_order_id_idx on public.goods_receipts(purchase_order_id);
create index goods_receipts_warehouse_id_idx on public.goods_receipts(warehouse_id);
create index goods_receipts_received_by_idx on public.goods_receipts(received_by);
create index goods_receipt_items_receipt_id_idx
  on public.goods_receipt_items(goods_receipt_id);
create index goods_receipt_items_order_item_id_idx
  on public.goods_receipt_items(purchase_order_item_id);
create index goods_receipt_items_variant_id_idx
  on public.goods_receipt_items(variant_id);

create trigger suppliers_set_updated_at before update on public.suppliers
for each row execute function private.set_updated_at();
create trigger purchase_orders_set_updated_at before update on public.purchase_orders
for each row execute function private.set_updated_at();

create trigger purchase_orders_immutable
before delete on public.purchase_orders
for each row execute function private.prevent_immutable_change();
create trigger purchase_order_items_immutable
before delete on public.purchase_order_items
for each row execute function private.prevent_immutable_change();
create trigger goods_receipts_immutable
before update or delete on public.goods_receipts
for each row execute function private.prevent_immutable_change();
create trigger goods_receipt_items_immutable
before update or delete on public.goods_receipt_items
for each row execute function private.prevent_immutable_change();

alter table public.suppliers enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_items enable row level security;
alter table public.goods_receipts enable row level security;
alter table public.goods_receipt_items enable row level security;

create policy suppliers_select on public.suppliers for select to authenticated
using ((select private.has_permission(business_id, 'purchases.view')));
create policy suppliers_manage on public.suppliers for all to authenticated
using ((select private.has_permission(business_id, 'purchases.manage')))
with check ((select private.has_permission(business_id, 'purchases.manage')));

create policy purchase_orders_select on public.purchase_orders for select to authenticated
using (
  (select private.has_permission(business_id, 'purchases.view'))
  and (select private.has_branch_access(branch_id))
);
create policy purchase_order_items_select on public.purchase_order_items
for select to authenticated
using (
  exists (
    select 1 from public.purchase_orders po
    where po.id = purchase_order_id
      and (select private.has_permission(po.business_id, 'purchases.view'))
      and (select private.has_branch_access(po.branch_id))
  )
);
create policy goods_receipts_select on public.goods_receipts for select to authenticated
using (
  (select private.has_permission(business_id, 'purchases.view'))
  and (select private.can_access_warehouse(warehouse_id))
);
create policy goods_receipt_items_select on public.goods_receipt_items
for select to authenticated
using (
  exists (
    select 1 from public.goods_receipts gr
    where gr.id = goods_receipt_id
      and (select private.has_permission(gr.business_id, 'purchases.view'))
      and (select private.can_access_warehouse(gr.warehouse_id))
  )
);

grant select, insert, update on public.suppliers to authenticated;
grant select on public.purchase_orders, public.purchase_order_items,
  public.goods_receipts, public.goods_receipt_items to authenticated;
revoke all on public.suppliers, public.purchase_orders, public.purchase_order_items,
  public.goods_receipts, public.goods_receipt_items from anon;

create or replace function public.create_purchase_order(
  target_business_id uuid,
  target_supplier_id uuid,
  target_warehouse_id uuid,
  operation_id uuid,
  line_items jsonb,
  expected_delivery_at timestamptz default null,
  supplier_document_reference text default null,
  order_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  business_currency text;
  warehouse_record record;
  variant_record record;
  item record;
  order_id uuid := gen_random_uuid();
  order_no text;
  subtotal_amount numeric(18,2) := 0;
  tax_amount_total numeric(18,2) := 0;
  line_tax numeric(18,2);
  line_total_amount numeric(18,2);
  existing_result jsonb;
  inserted_count integer;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if jsonb_typeof(line_items) <> 'array' or jsonb_array_length(line_items) = 0 then
    raise exception 'At least one purchase item is required';
  end if;
  if not private.has_permission(target_business_id, 'purchases.manage') then
    raise exception 'You do not have permission to manage purchases';
  end if;

  select b.currency_code into business_currency
  from public.businesses b
  where b.id = target_business_id and b.archived_at is null;
  if not found then raise exception 'Business not found'; end if;

  select w.id, w.branch_id into warehouse_record
  from public.warehouses w
  where w.id = target_warehouse_id and w.business_id = target_business_id
    and w.is_active and private.has_branch_access(w.branch_id);
  if not found then raise exception 'Warehouse is not accessible'; end if;
  if not exists (
    select 1 from public.suppliers s
    where s.id = target_supplier_id and s.business_id = target_business_id
      and s.is_active and s.archived_at is null
  ) then raise exception 'Supplier is inactive or unavailable'; end if;
  if (
    select count(*) <> count(distinct x.variant_id)
    from jsonb_to_recordset(line_items) as x(variant_id uuid)
  ) then raise exception 'Each product variant may appear only once'; end if;

  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (target_business_id, operation_id, 'purchase.create', caller_id)
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select result into existing_result
    from public.idempotency_records i
    where i.business_id = target_business_id
      and i.operation_id = create_purchase_order.operation_id
      and i.operation_type = 'purchase.create';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Purchase operation is already in progress';
  end if;

  order_no := 'PO-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS') || '-'
    || upper(substr(replace(order_id::text, '-', ''), 1, 8));
  insert into public.purchase_orders (
    id, business_id, branch_id, warehouse_id, supplier_id, order_number,
    supplier_reference, currency_code, expected_at, notes, operation_id, created_by
  ) values (
    order_id, target_business_id, warehouse_record.branch_id, target_warehouse_id,
    target_supplier_id, order_no, nullif(btrim(supplier_document_reference), ''),
    business_currency, expected_delivery_at, nullif(btrim(order_notes), ''),
    operation_id, caller_id
  );

  for item in
    select * from jsonb_to_recordset(line_items) as x(
      variant_id uuid, quantity numeric, unit_cost numeric, tax_rate numeric
    ) order by variant_id
  loop
    if item.variant_id is null or item.quantity is null or item.quantity <= 0
       or item.unit_cost is null or item.unit_cost < 0
       or coalesce(item.tax_rate, 0) < 0 or coalesce(item.tax_rate, 0) > 100 then
      raise exception 'Invalid purchase line';
    end if;
    select v.id, v.name, v.sku, p.name as product_name,
           p.allow_fractional_quantity
    into variant_record
    from public.product_variants v
    join public.products p on p.id = v.product_id and p.business_id = v.business_id
    where v.id = item.variant_id and v.business_id = target_business_id
      and v.is_active and v.archived_at is null
      and p.is_active and p.archived_at is null and p.track_inventory;
    if not found then raise exception 'Purchase variant is inactive or not stock tracked'; end if;
    if not variant_record.allow_fractional_quantity
       and item.quantity <> trunc(item.quantity) then
      raise exception 'Fractional quantity is not allowed for SKU %', variant_record.sku;
    end if;

    line_tax := round(item.quantity * item.unit_cost * coalesce(item.tax_rate, 0) / 100, 2);
    line_total_amount := round(item.quantity * item.unit_cost + line_tax, 2);
    subtotal_amount := subtotal_amount + round(item.quantity * item.unit_cost, 2);
    tax_amount_total := tax_amount_total + line_tax;
    insert into public.purchase_order_items (
      business_id, purchase_order_id, variant_id, product_name, variant_name,
      sku, ordered_quantity, unit_cost, tax_rate, tax_amount, line_total
    ) values (
      target_business_id, order_id, item.variant_id, variant_record.product_name,
      variant_record.name, variant_record.sku, round(item.quantity, 6),
      round(item.unit_cost, 4), round(coalesce(item.tax_rate, 0), 4),
      line_tax, line_total_amount
    );
  end loop;

  update public.purchase_orders
  set subtotal = subtotal_amount, tax_total = tax_amount_total,
      grand_total = round(subtotal_amount + tax_amount_total, 2)
  where id = order_id;

  existing_result := jsonb_build_object(
    'purchase_order_id', order_id, 'order_number', order_no,
    'grand_total', round(subtotal_amount + tax_amount_total, 2), 'status', 'ordered'
  );
  update public.idempotency_records set result = existing_result
  where business_id = target_business_id
    and idempotency_records.operation_id = create_purchase_order.operation_id
    and operation_type = 'purchase.create';
  perform private.write_tenant_audit(
    target_business_id, 'purchase_order.created', 'purchase_order', order_id::text,
    existing_result
  );
  return existing_result;
end;
$$;

create or replace function public.receive_purchase_order(
  target_purchase_order_id uuid,
  operation_id uuid,
  received_items jsonb,
  supplier_document_reference text default null,
  receipt_notes text default null
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
  receipt_id uuid := gen_random_uuid();
  receipt_no text;
  next_quantity numeric(20,6);
  next_average_cost numeric(18,4);
  receipt_total numeric(18,2) := 0;
  remaining_lines integer;
  existing_result jsonb;
  inserted_count integer;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if jsonb_typeof(received_items) <> 'array' or jsonb_array_length(received_items) = 0 then
    raise exception 'At least one received item is required';
  end if;
  if (
    select count(*) <> count(distinct x.purchase_order_item_id)
    from jsonb_to_recordset(received_items) as x(purchase_order_item_id uuid)
  ) then raise exception 'Each purchase line may appear only once'; end if;

  select * into order_record from public.purchase_orders
  where id = target_purchase_order_id for update;
  if not found or order_record.status not in ('ordered', 'partially_received') then
    raise exception 'Purchase order is not open for receiving';
  end if;
  if not private.has_permission(order_record.business_id, 'purchases.manage') then
    raise exception 'You do not have permission to receive purchases';
  end if;
  if not private.can_access_warehouse(order_record.warehouse_id) then
    raise exception 'Warehouse is not accessible';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(received_items) as x(purchase_order_item_id uuid)
    left join public.purchase_order_items poi
      on poi.id = x.purchase_order_item_id
     and poi.purchase_order_id = target_purchase_order_id
    where poi.id is null
  ) then raise exception 'A received line does not belong to this purchase order'; end if;

  select coalesce(sum(round(x.quantity * poi.unit_cost, 2)), 0)
  into receipt_total
  from jsonb_to_recordset(received_items) as x(
    purchase_order_item_id uuid, quantity numeric
  )
  join public.purchase_order_items poi
    on poi.id = x.purchase_order_item_id
   and poi.purchase_order_id = target_purchase_order_id;

  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (order_record.business_id, operation_id, 'purchase.receive', caller_id)
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select result into existing_result
    from public.idempotency_records i
    where i.business_id = order_record.business_id
      and i.operation_id = receive_purchase_order.operation_id
      and i.operation_type = 'purchase.receive';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Receipt operation is already in progress';
  end if;

  receipt_no := 'GRN-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS') || '-'
    || upper(substr(replace(receipt_id::text, '-', ''), 1, 8));
  insert into public.goods_receipts (
    id, business_id, purchase_order_id, warehouse_id, receipt_number,
    supplier_document_number, total_cost, operation_id, notes, received_by
  ) values (
    receipt_id, order_record.business_id, order_record.id, order_record.warehouse_id,
    receipt_no, nullif(btrim(supplier_document_reference), ''), receipt_total, operation_id,
    nullif(btrim(receipt_notes), ''), caller_id
  );

  for item in
    select x.purchase_order_item_id, x.quantity, poi.variant_id
    from jsonb_to_recordset(received_items) as x(
      purchase_order_item_id uuid, quantity numeric
    )
    join public.purchase_order_items poi
      on poi.id = x.purchase_order_item_id
     and poi.purchase_order_id = target_purchase_order_id
    order by poi.variant_id, poi.id
  loop
    if item.quantity is null or item.quantity <= 0 then
      raise exception 'Received quantity must be positive';
    end if;
    select * into order_item from public.purchase_order_items
    where id = item.purchase_order_item_id
      and purchase_order_id = target_purchase_order_id
    for update;
    if not found then raise exception 'Purchase order line not found'; end if;
    if order_item.received_quantity + item.quantity > order_item.ordered_quantity then
      raise exception 'Received quantity exceeds remaining quantity for SKU %', order_item.sku;
    end if;
    if item.quantity <> trunc(item.quantity) and not exists (
      select 1 from public.product_variants v
      join public.products p on p.id = v.product_id and p.business_id = v.business_id
      where v.id = order_item.variant_id and p.allow_fractional_quantity
    ) then raise exception 'Fractional quantity is not allowed for SKU %', order_item.sku;
    end if;

    insert into public.inventory_balances (business_id, warehouse_id, variant_id)
    values (order_record.business_id, order_record.warehouse_id, order_item.variant_id)
    on conflict (warehouse_id, variant_id) do nothing;
    select * into balance_record from public.inventory_balances b
    where b.warehouse_id = order_record.warehouse_id
      and b.variant_id = order_item.variant_id
    for update;
    next_quantity := balance_record.quantity_on_hand + round(item.quantity, 6);
    next_average_cost := case
      when next_quantity = 0 then order_item.unit_cost
      else round(
        ((balance_record.quantity_on_hand * balance_record.average_cost)
          + (item.quantity * order_item.unit_cost)) / next_quantity,
        4
      )
    end;

    update public.inventory_balances
    set quantity_on_hand = next_quantity, average_cost = next_average_cost,
        updated_at = now()
    where warehouse_id = order_record.warehouse_id
      and variant_id = order_item.variant_id;
    update public.purchase_order_items
    set received_quantity = received_quantity + round(item.quantity, 6)
    where id = order_item.id;

    insert into public.goods_receipt_items (
      business_id, goods_receipt_id, purchase_order_item_id, variant_id,
      quantity, unit_cost, line_total
    ) values (
      order_record.business_id, receipt_id, order_item.id, order_item.variant_id,
      round(item.quantity, 6), order_item.unit_cost,
      round(item.quantity * order_item.unit_cost, 2)
    );
    insert into public.inventory_movements (
      business_id, warehouse_id, variant_id, movement_type, quantity_delta,
      quantity_before, quantity_after, unit_cost, reference_type, reference_id,
      reason, operation_id, created_by
    ) values (
      order_record.business_id, order_record.warehouse_id, order_item.variant_id,
      'purchase', round(item.quantity, 6), balance_record.quantity_on_hand,
      next_quantity, order_item.unit_cost, 'goods_receipt', receipt_id,
      'Purchase receipt', operation_id, caller_id
    );
  end loop;

  if not exists (
    select 1 from public.goods_receipt_items gri where gri.goods_receipt_id = receipt_id
  ) then raise exception 'No valid purchase order lines were supplied'; end if;
  select count(*) into remaining_lines from public.purchase_order_items poi
  where poi.purchase_order_id = order_record.id
    and poi.received_quantity < poi.ordered_quantity;
  update public.purchase_orders
  set status = case when remaining_lines = 0 then 'received' else 'partially_received' end,
      completed_at = case when remaining_lines = 0 then now() else null end
  where id = order_record.id;

  existing_result := jsonb_build_object(
    'goods_receipt_id', receipt_id, 'receipt_number', receipt_no,
    'received_total', receipt_total,
    'purchase_status', case when remaining_lines = 0 then 'received' else 'partially_received' end
  );
  update public.idempotency_records set result = existing_result
  where business_id = order_record.business_id
    and idempotency_records.operation_id = receive_purchase_order.operation_id
    and operation_type = 'purchase.receive';
  perform private.write_tenant_audit(
    order_record.business_id, 'purchase_order.received', 'goods_receipt',
    receipt_id::text, existing_result
  );
  return existing_result;
end;
$$;

revoke all on function public.create_purchase_order(
  uuid, uuid, uuid, uuid, jsonb, timestamptz, text, text
) from public, anon;
revoke all on function public.receive_purchase_order(
  uuid, uuid, jsonb, text, text
) from public, anon;
grant execute on function public.create_purchase_order(
  uuid, uuid, uuid, uuid, jsonb, timestamptz, text, text
) to authenticated;
grant execute on function public.receive_purchase_order(
  uuid, uuid, jsonb, text, text
) to authenticated;
