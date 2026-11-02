-- Transactional order-discount authorization and total verification.
begin;

create extension if not exists pgtap with schema extensions;
select plan(8);

create temporary table discount_test_state (
  business_id uuid,
  branch_id uuid,
  unit_id uuid,
  warehouse_id uuid,
  variant_id uuid,
  sale_id uuid
);
grant all on discount_test_state to authenticated;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '70000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'discount-owner@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '70000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'discount-salesperson@example.test', '', now(), '{}', '{}', now(), now());

set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'discount-owner@example.test', true);

select lives_ok(
  $$select public.create_business_with_branch('Discount Test Business', 'retail', 'INR', 'Asia/Kolkata', 'Main Branch', 'MAIN', 'IN')$$,
  'owner creates a discount-test tenant'
);

insert into discount_test_state (business_id, branch_id, unit_id, warehouse_id)
select b.id, br.id, u.id, w.id
from public.businesses b
join public.branches br on br.business_id = b.id
join public.units u on u.business_id = b.id and u.name = 'Piece'
join public.warehouses w on w.business_id = b.id and w.branch_id = br.id and w.is_default
where b.name = 'Discount Test Business';

update discount_test_state set variant_id = (
  select (public.create_product_with_default_variant(
    business_id, 'Discount Product', 'goods', null, null, unit_id, null,
    '5001', true, false, 'Default', 'DISCOUNT-PRODUCT', null, 20, 100, 0
  ) ->> 'variant_id')::uuid
  from discount_test_state
);
select lives_ok(
  $$select public.adjust_inventory(
    (select business_id from discount_test_state),
    (select warehouse_id from discount_test_state),
    (select variant_id from discount_test_state),
    10, 'discount test opening stock',
    '71000000-0000-0000-0000-000000000001', 20
  )$$,
  'opening stock is created'
);

update discount_test_state set sale_id = (
  select (public.complete_sale(
    business_id, branch_id, null, null, null,
    '71000000-0000-0000-0000-000000000002',
    jsonb_build_array(jsonb_build_object(
      'variant_id', variant_id,
      'warehouse_id', warehouse_id,
      'quantity', 2,
      'unit_price', 100,
      'discount_amount', 0,
      'tax_rate', 18
    )),
    jsonb_build_array(jsonb_build_object('payment_method', 'cash', 'amount', 211)),
    25, 'Authorized fixed discount'
  ) ->> 'sale_id')::uuid
  from discount_test_state
);
select pass('authorized discounted sale completes');
select is(
  (select subtotal from public.sales where id = (select sale_id from discount_test_state)),
  200.00::numeric,
  'subtotal remains authoritative'
);
select is(
  (select tax_total from public.sales where id = (select sale_id from discount_test_state)),
  36.00::numeric,
  'tax remains exact after order discount'
);
select is(
  (select discount_total from public.sales where id = (select sale_id from discount_test_state)),
  25.00::numeric,
  'fixed discount is persisted exactly'
);
select is(
  (select grand_total from public.sales where id = (select sale_id from discount_test_state)),
  211.00::numeric,
  'discounted grand total is exact'
);

reset role;
insert into public.memberships (
  business_id, user_id, role_id, status, branch_access_all, joined_at
)
select t.business_id, '70000000-0000-0000-0000-000000000002', r.id,
       'active', true, now()
from discount_test_state t
join public.roles r on r.business_id = t.business_id and r.name = 'Salesperson';

set local role authenticated;
select set_config('request.jwt.claim.sub', '70000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'discount-salesperson@example.test', true);
select throws_ok(
  format(
    $$select public.complete_sale(%L, %L, null, null, null, %L,
      jsonb_build_array(jsonb_build_object(
        'variant_id', %L, 'warehouse_id', %L, 'quantity', 1,
        'unit_price', 100, 'discount_amount', 0, 'tax_rate', 18
      )),
      jsonb_build_array(jsonb_build_object('payment_method', 'cash', 'amount', 108)),
      10, 'Unauthorized discount')$$,
    (select business_id from discount_test_state),
    (select branch_id from discount_test_state),
    '71000000-0000-0000-0000-000000000003',
    (select variant_id from discount_test_state),
    (select warehouse_id from discount_test_state)
  ),
  'P0001',
  'You do not have permission to apply discounts',
  'salesperson without sales.discount cannot apply a discount'
);

select * from finish();
rollback;
