-- Persistent POS hold/park/resume carts. Held carts never reserve or move
-- inventory; current stock and prices are revalidated when checkout completes.

create table public.held_pos_carts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  warehouse_id uuid not null,
  customer_id uuid,
  label text not null check (length(btrim(label)) between 1 and 120),
  payment_method text not null default 'cash' check (payment_method in (
    'cash', 'upi', 'card', 'bank_transfer', 'wallet', 'customer_credit',
    'credit_note', 'split', 'partial'
  )),
  order_discount numeric(18,2) not null default 0 check (order_discount >= 0),
  operation_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, operation_id),
  constraint held_pos_carts_branch_fkey foreign key (branch_id, business_id)
    references public.branches(id, business_id) on delete restrict,
  constraint held_pos_carts_warehouse_fkey foreign key (warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete restrict,
  constraint held_pos_carts_customer_fkey foreign key (customer_id, business_id)
    references public.customers(id, business_id) on delete restrict
);

create table public.held_pos_cart_items (
  held_cart_id uuid not null,
  business_id uuid not null,
  variant_id uuid not null,
  quantity numeric(20,6) not null check (quantity > 0),
  created_at timestamptz not null default now(),
  primary key (held_cart_id, variant_id),
  constraint held_pos_cart_items_cart_fkey
    foreign key (held_cart_id, business_id)
    references public.held_pos_carts(id, business_id) on delete cascade,
  constraint held_pos_cart_items_variant_fkey
    foreign key (variant_id, business_id)
    references public.product_variants(id, business_id) on delete restrict
);

create index held_pos_carts_business_branch_created_idx
  on public.held_pos_carts(business_id, branch_id, updated_at desc);
create index held_pos_carts_warehouse_business_fk_idx
  on public.held_pos_carts(warehouse_id, business_id);
create index held_pos_carts_customer_business_fk_idx
  on public.held_pos_carts(customer_id, business_id)
  where customer_id is not null;
create index held_pos_carts_created_by_idx
  on public.held_pos_carts(created_by);
create index held_pos_carts_updated_by_idx
  on public.held_pos_carts(updated_by);
create index held_pos_cart_items_cart_business_fk_idx
  on public.held_pos_cart_items(held_cart_id, business_id);
create index held_pos_cart_items_variant_business_fk_idx
  on public.held_pos_cart_items(variant_id, business_id);

alter table public.held_pos_carts enable row level security;
alter table public.held_pos_cart_items enable row level security;

create policy held_pos_carts_select on public.held_pos_carts
for select to authenticated
using (
  (select private.has_permission(business_id, 'sales.create'))
  and (select private.has_branch_access(branch_id))
);

create policy held_pos_cart_items_select on public.held_pos_cart_items
for select to authenticated
using (
  exists (
    select 1
    from public.held_pos_carts held
    where held.id = held_cart_id
      and held.business_id = held_pos_cart_items.business_id
      and (select private.has_permission(held.business_id, 'sales.create'))
      and (select private.has_branch_access(held.branch_id))
  )
);

revoke all on public.held_pos_carts, public.held_pos_cart_items
from public, anon, authenticated;
grant select on public.held_pos_carts, public.held_pos_cart_items
to authenticated;

create or replace function public.hold_pos_cart(
  target_business_id uuid,
  target_branch_id uuid,
  target_warehouse_id uuid,
  target_customer_id uuid,
  operation_id uuid,
  cart_label text,
  selected_payment_method text,
  order_discount numeric,
  line_items jsonb,
  target_held_cart_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  saved_cart_id uuid;
  existing_label text;
  item record;
  variant_record record;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if jsonb_typeof(line_items) <> 'array' or jsonb_array_length(line_items) = 0 then
    raise exception 'At least one held cart item is required';
  end if;
  if length(btrim(coalesce(cart_label, ''))) not between 1 and 120 then
    raise exception 'Held cart label must be between 1 and 120 characters';
  end if;
  if selected_payment_method not in (
    'cash', 'upi', 'card', 'bank_transfer', 'wallet', 'customer_credit',
    'credit_note', 'split', 'partial'
  ) then raise exception 'Invalid held cart payment method'; end if;
  if coalesce(order_discount, 0) < 0 then
    raise exception 'Order discount cannot be negative';
  end if;
  if not private.has_permission(target_business_id, 'sales.create') then
    raise exception 'You do not have permission to hold sales';
  end if;
  if order_discount > 0
     and not private.has_permission(target_business_id, 'sales.discount') then
    raise exception 'You do not have permission to hold a discounted sale';
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
  ) then raise exception 'Invalid warehouse for held sale'; end if;
  if target_customer_id is not null and not exists (
    select 1 from public.customers customer
    where customer.id = target_customer_id
      and customer.business_id = target_business_id
      and customer.is_active
      and customer.archived_at is null
  ) then raise exception 'Invalid customer for held sale'; end if;

  if target_held_cart_id is not null then
    select held.id into saved_cart_id
    from public.held_pos_carts held
    where held.id = target_held_cart_id
      and held.business_id = target_business_id
    for update;
    if not found then raise exception 'Held cart not found'; end if;

    update public.held_pos_carts
    set branch_id = target_branch_id,
        warehouse_id = target_warehouse_id,
        customer_id = target_customer_id,
        label = btrim(cart_label),
        payment_method = selected_payment_method,
        order_discount = round(coalesce(hold_pos_cart.order_discount, 0), 2),
        operation_id = hold_pos_cart.operation_id,
        updated_by = caller_id,
        updated_at = now()
    where id = saved_cart_id;
    delete from public.held_pos_cart_items cart_item
    where cart_item.held_cart_id = saved_cart_id;
  else
    select held.id, held.label into saved_cart_id, existing_label
    from public.held_pos_carts held
    where held.business_id = target_business_id
      and held.operation_id = hold_pos_cart.operation_id;
    if found then
      return jsonb_build_object(
        'held_cart_id', saved_cart_id,
        'label', existing_label,
        'replayed', true
      );
    end if;

    saved_cart_id := gen_random_uuid();
    insert into public.held_pos_carts (
      id, business_id, branch_id, warehouse_id, customer_id, label,
      payment_method, order_discount, operation_id, created_by, updated_by
    ) values (
      saved_cart_id, target_business_id, target_branch_id, target_warehouse_id,
      target_customer_id, btrim(cart_label), selected_payment_method,
      round(coalesce(order_discount, 0), 2), operation_id, caller_id, caller_id
    );
  end if;

  for item in
    select *
    from jsonb_to_recordset(line_items) as x(variant_id uuid, quantity numeric)
    order by variant_id
  loop
    if item.variant_id is null or item.quantity is null or item.quantity <= 0 then
      raise exception 'Invalid held cart item';
    end if;
    select variant.id, product.allow_fractional_quantity
    into variant_record
    from public.product_variants variant
    join public.products product
      on product.id = variant.product_id
     and product.business_id = variant.business_id
    where variant.id = item.variant_id
      and variant.business_id = target_business_id
      and variant.is_active
      and variant.archived_at is null
      and product.is_active
      and product.archived_at is null;
    if not found then raise exception 'Held cart variant is unavailable'; end if;
    if not variant_record.allow_fractional_quantity
       and item.quantity <> trunc(item.quantity) then
      raise exception 'Fractional quantity is not allowed for held cart item';
    end if;
    insert into public.held_pos_cart_items (
      held_cart_id, business_id, variant_id, quantity
    ) values (
      saved_cart_id, target_business_id, item.variant_id,
      round(item.quantity, 6)
    );
  end loop;

  perform private.write_tenant_audit(
    target_business_id,
    case when target_held_cart_id is null then 'pos.cart_held' else 'pos.cart_updated' end,
    'held_pos_cart',
    saved_cart_id::text,
    jsonb_build_object('label', btrim(cart_label), 'item_count', jsonb_array_length(line_items))
  );

  return jsonb_build_object(
    'held_cart_id', saved_cart_id,
    'label', btrim(cart_label),
    'replayed', false
  );
end;
$$;

create or replace function public.discard_held_pos_cart(target_held_cart_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  held_record record;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;

  select held.id, held.business_id, held.branch_id, held.label
  into held_record
  from public.held_pos_carts held
  where held.id = target_held_cart_id
  for update;
  if not found then
    return jsonb_build_object('discarded', false);
  end if;
  if not private.has_permission(held_record.business_id, 'sales.create')
     or not private.has_branch_access(held_record.branch_id) then
    raise exception 'You do not have permission to discard this held cart';
  end if;

  delete from public.held_pos_carts where id = held_record.id;
  perform private.write_tenant_audit(
    held_record.business_id,
    'pos.cart_discarded',
    'held_pos_cart',
    held_record.id::text,
    jsonb_build_object('label', held_record.label)
  );
  return jsonb_build_object('discarded', true);
end;
$$;

revoke all on function public.hold_pos_cart(
  uuid, uuid, uuid, uuid, uuid, text, text, numeric, jsonb, uuid
) from public, anon, authenticated;
grant execute on function public.hold_pos_cart(
  uuid, uuid, uuid, uuid, uuid, text, text, numeric, jsonb, uuid
) to authenticated;

revoke all on function public.discard_held_pos_cart(uuid)
from public, anon, authenticated;
grant execute on function public.discard_held_pos_cart(uuid)
to authenticated;
