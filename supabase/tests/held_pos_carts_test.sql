-- Persistent POS held-cart verification. All fixtures roll back.
begin;

create extension if not exists pgtap with schema extensions;
select plan(23);

create temporary table held_cart_test_state (
  business_id uuid,
  branch_id uuid,
  warehouse_id uuid,
  unit_id uuid,
  variant_id uuid,
  held_cart_id uuid
);
grant all on held_cart_test_state to authenticated;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '33000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'held-owner@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '33000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'held-outsider@example.test', '', now(), '{}', '{}', now(), now());

set local role authenticated;
select set_config('request.jwt.claim.sub', '33000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'held-owner@example.test', true);

select lives_ok(
  $$select public.create_business_with_branch('Held Cart Test Business', 'retail', 'INR', 'Asia/Kolkata', 'Main Branch', 'MAIN', 'IN')$$,
  'owner creates a held-cart test tenant'
);

insert into held_cart_test_state (business_id, branch_id, warehouse_id, unit_id)
select business.id, branch.id, warehouse.id, unit_record.id
from public.businesses business
join public.branches branch on branch.business_id = business.id
join public.warehouses warehouse
  on warehouse.business_id = business.id and warehouse.branch_id = branch.id
join public.units unit_record
  on unit_record.business_id = business.id and unit_record.name = 'Piece'
where business.name = 'Held Cart Test Business';

update held_cart_test_state set variant_id = (
  select (public.create_product_with_default_variant(
    business_id, 'Held Product', 'goods', null, null, unit_id, null,
    '6001', true, false, 'Default', 'HELD-001', null, 25, 50, 0
  ) ->> 'variant_id')::uuid
  from held_cart_test_state
);
select is((select count(*) from public.products), 1::bigint, 'held-cart product is created');

create temporary table first_hold_result (result jsonb);
grant all on first_hold_result to authenticated;
insert into first_hold_result
select public.hold_pos_cart(
  business_id, branch_id, warehouse_id, null,
  '34000000-0000-0000-0000-000000000001',
  'Lunch counter', 'cash', 5,
  jsonb_build_array(jsonb_build_object('variant_id', variant_id, 'quantity', 2)),
  null
)
from held_cart_test_state;
update held_cart_test_state
set held_cart_id = (select (result ->> 'held_cart_id')::uuid from first_hold_result);

select ok(
  (select result ->> 'held_cart_id' is not null from first_hold_result),
  'holding a cart returns its identifier'
);
select is((select count(*) from public.held_pos_carts), 1::bigint, 'held cart is persisted');
select is((select count(*) from public.held_pos_cart_items), 1::bigint, 'held cart item is persisted');
select is((select quantity from public.held_pos_cart_items), 2::numeric, 'held quantity remains exact');
select is((select count(*) from public.inventory_movements), 0::bigint, 'holding a cart does not move stock');

select lives_ok(
  format(
    $$select public.hold_pos_cart(%L, %L, %L, null, %L, 'Replay ignored', 'cash', 0,
      jsonb_build_array(jsonb_build_object('variant_id', %L, 'quantity', 1)), null)$$,
    (select business_id from held_cart_test_state),
    (select branch_id from held_cart_test_state),
    (select warehouse_id from held_cart_test_state),
    '34000000-0000-0000-0000-000000000001',
    (select variant_id from held_cart_test_state)
  ),
  'replaying the hold operation is idempotent'
);
select is((select count(*) from public.held_pos_carts), 1::bigint, 'hold replay creates no duplicate cart');
select is((select quantity from public.held_pos_cart_items), 2::numeric, 'hold replay does not replace original items');

select lives_ok(
  format(
    $$select public.hold_pos_cart(%L, %L, %L, null, %L, 'Updated counter', 'wallet', 0,
      jsonb_build_array(jsonb_build_object('variant_id', %L, 'quantity', 3)), %L)$$,
    (select business_id from held_cart_test_state),
    (select branch_id from held_cart_test_state),
    (select warehouse_id from held_cart_test_state),
    '34000000-0000-0000-0000-000000000002',
    (select variant_id from held_cart_test_state),
    (select held_cart_id from held_cart_test_state)
  ),
  'a resumed cart can be parked again atomically'
);
select is((select label from public.held_pos_carts), 'Updated counter'::text, 're-park updates the cart label');
select is((select payment_method from public.held_pos_carts), 'wallet'::text, 're-park updates the payment method');
select is((select quantity from public.held_pos_cart_items), 3::numeric, 're-park atomically replaces cart items');
select is((select count(*) from public.inventory_movements), 0::bigint, 're-parking still does not move stock');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '33000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'held-outsider@example.test', true);

select is((select count(*) from public.held_pos_carts), 0::bigint, 'outsider cannot read held carts');
select throws_ok(
  format(
    $$select public.hold_pos_cart(%L, %L, %L, null, gen_random_uuid(), 'Unauthorized', 'cash', 0,
      jsonb_build_array(jsonb_build_object('variant_id', %L, 'quantity', 1)), null)$$,
    (select business_id from held_cart_test_state),
    (select branch_id from held_cart_test_state),
    (select warehouse_id from held_cart_test_state),
    (select variant_id from held_cart_test_state)
  ),
  'P0001',
  'You do not have permission to hold sales',
  'outsider cannot hold a cart in another tenant'
);
select throws_ok(
  format(
    $$select public.discard_held_pos_cart(%L)$$,
    (select held_cart_id from held_cart_test_state)
  ),
  'P0001',
  'You do not have permission to discard this held cart',
  'outsider cannot discard another tenant held cart'
);

reset role;
set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'anon', true);
select throws_ok(
  $$select public.discard_held_pos_cart(gen_random_uuid())$$,
  '42501',
  null,
  'anonymous callers cannot execute held-cart mutations'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '33000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'held-owner@example.test', true);

select lives_ok(
  format(
    $$select public.discard_held_pos_cart(%L)$$,
    (select held_cart_id from held_cart_test_state)
  ),
  'authorized owner discards a held cart'
);
select is((select count(*) from public.held_pos_carts), 0::bigint, 'discard removes the held cart');
select is((select count(*) from public.held_pos_cart_items), 0::bigint, 'discard cascades to held items');
select is(
  (select count(*) from public.tenant_audit_logs where action like 'pos.cart_%'),
  3::bigint,
  'hold, update, and discard actions are audited'
);

select * from finish();
rollback;
