-- Transactional sale return and refund verification. All fixtures roll back.
begin;

create extension if not exists pgtap with schema extensions;
select plan(21);

create temporary table sales_return_test_state (
  business_id uuid,
  branch_id uuid,
  unit_id uuid,
  warehouse_id uuid,
  variant_id uuid,
  sale_id uuid,
  sale_item_id uuid
);
grant all on sales_return_test_state to authenticated;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '60000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'returns-owner@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '60000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'returns-outsider@example.test', '', now(), '{}', '{}', now(), now());

set local role authenticated;
select set_config('request.jwt.claim.sub', '60000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'returns-owner@example.test', true);

select lives_ok(
  $$select public.create_business_with_branch('Returns Test Business', 'retail', 'INR', 'Asia/Kolkata', 'Main Branch', 'MAIN', 'IN')$$,
  'owner creates a return-test tenant'
);

insert into sales_return_test_state (business_id, branch_id, unit_id, warehouse_id)
select b.id, br.id, u.id, w.id
from public.businesses b
join public.branches br on br.business_id = b.id
join public.units u on u.business_id = b.id and u.name = 'Piece'
join public.warehouses w on w.business_id = b.id and w.branch_id = br.id and w.is_default
where b.name = 'Returns Test Business';

update sales_return_test_state set variant_id = (
  select (public.create_product_with_default_variant(
    business_id, 'Returnable Product', 'goods', null, null, unit_id, null,
    '4001', true, false, 'Default', 'RETURNABLE-PRODUCT', null, 20, 100, 0
  ) ->> 'variant_id')::uuid
  from sales_return_test_state
);

select lives_ok(
  $$select public.adjust_inventory(
    (select business_id from sales_return_test_state),
    (select warehouse_id from sales_return_test_state),
    (select variant_id from sales_return_test_state),
    10, 'return test opening stock',
    '61000000-0000-0000-0000-000000000001', 20
  )$$,
  'opening stock is created'
);

update sales_return_test_state set sale_id = (
  select (public.complete_sale(
    business_id, branch_id, null, null, null,
    '61000000-0000-0000-0000-000000000002',
    jsonb_build_array(jsonb_build_object(
      'variant_id', variant_id,
      'warehouse_id', warehouse_id,
      'quantity', 4,
      'unit_price', 100,
      'discount_amount', 0,
      'tax_rate', 0
    )),
    jsonb_build_array(jsonb_build_object('payment_method', 'cash', 'amount', 400)),
    0, 'Return test sale'
  ) ->> 'sale_id')::uuid
  from sales_return_test_state
);
select pass('cash sale completes');

update sales_return_test_state set sale_item_id = (
  select si.id from public.sale_items si
  where si.sale_id = sales_return_test_state.sale_id
);
select is(
  (select quantity_on_hand from public.inventory_balances ib
   join sales_return_test_state t
     on t.warehouse_id = ib.warehouse_id and t.variant_id = ib.variant_id),
  6.000000::numeric,
  'sale deducts inventory before the return'
);

select lives_ok(
  $$select public.process_sale_return(
    (select sale_id from sales_return_test_state),
    '61000000-0000-0000-0000-000000000003',
    jsonb_build_array(jsonb_build_object(
      'sale_item_id', (select sale_item_id from sales_return_test_state),
      'quantity', 1,
      'restock', true
    )),
    'cash', 'Customer returned one item'
  )$$,
  'partial return completes atomically'
);
select is(
  (select status from public.sales where id = (select sale_id from sales_return_test_state)),
  'partially_refunded',
  'sale is marked partially refunded'
);
select is(
  (select quantity_on_hand from public.inventory_balances ib
   join sales_return_test_state t
     on t.warehouse_id = ib.warehouse_id and t.variant_id = ib.variant_id),
  7.000000::numeric,
  'partial return restores stock'
);
select is((select refund_total from public.sale_returns), 100.00::numeric, 'return value is exact');
select is(
  (select amount from public.sale_refunds where status = 'settled'),
  100.00::numeric,
  'settled cash refund is recorded'
);
select is(
  (select quantity_delta from public.inventory_movements where movement_type = 'sale_return'),
  1.000000::numeric,
  'return inventory movement is append-only and exact'
);
select is(
  (public.get_business_dashboard(
    (select business_id from sales_return_test_state),
    now() - interval '1 day', now() + interval '1 day'
  ) ->> 'sales_total')::numeric,
  300.00::numeric,
  'dashboard nets the partial refund from sales'
);

select lives_ok(
  $$select public.process_sale_return(
    (select sale_id from sales_return_test_state),
    '61000000-0000-0000-0000-000000000003',
    jsonb_build_array(jsonb_build_object(
      'sale_item_id', (select sale_item_id from sales_return_test_state),
      'quantity', 1,
      'restock', true
    )),
    'cash', 'Customer returned one item'
  )$$,
  'return operation is idempotent'
);
select is((select count(*) from public.sale_returns), 1::bigint, 'idempotent replay creates no duplicate');
select throws_ok(
  $$select public.process_sale_return(
    (select sale_id from sales_return_test_state),
    '61000000-0000-0000-0000-000000000004',
    jsonb_build_array(jsonb_build_object(
      'sale_item_id', (select sale_item_id from sales_return_test_state),
      'quantity', 4,
      'restock', true
    )),
    'cash', 'Invalid excessive return'
  )$$,
  'P0001'
);
select throws_ok($$delete from public.sale_returns$$, '42501');

select lives_ok(
  $$select public.process_sale_return(
    (select sale_id from sales_return_test_state),
    '61000000-0000-0000-0000-000000000005',
    jsonb_build_array(jsonb_build_object(
      'sale_item_id', (select sale_item_id from sales_return_test_state),
      'quantity', 3,
      'restock', true
    )),
    'cash', 'Customer returned remaining items'
  )$$,
  'remaining quantity can be returned'
);
select is(
  (select status from public.sales where id = (select sale_id from sales_return_test_state)),
  'refunded',
  'sale is fully refunded'
);
select is(
  (select quantity_on_hand from public.inventory_balances ib
   join sales_return_test_state t
     on t.warehouse_id = ib.warehouse_id and t.variant_id = ib.variant_id),
  10.000000::numeric,
  'full return restores all sold stock'
);
select is(
  (public.get_business_dashboard(
    (select business_id from sales_return_test_state),
    now() - interval '1 day', now() + interval '1 day'
  ) ->> 'sales_total')::numeric,
  0.00::numeric,
  'dashboard nets a full refund to zero'
);
select is(
  (select sum(refund_total) from public.sale_returns),
  400.00::numeric,
  'partial and final return values equal the original sale'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '60000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'returns-outsider@example.test', true);
select is(
  (select count(*) from public.sale_returns)
    + (select count(*) from public.sale_return_items)
    + (select count(*) from public.sale_refunds),
  0::bigint,
  'outsider cannot read return or refund records'
);

select * from finish();
rollback;
