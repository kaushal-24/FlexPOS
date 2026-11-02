begin;

create extension if not exists pgtap with schema extensions;
select plan(12);

set local role authenticated;
select set_config('request.jwt.claim.sub', '01331716-1fbd-4780-bc16-b4dba20a96aa', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select ok(
  (select is_available from public.feature_modules where code = 'enterprise_operations'),
  'enterprise operations module is available'
);
select ok(
  (select relrowsecurity from pg_class where relname = 'enterprise_records'),
  'enterprise records have RLS enabled'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.create_enterprise_record(uuid,uuid,text,text,text,text,numeric,timestamptz,timestamptz,jsonb)',
    'execute'
  ),
  'anonymous users cannot execute enterprise record RPC'
);
select lives_ok(
  $$select public.create_enterprise_record(
    'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8', null, 'approval_workflow',
    'PGTAP-ENTERPRISE-001', 'Approval test', 'pending', 0, null, null,
    '{"approver":"owner"}'::jsonb
  )$$,
  'administrator can create an enterprise record'
);
select is(
  (select count(*)::integer from public.enterprise_records where reference_code = 'PGTAP-ENTERPRISE-001'),
  1,
  'enterprise record is visible to its tenant'
);
select lives_ok(
  $$select public.transition_enterprise_record(
    'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8',
    (select id from public.enterprise_records where reference_code = 'PGTAP-ENTERPRISE-001'),
    'approved', 'Approved by owner', '{}'::jsonb
  )$$,
  'enterprise record transitions are audited'
);
select is(
  (select count(*)::integer from public.enterprise_record_events where record_id = (select id from public.enterprise_records where reference_code = 'PGTAP-ENTERPRISE-001')),
  2,
  'creation and transition both create events'
);
select lives_ok(
  $$select public.upsert_integration_connection(
    'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8', 'sms', 'PGTAP SMS',
    'configured', 'vault://pgtap/sms', '{"sender_id":"FLEXPOS"}'::jsonb, null
  )$$,
  'administrator can save an integration status without raw credentials'
);
select is(
  (select count(*)::integer from public.integration_connections where display_name = 'PGTAP SMS'),
  1,
  'integration status is tenant scoped'
);
select is(
  (select secret_ref from public.integration_connections where display_name = 'PGTAP SMS'),
  'vault://pgtap/sms',
  'only the opaque secret reference is persisted'
);
select throws_ok(
  $$select public.upsert_integration_connection(
    'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8', 'sms', 'PGTAP raw',
    'configured', 'raw-api-key', '{}'::jsonb, null
  )$$,
  '23514'
);
select is(
  (select status from public.enterprise_records where reference_code = 'PGTAP-ENTERPRISE-001'),
  'approved',
  'record status reflects the audited transition'
);

select * from finish();
rollback;
