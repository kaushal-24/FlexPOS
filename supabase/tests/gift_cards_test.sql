-- Hashed gift-card issuance and atomic redemption verification. Fixtures roll back.
begin;

create extension if not exists pgtap with schema extensions;
select plan(41);

create temporary table gift_card_test_state (
  business_id uuid,
  branch_id uuid,
  warehouse_id uuid,
  unit_id uuid,
  variant_id uuid,
  gift_card_id uuid,
  gift_card_number text,
  redemption_sale_id uuid
);
grant all on gift_card_test_state to authenticated;

create temporary table gift_card_issue_result (result jsonb);
grant all on gift_card_issue_result to authenticated;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000',
   '51000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'gift-card-owner@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000',
   '51000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'gift-card-outsider@example.test', '', now(), '{}', '{}', now(), now());

set local role authenticated;
select set_config('request.jwt.claim.sub', '51000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'gift-card-owner@example.test', true);

select lives_ok(
  $$select public.create_business_with_branch(
    'Gift Card Test Business', 'retail', 'INR', 'Asia/Kolkata',
    'Main Branch', 'MAIN', 'IN'
  )$$,
  'owner creates a gift-card test tenant'
);

insert into gift_card_test_state (business_id, branch_id, warehouse_id, unit_id)
select b.id, br.id, w.id, u.id
from public.businesses b
join public.branches br on br.business_id = b.id
join public.warehouses w
  on w.business_id = b.id and w.branch_id = br.id and w.is_default
join public.units u on u.business_id = b.id and u.name = 'Piece'
where b.name = 'Gift Card Test Business';

update gift_card_test_state set variant_id = (
  select (public.create_product_with_default_variant(
    business_id, 'Gift Card Product', 'goods', null, null, unit_id, null,
    '6209', true, false, 'Default', 'GIFT-CARD-PRODUCT', null,
    20, 60, 0
  ) ->> 'variant_id')::uuid
  from gift_card_test_state
);
select is(
  (select count(*) from public.products p
   where p.business_id = (select business_id from gift_card_test_state)),
  1::bigint,
  'sale product is created'
);

select lives_ok(
  $$select public.adjust_inventory(
    (select business_id from gift_card_test_state),
    (select warehouse_id from gift_card_test_state),
    (select variant_id from gift_card_test_state),
    10, 'gift-card opening stock',
    '51100000-0000-0000-0000-000000000001', 20
  )$$,
  'opening stock is created'
);

insert into gift_card_issue_result
select public.issue_gift_card(
  business_id, branch_id, null,
  '51100000-0000-0000-0000-000000000002',
  150, now() + interval '1 year'
)
from gift_card_test_state;
update gift_card_test_state set
  gift_card_id = (select (result ->> 'gift_card_id')::uuid from gift_card_issue_result),
  gift_card_number = (select result ->> 'gift_card_number' from gift_card_issue_result);

select ok((select gift_card_id is not null from gift_card_test_state), 'gift-card issuance returns its identifier');
select matches(
  (select gift_card_number from gift_card_test_state),
  '^GC-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}$',
  'gift-card issuance returns a human-readable bearer number'
);

reset role;
select is(
  (select count(*) from public.gift_cards gc
   where gc.id = (select gift_card_id from gift_card_test_state)),
  1::bigint,
  'gift card is persisted'
);
select ok(
  (select code_hash ~ '^[0-9a-f]{64}$' from public.gift_cards
   where id = (select gift_card_id from gift_card_test_state)),
  'only a SHA-256 gift-card hash is persisted'
);
select is(
  (select current_balance from public.gift_cards
   where id = (select gift_card_id from gift_card_test_state)),
  150.00::numeric,
  'initial balance is exact'
);
select is(
  (select transaction_type || ':' || amount::text || ':' || balance_after::text
   from public.gift_card_transactions
   where gift_card_id = (select gift_card_id from gift_card_test_state)),
  'issue:150.00:150.00'::text,
  'issuance creates an exact immutable value-ledger entry'
);
select is(
  (select count(*) from public.tenant_audit_logs
   where action = 'gift_card.issued'
     and target_id = (select gift_card_id::text from gift_card_test_state)),
  1::bigint,
  'issuance is audited'
);
select ok(
  (select position(gift_card_number in coalesce(log.details::text, '')) = 0
   from gift_card_test_state
   cross join lateral (
     select details from public.tenant_audit_logs
     where action = 'gift_card.issued'
       and target_id = (select gift_card_id::text from gift_card_test_state)
     limit 1
   ) log),
  'the bearer number is not written to the audit log'
);

set local role authenticated;
select lives_ok(
  $$select public.issue_gift_card(
    (select business_id from gift_card_test_state),
    (select branch_id from gift_card_test_state), null,
    '51100000-0000-0000-0000-000000000002',
    150, now() + interval '1 year'
  )$$,
  'gift-card issuance is idempotent'
);

reset role;
select is(
  (select count(*) from public.gift_cards
   where business_id = (select business_id from gift_card_test_state)),
  1::bigint,
  'issuance replay creates no duplicate card'
);
select is(
  (select count(*) from public.gift_card_transactions
   where gift_card_id = (select gift_card_id from gift_card_test_state)),
  1::bigint,
  'issuance replay creates no duplicate ledger entry'
);

set local role authenticated;
select is(
  (public.lookup_gift_card(
    (select business_id from gift_card_test_state),
    (select gift_card_number from gift_card_test_state)
  ) ->> 'status'),
  'active'::text,
  'lookup reports the active status'
);
select is(
  (public.lookup_gift_card(
    (select business_id from gift_card_test_state),
    lower(replace((select gift_card_number from gift_card_test_state), '-', ' '))
  ) ->> 'balance')::numeric,
  150.00::numeric,
  'lookup normalizes case and separators without exposing the stored hash'
);
select throws_ok(
  $$select * from public.gift_cards$$,
  '42501', 'permission denied for table gift_cards',
  'clients cannot read the bearer-code table directly'
);

update gift_card_test_state set redemption_sale_id = (
  select (public.complete_sale_with_gift_card(
    business_id, branch_id, null, null, null,
    '51100000-0000-0000-0000-000000000003',
    jsonb_build_array(jsonb_build_object(
      'variant_id', variant_id,
      'warehouse_id', warehouse_id,
      'quantity', 1,
      'unit_price', 60,
      'discount_amount', 0,
      'tax_rate', 0
    )),
    gift_card_number, 60, 0, 'Gift-card redemption sale'
  ) ->> 'sale_id')::uuid
  from gift_card_test_state
);
select ok((select redemption_sale_id is not null from gift_card_test_state), 'gift card pays a sale atomically');

reset role;
select is(
  (select payment_method || ':' || status
   from public.payments
   where sale_id = (select redemption_sale_id from gift_card_test_state)),
  'gift_card:settled'::text,
  'gift-card payment is settled immediately'
);
select is(
  (select payment_status from public.sales
   where id = (select redemption_sale_id from gift_card_test_state)),
  'paid'::text,
  'gift-card sale is fully paid'
);
select is(
  (select paid_total::text || ':' || due_total::text from public.sales
   where id = (select redemption_sale_id from gift_card_test_state)),
  '60.00:0.00'::text,
  'paid and due totals are exact'
);
select is(
  (select current_balance from public.gift_cards
   where id = (select gift_card_id from gift_card_test_state)),
  90.00::numeric,
  'redemption decrements the balance exactly'
);
select is(
  (select amount::text || ':' || balance_after::text
   from public.gift_card_transactions
   where gift_card_id = (select gift_card_id from gift_card_test_state)
     and transaction_type = 'redeem'),
  '-60.00:90.00'::text,
  'redemption is captured in the immutable value ledger'
);
select is(
  (select ib.quantity_on_hand
   from public.inventory_balances ib
   join gift_card_test_state t
     on t.warehouse_id = ib.warehouse_id and t.variant_id = ib.variant_id),
  9.000000::numeric,
  'paid sale deducts inventory once'
);
select is(
  (select count(*) from public.tenant_audit_logs
   where action = 'gift_card.redeemed'
     and target_id = (select gift_card_id::text from gift_card_test_state)),
  1::bigint,
  'redemption is audited'
);

set local role authenticated;
select lives_ok(
  $$select public.complete_sale_with_gift_card(
    (select business_id from gift_card_test_state),
    (select branch_id from gift_card_test_state), null, null, null,
    '51100000-0000-0000-0000-000000000003',
    jsonb_build_array(jsonb_build_object(
      'variant_id', (select variant_id from gift_card_test_state),
      'warehouse_id', (select warehouse_id from gift_card_test_state),
      'quantity', 1, 'unit_price', 60, 'tax_rate', 0
    )),
    (select gift_card_number from gift_card_test_state), 60, 0, null
  )$$,
  'gift-card redemption is idempotent'
);

reset role;
select is(
  (select count(*) from public.sales
   where business_id = (select business_id from gift_card_test_state)),
  1::bigint,
  'redemption replay creates no duplicate sale'
);
select is(
  (select count(*) from public.gift_card_transactions
   where gift_card_id = (select gift_card_id from gift_card_test_state)
     and transaction_type = 'redeem'),
  1::bigint,
  'redemption replay creates no duplicate ledger entry'
);

set local role authenticated;
select throws_ok(
  $$select public.complete_sale_with_gift_card(
    (select business_id from gift_card_test_state),
    (select branch_id from gift_card_test_state), null, null, null,
    '51100000-0000-0000-0000-000000000004',
    jsonb_build_array(jsonb_build_object(
      'variant_id', (select variant_id from gift_card_test_state),
      'warehouse_id', (select warehouse_id from gift_card_test_state),
      'quantity', 1, 'unit_price', 100, 'tax_rate', 0
    )),
    (select gift_card_number from gift_card_test_state), 100, 0, null
  )$$,
  'P0001', 'Gift-card balance is insufficient',
  'an over-redemption is rejected atomically'
);

reset role;
select is(
  (select current_balance from public.gift_cards
   where id = (select gift_card_id from gift_card_test_state)),
  90.00::numeric,
  'failed redemption leaves the balance unchanged'
);
select is(
  (select ib.quantity_on_hand
   from public.inventory_balances ib
   join gift_card_test_state t
     on t.warehouse_id = ib.warehouse_id and t.variant_id = ib.variant_id),
  9.000000::numeric,
  'failed redemption leaves stock unchanged'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '51000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'gift-card-outsider@example.test', true);

select throws_ok(
  $$select public.issue_gift_card(
    (select business_id from gift_card_test_state),
    (select branch_id from gift_card_test_state), null,
    gen_random_uuid(), 50, null
  )$$,
  'P0001', 'Gift-card management permission required',
  'outsider cannot issue a gift card in another tenant'
);
select throws_ok(
  $$select public.lookup_gift_card(
    (select business_id from gift_card_test_state),
    (select gift_card_number from gift_card_test_state)
  )$$,
  'P0001', 'You do not have permission to create sales',
  'outsider cannot inspect another tenant gift card'
);
select throws_ok(
  $$select public.complete_sale_with_gift_card(
    (select business_id from gift_card_test_state),
    (select branch_id from gift_card_test_state), null, null, null,
    gen_random_uuid(), '[]'::jsonb,
    (select gift_card_number from gift_card_test_state), 1, 0, null
  )$$,
  'P0001', 'You do not have permission to create sales',
  'outsider cannot redeem another tenant gift card'
);

reset role;
select is(
  has_function_privilege(
    'anon', 'public.issue_gift_card(uuid,uuid,uuid,uuid,numeric,timestamptz)', 'execute'
  ), false, 'anonymous role cannot issue gift cards'
);
select is(
  has_function_privilege('anon', 'public.lookup_gift_card(uuid,text)', 'execute'),
  false, 'anonymous role cannot inspect gift cards'
);
select is(
  has_function_privilege(
    'anon',
    'public.complete_sale_with_gift_card(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text,numeric,numeric,text)',
    'execute'
  ), false, 'anonymous role cannot redeem gift cards'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.issue_gift_card(uuid,uuid,uuid,uuid,numeric,timestamptz)', 'execute'
  ) and has_function_privilege(
    'authenticated', 'public.lookup_gift_card(uuid,text)', 'execute'
  ) and has_function_privilege(
    'authenticated',
    'public.complete_sale_with_gift_card(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text,numeric,numeric,text)',
    'execute'
  ),
  'authenticated role can execute the permission-checked gift-card API'
);
select is(
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname in ('gift_cards', 'gift_card_transactions')
     and c.relrowsecurity),
  2::bigint,
  'RLS is enabled on both gift-card tables'
);
select ok(
  not has_table_privilege('anon', 'public.gift_cards', 'select')
    and not has_table_privilege('authenticated', 'public.gift_cards', 'select')
    and not has_table_privilege('authenticated', 'public.gift_cards', 'insert')
    and not has_table_privilege('authenticated', 'public.gift_cards', 'update')
    and not has_table_privilege('authenticated', 'public.gift_card_transactions', 'select'),
  'bearer-card storage and ledger have no direct client privileges'
);
select is(
  (select count(*)
   from pg_indexes
   where schemaname = 'public'
     and indexname in (
       'gift_cards_branch_business_idx',
       'gift_cards_customer_business_idx',
       'gift_cards_issued_by_idx',
       'gift_cards_business_active_expiry_idx',
       'gift_card_transactions_card_business_idx',
       'gift_card_transactions_sale_business_idx',
       'gift_card_transactions_payment_business_idx',
       'gift_card_transactions_actor_idx'
     )),
  8::bigint,
  'all gift-card foreign-key and lookup indexes exist'
);

select * from finish();
rollback;
