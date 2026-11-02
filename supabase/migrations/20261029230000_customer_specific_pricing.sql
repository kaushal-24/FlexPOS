-- Direct customer price overrides layered above customer-group and retail prices.

alter table public.product_prices
  add column if not exists customer_id uuid;

alter table public.product_prices
  drop constraint if exists product_prices_customer_fkey;

alter table public.product_prices
  add constraint product_prices_customer_fkey
  foreign key (customer_id, business_id)
  references public.customers(id, business_id) on delete cascade;

alter table public.product_prices
  drop constraint if exists product_prices_price_type_check;

alter table public.product_prices
  add constraint product_prices_price_type_check
  check (price_type in ('retail', 'wholesale', 'dealer', 'customer_group', 'customer'));

alter table public.product_prices
  drop constraint if exists product_prices_customer_group_type_check;

alter table public.product_prices
  add constraint product_prices_price_scope_check
  check (
    (price_type = 'customer_group' and customer_group_id is not null and customer_id is null)
    or (price_type = 'customer' and customer_id is not null and customer_group_id is null)
    or (price_type not in ('customer_group', 'customer')
      and customer_group_id is null and customer_id is null)
  );

drop index if exists public.product_prices_unique_scope_idx;

create unique index product_prices_unique_scope_idx
  on public.product_prices(
    business_id,
    variant_id,
    coalesce(branch_id, '00000000-0000-0000-0000-000000000000'::uuid),
    price_type,
    coalesce(customer_group_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(customer_id, '00000000-0000-0000-0000-000000000000'::uuid),
    minimum_quantity,
    coalesce(valid_from, '-infinity'::timestamptz)
  );

create index if not exists product_prices_customer_scope_idx
  on public.product_prices(business_id, customer_id, variant_id)
  where customer_id is not null;

comment on column public.product_prices.customer_id is
  'Required for customer prices; direct customer overrides take precedence over group prices.';
