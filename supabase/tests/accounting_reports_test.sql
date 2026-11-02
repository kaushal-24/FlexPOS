-- Transactional accounting and reporting verification. All fixtures roll back.
begin;

create extension if not exists pgtap with schema extensions;
select plan(17);

create temporary table accounting_test_state (
  business_id uuid,
  branch_id uuid,
  unit_id uuid,
  warehouse_id uuid,
  variant_id uuid,
  customer_id uuid,
  category_id uuid,
  expense_id uuid,
  sale_id uuid
);
grant all on accounting_test_state to authenticated;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '50000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'accounting-owner@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '50000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'accounting-outsider@example.test', '', now(), '{}', '{}', now(), now());

set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'accounting-owner@example.test', true);

select lives_ok(
  $$select public.create_business_with_branch('Accounting Test Business', 'retail', 'INR', 'Asia/Kolkata', 'Main Branch', 'MAIN', 'IN')$$,
  'owner creates an accounting tenant'
);

insert into accounting_test_state (
  business_id, branch_id, unit_id, warehouse_id, customer_id, category_id
)
select b.id, br.id, u.id, w.id,
  '52000000-0000-0000-0000-000000000001'::uuid, ec.id
from public.businesses b
join public.branches br on br.business_id = b.id
join public.units u on u.business_id = b.id and u.name = 'Piece'
join public.warehouses w on w.business_id = b.id and w.branch_id = br.id and w.is_default
join public.expense_categories ec on ec.business_id = b.id and ec.name = 'Other'
where b.name = 'Accounting Test Business';

insert into public.customers (id, business_id, code, name, credit_limit)
select customer_id, business_id, 'CREDIT-1', 'Credit Customer', 1000
from accounting_test_state;

update accounting_test_state set variant_id = (
  select (public.create_product_with_default_variant(
    business_id, 'Credit Product', 'goods', null, null, unit_id, null,
    '3001', true, false, 'Default', 'CREDIT-PRODUCT', null, 20, 100, 0
  ) ->> 'variant_id')::uuid
  from accounting_test_state
);
select is((select count(*) from public.expense_categories), 8::bigint, 'new business receives default expense categories');

select lives_ok(
  $$select public.create_expense(
    (select business_id from accounting_test_state),
    (select branch_id from accounting_test_state),
    (select category_id from accounting_test_state),
    '51000000-0000-0000-0000-000000000001', 250, 45, 'cash',
    'Test Vendor', 'REF-1', 'Test expense', current_date
  )$$,
  'authorized expense is recorded'
);
update accounting_test_state set expense_id = (select id from public.expenses where entry_type = 'expense');
select is((select amount from public.expenses where entry_type = 'expense'), 250.00::numeric, 'expense amount remains exact');

select lives_ok(
  $$select public.create_expense(
    (select business_id from accounting_test_state),
    (select branch_id from accounting_test_state),
    (select category_id from accounting_test_state),
    '51000000-0000-0000-0000-000000000001', 250, 45, 'cash',
    'Test Vendor', 'REF-1', 'Replay', current_date
  )$$,
  'expense operation is idempotent'
);
select is((select count(*) from public.expenses), 1::bigint, 'expense replay creates no duplicate');
select throws_ok($$update public.expenses set amount = 1$$, '42501');

select lives_ok(
  $$select public.reverse_expense(
    (select expense_id from accounting_test_state),
    '51000000-0000-0000-0000-000000000002', 'Entry correction'
  )$$,
  'expense is reversed with an append-only record'
);
select is(
  (select sum(case when entry_type = 'expense' then amount else -amount end) from public.expenses),
  0.00::numeric,
  'expense reversal nets to zero'
);

select lives_ok(
  $$select public.adjust_inventory(
    (select business_id from accounting_test_state),
    (select warehouse_id from accounting_test_state),
    (select variant_id from accounting_test_state),
    10, 'opening_balance', '51000000-0000-0000-0000-000000000003', 20
  )$$,
  'inventory is available for a credit sale'
);

update accounting_test_state set sale_id = (
  select (public.complete_sale(
    business_id, branch_id, null, null, customer_id,
    '51000000-0000-0000-0000-000000000004',
    jsonb_build_array(jsonb_build_object(
      'variant_id', variant_id, 'warehouse_id', warehouse_id,
      'quantity', 2, 'unit_price', 100, 'discount_amount', 0, 'tax_rate', 0
    )),
    jsonb_build_array(jsonb_build_object('payment_method', 'customer_credit', 'amount', 200)),
    0, 'Credit sale'
  ) ->> 'sale_id')::uuid
  from accounting_test_state
);
select is((select sum(amount) from public.customer_ledger_entries where direction = 'debit'), 200.00::numeric, 'credit sale posts a customer debit');

select lives_ok(
  $$select public.record_customer_repayment(
    (select business_id from accounting_test_state),
    (select branch_id from accounting_test_state),
    (select customer_id from accounting_test_state),
    '51000000-0000-0000-0000-000000000005', 75, 'cash', 'CASH-1', 'Partial repayment'
  )$$,
  'partial customer repayment is recorded'
);
select is((select due_total from public.sales where id = (select sale_id from accounting_test_state)), 125.00::numeric, 'repayment reduces the sale due');
select is(
  (select sum(case when direction = 'debit' then amount else -amount end) from public.customer_ledger_entries),
  125.00::numeric,
  'customer ledger balance matches remaining due'
);
select throws_ok(
  $$select public.record_customer_repayment(
    (select business_id from accounting_test_state),
    (select branch_id from accounting_test_state),
    (select customer_id from accounting_test_state),
    gen_random_uuid(), 126, 'cash', null, null
  )$$,
  'P0001'
);

select ok(
  (public.get_business_dashboard(
    (select business_id from accounting_test_state), now() - interval '1 day', now() + interval '1 day'
  ) ->> 'sales_total')::numeric = 200,
  'dashboard uses authoritative sales totals'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'accounting-outsider@example.test', true);
select is(
  (select count(*) from public.expenses)
    + (select count(*) from public.customer_ledger_entries)
    + (select count(*) from public.customer_receipts),
  0::bigint,
  'outsider cannot read accounting records'
);

select * from finish();
rollback;
