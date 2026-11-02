-- Stock-reserving sales orders. Open orders reserve inventory without moving
-- stock; cancellation releases it; fulfillment atomically releases the
-- reservation and completes the authoritative sale.

create table public.sales_orders (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  warehouse_id uuid not null,
  customer_id uuid,
  order_number text not null,
  title text not null check (length(btrim(title)) between 1 and 120),
  status text not null default 'open'
    check (status in ('open', 'cancelled', 'fulfilled')),
  requested_delivery_on date not null,
  subtotal numeric(18,2) not null check (subtotal >= 0),
  order_discount numeric(18,2) not null default 0 check (order_discount >= 0),
  discount_total numeric(18,2) not null default 0 check (discount_total >= 0),
  tax_total numeric(18,2) not null default 0 check (tax_total >= 0),
  grand_total numeric(18,2) not null check (grand_total >= 0),
  operation_id uuid not null,
  fulfilled_sale_id uuid,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, order_number),
  unique (business_id, operation_id),
  constraint sales_orders_branch_fkey foreign key (branch_id, business_id)
    references public.branches(id, business_id) on delete restrict,
  constraint sales_orders_warehouse_fkey foreign key (warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete restrict,
  constraint sales_orders_customer_fkey foreign key (customer_id, business_id)
    references public.customers(id, business_id) on delete restrict,
  constraint sales_orders_fulfilled_sale_fkey
    foreign key (fulfilled_sale_id, business_id)
    references public.sales(id, business_id) on delete restrict,
  check (
    (status = 'fulfilled' and fulfilled_sale_id is not null)
    or (status <> 'fulfilled' and fulfilled_sale_id is null)
  )
);

create table public.sales_order_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  order_id uuid not null,
  variant_id uuid not null,
  product_name text not null,
  variant_name text not null,
  sku text not null,
  quantity numeric(20,6) not null check (quantity > 0),
  reserved_quantity numeric(20,6) not null default 0
    check (reserved_quantity >= 0 and reserved_quantity <= quantity),
  track_inventory boolean not null,
  unit_price numeric(18,4) not null check (unit_price >= 0),
  discount_amount numeric(18,2) not null default 0 check (discount_amount >= 0),
  tax_rate numeric(8,4) not null default 0 check (tax_rate between 0 and 100),
  tax_amount numeric(18,2) not null default 0 check (tax_amount >= 0),
  line_total numeric(18,2) not null check (line_total >= 0),
  note text,
  created_at timestamptz not null default now(),
  unique (order_id, variant_id),
  constraint sales_order_items_order_fkey
    foreign key (order_id, business_id)
    references public.sales_orders(id, business_id) on delete cascade,
  constraint sales_order_items_variant_fkey
    foreign key (variant_id, business_id)
    references public.product_variants(id, business_id) on delete restrict,
  constraint sales_order_items_reservation_check check (
    (track_inventory and reserved_quantity = quantity)
    or (not track_inventory and reserved_quantity = 0)
  ),
  constraint sales_order_items_total_formula_check check (
    line_total = round(
      (quantity * unit_price) - discount_amount + tax_amount,
      2
    )
  )
);

create index sales_orders_business_status_updated_idx
  on public.sales_orders(business_id, status, updated_at desc);
create index sales_orders_branch_business_fk_idx
  on public.sales_orders(branch_id, business_id);
create index sales_orders_warehouse_business_fk_idx
  on public.sales_orders(warehouse_id, business_id);
create index sales_orders_customer_business_fk_idx
  on public.sales_orders(customer_id, business_id)
  where customer_id is not null;
create index sales_orders_fulfilled_sale_business_fk_idx
  on public.sales_orders(fulfilled_sale_id, business_id)
  where fulfilled_sale_id is not null;
create index sales_orders_created_by_idx on public.sales_orders(created_by);
create index sales_orders_updated_by_idx on public.sales_orders(updated_by);
create index sales_order_items_order_business_fk_idx
  on public.sales_order_items(order_id, business_id);
create index sales_order_items_variant_business_fk_idx
  on public.sales_order_items(variant_id, business_id);

alter table public.sales_orders enable row level security;
alter table public.sales_order_items enable row level security;

create policy sales_orders_select on public.sales_orders
for select to authenticated
using (
  (select private.has_permission(business_id, 'sales.create'))
  and (select private.has_branch_access(branch_id))
);

create policy sales_order_items_select on public.sales_order_items
for select to authenticated
using (
  exists (
    select 1 from public.sales_orders sales_order
    where sales_order.id = order_id
      and sales_order.business_id = sales_order_items.business_id
      and (select private.has_permission(sales_order.business_id, 'sales.create'))
      and (select private.has_branch_access(sales_order.branch_id))
  )
);

revoke all on public.sales_orders, public.sales_order_items
from public, anon, authenticated;
grant select on public.sales_orders, public.sales_order_items to authenticated;

create or replace function public.save_sales_order(
  target_business_id uuid,
  target_branch_id uuid,
  target_warehouse_id uuid,
  target_customer_id uuid,
  operation_id uuid,
  order_title text,
  requested_delivery_on date,
  line_items jsonb,
  order_discount numeric default 0,
  target_order_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  saved_order_id uuid;
  previous_warehouse_id uuid;
  existing_result record;
  order_no text;
  old_item record;
  line_record record;
  variant_record record;
  balance_record public.inventory_balances%rowtype;
  reserved_amount numeric(20,6);
  subtotal_amount numeric(18,2) := 0;
  line_discount_total numeric(18,2) := 0;
  tax_amount_total numeric(18,2) := 0;
  calculated_tax numeric(18,2);
  calculated_line_total numeric(18,2);
  grand_total_amount numeric(18,2);
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if jsonb_typeof(line_items) <> 'array' or jsonb_array_length(line_items) = 0 then
    raise exception 'At least one sales order item is required';
  end if;
  if length(btrim(coalesce(order_title, ''))) not between 1 and 120 then
    raise exception 'Sales order title must be between 1 and 120 characters';
  end if;
  if requested_delivery_on is null or requested_delivery_on < current_date then
    raise exception 'Requested delivery date cannot be in the past';
  end if;
  if coalesce(order_discount, 0) < 0 then
    raise exception 'Order discount cannot be negative';
  end if;
  if not private.has_permission(target_business_id, 'sales.create') then
    raise exception 'You do not have permission to create sales orders';
  end if;
  if order_discount > 0
     and not private.has_permission(target_business_id, 'sales.discount') then
    raise exception 'You do not have permission to discount sales orders';
  end if;
  if not private.has_branch_access(target_branch_id) then
    raise exception 'Branch is not accessible';
  end if;
  if not exists (
    select 1 from public.warehouses warehouse
    where warehouse.id = target_warehouse_id
      and warehouse.business_id = target_business_id
      and warehouse.branch_id = target_branch_id
      and warehouse.is_active
  ) then raise exception 'Invalid warehouse for sales order'; end if;
  if target_customer_id is not null and not exists (
    select 1 from public.customers customer
    where customer.id = target_customer_id
      and customer.business_id = target_business_id
      and customer.is_active
      and customer.archived_at is null
  ) then raise exception 'Invalid customer for sales order'; end if;

  if target_order_id is not null then
    select sales_order.id, sales_order.order_number, sales_order.warehouse_id
    into saved_order_id, order_no, previous_warehouse_id
    from public.sales_orders sales_order
    where sales_order.id = target_order_id
      and sales_order.business_id = target_business_id
      and sales_order.status = 'open'
    for update;
    if not found then raise exception 'Open sales order not found'; end if;

    for old_item in
      select item.variant_id, item.reserved_quantity
      from public.sales_order_items item
      where item.order_id = saved_order_id
        and item.reserved_quantity > 0
      order by item.variant_id
    loop
      select * into balance_record
      from public.inventory_balances balance
      where balance.warehouse_id = previous_warehouse_id
        and balance.variant_id = old_item.variant_id
      for update;
      if not found or balance_record.quantity_reserved < old_item.reserved_quantity then
        raise exception 'Sales order reservation is inconsistent';
      end if;
      update public.inventory_balances
      set quantity_reserved = quantity_reserved - old_item.reserved_quantity,
          updated_at = now()
      where warehouse_id = previous_warehouse_id
        and variant_id = old_item.variant_id;
    end loop;

    update public.sales_orders
    set branch_id = target_branch_id,
        warehouse_id = target_warehouse_id,
        customer_id = target_customer_id,
        title = btrim(order_title),
        requested_delivery_on = save_sales_order.requested_delivery_on,
        operation_id = save_sales_order.operation_id,
        order_discount = round(coalesce(save_sales_order.order_discount, 0), 2),
        updated_by = caller_id,
        updated_at = now()
    where id = saved_order_id;
    delete from public.sales_order_items item
    where item.order_id = saved_order_id;
  else
    select sales_order.id, sales_order.order_number, sales_order.title
    into existing_result
    from public.sales_orders sales_order
    where sales_order.business_id = target_business_id
      and sales_order.operation_id = save_sales_order.operation_id;
    if found then
      return jsonb_build_object(
        'order_id', existing_result.id,
        'order_number', existing_result.order_number,
        'title', existing_result.title,
        'replayed', true
      );
    end if;

    saved_order_id := gen_random_uuid();
    order_no := 'SO-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS') || '-' ||
      upper(substr(replace(saved_order_id::text, '-', ''), 1, 8));
    insert into public.sales_orders (
      id, business_id, branch_id, warehouse_id, customer_id, order_number,
      title, requested_delivery_on, subtotal, order_discount, discount_total,
      tax_total, grand_total, operation_id, created_by, updated_by
    ) values (
      saved_order_id, target_business_id, target_branch_id, target_warehouse_id,
      target_customer_id, order_no, btrim(order_title), requested_delivery_on,
      0, round(coalesce(order_discount, 0), 2), 0, 0, 0,
      operation_id, caller_id, caller_id
    );
  end if;

  for line_record in
    select *
    from jsonb_to_recordset(line_items) as x(
      variant_id uuid, quantity numeric, unit_price numeric,
      discount_amount numeric, tax_rate numeric, note text
    )
    order by variant_id
  loop
    if line_record.variant_id is null
       or line_record.quantity is null or line_record.quantity <= 0
       or line_record.unit_price is null or line_record.unit_price < 0
       or coalesce(line_record.discount_amount, 0) < 0
       or coalesce(line_record.tax_rate, 0) < 0
       or coalesce(line_record.tax_rate, 0) > 100 then
      raise exception 'Invalid sales order line';
    end if;
    select variant.id, variant.name, variant.sku, product.name as product_name,
           product.track_inventory, product.allow_fractional_quantity
    into variant_record
    from public.product_variants variant
    join public.products product
      on product.id = variant.product_id
     and product.business_id = variant.business_id
    where variant.id = line_record.variant_id
      and variant.business_id = target_business_id
      and variant.is_active
      and variant.archived_at is null
      and product.is_active
      and product.archived_at is null;
    if not found then raise exception 'Sales order variant is unavailable'; end if;
    if not variant_record.allow_fractional_quantity
       and line_record.quantity <> trunc(line_record.quantity) then
      raise exception 'Fractional quantity is not allowed for sales order item';
    end if;
    if coalesce(line_record.discount_amount, 0) >
       line_record.quantity * line_record.unit_price then
      raise exception 'Sales order line discount exceeds line value';
    end if;

    reserved_amount := 0;
    if variant_record.track_inventory then
      insert into public.inventory_balances (
        business_id, warehouse_id, variant_id
      ) values (
        target_business_id, target_warehouse_id, line_record.variant_id
      ) on conflict (warehouse_id, variant_id) do nothing;
      select * into balance_record
      from public.inventory_balances balance
      where balance.warehouse_id = target_warehouse_id
        and balance.variant_id = line_record.variant_id
      for update;
      if balance_record.quantity_on_hand - balance_record.quantity_reserved <
         round(line_record.quantity, 6) then
        raise exception 'Insufficient available stock for SKU %', variant_record.sku;
      end if;
      reserved_amount := round(line_record.quantity, 6);
      update public.inventory_balances
      set quantity_reserved = quantity_reserved + reserved_amount,
          updated_at = now()
      where warehouse_id = target_warehouse_id
        and variant_id = line_record.variant_id;
    end if;

    calculated_tax := round(
      ((line_record.quantity * line_record.unit_price) -
        coalesce(line_record.discount_amount, 0)) *
      coalesce(line_record.tax_rate, 0) / 100,
      2
    );
    calculated_line_total := round(
      (line_record.quantity * line_record.unit_price) -
      coalesce(line_record.discount_amount, 0) + calculated_tax,
      2
    );
    subtotal_amount := subtotal_amount +
      round(line_record.quantity * line_record.unit_price, 2);
    line_discount_total := line_discount_total +
      round(coalesce(line_record.discount_amount, 0), 2);
    tax_amount_total := tax_amount_total + calculated_tax;

    insert into public.sales_order_items (
      business_id, order_id, variant_id, product_name, variant_name, sku,
      quantity, reserved_quantity, track_inventory, unit_price,
      discount_amount, tax_rate, tax_amount, line_total, note
    ) values (
      target_business_id, saved_order_id, line_record.variant_id,
      variant_record.product_name, variant_record.name, variant_record.sku,
      round(line_record.quantity, 6), reserved_amount,
      variant_record.track_inventory, round(line_record.unit_price, 4),
      round(coalesce(line_record.discount_amount, 0), 2),
      round(coalesce(line_record.tax_rate, 0), 4), calculated_tax,
      calculated_line_total, nullif(btrim(line_record.note), '')
    );
  end loop;

  if round(coalesce(order_discount, 0), 2) >
     subtotal_amount - line_discount_total then
    raise exception 'Order discount exceeds sales order value';
  end if;
  grand_total_amount := round(
    subtotal_amount - line_discount_total -
    round(coalesce(order_discount, 0), 2) + tax_amount_total,
    2
  );
  update public.sales_orders
  set subtotal = subtotal_amount,
      order_discount = round(coalesce(save_sales_order.order_discount, 0), 2),
      discount_total = line_discount_total +
        round(coalesce(save_sales_order.order_discount, 0), 2),
      tax_total = tax_amount_total,
      grand_total = grand_total_amount
  where id = saved_order_id;

  perform private.write_tenant_audit(
    target_business_id,
    case when target_order_id is null
      then 'sales.order_created' else 'sales.order_updated' end,
    'sales_order',
    saved_order_id::text,
    jsonb_build_object(
      'order_number', order_no,
      'grand_total', grand_total_amount,
      'requested_delivery_on', requested_delivery_on
    )
  );
  return jsonb_build_object(
    'order_id', saved_order_id,
    'order_number', order_no,
    'title', btrim(order_title),
    'grand_total', grand_total_amount,
    'replayed', false
  );
end;
$$;

create or replace function public.cancel_sales_order(target_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  order_record record;
  item_record record;
  balance_record public.inventory_balances%rowtype;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select sales_order.id, sales_order.business_id, sales_order.branch_id,
         sales_order.warehouse_id, sales_order.order_number, sales_order.status
  into order_record
  from public.sales_orders sales_order
  where sales_order.id = target_order_id
  for update;
  if not found then return jsonb_build_object('cancelled', false); end if;
  if not private.has_permission(order_record.business_id, 'sales.create')
     or not private.has_branch_access(order_record.branch_id) then
    raise exception 'You do not have permission to cancel this sales order';
  end if;
  if order_record.status <> 'open' then
    raise exception 'Only open sales orders can be cancelled';
  end if;

  for item_record in
    select item.variant_id, item.reserved_quantity
    from public.sales_order_items item
    where item.order_id = order_record.id
      and item.reserved_quantity > 0
    order by item.variant_id
  loop
    select * into balance_record
    from public.inventory_balances balance
    where balance.warehouse_id = order_record.warehouse_id
      and balance.variant_id = item_record.variant_id
    for update;
    if not found or balance_record.quantity_reserved < item_record.reserved_quantity then
      raise exception 'Sales order reservation is inconsistent';
    end if;
    update public.inventory_balances
    set quantity_reserved = quantity_reserved - item_record.reserved_quantity,
        updated_at = now()
    where warehouse_id = order_record.warehouse_id
      and variant_id = item_record.variant_id;
  end loop;

  update public.sales_orders
  set status = 'cancelled', updated_by = caller_id, updated_at = now()
  where id = order_record.id;
  perform private.write_tenant_audit(
    order_record.business_id, 'sales.order_cancelled', 'sales_order',
    order_record.id::text,
    jsonb_build_object('order_number', order_record.order_number)
  );
  return jsonb_build_object('cancelled', true);
end;
$$;

create or replace function public.fulfill_sales_order(
  target_order_id uuid,
  target_register_id uuid,
  target_shift_id uuid,
  operation_id uuid,
  payment_lines jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  order_record record;
  item_record record;
  balance_record public.inventory_balances%rowtype;
  sale_lines jsonb;
  sale_result jsonb;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if jsonb_typeof(payment_lines) <> 'array' or jsonb_array_length(payment_lines) = 0 then
    raise exception 'At least one payment is required';
  end if;

  select sales_order.*
  into order_record
  from public.sales_orders sales_order
  where sales_order.id = target_order_id
  for update;
  if not found then raise exception 'Sales order not found'; end if;
  if not private.has_permission(order_record.business_id, 'sales.create')
     or not private.has_branch_access(order_record.branch_id) then
    raise exception 'You do not have permission to fulfill this sales order';
  end if;
  if order_record.status = 'fulfilled' then
    select jsonb_build_object(
      'sale_id', sale.id,
      'invoice_number', sale.invoice_number,
      'grand_total', sale.grand_total,
      'payment_status', sale.payment_status,
      'sales_order_id', order_record.id,
      'order_number', order_record.order_number,
      'replayed', true
    ) into sale_result
    from public.sales sale
    where sale.id = order_record.fulfilled_sale_id;
    return sale_result;
  end if;
  if order_record.status <> 'open' then
    raise exception 'Only open sales orders can be fulfilled';
  end if;

  for item_record in
    select item.variant_id, item.reserved_quantity
    from public.sales_order_items item
    where item.order_id = order_record.id
      and item.reserved_quantity > 0
    order by item.variant_id
  loop
    select * into balance_record
    from public.inventory_balances balance
    where balance.warehouse_id = order_record.warehouse_id
      and balance.variant_id = item_record.variant_id
    for update;
    if not found or balance_record.quantity_reserved < item_record.reserved_quantity then
      raise exception 'Sales order reservation is inconsistent';
    end if;
    update public.inventory_balances
    set quantity_reserved = quantity_reserved - item_record.reserved_quantity,
        updated_at = now()
    where warehouse_id = order_record.warehouse_id
      and variant_id = item_record.variant_id;
  end loop;

  select jsonb_agg(
    jsonb_build_object(
      'variant_id', item.variant_id,
      'warehouse_id', case when item.track_inventory
        then order_record.warehouse_id else null end,
      'quantity', item.quantity,
      'unit_price', item.unit_price,
      'discount_amount', item.discount_amount,
      'tax_rate', item.tax_rate,
      'note', item.note
    ) order by item.variant_id
  ) into sale_lines
  from public.sales_order_items item
  where item.order_id = order_record.id;

  sale_result := public.complete_sale(
    order_record.business_id,
    order_record.branch_id,
    target_register_id,
    target_shift_id,
    order_record.customer_id,
    operation_id,
    sale_lines,
    payment_lines,
    order_record.order_discount,
    'Fulfilled sales order ' || order_record.order_number
  );

  update public.sales
  set sale_type = 'sales_order'
  where id = (sale_result ->> 'sale_id')::uuid;
  update public.sales_orders
  set status = 'fulfilled',
      fulfilled_sale_id = (sale_result ->> 'sale_id')::uuid,
      updated_by = caller_id,
      updated_at = now()
  where id = order_record.id;

  perform private.write_tenant_audit(
    order_record.business_id, 'sales.order_fulfilled', 'sales_order',
    order_record.id::text,
    jsonb_build_object(
      'order_number', order_record.order_number,
      'sale_id', sale_result ->> 'sale_id'
    )
  );
  return sale_result || jsonb_build_object(
    'sales_order_id', order_record.id,
    'order_number', order_record.order_number,
    'replayed', false
  );
end;
$$;

revoke all on function public.save_sales_order(
  uuid, uuid, uuid, uuid, uuid, text, date, jsonb, numeric, uuid
) from public, anon, authenticated;
grant execute on function public.save_sales_order(
  uuid, uuid, uuid, uuid, uuid, text, date, jsonb, numeric, uuid
) to authenticated;

revoke all on function public.cancel_sales_order(uuid)
from public, anon, authenticated;
grant execute on function public.cancel_sales_order(uuid) to authenticated;

revoke all on function public.fulfill_sales_order(
  uuid, uuid, uuid, uuid, jsonb
) from public, anon, authenticated;
grant execute on function public.fulfill_sales_order(
  uuid, uuid, uuid, uuid, jsonb
) to authenticated;
