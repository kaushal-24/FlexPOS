-- Payment verification, reconciliation, and provider idempotency checks.
-- All fixtures are transactional and roll back.
begin;

create extension if not exists pgtap with schema extensions;
select plan(44);

create temporary table payment_verification_test_state (
  business_id uuid,
  branch_id uuid,
  warehouse_id uuid,
  unit_id uuid,
  variant_id uuid,
  manual_sale_id uuid,
  manual_payment_id uuid,
  failed_sale_id uuid,
  failed_payment_id uuid,
  provider_sale_id uuid,
  provider_payment_id uuid,
  retry_sale_id uuid,
  retry_payment_id uuid
);
grant all on payment_verification_test_state to authenticated, service_role;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000',
   '52000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'payment-owner@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '52000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'payment-outsider@example.test', '', now(), '{}', '{}', now(), now());

set local role authenticated;
select set_config('request.jwt.claim.sub', '52000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'payment-owner@example.test', true);

select lives_ok(
  $$select public.create_business_with_branch(
    'Payment Verification Test Business', 'retail', 'INR', 'Asia/Kolkata',
    'Main Branch', 'MAIN', 'IN'
  )$$,
  'owner creates the payment-verification test tenant'
);

insert into payment_verification_test_state (
  business_id, branch_id, warehouse_id, unit_id
)
select business.id, branch.id, warehouse.id, unit.id
from public.businesses business
join public.branches branch on branch.business_id = business.id
join public.warehouses warehouse
  on warehouse.business_id = business.id
 and warehouse.branch_id = branch.id
 and warehouse.is_default
join public.units unit
  on unit.business_id = business.id and unit.name = 'Piece'
where business.name = 'Payment Verification Test Business';

update payment_verification_test_state set variant_id = (
  select (public.create_product_with_default_variant(
    business_id, 'Verification Product', 'goods', null, null, unit_id, null,
    '6209', true, false, 'Default', 'VERIFY-PRODUCT', null,
    20, 100, 0
  ) ->> 'variant_id')::uuid
  from payment_verification_test_state
);
select is(
  (select count(*) from public.products product
   where product.business_id = (
     select business_id from payment_verification_test_state
   )),
  1::bigint,
  'sale product is created'
);

select lives_ok(
  $$select public.adjust_inventory(
    (select business_id from payment_verification_test_state),
    (select warehouse_id from payment_verification_test_state),
    (select variant_id from payment_verification_test_state),
    20, 'payment verification opening stock',
    '52100000-0000-0000-0000-000000000001', 20
  )$$,
  'opening stock is created'
);

update payment_verification_test_state set manual_sale_id = (
  select (public.complete_sale(
    business_id, branch_id, null, null, null,
    '52100000-0000-0000-0000-000000000002',
    jsonb_build_array(jsonb_build_object(
      'variant_id', variant_id, 'warehouse_id', warehouse_id,
      'quantity', 1, 'unit_price', 100, 'discount_amount', 0, 'tax_rate', 0
    )),
    jsonb_build_array(jsonb_build_object(
      'payment_method', 'card', 'amount', 100, 'reference', 'CARD-INITIAL'
    )), 0, 'Manual reconciliation sale'
  ) ->> 'sale_id')::uuid
  from payment_verification_test_state
);
update payment_verification_test_state set manual_payment_id = (
  select payment.id from public.payments payment
  where payment.sale_id = manual_sale_id
);
select ok(
  (select manual_sale_id is not null from payment_verification_test_state),
  'pending card sale is created'
);

reset role;
select is(
  (select sale.payment_status || ':' || sale.paid_total::text || ':' || sale.due_total::text
   from public.sales sale
   where sale.id = (select manual_sale_id from payment_verification_test_state)),
  'pending:0.00:100.00'::text,
  'unverified card payment is not settled'
);

set local role authenticated;
select lives_ok(
  $$select public.reconcile_payment(
    (select manual_payment_id from payment_verification_test_state),
    '52100000-0000-0000-0000-000000000003',
    'settled', 'BANK-EVIDENCE-1001',
    'Verified against the merchant settlement report.'
  )$$,
  'authorized manual reconciliation settles a pending payment'
);

reset role;
select is(
  (select payment.status from public.payments payment
   where payment.id = (select manual_payment_id from payment_verification_test_state)),
  'settled'::text,
  'manual reconciliation settles the payment row'
);
select is(
  (select sale.payment_status || ':' || sale.paid_total::text || ':' || sale.due_total::text
   from public.sales sale
   where sale.id = (select manual_sale_id from payment_verification_test_state)),
  'paid:100.00:0.00'::text,
  'manual reconciliation atomically refreshes exact sale totals'
);
select is(
  (select event.source || ':' || event.outcome || ':' || event.applied::text
   from public.payment_verification_events event
   where event.payment_id = (
     select manual_payment_id from payment_verification_test_state
   )),
  'manual:settled:true'::text,
  'manual reconciliation appends an immutable applied event'
);
select is(
  (select count(*) from public.tenant_audit_logs audit
   where audit.action = 'payment.reconciled'
     and audit.target_id = (
       select manual_payment_id::text from payment_verification_test_state
     )),
  1::bigint,
  'manual reconciliation is audited'
);

set local role authenticated;
select lives_ok(
  $$select public.reconcile_payment(
    (select manual_payment_id from payment_verification_test_state),
    '52100000-0000-0000-0000-000000000003',
    'settled', 'BANK-EVIDENCE-1001',
    'Verified against the merchant settlement report.'
  )$$,
  'manual reconciliation replay is idempotent'
);
reset role;
select is(
  (select count(*) from public.payment_verification_events event
   where event.payment_id = (
     select manual_payment_id from payment_verification_test_state
   )),
  1::bigint,
  'manual reconciliation replay creates no duplicate event'
);

set local role authenticated;
update payment_verification_test_state set failed_sale_id = (
  select (public.complete_sale(
    business_id, branch_id, null, null, null,
    '52100000-0000-0000-0000-000000000004',
    jsonb_build_array(jsonb_build_object(
      'variant_id', variant_id, 'warehouse_id', warehouse_id,
      'quantity', 1, 'unit_price', 100, 'discount_amount', 0, 'tax_rate', 0
    )),
    jsonb_build_array(jsonb_build_object(
      'payment_method', 'upi', 'amount', 100, 'reference', 'UPI-FAILED'
    )), 0, 'Failed manual verification sale'
  ) ->> 'sale_id')::uuid
  from payment_verification_test_state
);
update payment_verification_test_state set failed_payment_id = (
  select payment.id from public.payments payment where payment.sale_id = failed_sale_id
);
select ok(
  (select failed_sale_id is not null from payment_verification_test_state),
  'second pending sale is created for a failed verification'
);
select lives_ok(
  $$select public.reconcile_payment(
    (select failed_payment_id from payment_verification_test_state),
    '52100000-0000-0000-0000-000000000005',
    'failed', 'UPI-REJECTION-1002',
    'Provider dashboard confirms the payment was rejected.'
  )$$,
  'authorized manual reconciliation can record a failed payment'
);
reset role;
select is(
  (select payment.status from public.payments payment
   where payment.id = (select failed_payment_id from payment_verification_test_state)),
  'failed'::text,
  'failed verification never settles the payment'
);
select is(
  (select sale.payment_status || ':' || sale.paid_total::text || ':' || sale.due_total::text
   from public.sales sale
   where sale.id = (select failed_sale_id from payment_verification_test_state)),
  'unpaid:0.00:100.00'::text,
  'failed verification leaves the sale fully due'
);
select is(
  (select event.outcome from public.payment_verification_events event
   where event.payment_id = (select failed_payment_id from payment_verification_test_state)),
  'failed'::text,
  'failed manual verification is recorded'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '52000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.email', 'payment-outsider@example.test', true);
select throws_ok(
  $$select public.reconcile_payment(
    (select failed_payment_id from payment_verification_test_state),
    gen_random_uuid(), 'settled', 'OUTSIDER-1003',
    'An outsider must not reconcile another tenant payment.'
  )$$,
  'P0001', 'Payment reconciliation permission required',
  'an outsider cannot reconcile another tenant payment'
);
select is(
  (select count(*) from public.payment_verification_events),
  0::bigint,
  'RLS hides verification events from an outsider'
);

select set_config('request.jwt.claim.sub', '52000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.email', 'payment-owner@example.test', true);
update payment_verification_test_state set provider_sale_id = (
  select (public.complete_sale(
    business_id, branch_id, null, null, null,
    '52100000-0000-0000-0000-000000000006',
    jsonb_build_array(jsonb_build_object(
      'variant_id', variant_id, 'warehouse_id', warehouse_id,
      'quantity', 1, 'unit_price', 100, 'discount_amount', 0, 'tax_rate', 0
    )),
    jsonb_build_array(jsonb_build_object(
      'payment_method', 'wallet', 'amount', 100,
      'reference', 'WALLET-1004', 'provider', 'demo_pay'
    )), 0, 'Provider verification sale'
  ) ->> 'sale_id')::uuid
  from payment_verification_test_state
);
update payment_verification_test_state set provider_payment_id = (
  select payment.id from public.payments payment where payment.sale_id = provider_sale_id
);
select ok(
  (select provider_sale_id is not null from payment_verification_test_state),
  'provider-backed pending sale is created'
);

select set_config('request.jwt.claim.sub', '', true);
reset role;
set local role service_role;
select lives_ok(
  $$select public.record_provider_payment_verification(
    (select provider_payment_id from payment_verification_test_state),
    'demo_pay', 'evt_provider_1001', 'wallet_payment_1004',
    'settled', 100, 'INR', repeat('a', 64)
  )$$,
  'service-only provider intake settles an exactly matched payment'
);

reset role;
select is(
  (select payment.provider || ':' || payment.status
   from public.payments payment
   where payment.id = (select provider_payment_id from payment_verification_test_state)),
  'demo_pay:settled'::text,
  'provider verification records the provider and settlement'
);
select is(
  (select sale.payment_status || ':' || sale.paid_total::text || ':' || sale.due_total::text
   from public.sales sale
   where sale.id = (select provider_sale_id from payment_verification_test_state)),
  'paid:100.00:0.00'::text,
  'provider settlement atomically pays the sale'
);
select is(
  (select event.outcome || ':' || event.applied::text
   from public.payment_verification_events event
   where event.provider_event_id = 'evt_provider_1001'),
  'settled:true'::text,
  'provider settlement creates an applied verification event'
);
select is(
  (select event.payload_sha256 from public.payment_verification_events event
   where event.provider_event_id = 'evt_provider_1001'),
  repeat('a', 64),
  'only the provider payload digest is retained'
);
select is(
  (select count(*) from public.tenant_audit_logs audit
   where audit.action = 'payment.provider_verified'
     and audit.target_id = (
       select provider_payment_id::text from payment_verification_test_state
     )),
  1::bigint,
  'provider verification is audited'
);

set local role service_role;
select lives_ok(
  $$select public.record_provider_payment_verification(
    (select provider_payment_id from payment_verification_test_state),
    'demo_pay', 'evt_provider_1001', 'wallet_payment_1004',
    'settled', 100, 'INR', repeat('a', 64)
  )$$,
  'provider event replay is idempotent'
);
reset role;
select is(
  (select count(*) from public.payment_verification_events event
   where event.provider_event_id = 'evt_provider_1001'),
  1::bigint,
  'provider replay creates no duplicate verification event'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '52000000-0000-0000-0000-000000000001', true);
update payment_verification_test_state set retry_sale_id = (
  select (public.complete_sale(
    business_id, branch_id, null, null, null,
    '52100000-0000-0000-0000-000000000007',
    jsonb_build_array(jsonb_build_object(
      'variant_id', variant_id, 'warehouse_id', warehouse_id,
      'quantity', 1, 'unit_price', 100, 'discount_amount', 0, 'tax_rate', 0
    )),
    jsonb_build_array(jsonb_build_object(
      'payment_method', 'card', 'amount', 100, 'provider', 'demo_pay'
    )), 0, 'Provider retry sale'
  ) ->> 'sale_id')::uuid
  from payment_verification_test_state
);
update payment_verification_test_state set retry_payment_id = (
  select payment.id from public.payments payment where payment.sale_id = retry_sale_id
);
select ok(
  (select retry_sale_id is not null from payment_verification_test_state),
  'retry test sale is created'
);

select set_config('request.jwt.claim.sub', '', true);
reset role;
set local role service_role;
select throws_ok(
  $$select public.record_provider_payment_verification(
    (select retry_payment_id from payment_verification_test_state),
    'demo_pay', 'evt_provider_mismatch', 'card_payment_1005',
    'settled', 99, 'INR', repeat('b', 64)
  )$$,
  'P0001', 'Provider amount does not match the recorded payment',
  'amount mismatch is rejected before settlement'
);
reset role;
select is(
  (select count(*) from public.payment_verification_events event
   where event.provider_event_id = 'evt_provider_mismatch'),
  0::bigint,
  'rejected amount mismatch creates no event'
);

set local role service_role;
select lives_ok(
  $$select public.record_provider_payment_verification(
    (select retry_payment_id from payment_verification_test_state),
    'demo_pay', 'evt_provider_failed', 'card_payment_1005',
    'failed', 100, 'INR', repeat('b', 64)
  )$$,
  'provider intake records a failed attempt'
);
reset role;
select is(
  (select sale.payment_status || ':' || sale.paid_total::text || ':' || sale.due_total::text
   from public.sales sale
   where sale.id = (select retry_sale_id from payment_verification_test_state)),
  'unpaid:0.00:100.00'::text,
  'provider failure leaves the sale unpaid'
);

set local role service_role;
select lives_ok(
  $$select public.record_provider_payment_verification(
    (select retry_payment_id from payment_verification_test_state),
    'demo_pay', 'evt_provider_recovered', 'card_payment_1005',
    'settled', 100, 'INR', repeat('c', 64)
  )$$,
  'a later verified settlement can recover a failed attempt'
);
reset role;
select is(
  (select sale.payment_status || ':' || sale.paid_total::text || ':' || sale.due_total::text
   from public.sales sale
   where sale.id = (select retry_sale_id from payment_verification_test_state)),
  'paid:100.00:0.00'::text,
  'recovered provider settlement pays the sale exactly once'
);
select is(
  (select count(*) from public.payment_verification_events event
   where event.payment_id = (select retry_payment_id from payment_verification_test_state)),
  2::bigint,
  'failed and recovered provider events remain in the immutable history'
);

select is(
  has_function_privilege(
    'anon', 'public.reconcile_payment(uuid,uuid,text,text,text)', 'execute'
  ), false,
  'anonymous callers cannot reconcile payments'
);
select ok(
  has_function_privilege(
    'authenticated', 'public.reconcile_payment(uuid,uuid,text,text,text)', 'execute'
  ),
  'authenticated users can call the permission-checked reconciliation RPC'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.record_provider_payment_verification(uuid,text,text,text,text,numeric,text,text)',
    'execute'
  ) and has_function_privilege(
    'service_role',
    'public.record_provider_payment_verification(uuid,text,text,text,text,numeric,text,text)',
    'execute'
  ),
  'provider intake is service-role only'
);
select ok(
  (select relrowsecurity from pg_class
   where oid = 'public.payment_verification_events'::regclass),
  'RLS is enabled on payment verification events'
);
select ok(
  has_table_privilege(
    'authenticated', 'public.payment_verification_events', 'select'
  )
  and not has_table_privilege(
    'authenticated', 'public.payment_verification_events', 'insert'
  )
  and not has_table_privilege(
    'authenticated', 'public.payment_verification_events', 'update'
  )
  and not has_table_privilege(
    'anon', 'public.payment_verification_events', 'select'
  ),
  'clients have read-only, RLS-scoped event access'
);
select is(
  (select count(*) from pg_indexes
   where schemaname = 'public'
     and indexname in (
       'payment_verification_provider_event_uidx',
       'payment_verification_operation_uidx',
       'payment_verification_payment_business_idx',
       'payment_verification_business_created_idx',
       'payment_verification_actor_idx'
     )),
  5::bigint,
  'verification uniqueness, foreign-key, and lookup indexes exist'
);
select throws_ok(
  $$update public.payment_verification_events
    set evidence_note = 'tampered'
    where source = 'manual'$$,
  'P0001',
  'payment_verification_events is immutable; create a reversing transaction instead',
  'verification history cannot be edited'
);
select is(
  (select count(*) from public.payment_verification_events),
  5::bigint,
  'all expected manual and provider events exist exactly once'
);

select * from finish();
rollback;
