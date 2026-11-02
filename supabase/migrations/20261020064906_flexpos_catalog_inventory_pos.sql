-- FlexPOS production core: catalog, inventory, customers, registers, and POS.
-- Financial values use exact NUMERIC arithmetic. Operational mutations that
-- affect stock or money are available only through authorized RPC functions.

insert into public.permissions (code, category, description) values
  ('registers.manage', 'Sales', 'Create registers and manage cashier shifts')
on conflict (code) do update set
  category = excluded.category,
  description = excluded.description;

alter table public.branches
  add constraint branches_id_business_unique unique (id, business_id);

create table public.units (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 80),
  symbol text not null check (length(btrim(symbol)) between 1 and 16),
  precision smallint not null default 0 check (precision between 0 and 6),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, name),
  unique (id, business_id)
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  parent_id uuid,
  name text not null check (length(btrim(name)) between 1 and 120),
  color text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, name),
  unique (id, business_id),
  constraint categories_parent_fkey foreign key (parent_id, business_id)
    references public.categories(id, business_id) on delete restrict
);

create table public.brands (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 120),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, name),
  unique (id, business_id)
);

create table public.tax_rates (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 80),
  rate numeric(7,4) not null check (rate >= 0 and rate <= 100),
  tax_type text not null default 'gst'
    check (tax_type in ('gst', 'vat', 'sales_tax', 'service_tax', 'other')),
  is_inclusive boolean not null default false,
  effective_from date not null default current_date,
  effective_to date,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, name, effective_from),
  check (effective_to is null or effective_to >= effective_from),
  unique (id, business_id)
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  category_id uuid,
  brand_id uuid,
  base_unit_id uuid not null,
  tax_rate_id uuid,
  name text not null check (length(btrim(name)) between 1 and 180),
  description text,
  product_type text not null default 'goods'
    check (product_type in ('goods', 'service', 'bundle')),
  hsn_sac text,
  track_inventory boolean not null default true,
  allow_fractional_quantity boolean not null default false,
  is_favorite boolean not null default false,
  is_active boolean not null default true,
  attributes jsonb not null default '{}'::jsonb check (jsonb_typeof(attributes) = 'object'),
  archived_at timestamptz,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, business_id),
  constraint products_category_fkey foreign key (category_id, business_id)
    references public.categories(id, business_id) on delete restrict,
  constraint products_brand_fkey foreign key (brand_id, business_id)
    references public.brands(id, business_id) on delete restrict,
  constraint products_unit_fkey foreign key (base_unit_id, business_id)
    references public.units(id, business_id) on delete restrict,
  constraint products_tax_rate_fkey foreign key (tax_rate_id, business_id)
    references public.tax_rates(id, business_id) on delete restrict
);

create table public.product_variants (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  product_id uuid not null,
  name text not null default 'Default' check (length(btrim(name)) between 1 and 180),
  sku text not null check (length(btrim(sku)) between 1 and 80),
  cost_price numeric(18,4) not null default 0 check (cost_price >= 0),
  selling_price numeric(18,4) not null default 0 check (selling_price >= 0),
  mrp numeric(18,4) check (mrp is null or mrp >= 0),
  weight numeric(18,6) check (weight is null or weight >= 0),
  attributes jsonb not null default '{}'::jsonb check (jsonb_typeof(attributes) = 'object'),
  is_active boolean not null default true,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, sku),
  unique (id, business_id),
  constraint product_variants_product_fkey foreign key (product_id, business_id)
    references public.products(id, business_id) on delete cascade
);

create table public.product_barcodes (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  variant_id uuid not null,
  barcode text not null check (length(btrim(barcode)) between 1 and 128),
  barcode_type text not null default 'code128'
    check (barcode_type in ('code128', 'ean8', 'ean13', 'upc', 'qr', 'internal')),
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  unique (business_id, barcode),
  constraint product_barcodes_variant_fkey foreign key (variant_id, business_id)
    references public.product_variants(id, business_id) on delete cascade
);

create table public.product_prices (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  variant_id uuid not null,
  branch_id uuid,
  price_type text not null default 'retail'
    check (price_type in ('retail', 'wholesale', 'dealer', 'customer_group')),
  amount numeric(18,4) not null check (amount >= 0),
  minimum_quantity numeric(18,6) not null default 1 check (minimum_quantity > 0),
  valid_from timestamptz,
  valid_to timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint product_prices_variant_fkey foreign key (variant_id, business_id)
    references public.product_variants(id, business_id) on delete cascade,
  constraint product_prices_branch_fkey foreign key (branch_id, business_id)
    references public.branches(id, business_id) on delete cascade,
  check (valid_to is null or valid_from is null or valid_to > valid_from)
);

create unique index product_prices_unique_scope_idx
  on public.product_prices(
    business_id,
    variant_id,
    coalesce(branch_id, '00000000-0000-0000-0000-000000000000'::uuid),
    price_type,
    minimum_quantity,
    coalesce(valid_from, '-infinity'::timestamptz)
  );

create table public.warehouses (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  name text not null check (length(btrim(name)) between 1 and 120),
  code text not null check (length(btrim(code)) between 1 and 30),
  is_default boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, code),
  unique (id, business_id),
  constraint warehouses_branch_fkey foreign key (branch_id, business_id)
    references public.branches(id, business_id) on delete restrict
);

create unique index warehouses_one_default_per_branch_idx
  on public.warehouses(branch_id) where is_default and is_active;

create table public.inventory_balances (
  business_id uuid not null references public.businesses(id) on delete cascade,
  warehouse_id uuid not null,
  variant_id uuid not null,
  quantity_on_hand numeric(20,6) not null default 0,
  quantity_reserved numeric(20,6) not null default 0 check (quantity_reserved >= 0),
  reorder_point numeric(20,6) not null default 0 check (reorder_point >= 0),
  safety_stock numeric(20,6) not null default 0 check (safety_stock >= 0),
  average_cost numeric(18,4) not null default 0 check (average_cost >= 0),
  updated_at timestamptz not null default now(),
  primary key (warehouse_id, variant_id),
  constraint inventory_balances_warehouse_fkey foreign key (warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete cascade,
  constraint inventory_balances_variant_fkey foreign key (variant_id, business_id)
    references public.product_variants(id, business_id) on delete cascade,
  check (quantity_reserved <= greatest(quantity_on_hand, 0))
);

create table public.inventory_movements (
  id bigint generated always as identity primary key,
  business_id uuid not null references public.businesses(id) on delete cascade,
  warehouse_id uuid not null,
  variant_id uuid not null,
  movement_type text not null check (movement_type in (
    'opening', 'purchase', 'sale', 'sale_return', 'purchase_return',
    'adjustment', 'damage', 'wastage', 'transfer_out', 'transfer_in', 'stocktake'
  )),
  quantity_delta numeric(20,6) not null check (quantity_delta <> 0),
  quantity_before numeric(20,6) not null,
  quantity_after numeric(20,6) not null,
  unit_cost numeric(18,4) check (unit_cost is null or unit_cost >= 0),
  reference_type text,
  reference_id uuid,
  reason text,
  operation_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint inventory_movements_warehouse_fkey foreign key (warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete restrict,
  constraint inventory_movements_variant_fkey foreign key (variant_id, business_id)
    references public.product_variants(id, business_id) on delete restrict,
  unique (business_id, operation_id, warehouse_id, variant_id, movement_type)
);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  code text,
  name text not null check (length(btrim(name)) between 1 and 180),
  phone text,
  email text,
  gstin text,
  billing_address jsonb not null default '{}'::jsonb check (jsonb_typeof(billing_address) = 'object'),
  shipping_address jsonb not null default '{}'::jsonb check (jsonb_typeof(shipping_address) = 'object'),
  credit_limit numeric(18,2) not null default 0 check (credit_limit >= 0),
  loyalty_points numeric(20,4) not null default 0 check (loyalty_points >= 0),
  is_active boolean not null default true,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, code)
);

create table public.registers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  name text not null check (length(btrim(name)) between 1 and 100),
  code text not null check (length(btrim(code)) between 1 and 30),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, code),
  unique (id, business_id),
  constraint registers_branch_fkey foreign key (branch_id, business_id)
    references public.branches(id, business_id) on delete restrict
);

create table public.register_shifts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  register_id uuid not null,
  opened_by uuid not null references auth.users(id) on delete restrict,
  closed_by uuid references auth.users(id) on delete restrict,
  status text not null default 'open' check (status in ('open', 'closed')),
  opening_cash numeric(18,2) not null default 0 check (opening_cash >= 0),
  expected_cash numeric(18,2),
  closing_cash numeric(18,2),
  difference_amount numeric(18,2),
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  notes text,
  constraint register_shifts_register_fkey foreign key (register_id, business_id)
    references public.registers(id, business_id) on delete restrict,
  check (
    (status = 'open' and closed_at is null and closed_by is null)
    or (status = 'closed' and closed_at is not null and closed_by is not null)
  )
);

create unique index register_shifts_one_open_idx
  on public.register_shifts(register_id) where status = 'open';

create table public.sales (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  register_id uuid,
  shift_id uuid,
  customer_id uuid,
  invoice_number text not null,
  sale_type text not null default 'invoice'
    check (sale_type in ('draft', 'held', 'quotation', 'sales_order', 'invoice')),
  status text not null default 'completed'
    check (status in ('draft', 'held', 'completed', 'cancelled', 'refunded', 'partially_refunded')),
  payment_status text not null default 'unpaid'
    check (payment_status in ('unpaid', 'pending', 'partially_paid', 'paid', 'refunded', 'partially_refunded')),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  subtotal numeric(18,2) not null check (subtotal >= 0),
  discount_total numeric(18,2) not null default 0 check (discount_total >= 0),
  tax_total numeric(18,2) not null default 0 check (tax_total >= 0),
  service_charge_total numeric(18,2) not null default 0 check (service_charge_total >= 0),
  rounding_amount numeric(18,2) not null default 0,
  grand_total numeric(18,2) not null check (grand_total >= 0),
  paid_total numeric(18,2) not null default 0 check (paid_total >= 0),
  due_total numeric(18,2) not null default 0 check (due_total >= 0),
  notes text,
  operation_id uuid not null,
  completed_by uuid not null references auth.users(id) on delete restrict,
  completed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (business_id, invoice_number),
  unique (business_id, operation_id),
  unique (id, business_id),
  constraint sales_register_fkey foreign key (register_id, business_id)
    references public.registers(id, business_id) on delete restrict,
  constraint sales_branch_fkey foreign key (branch_id, business_id)
    references public.branches(id, business_id) on delete restrict,
  constraint sales_shift_fkey foreign key (shift_id)
    references public.register_shifts(id) on delete restrict,
  constraint sales_customer_fkey foreign key (customer_id, business_id)
    references public.customers(id, business_id) on delete restrict,
  check (grand_total = round(subtotal - discount_total + tax_total + service_charge_total + rounding_amount, 2)),
  check (due_total = greatest(grand_total - paid_total, 0))
);

create table public.sale_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  sale_id uuid not null,
  variant_id uuid not null,
  warehouse_id uuid,
  product_name text not null,
  variant_name text not null,
  sku text not null,
  quantity numeric(20,6) not null check (quantity > 0),
  unit_price numeric(18,4) not null check (unit_price >= 0),
  unit_cost numeric(18,4) not null default 0 check (unit_cost >= 0),
  discount_amount numeric(18,2) not null default 0 check (discount_amount >= 0),
  tax_rate numeric(7,4) not null default 0 check (tax_rate >= 0 and tax_rate <= 100),
  tax_amount numeric(18,2) not null default 0 check (tax_amount >= 0),
  line_total numeric(18,2) not null check (line_total >= 0),
  note text,
  created_at timestamptz not null default now(),
  constraint sale_items_sale_fkey foreign key (sale_id, business_id)
    references public.sales(id, business_id) on delete cascade
    deferrable initially deferred,
  constraint sale_items_variant_fkey foreign key (variant_id, business_id)
    references public.product_variants(id, business_id) on delete restrict,
  constraint sale_items_warehouse_fkey foreign key (warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete restrict,
  check (line_total = round((quantity * unit_price) - discount_amount + tax_amount, 2))
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  sale_id uuid not null,
  payment_method text not null check (payment_method in (
    'cash', 'upi', 'card', 'bank_transfer', 'wallet', 'gift_card', 'customer_credit'
  )),
  status text not null check (status in ('pending', 'settled', 'failed', 'refunded', 'partially_refunded')),
  amount numeric(18,2) not null check (amount > 0),
  reference text,
  provider text,
  provider_payload jsonb not null default '{}'::jsonb check (jsonb_typeof(provider_payload) = 'object'),
  received_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  settled_at timestamptz,
  constraint payments_sale_fkey foreign key (sale_id, business_id)
    references public.sales(id, business_id) on delete restrict,
  check ((status = 'settled' and settled_at is not null) or status <> 'settled')
);

create table public.idempotency_records (
  business_id uuid not null references public.businesses(id) on delete cascade,
  operation_id uuid not null,
  operation_type text not null,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  request_hash text,
  result jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '90 days'),
  primary key (business_id, operation_id, operation_type)
);

create index products_business_active_name_idx
  on public.products(business_id, name) where archived_at is null and is_active;
create index products_category_id_idx on public.products(category_id);
create index products_brand_id_idx on public.products(brand_id);
create index products_base_unit_id_idx on public.products(base_unit_id);
create index products_tax_rate_id_idx on public.products(tax_rate_id);
create index products_created_by_idx on public.products(created_by);
create index product_variants_product_id_idx on public.product_variants(product_id);
create index product_variants_business_active_idx
  on public.product_variants(business_id, is_active) where archived_at is null;
create index product_barcodes_variant_id_idx on public.product_barcodes(variant_id);
create index product_prices_variant_id_idx on public.product_prices(variant_id);
create index product_prices_branch_id_idx on public.product_prices(branch_id) where branch_id is not null;
create index warehouses_branch_id_idx on public.warehouses(branch_id);
create index inventory_balances_business_variant_idx on public.inventory_balances(business_id, variant_id);
create index inventory_balances_low_stock_idx
  on public.inventory_balances(business_id, warehouse_id, quantity_on_hand)
  where quantity_on_hand <= reorder_point;
create index inventory_movements_business_variant_created_idx
  on public.inventory_movements(business_id, variant_id, created_at desc);
create index inventory_movements_warehouse_created_idx
  on public.inventory_movements(warehouse_id, created_at desc);
create index inventory_movements_created_by_idx on public.inventory_movements(created_by);
create index customers_business_name_idx on public.customers(business_id, name) where archived_at is null;
create index customers_phone_idx on public.customers(business_id, phone) where phone is not null;
create index registers_branch_id_idx on public.registers(branch_id);
create index register_shifts_business_opened_idx on public.register_shifts(business_id, opened_at desc);
create index register_shifts_opened_by_idx on public.register_shifts(opened_by);
create index register_shifts_closed_by_idx on public.register_shifts(closed_by) where closed_by is not null;
create index sales_business_completed_idx on public.sales(business_id, completed_at desc);
create index sales_branch_completed_idx on public.sales(branch_id, completed_at desc);
create index sales_register_id_idx on public.sales(register_id) where register_id is not null;
create index sales_shift_id_idx on public.sales(shift_id) where shift_id is not null;
create index sales_customer_id_idx on public.sales(customer_id) where customer_id is not null;
create index sales_completed_by_idx on public.sales(completed_by);
create index sale_items_sale_id_idx on public.sale_items(sale_id);
create index sale_items_variant_id_idx on public.sale_items(variant_id);
create index sale_items_warehouse_id_idx on public.sale_items(warehouse_id) where warehouse_id is not null;
create index payments_sale_id_idx on public.payments(sale_id);
create index payments_received_by_idx on public.payments(received_by);
create index idempotency_actor_idx on public.idempotency_records(actor_user_id);
create index idempotency_expiry_idx on public.idempotency_records(expires_at);

create trigger units_set_updated_at before update on public.units
for each row execute function private.set_updated_at();
create trigger categories_set_updated_at before update on public.categories
for each row execute function private.set_updated_at();
create trigger brands_set_updated_at before update on public.brands
for each row execute function private.set_updated_at();
create trigger tax_rates_set_updated_at before update on public.tax_rates
for each row execute function private.set_updated_at();
create trigger products_set_updated_at before update on public.products
for each row execute function private.set_updated_at();
create trigger product_variants_set_updated_at before update on public.product_variants
for each row execute function private.set_updated_at();
create trigger product_prices_set_updated_at before update on public.product_prices
for each row execute function private.set_updated_at();
create trigger warehouses_set_updated_at before update on public.warehouses
for each row execute function private.set_updated_at();
create trigger customers_set_updated_at before update on public.customers
for each row execute function private.set_updated_at();
create trigger registers_set_updated_at before update on public.registers
for each row execute function private.set_updated_at();

create or replace function private.can_access_warehouse(target_warehouse_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.warehouses w
    where w.id = target_warehouse_id
      and (select private.is_business_member(w.business_id))
      and (select private.has_branch_access(w.branch_id))
  );
$$;

create or replace function private.can_access_register(target_register_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.registers r
    where r.id = target_register_id
      and (select private.is_business_member(r.business_id))
      and (select private.has_branch_access(r.branch_id))
  );
$$;

create or replace function private.prevent_immutable_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception '% is immutable; create a reversing transaction instead', tg_table_name;
end;
$$;

revoke all on function private.can_access_warehouse(uuid) from public, anon, authenticated, service_role;
revoke all on function private.can_access_register(uuid) from public, anon, authenticated, service_role;
revoke all on function private.prevent_immutable_change() from public, anon, authenticated, service_role;
grant execute on function private.can_access_warehouse(uuid) to authenticated;
grant execute on function private.can_access_register(uuid) to authenticated;

create trigger inventory_movements_immutable
before update or delete on public.inventory_movements
for each row execute function private.prevent_immutable_change();

create trigger sale_items_immutable
before update or delete on public.sale_items
for each row execute function private.prevent_immutable_change();

alter table public.units enable row level security;
alter table public.categories enable row level security;
alter table public.brands enable row level security;
alter table public.tax_rates enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.product_barcodes enable row level security;
alter table public.product_prices enable row level security;
alter table public.warehouses enable row level security;
alter table public.inventory_balances enable row level security;
alter table public.inventory_movements enable row level security;
alter table public.customers enable row level security;
alter table public.registers enable row level security;
alter table public.register_shifts enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.payments enable row level security;
alter table public.idempotency_records enable row level security;

create policy units_select on public.units for select to authenticated
using ((select private.is_business_member(business_id)));
create policy units_manage on public.units for all to authenticated
using ((select private.has_permission(business_id, 'products.manage')))
with check ((select private.has_permission(business_id, 'products.manage')));

create policy categories_select on public.categories for select to authenticated
using ((select private.is_business_member(business_id)));
create policy categories_manage on public.categories for all to authenticated
using ((select private.has_permission(business_id, 'products.manage')))
with check ((select private.has_permission(business_id, 'products.manage')));

create policy brands_select on public.brands for select to authenticated
using ((select private.is_business_member(business_id)));
create policy brands_manage on public.brands for all to authenticated
using ((select private.has_permission(business_id, 'products.manage')))
with check ((select private.has_permission(business_id, 'products.manage')));

create policy tax_rates_select on public.tax_rates for select to authenticated
using ((select private.is_business_member(business_id)));
create policy tax_rates_manage on public.tax_rates for all to authenticated
using ((select private.has_permission(business_id, 'business.manage')))
with check ((select private.has_permission(business_id, 'business.manage')));

create policy products_select on public.products for select to authenticated
using ((select private.has_permission(business_id, 'products.view')));
create policy products_insert on public.products for insert to authenticated
with check (
  (select private.has_permission(business_id, 'products.manage'))
  and created_by = (select auth.uid())
);
create policy products_update on public.products for update to authenticated
using ((select private.has_permission(business_id, 'products.manage')))
with check ((select private.has_permission(business_id, 'products.manage')));

create policy product_variants_select on public.product_variants for select to authenticated
using ((select private.has_permission(business_id, 'products.view')));
create policy product_variants_manage on public.product_variants for all to authenticated
using ((select private.has_permission(business_id, 'products.manage')))
with check ((select private.has_permission(business_id, 'products.manage')));

create policy product_barcodes_select on public.product_barcodes for select to authenticated
using ((select private.has_permission(business_id, 'products.view')));
create policy product_barcodes_manage on public.product_barcodes for all to authenticated
using ((select private.has_permission(business_id, 'products.manage')))
with check ((select private.has_permission(business_id, 'products.manage')));

create policy product_prices_select on public.product_prices for select to authenticated
using (
  (select private.has_permission(business_id, 'products.view'))
  and (branch_id is null or (select private.has_branch_access(branch_id)))
);
create policy product_prices_manage on public.product_prices for all to authenticated
using ((select private.has_permission(business_id, 'products.manage')))
with check (
  (select private.has_permission(business_id, 'products.manage'))
  and (branch_id is null or (select private.has_branch_access(branch_id)))
);

create policy warehouses_select on public.warehouses for select to authenticated
using (
  (select private.has_permission(business_id, 'inventory.view'))
  and (select private.has_branch_access(branch_id))
);
create policy warehouses_manage on public.warehouses for all to authenticated
using ((select private.has_permission(business_id, 'inventory.manage')))
with check (
  (select private.has_permission(business_id, 'inventory.manage'))
  and (select private.has_branch_access(branch_id))
);

create policy inventory_balances_select on public.inventory_balances for select to authenticated
using (
  (select private.has_permission(business_id, 'inventory.view'))
  and (select private.can_access_warehouse(warehouse_id))
);

create policy inventory_movements_select on public.inventory_movements for select to authenticated
using (
  (select private.has_permission(business_id, 'inventory.view'))
  and (select private.can_access_warehouse(warehouse_id))
);

create policy customers_select on public.customers for select to authenticated
using ((select private.has_permission(business_id, 'customers.view')));
create policy customers_manage on public.customers for all to authenticated
using ((select private.has_permission(business_id, 'customers.manage')))
with check ((select private.has_permission(business_id, 'customers.manage')));

create policy registers_select on public.registers for select to authenticated
using ((select private.has_branch_access(branch_id)));
create policy registers_manage on public.registers for all to authenticated
using ((select private.has_permission(business_id, 'registers.manage')))
with check (
  (select private.has_permission(business_id, 'registers.manage'))
  and (select private.has_branch_access(branch_id))
);

create policy register_shifts_select on public.register_shifts for select to authenticated
using ((select private.can_access_register(register_id)));

create policy sales_select on public.sales for select to authenticated
using (
  (select private.has_permission(business_id, 'sales.view'))
  and (select private.has_branch_access(branch_id))
);

create policy sale_items_select on public.sale_items for select to authenticated
using (
  exists (
    select 1 from public.sales s
    where s.id = sale_id
      and (select private.has_permission(s.business_id, 'sales.view'))
      and (select private.has_branch_access(s.branch_id))
  )
);

create policy payments_select on public.payments for select to authenticated
using (
  exists (
    select 1 from public.sales s
    where s.id = sale_id
      and (select private.has_permission(s.business_id, 'sales.view'))
      and (select private.has_branch_access(s.branch_id))
  )
);

-- Catalog and customer master data use RLS-protected direct writes.
grant select, insert, update on public.units, public.categories, public.brands,
  public.tax_rates, public.products, public.product_variants,
  public.product_barcodes, public.product_prices, public.warehouses,
  public.customers, public.registers to authenticated;
grant delete on public.product_barcodes, public.product_prices to authenticated;

-- Transactional records are read-only through the Data API. Trusted RPCs own writes.
grant select on public.inventory_balances, public.inventory_movements,
  public.register_shifts, public.sales, public.sale_items, public.payments
to authenticated;
revoke all on public.idempotency_records from anon, authenticated;

create or replace function private.protect_product_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.business_id <> old.business_id or new.created_by <> old.created_by then
    raise exception 'Product tenant and creator fields are immutable';
  end if;
  return new;
end;
$$;

revoke all on function private.protect_product_identity() from public, anon, authenticated, service_role;

create trigger products_protect_identity
before update on public.products
for each row execute function private.protect_product_identity();

create or replace function private.seed_branch_operational_defaults()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.units (business_id, name, symbol, precision)
  values
    (new.business_id, 'Piece', 'pc', 0),
    (new.business_id, 'Kilogram', 'kg', 3),
    (new.business_id, 'Litre', 'L', 3),
    (new.business_id, 'Hour', 'hr', 2)
  on conflict (business_id, name) do nothing;

  insert into public.warehouses (business_id, branch_id, name, code, is_default)
  values (new.business_id, new.id, new.name || ' Warehouse', new.code || '-WH', true)
  on conflict (business_id, code) do nothing;

  insert into public.registers (business_id, branch_id, name, code)
  values (new.business_id, new.id, new.name || ' Register', new.code || '-REG')
  on conflict (business_id, code) do nothing;
  return new;
end;
$$;

revoke all on function private.seed_branch_operational_defaults()
from public, anon, authenticated, service_role;

create trigger branches_seed_operational_defaults
after insert on public.branches
for each row execute function private.seed_branch_operational_defaults();

create index categories_parent_id_idx on public.categories(parent_id) where parent_id is not null;

create or replace function public.create_product_with_default_variant(
  target_business_id uuid,
  product_name text,
  product_type text,
  target_category_id uuid,
  target_brand_id uuid,
  target_unit_id uuid,
  target_tax_rate_id uuid,
  target_hsn_sac text,
  track_stock boolean,
  fractional_quantity boolean,
  variant_name text,
  variant_sku text,
  variant_barcode text,
  variant_cost numeric,
  variant_price numeric,
  variant_mrp numeric
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  new_product_id uuid;
  new_variant_id uuid;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if not private.has_permission(target_business_id, 'products.manage') then
    raise exception 'You do not have permission to manage products';
  end if;
  if length(btrim(product_name)) = 0 or length(btrim(variant_sku)) = 0 then
    raise exception 'Product name and SKU are required';
  end if;
  if coalesce(variant_cost, 0) < 0 or coalesce(variant_price, 0) < 0
     or (variant_mrp is not null and variant_mrp < 0) then
    raise exception 'Prices cannot be negative';
  end if;
  if not exists (
    select 1 from public.units u
    where u.id = target_unit_id and u.business_id = target_business_id and u.is_active
  ) then raise exception 'Invalid unit'; end if;
  if target_category_id is not null and not exists (
    select 1 from public.categories c
    where c.id = target_category_id and c.business_id = target_business_id and c.is_active
  ) then raise exception 'Invalid category'; end if;
  if target_brand_id is not null and not exists (
    select 1 from public.brands b
    where b.id = target_brand_id and b.business_id = target_business_id and b.is_active
  ) then raise exception 'Invalid brand'; end if;
  if target_tax_rate_id is not null and not exists (
    select 1 from public.tax_rates t
    where t.id = target_tax_rate_id and t.business_id = target_business_id and t.is_active
  ) then raise exception 'Invalid tax rate'; end if;

  insert into public.products (
    business_id, category_id, brand_id, base_unit_id, tax_rate_id, name,
    product_type, hsn_sac, track_inventory, allow_fractional_quantity, created_by
  ) values (
    target_business_id, target_category_id, target_brand_id, target_unit_id,
    target_tax_rate_id, btrim(product_name), coalesce(product_type, 'goods'),
    nullif(btrim(target_hsn_sac), ''), coalesce(track_stock, true),
    coalesce(fractional_quantity, false), caller_id
  ) returning id into new_product_id;

  insert into public.product_variants (
    business_id, product_id, name, sku, cost_price, selling_price, mrp
  ) values (
    target_business_id, new_product_id, coalesce(nullif(btrim(variant_name), ''), 'Default'),
    btrim(variant_sku), round(coalesce(variant_cost, 0), 4),
    round(coalesce(variant_price, 0), 4),
    case when variant_mrp is null then null else round(variant_mrp, 4) end
  ) returning id into new_variant_id;

  if nullif(btrim(variant_barcode), '') is not null then
    insert into public.product_barcodes (
      business_id, variant_id, barcode, barcode_type, is_primary
    ) values (
      target_business_id, new_variant_id, btrim(variant_barcode), 'code128', true
    );
  end if;

  perform private.write_tenant_audit(
    target_business_id, 'product.created', 'product', new_product_id::text,
    jsonb_build_object('variant_id', new_variant_id, 'sku', btrim(variant_sku))
  );

  return jsonb_build_object('product_id', new_product_id, 'variant_id', new_variant_id);
end;
$$;

create or replace function public.adjust_inventory(
  target_business_id uuid,
  target_warehouse_id uuid,
  target_variant_id uuid,
  quantity_delta numeric,
  adjustment_reason text,
  operation_id uuid,
  target_unit_cost numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  existing_result jsonb;
  balance_record public.inventory_balances%rowtype;
  next_quantity numeric(20,6);
  movement_id bigint;
  inserted_count integer;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if quantity_delta is null or quantity_delta = 0 then raise exception 'Quantity change cannot be zero'; end if;
  if target_unit_cost is not null and target_unit_cost < 0 then raise exception 'Unit cost cannot be negative'; end if;
  if length(btrim(coalesce(adjustment_reason, ''))) < 3 then
    raise exception 'A meaningful adjustment reason is required';
  end if;
  if not private.has_permission(target_business_id, 'inventory.manage') then
    raise exception 'You do not have permission to adjust inventory';
  end if;
  if not exists (
    select 1 from public.warehouses w
    where w.id = target_warehouse_id and w.business_id = target_business_id
      and w.is_active and private.has_branch_access(w.branch_id)
  ) then raise exception 'Warehouse is not accessible'; end if;
  if not exists (
    select 1
    from public.product_variants v
    join public.products p on p.id = v.product_id and p.business_id = v.business_id
    where v.id = target_variant_id and v.business_id = target_business_id
      and v.is_active and v.archived_at is null and p.track_inventory
  ) then raise exception 'Variant is not stock tracked or is inactive'; end if;

  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (target_business_id, operation_id, 'inventory.adjust', caller_id)
  on conflict do nothing;
  get diagnostics inserted_count = row_count;

  if inserted_count = 0 then
    select result into existing_result
    from public.idempotency_records
    where business_id = target_business_id
      and idempotency_records.operation_id = adjust_inventory.operation_id
      and operation_type = 'inventory.adjust';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Inventory operation is already in progress';
  end if;

  insert into public.inventory_balances (business_id, warehouse_id, variant_id)
  values (target_business_id, target_warehouse_id, target_variant_id)
  on conflict (warehouse_id, variant_id) do nothing;

  select * into balance_record
  from public.inventory_balances b
  where b.warehouse_id = target_warehouse_id and b.variant_id = target_variant_id
  for update;

  next_quantity := balance_record.quantity_on_hand + round(quantity_delta, 6);
  if next_quantity < balance_record.quantity_reserved then
    raise exception 'Adjustment would reduce stock below reserved quantity';
  end if;
  if next_quantity < 0 then raise exception 'Negative inventory is not allowed'; end if;

  insert into public.inventory_movements (
    business_id, warehouse_id, variant_id, movement_type, quantity_delta,
    quantity_before, quantity_after, unit_cost, reference_type, reason,
    operation_id, created_by
  ) values (
    target_business_id, target_warehouse_id, target_variant_id, 'adjustment',
    round(quantity_delta, 6), balance_record.quantity_on_hand, next_quantity,
    case when target_unit_cost is null then null else round(target_unit_cost, 4) end,
    'manual_adjustment', btrim(adjustment_reason), operation_id, caller_id
  ) returning id into movement_id;

  update public.inventory_balances
  set quantity_on_hand = next_quantity,
      average_cost = case
        when target_unit_cost is null then average_cost
        else round(target_unit_cost, 4)
      end,
      updated_at = now()
  where warehouse_id = target_warehouse_id and variant_id = target_variant_id;

  existing_result := jsonb_build_object(
    'movement_id', movement_id,
    'quantity_before', balance_record.quantity_on_hand,
    'quantity_after', next_quantity
  );
  update public.idempotency_records set result = existing_result
  where business_id = target_business_id
    and idempotency_records.operation_id = adjust_inventory.operation_id
    and operation_type = 'inventory.adjust';

  perform private.write_tenant_audit(
    target_business_id, 'inventory.adjusted', 'inventory_movement', movement_id::text,
    existing_result || jsonb_build_object('reason', btrim(adjustment_reason))
  );
  return existing_result;
end;
$$;

create or replace function public.open_register_shift(
  target_business_id uuid,
  target_register_id uuid,
  opening_cash_amount numeric default 0,
  shift_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  new_shift_id uuid;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if coalesce(opening_cash_amount, 0) < 0 then raise exception 'Opening cash cannot be negative'; end if;
  if not private.has_permission(target_business_id, 'sales.create') then
    raise exception 'You do not have permission to operate a register';
  end if;
  if not exists (
    select 1 from public.registers r
    where r.id = target_register_id and r.business_id = target_business_id
      and r.is_active and private.has_branch_access(r.branch_id)
  ) then raise exception 'Register is not accessible'; end if;

  insert into public.register_shifts (
    business_id, register_id, opened_by, opening_cash, notes
  ) values (
    target_business_id, target_register_id, caller_id,
    round(coalesce(opening_cash_amount, 0), 2), nullif(btrim(shift_notes), '')
  ) returning id into new_shift_id;

  perform private.write_tenant_audit(
    target_business_id, 'register_shift.opened', 'register_shift', new_shift_id::text,
    jsonb_build_object('register_id', target_register_id, 'opening_cash', round(coalesce(opening_cash_amount, 0), 2))
  );
  return jsonb_build_object('shift_id', new_shift_id, 'status', 'open');
exception
  when unique_violation then
    raise exception 'This register already has an open shift';
end;
$$;

create or replace function public.close_register_shift(
  target_shift_id uuid,
  closing_cash_amount numeric,
  shift_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  shift_record public.register_shifts%rowtype;
  expected_amount numeric(18,2);
  difference numeric(18,2);
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if closing_cash_amount is null or closing_cash_amount < 0 then
    raise exception 'Closing cash cannot be negative';
  end if;

  select * into shift_record
  from public.register_shifts
  where id = target_shift_id
  for update;
  if not found or shift_record.status <> 'open' then raise exception 'Open shift not found'; end if;
  if shift_record.opened_by <> caller_id
     and not private.has_permission(shift_record.business_id, 'registers.manage') then
    raise exception 'You do not have permission to close this shift';
  end if;

  select round(
    shift_record.opening_cash + coalesce(sum(p.amount), 0), 2
  ) into expected_amount
  from public.payments p
  join public.sales s on s.id = p.sale_id and s.business_id = p.business_id
  where s.shift_id = target_shift_id
    and p.payment_method = 'cash'
    and p.status = 'settled';

  difference := round(closing_cash_amount - expected_amount, 2);
  update public.register_shifts
  set status = 'closed', closed_by = caller_id, closed_at = now(),
      expected_cash = expected_amount, closing_cash = round(closing_cash_amount, 2),
      difference_amount = difference,
      notes = coalesce(nullif(btrim(shift_notes), ''), notes)
  where id = target_shift_id;

  perform private.write_tenant_audit(
    shift_record.business_id, 'register_shift.closed', 'register_shift', target_shift_id::text,
    jsonb_build_object('expected_cash', expected_amount, 'closing_cash', round(closing_cash_amount, 2), 'difference', difference)
  );
  return jsonb_build_object(
    'shift_id', target_shift_id, 'status', 'closed',
    'expected_cash', expected_amount, 'closing_cash', round(closing_cash_amount, 2),
    'difference', difference
  );
end;
$$;

create or replace function public.complete_sale(
  target_business_id uuid,
  target_branch_id uuid,
  target_register_id uuid,
  target_shift_id uuid,
  target_customer_id uuid,
  operation_id uuid,
  line_items jsonb,
  payment_lines jsonb,
  order_discount numeric default 0,
  sale_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  business_currency text;
  existing_result jsonb;
  inserted_count integer;
  sale_id uuid := gen_random_uuid();
  invoice_no text;
  item record;
  payment record;
  variant_record record;
  balance_record public.inventory_balances%rowtype;
  subtotal_amount numeric(18,2) := 0;
  line_discount_total numeric(18,2) := 0;
  tax_amount_total numeric(18,2) := 0;
  grand_total_amount numeric(18,2);
  payment_total numeric(18,2) := 0;
  settled_total numeric(18,2) := 0;
  calculated_tax numeric(18,2);
  calculated_line_total numeric(18,2);
  next_quantity numeric(20,6);
  all_payments_settled boolean := true;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if jsonb_typeof(line_items) <> 'array' or jsonb_array_length(line_items) = 0 then
    raise exception 'At least one sale item is required';
  end if;
  if jsonb_typeof(payment_lines) <> 'array' or jsonb_array_length(payment_lines) = 0 then
    raise exception 'At least one payment is required';
  end if;
  if coalesce(order_discount, 0) < 0 then raise exception 'Order discount cannot be negative'; end if;
  if not private.has_permission(target_business_id, 'sales.create') then
    raise exception 'You do not have permission to create sales';
  end if;
  if order_discount > 0 and not private.has_permission(target_business_id, 'sales.discount') then
    raise exception 'You do not have permission to apply discounts';
  end if;
  if not private.has_branch_access(target_branch_id) then raise exception 'Branch is not accessible'; end if;

  select currency_code into business_currency
  from public.businesses where id = target_business_id and archived_at is null;
  if not found then raise exception 'Business not found'; end if;
  if not exists (
    select 1 from public.branches b
    where b.id = target_branch_id and b.business_id = target_business_id
      and b.is_active and b.archived_at is null
  ) then raise exception 'Invalid branch'; end if;
  if target_register_id is not null and not exists (
    select 1 from public.registers r
    where r.id = target_register_id and r.business_id = target_business_id
      and r.branch_id = target_branch_id and r.is_active
  ) then raise exception 'Invalid register'; end if;
  if target_shift_id is not null and not exists (
    select 1 from public.register_shifts rs
    where rs.id = target_shift_id and rs.business_id = target_business_id
      and rs.register_id = target_register_id and rs.status = 'open'
  ) then raise exception 'A valid open register shift is required'; end if;
  if target_customer_id is not null and not exists (
    select 1 from public.customers c
    where c.id = target_customer_id and c.business_id = target_business_id
      and c.is_active and c.archived_at is null
  ) then raise exception 'Invalid customer'; end if;

  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (target_business_id, operation_id, 'sale.complete', caller_id)
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select result into existing_result
    from public.idempotency_records
    where business_id = target_business_id
      and idempotency_records.operation_id = complete_sale.operation_id
      and operation_type = 'sale.complete';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Sale operation is already in progress';
  end if;

  for item in
    select * from jsonb_to_recordset(line_items) as x(
      variant_id uuid, warehouse_id uuid, quantity numeric, unit_price numeric,
      discount_amount numeric, tax_rate numeric, note text
    ) order by variant_id, warehouse_id
  loop
    if item.variant_id is null or item.quantity is null or item.quantity <= 0
       or item.unit_price is null or item.unit_price < 0
       or coalesce(item.discount_amount, 0) < 0
       or coalesce(item.tax_rate, 0) < 0 or coalesce(item.tax_rate, 0) > 100 then
      raise exception 'Invalid sale line';
    end if;

    select v.id, v.name, v.sku, v.cost_price, p.name as product_name,
           p.track_inventory, p.allow_fractional_quantity
    into variant_record
    from public.product_variants v
    join public.products p on p.id = v.product_id and p.business_id = v.business_id
    where v.id = item.variant_id and v.business_id = target_business_id
      and v.is_active and v.archived_at is null
      and p.is_active and p.archived_at is null;
    if not found then raise exception 'Sale variant is inactive or unavailable'; end if;
    if not variant_record.allow_fractional_quantity and item.quantity <> trunc(item.quantity) then
      raise exception 'Fractional quantity is not allowed for SKU %', variant_record.sku;
    end if;
    if coalesce(item.discount_amount, 0) > item.quantity * item.unit_price then
      raise exception 'Line discount exceeds line value';
    end if;

    if variant_record.track_inventory then
      if item.warehouse_id is null then raise exception 'Warehouse is required for stock items'; end if;
      if not exists (
        select 1 from public.warehouses w
        where w.id = item.warehouse_id and w.business_id = target_business_id
          and w.branch_id = target_branch_id and w.is_active
      ) then raise exception 'Invalid warehouse for sale branch'; end if;

      insert into public.inventory_balances (business_id, warehouse_id, variant_id)
      values (target_business_id, item.warehouse_id, item.variant_id)
      on conflict (warehouse_id, variant_id) do nothing;
      select * into balance_record
      from public.inventory_balances b
      where b.warehouse_id = item.warehouse_id and b.variant_id = item.variant_id
      for update;
      next_quantity := balance_record.quantity_on_hand - round(item.quantity, 6);
      if next_quantity < balance_record.quantity_reserved or next_quantity < 0 then
        raise exception 'Insufficient available stock for SKU %', variant_record.sku;
      end if;
      update public.inventory_balances as ib
      set quantity_on_hand = next_quantity, updated_at = now()
      where ib.warehouse_id = item.warehouse_id
        and ib.variant_id = item.variant_id;
      insert into public.inventory_movements (
        business_id, warehouse_id, variant_id, movement_type, quantity_delta,
        quantity_before, quantity_after, unit_cost, reference_type, reference_id,
        reason, operation_id, created_by
      ) values (
        target_business_id, item.warehouse_id, item.variant_id, 'sale',
        -round(item.quantity, 6), balance_record.quantity_on_hand, next_quantity,
        variant_record.cost_price, 'sale', sale_id, 'POS sale', operation_id, caller_id
      );
    end if;

    calculated_tax := round(
      ((item.quantity * item.unit_price) - coalesce(item.discount_amount, 0))
      * coalesce(item.tax_rate, 0) / 100, 2
    );
    calculated_line_total := round(
      (item.quantity * item.unit_price) - coalesce(item.discount_amount, 0) + calculated_tax, 2
    );
    subtotal_amount := subtotal_amount + round(item.quantity * item.unit_price, 2);
    line_discount_total := line_discount_total + round(coalesce(item.discount_amount, 0), 2);
    tax_amount_total := tax_amount_total + calculated_tax;

    insert into public.sale_items (
      id, business_id, sale_id, variant_id, warehouse_id, product_name, variant_name,
      sku, quantity, unit_price, unit_cost, discount_amount, tax_rate, tax_amount,
      line_total, note
    ) values (
      gen_random_uuid(), target_business_id, sale_id, item.variant_id, item.warehouse_id,
      variant_record.product_name, variant_record.name, variant_record.sku,
      round(item.quantity, 6), round(item.unit_price, 4), variant_record.cost_price,
      round(coalesce(item.discount_amount, 0), 2), round(coalesce(item.tax_rate, 0), 4),
      calculated_tax, calculated_line_total, nullif(btrim(item.note), '')
    );
  end loop;

  if round(coalesce(order_discount, 0), 2) > subtotal_amount - line_discount_total then
    raise exception 'Order discount exceeds sale value';
  end if;
  grand_total_amount := round(
    subtotal_amount - line_discount_total - round(coalesce(order_discount, 0), 2) + tax_amount_total,
    2
  );

  for payment in
    select * from jsonb_to_recordset(payment_lines) as x(
      payment_method text, amount numeric, reference text, provider text
    )
  loop
    if payment.payment_method not in ('cash', 'upi', 'card', 'bank_transfer', 'wallet', 'gift_card', 'customer_credit')
       or payment.amount is null or payment.amount <= 0 then
      raise exception 'Invalid payment line';
    end if;
    payment_total := payment_total + round(payment.amount, 2);
    if payment.payment_method = 'cash' then
      settled_total := settled_total + round(payment.amount, 2);
    else
      all_payments_settled := false;
    end if;
  end loop;
  if payment_total <> grand_total_amount then
    raise exception 'Payments (%) must equal sale total (%)', payment_total, grand_total_amount;
  end if;

  invoice_no := 'FP-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS') || '-' || upper(substr(replace(sale_id::text, '-', ''), 1, 8));
  insert into public.sales (
    id, business_id, branch_id, register_id, shift_id, customer_id, invoice_number,
    sale_type, status, payment_status, currency_code, subtotal, discount_total,
    tax_total, grand_total, paid_total, due_total, notes, operation_id,
    completed_by, completed_at
  ) values (
    sale_id, target_business_id, target_branch_id, target_register_id, target_shift_id,
    target_customer_id, invoice_no, 'invoice', 'completed',
    case when all_payments_settled then 'paid' else 'pending' end,
    business_currency, subtotal_amount,
    line_discount_total + round(coalesce(order_discount, 0), 2), tax_amount_total,
    grand_total_amount, settled_total, greatest(grand_total_amount - settled_total, 0),
    nullif(btrim(sale_notes), ''), operation_id, caller_id, now()
  );

  for payment in
    select * from jsonb_to_recordset(payment_lines) as x(
      payment_method text, amount numeric, reference text, provider text
    )
  loop
    insert into public.payments (
      business_id, sale_id, payment_method, status, amount, reference, provider,
      received_by, settled_at
    ) values (
      target_business_id, sale_id, payment.payment_method,
      case when payment.payment_method = 'cash' then 'settled' else 'pending' end,
      round(payment.amount, 2), nullif(btrim(payment.reference), ''),
      nullif(btrim(payment.provider), ''), caller_id,
      case when payment.payment_method = 'cash' then now() else null end
    );
  end loop;

  existing_result := jsonb_build_object(
    'sale_id', sale_id, 'invoice_number', invoice_no,
    'grand_total', grand_total_amount,
    'payment_status', case when all_payments_settled then 'paid' else 'pending' end
  );
  update public.idempotency_records set result = existing_result
  where business_id = target_business_id
    and idempotency_records.operation_id = complete_sale.operation_id
    and operation_type = 'sale.complete';
  perform private.write_tenant_audit(
    target_business_id, 'sale.completed', 'sale', sale_id::text, existing_result
  );
  return existing_result;
end;
$$;

revoke all on function public.create_product_with_default_variant(
  uuid, text, text, uuid, uuid, uuid, uuid, text, boolean, boolean,
  text, text, text, numeric, numeric, numeric
) from public, anon;
revoke all on function public.adjust_inventory(uuid, uuid, uuid, numeric, text, uuid, numeric)
from public, anon;
revoke all on function public.open_register_shift(uuid, uuid, numeric, text)
from public, anon;
revoke all on function public.close_register_shift(uuid, numeric, text)
from public, anon;
revoke all on function public.complete_sale(
  uuid, uuid, uuid, uuid, uuid, uuid, jsonb, jsonb, numeric, text
) from public, anon;

grant execute on function public.create_product_with_default_variant(
  uuid, text, text, uuid, uuid, uuid, uuid, text, boolean, boolean,
  text, text, text, numeric, numeric, numeric
) to authenticated;
grant execute on function public.adjust_inventory(uuid, uuid, uuid, numeric, text, uuid, numeric)
to authenticated;
grant execute on function public.open_register_shift(uuid, uuid, numeric, text)
to authenticated;
grant execute on function public.close_register_shift(uuid, numeric, text)
to authenticated;
grant execute on function public.complete_sale(
  uuid, uuid, uuid, uuid, uuid, uuid, jsonb, jsonb, numeric, text
) to authenticated;




