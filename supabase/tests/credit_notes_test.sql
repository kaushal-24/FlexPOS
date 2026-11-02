-- Transactional credit-note issuance and redemption verification.
begin;

create extension if not exists pgtap with schema extensions;
select plan(35);

create temporary table credit_note_test_state (
  business_id uuid,
  branch_id uuid,
  unit_id uuid,
  warehouse_id uuid,
  variant_id uuid,
  original_sale_id uuid,
  original_sale_item_id uuid,
  credit_note_number text,
  first_redemption_sale_id uuid,
  final_redemption_sale_id uuid
);
grant all on credit_note_test_state to authenticated;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000',
   '82000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'credit-note-owner@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '82000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'credit-note-outsider@example.test', '', now(), '{}', '{}', now(), now());

set local role authenticated;
select set_config(
  'request.jwt.claim.sub', '82000000-0000-0000-0000-000000000001', true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.email', 'credit-note-owner@example.test', true
);

select lives_ok(
  $$select public.create_business_with_branch(
    'Credit Note Test Business', 'retail', 'INR', 'Asia/Kolkata',
    'Main Branch', 'MAIN', 'IN'
  )$$,
  'owner creates a credit-note test tenant'
);

insert into credit_note_test_state (
  business_id, branch_id, unit_id, warehouse_id
)
select b.id, br.id, u.id, w.id
from public.businesses b
join public.branches br on br.business_id = b.id
join public.units u on u.business_id = b.id and u.name = 'Piece'
join public.warehouses w
  on w.business_id = b.id and w.branch_id = br.id and w.is_default
where b.name = 'Credit Note Test Business';

update credit_note_test_state set variant_id = (
  select (public.create_product_with_default_variant(
    business_id, 'Credit Note Product', 'goods', null, null, unit_id, null,
    '5001', true, false, 'Default', 'CREDIT-NOTE-PRODUCT', null,
    20, 100, 0
  ) ->> 'variant_id')::uuid
  from credit_note_test_state
);

select lives_ok(
  $$select public.adjust_inventory(
    (select business_id from credit_note_test_state),
    (select warehouse_id from credit_note_test_state),
    (select variant_id from credit_note_test_state),
    10, 'credit-note opening stock',
    '82100000-0000-0000-0000-000000000001', 20
  )$$,
  'opening stock is created'
);

update credit_note_test_state set original_sale_id = (
  select (public.complete_sale(
    business_id, branch_id, null, null, null,
    '82100000-0000-0000-0000-000000000002',
    jsonb_build_array(jsonb_build_object(
      'variant_id', variant_id,
      'warehouse_id', warehouse_id,
      'quantity', 2,
      'unit_price', 100,
      'discount_amount', 0,
      'tax_rate', 0
    )),
    jsonb_build_array(jsonb_build_object(
      'payment_method', 'cash', 'amount', 200
    )),
    0, 'Credit-note source sale'
  ) ->> 'sale_id')::uuid
  from credit_note_test_state
);
select pass('source cash sale completes');

update credit_note_test_state set original_sale_item_id = (
  select si.id
  from public.sale_items si
  where si.sale_id = credit_note_test_state.original_sale_id
);
select is(
  (select ib.quantity_on_hand
   from public.inventory_balances ib
   join credit_note_test_state t
     on t.warehouse_id = ib.warehouse_id
    and t.variant_id = ib.variant_id),
  8.000000::numeric,
  'source sale deducts inventory'
);

update credit_note_test_state set credit_note_number = (
  select public.process_sale_credit_note_return(
    original_sale_id,
    '82100000-0000-0000-0000-000000000003',
    jsonb_build_array(jsonb_build_object(
      'sale_item_id', original_sale_item_id,
      'quantity', 1,
      'restock', true
    )),
    'Customer chose store credit'
  ) ->> 'credit_note_number'
  from credit_note_test_state
);
select pass('credit-note return completes atomically');

select is(
  (select status from public.sales
   where id = (select original_sale_id from credit_note_test_state)),
  'partially_refunded',
  'source sale records the partial return'
);
select is(
  (select ib.quantity_on_hand
   from public.inventory_balances ib
   join credit_note_test_state t
     on t.warehouse_id = ib.warehouse_id
    and t.variant_id = ib.variant_id),
  9.000000::numeric,
  'credit-note return restores inventory'
);
select is(
  (select issued_amount from public.credit_notes),
  100.00::numeric,
  'credit note preserves the exact return value'
);
select is(
  (select count(*) from public.sale_refunds),
  0::bigint,
  'credit-note issuance does not move cash'
);
select is(
  (select count(*)
   from public.credit_notes cn
   join public.sale_returns sr
     on sr.id = cn.return_id and sr.business_id = cn.business_id),
  1::bigint,
  'credit note is linked to its immutable return document'
);
select matches(
  (select credit_note_number from credit_note_test_state),
  '^CN-[0-9]{14}-[A-F0-9]{8}$',
  'credit note receives a stable human-readable number'
);

select lives_ok(
  $$select public.process_sale_credit_note_return(
    (select original_sale_id from credit_note_test_state),
    '82100000-0000-0000-0000-000000000003',
    jsonb_build_array(jsonb_build_object(
      'sale_item_id',
        (select original_sale_item_id from credit_note_test_state),
      'quantity', 1,
      'restock', true
    )),
    'Customer chose store credit'
  )$$,
  'credit-note issuance is idempotent'
);
select is(
  (select count(*) from public.credit_notes),
  1::bigint,
  'issuance replay creates no duplicate credit note'
);
select is(
  (select count(*) from public.sale_returns),
  1::bigint,
  'issuance replay creates no duplicate return'
);
select throws_ok(
  $$delete from public.credit_notes$$,
  '42501',
  'permission denied for table credit_notes',
  'credit-note documents are immutable'
);

update credit_note_test_state set first_redemption_sale_id = (
  select (public.complete_sale_with_credit_note(
    business_id, branch_id, null, null, null,
    '82100000-0000-0000-0000-000000000004',
    jsonb_build_array(jsonb_build_object(
      'variant_id', variant_id,
      'warehouse_id', warehouse_id,
      'quantity', 1,
      'unit_price', 60,
      'discount_amount', 0,
      'tax_rate', 0
    )),
    credit_note_number, 60, 0, 'Partial credit-note redemption'
  ) ->> 'sale_id')::uuid
  from credit_note_test_state
);
select pass('credit note pays a sale atomically');

select is(
  (select payment_method || ':' || status
   from public.payments
   where sale_id = (
     select first_redemption_sale_id from credit_note_test_state
   )),
  'credit_note:settled',
  'credit-note payment is recorded as settled'
);
select is(
  (select payment_status from public.sales
   where id = (
     select first_redemption_sale_id from credit_note_test_state
   )),
  'paid',
  'credit-note sale is fully paid'
);
select is(
  (select amount from public.credit_note_redemptions),
  60.00::numeric,
  'partial redemption is exact'
);
select is(
  (select cn.issued_amount - coalesce(sum(cnr.amount), 0)
   from public.credit_notes cn
   left join public.credit_note_redemptions cnr
     on cnr.credit_note_id = cn.id
   group by cn.id, cn.issued_amount),
  40.00::numeric,
  'credit note retains the exact remaining balance'
);

select lives_ok(
  $$select public.complete_sale_with_credit_note(
    (select business_id from credit_note_test_state),
    (select branch_id from credit_note_test_state), null, null, null,
    '82100000-0000-0000-0000-000000000004',
    jsonb_build_array(jsonb_build_object(
      'variant_id', (select variant_id from credit_note_test_state),
      'warehouse_id', (select warehouse_id from credit_note_test_state),
      'quantity', 1,
      'unit_price', 60,
      'discount_amount', 0,
      'tax_rate', 0
    )),
    (select credit_note_number from credit_note_test_state),
    60, 0, 'Partial credit-note redemption'
  )$$,
  'credit-note redemption is idempotent'
);
select is(
  (select count(*) from public.credit_note_redemptions),
  1::bigint,
  'redemption replay creates no duplicate ledger entry'
);

select throws_ok(
  $$select public.complete_sale_with_credit_note(
    (select business_id from credit_note_test_state),
    (select branch_id from credit_note_test_state), null, null, null,
    '82100000-0000-0000-0000-000000000005',
    jsonb_build_array(jsonb_build_object(
      'variant_id', (select variant_id from credit_note_test_state),
      'warehouse_id', (select warehouse_id from credit_note_test_state),
      'quantity', 1,
      'unit_price', 50,
      'discount_amount', 0,
      'tax_rate', 0
    )),
    (select credit_note_number from credit_note_test_state),
    50, 0, 'Invalid over-redemption'
  )$$,
  'P0001',
  'Credit note balance is insufficient',
  'redemption cannot exceed the remaining balance'
);
select is(
  (select ib.quantity_on_hand
   from public.inventory_balances ib
   join credit_note_test_state t
     on t.warehouse_id = ib.warehouse_id
    and t.variant_id = ib.variant_id),
  8.000000::numeric,
  'failed over-redemption rolls back its inventory change'
);

update credit_note_test_state set final_redemption_sale_id = (
  select (public.complete_sale_with_credit_note(
    business_id, branch_id, null, null, null,
    '82100000-0000-0000-0000-000000000006',
    jsonb_build_array(jsonb_build_object(
      'variant_id', variant_id,
      'warehouse_id', warehouse_id,
      'quantity', 1,
      'unit_price', 40,
      'discount_amount', 0,
      'tax_rate', 0
    )),
    credit_note_number, 40, 0, 'Final credit-note redemption'
  ) ->> 'sale_id')::uuid
  from credit_note_test_state
);
select pass('remaining credit-note balance can be redeemed');
select is(
  (select sum(amount) from public.credit_note_redemptions),
  100.00::numeric,
  'redemptions cannot exceed the issued amount'
);
select is(
  (select cn.issued_amount - coalesce(sum(cnr.amount), 0)
   from public.credit_notes cn
   left join public.credit_note_redemptions cnr
     on cnr.credit_note_id = cn.id
   group by cn.id, cn.issued_amount),
  0.00::numeric,
  'fully redeemed credit note has zero balance'
);
select throws_ok(
  $$delete from public.credit_note_redemptions$$,
  '42501',
  'permission denied for table credit_note_redemptions',
  'credit-note redemptions are immutable'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claim.sub', '82000000-0000-0000-0000-000000000002', true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.email', 'credit-note-outsider@example.test', true
);
select is(
  (select count(*) from public.credit_notes)
    + (select count(*) from public.credit_note_redemptions),
  0::bigint,
  'outsider cannot read another tenant credit-note ledger'
);
select throws_ok(
  $$select public.complete_sale_with_credit_note(
    (select business_id from credit_note_test_state),
    (select branch_id from credit_note_test_state), null, null, null,
    '82100000-0000-0000-0000-000000000007',
    jsonb_build_array(jsonb_build_object(
      'variant_id', (select variant_id from credit_note_test_state),
      'warehouse_id', (select warehouse_id from credit_note_test_state),
      'quantity', 1,
      'unit_price', 1,
      'discount_amount', 0,
      'tax_rate', 0
    )),
    (select credit_note_number from credit_note_test_state),
    1, 0, 'Unauthorized redemption'
  )$$,
  'P0001',
  'You do not have permission to create sales',
  'outsider cannot redeem another tenant credit note'
);

reset role;
select is(
  has_function_privilege(
    'anon',
    'public.process_sale_credit_note_return(uuid,uuid,jsonb,text)',
    'execute'
  ),
  false,
  'anonymous role cannot issue credit notes'
);
select is(
  has_function_privilege(
    'anon',
    'public.complete_sale_with_credit_note(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text,numeric,numeric,text)',
    'execute'
  ),
  false,
  'anonymous role cannot redeem credit notes'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.process_sale_credit_note_return(uuid,uuid,jsonb,text)',
    'execute'
  ) and has_function_privilege(
    'authenticated',
    'public.complete_sale_with_credit_note(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text,numeric,numeric,text)',
    'execute'
  ),
  true,
  'authenticated application role can call both permission-checked RPCs'
);
select is(
  (select count(*)
   from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname in ('credit_notes', 'credit_note_redemptions')
     and c.relrowsecurity),
  2::bigint,
  'RLS is enabled on both credit-note tables'
);
select is(
  (select count(*) from pg_policies
   where schemaname = 'public'
     and tablename in ('credit_notes', 'credit_note_redemptions')),
  2::bigint,
  'both credit-note tables have tenant-scoped read policies'
);

select * from finish();
rollback;
