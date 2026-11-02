begin;

create extension if not exists pgtap with schema extensions;
select plan(11);

select set_config('request.jwt.claim.sub', '01331716-1fbd-4780-bc16-b4dba20a96aa', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select ok(
  (select relrowsecurity from pg_class where relname = 'business_loyalty_settings'),
  'loyalty settings have RLS'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.redeem_customer_loyalty_points(uuid,uuid,uuid,uuid,numeric,text)',
    'execute'
  ),
  'anonymous users cannot redeem loyalty'
);
select ok(
  exists (select 1 from public.business_loyalty_settings
          where business_id = 'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8'),
  'business has seeded loyalty settings'
);
select lives_ok(
  $$select public.set_business_loyalty_settings(
    'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8', true, 2, 100, 100
  )$$,
  'authorized business can configure loyalty'
);
select is(
  (select earn_points_per_currency from public.business_loyalty_settings
   where business_id = 'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8'),
  2::numeric,
  'earn rate persisted'
);

insert into public.customers (business_id, name, email)
values ('c2c28e90-c16f-4c34-91f6-d8cc19a36ff8', 'PGTAP loyalty',
        'pgtap-loyalty@example.invalid');
insert into public.sales (
  business_id, branch_id, customer_id, invoice_number, sale_type, status,
  payment_status, currency_code, subtotal, discount_total, tax_total,
  service_charge_total, rounding_amount, grand_total, paid_total, due_total,
  operation_id, completed_by
)
select 'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8',
       '5a0ff467-ef70-4e25-a73d-f8fd91f31d74', c.id,
       'PGTAP-LOYALTY-' || substr(gen_random_uuid()::text, 1, 8),
       'invoice', 'completed', 'paid', 'INR', 125, 0, 0, 0, 0, 125, 125, 0,
       gen_random_uuid(), '01331716-1fbd-4780-bc16-b4dba20a96aa'
from public.customers c
where c.email = 'pgtap-loyalty@example.invalid';

select is(
  (select count(*)::int from public.customer_loyalty_transactions
   where customer_id = (select id from public.customers
                        where email = 'pgtap-loyalty@example.invalid')),
  1,
  'paid completed sale earns one idempotent loyalty ledger row'
);
select is(
  (select points_delta from public.customer_loyalty_transactions
   where customer_id = (select id from public.customers
                        where email = 'pgtap-loyalty@example.invalid')),
  250::numeric,
  'sale earn amount follows configured rate'
);
select is(
  (select loyalty_points from public.customers
   where email = 'pgtap-loyalty@example.invalid'),
  250::numeric,
  'customer balance mirrors earned points'
);
select lives_ok(
  $$select public.redeem_customer_loyalty_points(
    'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8',
    (select id from public.customers where email = 'pgtap-loyalty@example.invalid'),
    '5a0ff467-ef70-4e25-a73d-f8fd91f31d74', gen_random_uuid(), 100,
    'PGTAP redemption'
  )$$,
  'authorized cashier can redeem points'
);
select is(
  (select loyalty_points from public.customers
   where email = 'pgtap-loyalty@example.invalid'),
  150::numeric,
  'redeem decrements balance'
);
select throws_ok(
  $$select public.redeem_customer_loyalty_points(
    'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8',
    (select id from public.customers where email = 'pgtap-loyalty@example.invalid'),
    '5a0ff467-ef70-4e25-a73d-f8fd91f31d74', gen_random_uuid(), 1000,
    'too much'
  )$$,
  'P0001', 'Insufficient loyalty points',
  'redemption cannot overdraw balance'
);

select * from finish();
rollback;
