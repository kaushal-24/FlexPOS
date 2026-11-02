-- Transactional customer and purchasing verification. All fixtures roll back.
begin;

create extension if not exists pgtap with schema extensions;
select plan(18);

create temporary table purchasing_test_state (
  business_id uuid,
  branch_id uuid,
  unit_id uuid,
  warehouse_id uuid,
  variant_id uuid,
  supplier_id uuid,
  purchase_order_id uuid,
  purchase_order_item_id uuid,
  create_operation_id uuid,
  first_receipt_operation_id uuid,
  second_receipt_operation_id uuid
);
grant all on purchasing_test_state to authenticated;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '40000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'purchasing-owner@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '40000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'purchasing-outsider@example.test', '', now(), '{}', '{}', now(), now());

set local role authenticated;
select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'purchasing-owner@example.test', true);

select lives_ok(
  $$select public.create_business_with_branch('Purchasing Test Business', 'retail', 'INR', 'Asia/Kolkata', 'Main Branch', 'MAIN', 'IN')$$,
  'owner creates a business for purchasing'
);

insert into purchasing_test_state (
  business_id, branch_id, unit_id, warehouse_id,
  supplier_id, create_operation_id, first_receipt_operation_id,
  second_receipt_operation_id
)
select b.id, br.id, u.id, w.id,
  '42000000-0000-0000-0000-000000000001'::uuid,
  '41000000-0000-0000-0000-000000000001'::uuid,
  '41000000-0000-0000-0000-000000000002'::uuid,
  '41000000-0000-0000-0000-000000000003'::uuid
from public.businesses b
join public.branches br on br.business_id = b.id
join public.units u on u.business_id = b.id and u.name = 'Piece'
join public.warehouses w on w.business_id = b.id and w.branch_id = br.id and w.is_default
where b.name = 'Purchasing Test Business';

update purchasing_test_state set variant_id = (
  select (result ->> 'variant_id')::uuid
  from (
    select public.create_product_with_default_variant(
      (select business_id from purchasing_test_state),
      'Purchase Test Product', 'goods', null, null,
      (select unit_id from purchasing_test_state), null, '2001', true, false,
      'Default', 'PURCHASE-001', '890000000002', 10, 20, 25
    ) result
  ) created
);
select is((select count(*) from public.products), 1::bigint, 'stock product is created');

insert into public.customers (business_id, code, name, phone, credit_limit)
values ((select business_id from purchasing_test_state), 'C-001', 'Test Customer', '9000000000', 5000);
select is((select count(*) from public.customers), 1::bigint, 'authorized user creates a customer');

insert into public.suppliers (id, business_id, code, name, phone)
values (
  (select supplier_id from purchasing_test_state),
  (select business_id from purchasing_test_state),
  'S-001', 'Test Supplier', '9111111111'
);
select is((select count(*) from public.suppliers), 1::bigint, 'authorized user creates a supplier');

update purchasing_test_state set purchase_order_id = (
  select (result ->> 'purchase_order_id')::uuid
  from (
    select public.create_purchase_order(
      (select business_id from purchasing_test_state),
      (select supplier_id from purchasing_test_state),
      (select warehouse_id from purchasing_test_state),
      (select create_operation_id from purchasing_test_state),
      jsonb_build_array(jsonb_build_object(
        'variant_id', (select variant_id from purchasing_test_state),
        'quantity', 5, 'unit_cost', 10, 'tax_rate', 18
      )), null, 'SUP-REF-1', 'Test purchase order'
    ) result
  ) created
);
update purchasing_test_state set purchase_order_item_id = (
  select id from public.purchase_order_items
  where purchase_order_id = (select purchase_order_id from purchasing_test_state)
);

select is((select grand_total from public.purchase_orders), 59.00::numeric, 'purchase tax and total are exact');
select is((select count(*) from public.inventory_balances), 0::bigint, 'placing an order does not change stock');

select lives_ok(
  format(
    $$select public.receive_purchase_order(%L, %L, jsonb_build_array(jsonb_build_object('purchase_order_item_id', %L, 'quantity', 2)), 'GRN-1', 'Partial receipt')$$,
    (select purchase_order_id from purchasing_test_state),
    (select first_receipt_operation_id from purchasing_test_state),
    (select purchase_order_item_id from purchasing_test_state)
  ),
  'partial receipt completes atomically'
);
select is((select quantity_on_hand from public.inventory_balances), 2::numeric, 'partial receipt increases stock');
select is((select status from public.purchase_orders), 'partially_received', 'order is marked partially received');

select lives_ok(
  format(
    $$select public.receive_purchase_order(%L, %L, jsonb_build_array(jsonb_build_object('purchase_order_item_id', %L, 'quantity', 2)), 'GRN-1', 'Replay')$$,
    (select purchase_order_id from purchasing_test_state),
    (select first_receipt_operation_id from purchasing_test_state),
    (select purchase_order_item_id from purchasing_test_state)
  ),
  'replaying a receipt returns the stored result'
);
select is((select count(*) from public.goods_receipts), 1::bigint, 'idempotent receipt replay creates no duplicate');

select throws_ok(
  format(
    $$select public.receive_purchase_order(%L, gen_random_uuid(), jsonb_build_array(jsonb_build_object('purchase_order_item_id', %L, 'quantity', 4)), null, null)$$,
    (select purchase_order_id from purchasing_test_state),
    (select purchase_order_item_id from purchasing_test_state)
  ),
  'P0001'
);

select lives_ok(
  format(
    $$select public.receive_purchase_order(%L, %L, jsonb_build_array(jsonb_build_object('purchase_order_item_id', %L, 'quantity', 3)), 'GRN-2', 'Final receipt')$$,
    (select purchase_order_id from purchasing_test_state),
    (select second_receipt_operation_id from purchasing_test_state),
    (select purchase_order_item_id from purchasing_test_state)
  ),
  'final receipt completes the order'
);
select is((select quantity_on_hand from public.inventory_balances), 5::numeric, 'all receipts produce the correct stock');
select is((select status from public.purchase_orders), 'received', 'fully received order is completed');
select is((select count(*) from public.inventory_movements where movement_type = 'purchase'), 2::bigint, 'each receipt appends an immutable stock movement');

select throws_ok(
  $$update public.goods_receipts set total_cost = 0$$,
  '42501'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'purchasing-outsider@example.test', true);
select is(
  (select count(*) from public.customers)
    + (select count(*) from public.suppliers)
    + (select count(*) from public.purchase_orders)
    + (select count(*) from public.goods_receipts),
  0::bigint,
  'outsider cannot read another tenant customers or purchasing data'
);

select * from finish();
rollback;
