-- Custom POS service-item verification. All fixtures roll back.
begin;

create extension if not exists pgtap with schema extensions;
select plan(12);

create temporary table custom_sale_item_test_state (
  business_id uuid,
  unit_id uuid,
  tax_rate_id uuid,
  product_id uuid,
  variant_id uuid,
  operation_id uuid
);
grant all on custom_sale_item_test_state to authenticated;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000',
   '54000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'custom-item-owner@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '54000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'custom-item-outsider@example.test', '', now(), '{}', '{}', now(), now());

set local role authenticated;
select set_config('request.jwt.claim.sub', '54000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'custom-item-owner@example.test', true);

select lives_ok(
  $$select public.create_business_with_branch(
    'Custom Sale Item Test Business', 'retail', 'INR', 'Asia/Kolkata',
    'Main Branch', 'MAIN', 'IN'
  )$$,
  'owner creates a custom-item test tenant'
);

insert into custom_sale_item_test_state (business_id, unit_id, operation_id)
select business.id, unit_record.id,
  '54100000-0000-0000-0000-000000000001'::uuid
from public.businesses business
join public.units unit_record
  on unit_record.business_id = business.id and unit_record.name = 'Piece'
where business.name = 'Custom Sale Item Test Business';

select ok(
  (select business_id is not null and unit_id is not null
   from custom_sale_item_test_state),
  'test tenant and default unit are available'
);

create temporary table custom_item_first_result (result jsonb);
grant all on custom_item_first_result to authenticated;
insert into custom_item_first_result
select public.create_custom_sale_item(
  business_id, unit_id, null, 'Installation service', 125.50, operation_id
)
from custom_sale_item_test_state;

update custom_sale_item_test_state
set product_id = (select (result ->> 'product_id')::uuid from custom_item_first_result),
    variant_id = (select (result ->> 'variant_id')::uuid from custom_item_first_result);

select is((select count(*) from public.products), 1::bigint,
  'custom item creates one service product');
select is((select product_type from public.products), 'service'::text,
  'custom item is a service product');
select is((select track_inventory from public.products), false,
  'custom item does not require stock');
select is((select selling_price from public.product_variants), 125.50::numeric,
  'custom item preserves its exact unit price');
select matches(
  (select sku from public.product_variants), '^CUSTOM-[A-F0-9]{12}$',
  'custom item receives a generated safe SKU'
);
select is(
  (select result ->> 'name' from custom_item_first_result),
  'Installation service'::text,
  'custom item result returns the normalized name'
);

select lives_ok(
  format(
    $$select public.create_custom_sale_item(%L, %L, null, 'Ignored replay', 999, %L)$$,
    (select business_id from custom_sale_item_test_state),
    (select unit_id from custom_sale_item_test_state),
    (select operation_id from custom_sale_item_test_state)
  ),
  'replaying the custom-item operation is idempotent'
);
select is((select count(*) from public.products), 1::bigint,
  'custom-item replay does not create a duplicate product');

select throws_ok(
  format(
    $$select public.create_custom_sale_item(%L, %L, null, 'Invalid', 0, gen_random_uuid())$$,
    (select business_id from custom_sale_item_test_state),
    (select unit_id from custom_sale_item_test_state)
  ),
  'P0001', 'Custom item price must be greater than zero',
  'custom item price must be positive'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '54000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.email', 'custom-item-outsider@example.test', true);
select throws_ok(
  format(
    $$select public.create_custom_sale_item(%L, %L, null, 'Unauthorized', 10, gen_random_uuid())$$,
    (select business_id from custom_sale_item_test_state),
    (select unit_id from custom_sale_item_test_state)
  ),
  'P0001', 'Custom sale item permission required',
  'an outsider cannot create a custom item'
);

select * from finish();
rollback;
