begin;

create extension if not exists pgtap with schema extensions;
select plan(8);

set local role authenticated;
select set_config('request.jwt.claim.sub', '01331716-1fbd-4780-bc16-b4dba20a96aa', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select ok(
  (select is_available from public.feature_modules where code = 'restaurant_operations'),
  'restaurant module is available'
);
select ok(
  (select relrowsecurity from pg_class where relname = 'industry_workflows'),
  'industry workflows have RLS enabled'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.create_industry_workflow(uuid,uuid,text,text,text,text,uuid,uuid,uuid,timestamptz,timestamptz,numeric,numeric,numeric,numeric,jsonb)',
    'execute'
  ),
  'anonymous users cannot execute industry workflow RPC'
);

select lives_ok(
  $$select public.set_business_feature_entitlement(
    'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8', 'restaurant_operations', true
  )$$,
  'administrator can enable an industry module'
);
select lives_ok(
  $$select public.create_industry_workflow(
    'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8', null, 'restaurant_table',
    'PGTAP-INDUSTRY-001', 'Four seat table', 'open', null, null, null,
    null, null, 0, 0, 0, 0, '{"capacity":4}'::jsonb
  )$$,
  'administrator can create a typed industry workflow'
);
select is(
  (select count(*)::integer from public.industry_workflows where reference_code = 'PGTAP-INDUSTRY-001'),
  1,
  'workflow is visible to the creating tenant'
);
select lives_ok(
  $$select public.transition_industry_workflow(
    'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8',
    (select id from public.industry_workflows where reference_code = 'PGTAP-INDUSTRY-001'),
    'ready', 'Prepared for service', '{}'::jsonb
  )$$,
  'workflow transitions are atomic'
);
select is(
  (select count(*)::integer from public.industry_workflow_events where workflow_id = (select id from public.industry_workflows where reference_code = 'PGTAP-INDUSTRY-001')),
  2,
  'creation and transition are both audited'
);

select * from finish();
rollback;
