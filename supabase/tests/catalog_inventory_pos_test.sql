-- Transactional production-core verification. All fixtures roll back.
begin;

create extension if not exists pgtap with schema extensions;
select plan(61);

create temporary table core_test_state (
  business_id uuid,
  branch_id uuid,
  unit_id uuid,
  warehouse_id uuid,
  register_id uuid,
  shift_id uuid,
  customer_id uuid,
  variant_id uuid,
  first_operation_id uuid,
  sale_operation_id uuid,
  sale_id uuid
);
grant all on core_test_state to authenticated;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '30000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'core-owner@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '30000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'core-outsider@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '30000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'core-cashier@example.test', '', now(), '{}', '{}', now(), now());

set local role authenticated;
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'core-owner@example.test', true);

select lives_ok(
  $$select public.create_business_with_branch('Core Test Business', 'retail', 'INR', 'Asia/Kolkata', 'Main Branch', 'MAIN', 'IN')$$,
  'owner creates a business and branch'
);

insert into core_test_state (
  business_id, branch_id, unit_id, warehouse_id, register_id,
  customer_id, first_operation_id, sale_operation_id
)
select b.id, br.id, u.id, w.id, r.id,
  '32000000-0000-0000-0000-000000000001'::uuid,
  '31000000-0000-0000-0000-000000000001'::uuid,
  '31000000-0000-0000-0000-000000000002'::uuid
from public.businesses b
join public.branches br on br.business_id = b.id
join public.units u on u.business_id = b.id and u.name = 'Piece'
join public.warehouses w on w.business_id = b.id and w.branch_id = br.id and w.is_default
join public.registers r on r.business_id = b.id and r.branch_id = br.id
where b.name = 'Core Test Business';

insert into public.customers (id, business_id, code, name, credit_limit)
select customer_id, business_id, 'PARTIAL-1', 'Partial Payment Customer', 1000
from core_test_state;

select is((select count(*) from public.units), 4::bigint, 'branch onboarding seeds standard units');
select is((select count(*) from public.warehouses), 1::bigint, 'branch onboarding seeds a default warehouse');
select is((select count(*) from public.registers), 1::bigint, 'branch onboarding seeds a register');

update core_test_state set variant_id = (
  select (result ->> 'variant_id')::uuid
  from (
    select public.create_product_with_default_variant(
      (select business_id from core_test_state),
      'Test Product', 'goods', null, null,
      (select unit_id from core_test_state), null, '1001', true, false,
      'Default', 'TEST-001', '890000000001', 60, 100, 120
    ) result
  ) created
);

select is((select count(*) from public.products), 1::bigint, 'product RPC creates the product');
select is((select count(*) from public.product_variants), 1::bigint, 'product RPC creates its default variant');

select lives_ok(
  format(
    $$select public.adjust_inventory(%L, %L, %L, 10, 'Opening stock', %L, 60)$$,
    (select business_id from core_test_state),
    (select warehouse_id from core_test_state),
    (select variant_id from core_test_state),
    (select first_operation_id from core_test_state)
  ),
  'authorized adjustment creates stock atomically'
);

select is(
  (select quantity_on_hand from public.inventory_balances),
  10::numeric,
  'stock balance reflects opening adjustment'
);

select lives_ok(
  format(
    $$select public.adjust_inventory(%L, %L, %L, 10, 'Opening stock', %L, 60)$$,
    (select business_id from core_test_state),
    (select warehouse_id from core_test_state),
    (select variant_id from core_test_state),
    (select first_operation_id from core_test_state)
  ),
  'replaying an adjustment operation is idempotent'
);

select is((select count(*) from public.inventory_movements), 1::bigint, 'idempotent replay creates no duplicate movement');

select throws_ok(
  format(
    $$select public.adjust_inventory(%L, %L, %L, -11, 'Invalid negative stock', gen_random_uuid(), 60)$$,
    (select business_id from core_test_state),
    (select warehouse_id from core_test_state),
    (select variant_id from core_test_state)
  ),
  'P0001'
);

update core_test_state set shift_id = (
  select (result ->> 'shift_id')::uuid
  from (
    select public.open_register_shift(
      (select business_id from core_test_state),
      (select register_id from core_test_state), 500, 'Morning shift'
    ) result
  ) opened
);

update core_test_state set sale_id = (
  select (result ->> 'sale_id')::uuid
  from (
    select public.complete_sale(
      (select business_id from core_test_state),
      (select branch_id from core_test_state),
      (select register_id from core_test_state),
      (select shift_id from core_test_state), null,
      (select sale_operation_id from core_test_state),
      jsonb_build_array(jsonb_build_object(
        'variant_id', (select variant_id from core_test_state),
        'warehouse_id', (select warehouse_id from core_test_state),
        'quantity', 2, 'unit_price', 100, 'discount_amount', 10, 'tax_rate', 18
      )),
      jsonb_build_array(jsonb_build_object('payment_method', 'cash', 'amount', 224.20)),
      0, 'Verified cash sale'
    ) result
  ) completed
);

select is((select grand_total from public.sales), 224.20::numeric, 'sale tax, discount, and total are exact');
select is((select quantity_on_hand from public.inventory_balances), 8::numeric, 'completed sale decrements stock');
select is((select payment_status from public.sales), 'paid', 'cash sale is settled');
select is((select count(*) from public.inventory_movements), 2::bigint, 'sale appends an immutable stock movement');

select lives_ok(
  format(
    $$select public.complete_sale(%L, %L, %L, %L, null, %L,
      jsonb_build_array(jsonb_build_object('variant_id', %L, 'warehouse_id', %L, 'quantity', 2, 'unit_price', 100, 'discount_amount', 10, 'tax_rate', 18)),
      jsonb_build_array(jsonb_build_object('payment_method', 'cash', 'amount', 224.20)), 0, 'Replay')$$,
    (select business_id from core_test_state),
    (select branch_id from core_test_state),
    (select register_id from core_test_state),
    (select shift_id from core_test_state),
    (select sale_operation_id from core_test_state),
    (select variant_id from core_test_state),
    (select warehouse_id from core_test_state)
  ),
  'replaying a completed sale returns the stored result'
);

select is((select count(*) from public.sales), 1::bigint, 'idempotent sale replay creates no duplicate');

create temporary table split_payment_result (result jsonb);
grant all on split_payment_result to authenticated;

select lives_ok(
  format(
    $$insert into split_payment_result
      select public.complete_sale(%L, %L, %L, %L, null, %L,
        jsonb_build_array(jsonb_build_object(
          'variant_id', %L, 'warehouse_id', %L, 'quantity', 1,
          'unit_price', 100, 'discount_amount', 0, 'tax_rate', 18
        )),
        jsonb_build_array(
          jsonb_build_object('payment_method', 'cash', 'amount', 40),
          jsonb_build_object('payment_method', 'card', 'amount', 35),
          jsonb_build_object('payment_method', 'wallet', 'amount', 43)
        ), 0, 'Verified split payment')$$,
    (select business_id from core_test_state),
    (select branch_id from core_test_state),
    (select register_id from core_test_state),
    (select shift_id from core_test_state),
    '31000000-0000-0000-0000-000000000008',
    (select variant_id from core_test_state),
    (select warehouse_id from core_test_state)
  ),
  'sale accepts exact cash, card, and wallet split tender'
);

select is(
  (select count(*) from public.payments
    where sale_id = (select (result ->> 'sale_id')::uuid from split_payment_result)),
  3::bigint,
  'split sale persists one payment row per tender'
);
select is(
  (select sum(amount) from public.payments
    where sale_id = (select (result ->> 'sale_id')::uuid from split_payment_result)),
  118.00::numeric,
  'split payment rows sum exactly to the sale total'
);
select is(
  (select count(*) from public.payments
    where sale_id = (select (result ->> 'sale_id')::uuid from split_payment_result)
      and payment_method = 'cash' and status = 'settled'),
  1::bigint,
  'cash portion settles immediately'
);
select is(
  (select count(*) from public.payments
    where sale_id = (select (result ->> 'sale_id')::uuid from split_payment_result)
      and payment_method in ('card', 'wallet') and status = 'pending'),
  2::bigint,
  'card and wallet portions await provider settlement'
);
select is(
  (select payment_status from public.sales
    where id = (select (result ->> 'sale_id')::uuid from split_payment_result)),
  'partially_paid'::text,
  'settled cash marks a mixed-tender sale partially paid'
);

create temporary table partial_payment_result (result jsonb);
grant all on partial_payment_result to authenticated;

select lives_ok(
  format(
    $$insert into partial_payment_result
      select public.complete_sale(%L, %L, %L, %L, %L, %L,
        jsonb_build_array(jsonb_build_object(
          'variant_id', %L, 'warehouse_id', %L, 'quantity', 1,
          'unit_price', 100, 'discount_amount', 0, 'tax_rate', 18
        )),
        jsonb_build_array(
          jsonb_build_object('payment_method', 'cash', 'amount', 60),
          jsonb_build_object('payment_method', 'customer_credit', 'amount', 58)
        ), 0, 'Verified partial payment')$$,
    (select business_id from core_test_state),
    (select branch_id from core_test_state),
    (select register_id from core_test_state),
    (select shift_id from core_test_state),
    (select customer_id from core_test_state),
    '31000000-0000-0000-0000-000000000010',
    (select variant_id from core_test_state),
    (select warehouse_id from core_test_state)
  ),
  'sale accepts cash now and customer credit for the balance'
);
select is(
  (select payment_status from public.sales
    where id = (select (result ->> 'sale_id')::uuid from partial_payment_result)),
  'partially_paid'::text,
  'partial checkout persists the partially-paid state'
);
select is(
  (select paid_total from public.sales
    where id = (select (result ->> 'sale_id')::uuid from partial_payment_result)),
  60.00::numeric,
  'partial checkout persists the exact settled amount'
);
select is(
  (select due_total from public.sales
    where id = (select (result ->> 'sale_id')::uuid from partial_payment_result)),
  58.00::numeric,
  'partial checkout persists the exact outstanding balance'
);
select is(
  (select count(*) from public.payments
    where sale_id = (select (result ->> 'sale_id')::uuid from partial_payment_result)),
  2::bigint,
  'partial checkout persists both payment components'
);
select is(
  (select sum(amount) from public.customer_ledger_entries
    where sale_id = (select (result ->> 'sale_id')::uuid from partial_payment_result)
      and direction = 'debit'),
  58.00::numeric,
  'outstanding balance posts to the customer credit ledger'
);

select throws_ok(
  format(
    $$select public.complete_sale(%L, %L, %L, %L, null, %L,
      jsonb_build_array(jsonb_build_object(
        'variant_id', %L, 'warehouse_id', %L, 'quantity', 1,
        'unit_price', 100, 'discount_amount', 0, 'tax_rate', 18
      )),
      jsonb_build_array(
        jsonb_build_object('payment_method', 'cash', 'amount', 40),
        jsonb_build_object('payment_method', 'wallet', 'amount', 77)
      ), 0, 'Invalid split payment')$$,
    (select business_id from core_test_state),
    (select branch_id from core_test_state),
    (select register_id from core_test_state),
    (select shift_id from core_test_state),
    '31000000-0000-0000-0000-000000000009',
    (select variant_id from core_test_state),
    (select warehouse_id from core_test_state)
  ),
  'P0001'
);
select is(
  (select count(*) from public.sales),
  3::bigint,
  'rejected under-allocation creates no sale'
);

select lives_ok(
  format(
    $$select public.record_register_cash_movement(%L, %L, 'cash_in', 100, 'Float top-up')$$,
    (select shift_id from core_test_state),
    '31000000-0000-0000-0000-000000000004'
  ),
  'opening cashier records cash in'
);

select lives_ok(
  format(
    $$select public.record_register_cash_movement(%L, %L, 'cash_out', 50, 'Petty cash purchase')$$,
    (select shift_id from core_test_state),
    '31000000-0000-0000-0000-000000000005'
  ),
  'opening cashier records cash out'
);

select lives_ok(
  format(
    $$select public.record_register_cash_movement(%L, %L, 'cash_in', 100, 'Float top-up')$$,
    (select shift_id from core_test_state),
    '31000000-0000-0000-0000-000000000004'
  ),
  'cash movement replay is idempotent'
);

select is(
  (select count(*) from public.register_cash_movements),
  2::bigint,
  'idempotent movement replay creates no duplicate'
);

select lives_ok(
  format(
    $$select public.process_sale_return(%L, %L,
      jsonb_build_array(jsonb_build_object(
        'sale_item_id', %L, 'quantity', 1, 'restock', true
      )), 'cash', 'Customer returned one unit')$$,
    (select sale_id from core_test_state),
    '31000000-0000-0000-0000-000000000006',
    (select id from public.sale_items where sale_id = (select sale_id from core_test_state))
  ),
  'cash refund is recorded against the shift sale'
);

select is(
  (select amount from public.sale_refunds),
  112.10::numeric,
  'partial cash refund amount remains exact'
);

select is(
  (public.get_register_shift_report((select shift_id from core_test_state)) ->> 'report_type'),
  'X'::text,
  'open shift returns an X report'
);

select is(
  (public.get_register_shift_report((select shift_id from core_test_state)) ->> 'cash_refunds')::numeric,
  112.10::numeric,
  'X report includes settled cash refunds'
);

select is(
  (public.get_register_shift_report((select shift_id from core_test_state)) ->> 'expected_cash')::numeric,
  762.10::numeric,
  'X report reconciles opening cash, sales, refunds, cash in, and cash out'
);

select throws_ok(
  format(
    $$select public.record_register_cash_movement(%L, gen_random_uuid(), 'cash_out', 800, 'Excessive bank drop')$$,
    (select shift_id from core_test_state)
  ),
  'P0001',
  'Cash out exceeds expected drawer cash',
  'cash out cannot make expected drawer cash negative'
);

create temporary table exchange_result (result jsonb);
grant all on exchange_result to authenticated;
insert into exchange_result
select public.process_sale_exchange(
  (select sale_id from core_test_state),
  '31000000-0000-0000-0000-000000000007',
  (select register_id from core_test_state),
  (select shift_id from core_test_state),
  jsonb_build_array(jsonb_build_object(
    'sale_item_id', (select id from public.sale_items where sale_id = (select sale_id from core_test_state)),
    'quantity', 1,
    'restock', true
  )),
  jsonb_build_array(jsonb_build_object(
    'variant_id', (select variant_id from core_test_state),
    'warehouse_id', (select warehouse_id from core_test_state),
    'quantity', 1,
    'unit_price', 150,
    'discount_amount', 0,
    'tax_rate', 0
  )),
  150,
  'Exchange remaining unit for replacement'
);

select ok(
  (select result ->> 'exchange_number' is not null from exchange_result),
  'exchange returns a traceable exchange number'
);
select is((select count(*) from public.sale_exchanges), 1::bigint, 'exchange record is persisted');
select is(
  (select (result ->> 'cash_difference')::numeric from exchange_result),
  37.90::numeric,
  'exchange calculates exact cash to collect'
);
select is(
  (select status from public.sales where id = (select sale_id from core_test_state)),
  'refunded'::text,
  'exchange fully returns the original sale'
);
select is((select count(*) from public.sales), 4::bigint, 'exchange creates one replacement sale');
select is(
  (select quantity_on_hand from public.inventory_balances),
  7::numeric,
  'exchange restores returned stock and deducts replacement stock atomically'
);
select lives_ok(
  format(
    $$select public.process_sale_exchange(%L, %L, %L, %L,
      jsonb_build_array(jsonb_build_object('sale_item_id', %L, 'quantity', 1, 'restock', true)),
      jsonb_build_array(jsonb_build_object('variant_id', %L, 'warehouse_id', %L, 'quantity', 1, 'unit_price', 150, 'discount_amount', 0, 'tax_rate', 0)),
      150, 'Exchange remaining unit for replacement')$$,
    (select sale_id from core_test_state),
    '31000000-0000-0000-0000-000000000007',
    (select register_id from core_test_state),
    (select shift_id from core_test_state),
    (select id from public.sale_items where sale_id = (select sale_id from core_test_state)),
    (select variant_id from core_test_state),
    (select warehouse_id from core_test_state)
  ),
  'exchange replay returns the stored result'
);
select is((select count(*) from public.sale_exchanges), 1::bigint, 'exchange replay creates no duplicate');
select is(
  (public.get_register_shift_report((select shift_id from core_test_state)) ->> 'expected_cash')::numeric,
  800.00::numeric,
  'X report includes the exchange refund and replacement cash sale'
);

reset role;
insert into public.memberships (
  business_id, user_id, role_id, status, branch_access_all, joined_at
)
select t.business_id, '30000000-0000-0000-0000-000000000003', r.id,
       'active', true, now()
from core_test_state t
join public.roles r on r.business_id = t.business_id and r.name = 'Cashier';

set local role authenticated;
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000003', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'core-cashier@example.test', true);

select throws_ok(
  format(
    $$select public.complete_sale(%L, %L, %L, %L, null, %L,
      jsonb_build_array(jsonb_build_object('variant_id', %L, 'warehouse_id', %L, 'quantity', 1, 'unit_price', 100, 'discount_amount', 0, 'tax_rate', 0)),
      jsonb_build_array(jsonb_build_object('payment_method', 'cash', 'amount', 100)), 0, 'Wrong cashier shift')$$,
    (select business_id from core_test_state),
    (select branch_id from core_test_state),
    (select register_id from core_test_state),
    (select shift_id from core_test_state),
    '31000000-0000-0000-0000-000000000003',
    (select variant_id from core_test_state),
    (select warehouse_id from core_test_state)
  ),
  'P0001',
  'Register shift belongs to another cashier',
  'cashier cannot post a sale into another cashier shift'
);

select is(
  (select count(*) from public.sales),
  4::bigint,
  'rejected cross-cashier shift assignment creates no sale'
);

select throws_ok(
  format(
    $$select public.record_register_cash_movement(%L, gen_random_uuid(), 'cash_out', 10, 'Unauthorized drop')$$,
    (select shift_id from core_test_state)
  ),
  'P0001',
  'You do not have permission to move cash for this shift',
  'another cashier cannot move cash for the shift'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'core-owner@example.test', true);

create temporary table close_result (result jsonb);
grant all on close_result to authenticated;
insert into close_result
select public.close_register_shift(
  (select shift_id from core_test_state), 800.00, 'Balanced close'
);

select is(
  (select (result ->> 'expected_cash')::numeric from close_result),
  800.00::numeric,
  'shift close includes sales, refunds, cash in, and cash out exactly'
);
select is(
  (select (result ->> 'difference')::numeric from close_result),
  0.00::numeric,
  'shift close reports an exact balanced difference'
);
select is(
  (select status from public.register_shifts where id = (select shift_id from core_test_state)),
  'closed'::text,
  'shift close persists the closed state'
);

select is(
  (public.get_register_shift_report((select shift_id from core_test_state)) ->> 'report_type'),
  'Z'::text,
  'closed shift returns a Z report'
);
select is(
  (public.get_register_shift_report((select shift_id from core_test_state)) ->> 'cash_in')::numeric,
  100.00::numeric,
  'Z report includes cash in'
);
select is(
  (public.get_register_shift_report((select shift_id from core_test_state)) ->> 'cash_out')::numeric,
  50.00::numeric,
  'Z report includes cash out'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'core-outsider@example.test', true);

select is(
  (select count(*) from public.products) + (select count(*) from public.sales) + (select count(*) from public.inventory_balances),
  0::bigint,
  'outsider cannot read another tenant catalog, sales, or stock'
);

select throws_ok(
  format(
    $$select public.get_register_shift_report(%L)$$,
    (select shift_id from core_test_state)
  ),
  'P0001',
  'You do not have permission to view this shift report',
  'outsider cannot read another tenant shift report'
);

select * from finish();
rollback;
