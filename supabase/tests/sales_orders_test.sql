-- Stock-reserving sales order verification. All fixtures roll back.
begin;

create extension if not exists pgtap with schema extensions;
select plan(40);

create temporary table sales_order_test_state (
  business_id uuid,
  branch_id uuid,
  warehouse_id uuid,
  unit_id uuid,
  variant_id uuid,
  first_order_id uuid,
  second_order_id uuid
);
grant all on sales_order_test_state to authenticated;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '47000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'order-owner@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '47000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'order-outsider@example.test', '', now(), '{}', '{}', now(), now());

set local role authenticated;
select set_config('request.jwt.claim.sub', '47000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'order-owner@example.test', true);

select lives_ok(
  $$select public.create_business_with_branch('Sales Order Test Business', 'retail', 'INR', 'Asia/Kolkata', 'Main Branch', 'MAIN', 'IN')$$,
  'owner creates a sales order test tenant'
);

insert into sales_order_test_state (business_id, branch_id, warehouse_id, unit_id)
select business.id, branch.id, warehouse.id, unit_record.id
from public.businesses business
join public.branches branch on branch.business_id = business.id
join public.warehouses warehouse
  on warehouse.business_id = business.id and warehouse.branch_id = branch.id
join public.units unit_record
  on unit_record.business_id = business.id and unit_record.name = 'Piece'
where business.name = 'Sales Order Test Business';

update sales_order_test_state set variant_id = (
  select (public.create_product_with_default_variant(
    business_id, 'Reserved Product', 'goods', null, null, unit_id, null,
    '6202', true, false, 'Default', 'ORDER-001', null, 25, 50, 0
  ) ->> 'variant_id')::uuid
  from sales_order_test_state
);
select is((select count(*) from public.products), 1::bigint, 'sales order product is created');

select lives_ok(
  format(
    $$select public.adjust_inventory(%L, %L, %L, 10, 'Sales order opening stock', %L, 25)$$,
    (select business_id from sales_order_test_state),
    (select warehouse_id from sales_order_test_state),
    (select variant_id from sales_order_test_state),
    '48000000-0000-0000-0000-000000000001'
  ),
  'opening stock is added for reservation tests'
);
select is(
  (select quantity_on_hand from public.inventory_balances),
  10::numeric,
  'opening stock quantity is exact'
);

create temporary table first_order_result (result jsonb);
grant all on first_order_result to authenticated;
insert into first_order_result
select public.save_sales_order(
  business_id, branch_id, warehouse_id, null,
  '49000000-0000-0000-0000-000000000001',
  'October delivery', current_date + 30,
  jsonb_build_array(jsonb_build_object(
    'variant_id', variant_id, 'quantity', 2, 'unit_price', 50,
    'discount_amount', 0, 'tax_rate', 10
  )),
  5, null
)
from sales_order_test_state;
update sales_order_test_state
set first_order_id = (
  select (result ->> 'order_id')::uuid from first_order_result
);

select ok((select result ->> 'order_id' is not null from first_order_result), 'saving a sales order returns its identifier');
select matches((select result ->> 'order_number' from first_order_result), '^SO-[0-9]{14}-[A-F0-9]{8}$', 'sales order number is generated');
select is((select count(*) from public.sales_orders), 1::bigint, 'sales order is persisted');
select is((select count(*) from public.sales_order_items), 1::bigint, 'sales order item is persisted');
select is((select subtotal from public.sales_orders), 100::numeric, 'sales order subtotal is exact');
select is((select discount_total from public.sales_orders), 5::numeric, 'sales order discount is exact');
select is((select tax_total from public.sales_orders), 10::numeric, 'sales order tax is exact');
select is((select grand_total from public.sales_orders), 105::numeric, 'sales order grand total is exact');
select is((select quantity_reserved from public.inventory_balances), 2::numeric, 'open sales order reserves stock');
select is((select count(*) from public.inventory_movements where movement_type = 'sale'), 0::bigint, 'reservation does not move inventory');

select lives_ok(
  format(
    $$select public.save_sales_order(%L, %L, %L, null, %L, 'Replay ignored', current_date + 7,
      jsonb_build_array(jsonb_build_object('variant_id', %L, 'quantity', 1, 'unit_price', 1, 'tax_rate', 0)), 0, null)$$,
    (select business_id from sales_order_test_state),
    (select branch_id from sales_order_test_state),
    (select warehouse_id from sales_order_test_state),
    '49000000-0000-0000-0000-000000000001',
    (select variant_id from sales_order_test_state)
  ),
  'replaying a sales order operation is idempotent'
);
select is((select count(*) from public.sales_orders), 1::bigint, 'sales order replay creates no duplicate');

select lives_ok(
  format(
    $$select public.save_sales_order(%L, %L, %L, null, %L, 'Updated delivery', current_date + 45,
      jsonb_build_array(jsonb_build_object('variant_id', %L, 'quantity', 3, 'unit_price', 50, 'tax_rate', 10)), 0, %L)$$,
    (select business_id from sales_order_test_state),
    (select branch_id from sales_order_test_state),
    (select warehouse_id from sales_order_test_state),
    '49000000-0000-0000-0000-000000000002',
    (select variant_id from sales_order_test_state),
    (select first_order_id from sales_order_test_state)
  ),
  'open sales order can be updated atomically'
);
select is((select title from public.sales_orders), 'Updated delivery'::text, 'sales order title is updated');
select is((select grand_total from public.sales_orders), 165::numeric, 'updated sales order total is exact');
select is((select quantity_reserved from public.inventory_balances), 3::numeric, 'updating replaces the stock reservation exactly');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '47000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'order-outsider@example.test', true);

select is((select count(*) from public.sales_orders), 0::bigint, 'outsider cannot read sales orders');
select throws_ok(
  format(
    $$select public.save_sales_order(%L, %L, %L, null, gen_random_uuid(), 'Unauthorized', current_date + 7,
      jsonb_build_array(jsonb_build_object('variant_id', %L, 'quantity', 1, 'unit_price', 1, 'tax_rate', 0)), 0, null)$$,
    (select business_id from sales_order_test_state),
    (select branch_id from sales_order_test_state),
    (select warehouse_id from sales_order_test_state),
    (select variant_id from sales_order_test_state)
  ),
  'P0001',
  'You do not have permission to create sales orders',
  'outsider cannot create a sales order in another tenant'
);
select throws_ok(
  format($$select public.cancel_sales_order(%L)$$, (select first_order_id from sales_order_test_state)),
  'P0001',
  'You do not have permission to cancel this sales order',
  'outsider cannot cancel another tenant sales order'
);

reset role;
set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'anon', true);
select throws_ok(
  $$select public.cancel_sales_order(gen_random_uuid())$$,
  '42501',
  null,
  'anonymous callers cannot execute sales order mutations'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '47000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'order-owner@example.test', true);

create temporary table second_order_result (result jsonb);
grant all on second_order_result to authenticated;
insert into second_order_result
select public.save_sales_order(
  business_id, branch_id, warehouse_id, null,
  '49000000-0000-0000-0000-000000000003',
  'Cancellable order', current_date + 30,
  jsonb_build_array(jsonb_build_object(
    'variant_id', variant_id, 'quantity', 2, 'unit_price', 50,
    'discount_amount', 0, 'tax_rate', 10
  )),
  0, null
)
from sales_order_test_state;
update sales_order_test_state
set second_order_id = (
  select (result ->> 'order_id')::uuid from second_order_result
);
select ok((select second_order_id is not null from sales_order_test_state), 'second sales order is saved for cancellation');
select is((select quantity_reserved from public.inventory_balances), 5::numeric, 'multiple open orders reserve cumulative stock');

select throws_ok(
  format(
    $$select public.save_sales_order(%L, %L, %L, null, gen_random_uuid(), 'Too large', current_date + 7,
      jsonb_build_array(jsonb_build_object('variant_id', %L, 'quantity', 6, 'unit_price', 50, 'tax_rate', 0)), 0, null)$$,
    (select business_id from sales_order_test_state),
    (select branch_id from sales_order_test_state),
    (select warehouse_id from sales_order_test_state),
    (select variant_id from sales_order_test_state)
  ),
  'P0001',
  'Insufficient available stock for SKU ORDER-001',
  'sales order rejects an over-reservation'
);
select is((select quantity_reserved from public.inventory_balances), 5::numeric, 'failed reservation leaves stock unchanged');

select lives_ok(
  format($$select public.cancel_sales_order(%L)$$, (select second_order_id from sales_order_test_state)),
  'authorized owner cancels an open sales order'
);
select is(
  (select status from public.sales_orders where id = (select second_order_id from sales_order_test_state)),
  'cancelled'::text,
  'cancelled sales order retains its lifecycle record'
);
select is((select quantity_reserved from public.inventory_balances), 3::numeric, 'cancellation releases only its reservation');

create temporary table fulfilled_order_result (result jsonb);
grant all on fulfilled_order_result to authenticated;
insert into fulfilled_order_result
select public.fulfill_sales_order(
  first_order_id, null, null,
  '4a000000-0000-0000-0000-000000000001',
  jsonb_build_array(jsonb_build_object('payment_method', 'cash', 'amount', 165))
)
from sales_order_test_state;
select ok((select result ->> 'sale_id' is not null from fulfilled_order_result), 'open sales order fulfills into a completed sale');
select ok(
  (select status = 'fulfilled' and fulfilled_sale_id is not null
   from public.sales_orders
   where id = (select first_order_id from sales_order_test_state)),
  'fulfilled sales order links its completed sale'
);
select is((select sale_type from public.sales), 'sales_order'::text, 'fulfilled sale is classified as a sales order');
select is((select quantity_reserved from public.inventory_balances), 0::numeric, 'fulfillment releases the reservation');
select is((select quantity_on_hand from public.inventory_balances), 7::numeric, 'fulfillment deducts the ordered stock exactly once');
select is((select count(*) from public.inventory_movements where movement_type = 'sale'), 1::bigint, 'fulfillment creates one immutable sale movement');

select lives_ok(
  format(
    $$select public.fulfill_sales_order(%L, null, null, %L,
      jsonb_build_array(jsonb_build_object('payment_method', 'cash', 'amount', 165)))$$,
    (select first_order_id from sales_order_test_state),
    '4a000000-0000-0000-0000-000000000001'
  ),
  'replaying fulfillment returns the existing sale'
);
select is((select count(*) from public.sales), 1::bigint, 'fulfillment replay creates no duplicate sale');
select is(
  (select count(*) from public.tenant_audit_logs where action like 'sales.order_%'),
  5::bigint,
  'create, update, cancel, and fulfill sales order actions are audited'
);

select * from finish();
rollback;
