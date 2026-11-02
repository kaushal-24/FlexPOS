begin;

create extension if not exists pgtap with schema extensions;
select plan(17);

set local role authenticated;
select set_config('request.jwt.claim.sub', '01331716-1fbd-4780-bc16-b4dba20a96aa', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select ok(
  (select relrowsecurity from pg_class where relname = 'invoice_documents'),
  'invoice documents have RLS enabled'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.record_invoice_document(uuid,uuid,text,jsonb)',
    'execute'
  ),
  'anonymous users cannot create invoice snapshots'
);
select lives_ok(
  $$select public.record_invoice_document(
    'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8',
    (select id from public.sales where business_id = 'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8' order by created_at desc limit 1),
    'classic', '{"source":"PGTAP"}'::jsonb
  )$$,
  'completed sales can create immutable invoice snapshots'
);
select is(
  (select count(*)::integer from public.invoice_documents where invoice_number like 'PGTAP%'),
  0,
  'invoice test does not assume a production invoice number'
);
select ok(
  exists (select 1 from public.invoice_documents where sale_id = (select id from public.sales where business_id = 'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8' order by created_at desc limit 1)),
  'invoice snapshot is persisted for the selected sale'
);
select ok(
  ((select snapshot from public.invoice_documents where sale_id = (select id from public.sales where business_id = 'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8' order by created_at desc limit 1)) ? 'items'),
  'invoice snapshot contains line-item history'
);
select lives_ok(
  $$select public.record_invoice_document(
    'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8',
    (select id from public.sales where business_id = 'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8' order by created_at desc limit 1),
    'detailed', '{}'::jsonb
  )$$,
  'invoice snapshot creation is idempotent'
);
select throws_ok(
  $$select public.record_invoice_document(
    'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8',
    (select id from public.sales where business_id = 'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8' order by created_at desc limit 1),
    'invalid', '{}'::jsonb
  )$$,
  'P0001', 'Invalid invoice template'
);
select ok(
  exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'gift_cards' and policyname = 'gift_cards_select'),
  'gift cards have an explicit authenticated read policy'
);
select ok(
  exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'gift_card_transactions' and policyname = 'gift_card_transactions_select'),
  'gift-card transactions have an explicit authenticated read policy'
);
select is(
  (select count(*)::integer from pg_policies where schemaname = 'public' and tablename = 'customer_groups' and cmd = 'SELECT'),
  1,
  'customer groups have one read policy'
);
select is(
  (select count(*)::integer from pg_policies where schemaname = 'public' and tablename = 'promotions' and cmd = 'SELECT'),
  1,
  'promotions have one read policy'
);
select ok(
  exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'invoice_documents'),
  'invoice documents are available to authorized realtime subscribers'
);
select ok(
  exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'sales'),
  'sales are available to authorized realtime subscribers'
);
select ok(
  has_function_privilege('authenticated', 'public.list_sales_keyset(uuid,timestamptz,uuid,integer)', 'execute'),
  'authenticated users can call the bounded sales keyset RPC'
);
select lives_ok(
  $$select * from public.list_sales_keyset('c2c28e90-c16f-4c34-91f6-d8cc19a36ff8', null, null, 5)$$,
  'sales keyset RPC returns a bounded page'
);
select ok(
  has_function_privilege('authenticated', 'public.list_products_keyset(uuid,timestamptz,uuid,integer)', 'execute'),
  'authenticated users can call the bounded products keyset RPC'
);

select * from finish();
rollback;
