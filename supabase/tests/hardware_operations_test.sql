begin;

create extension if not exists pgtap with schema extensions;
select plan(15);

set local role authenticated;
select set_config('request.jwt.claim.sub', '01331716-1fbd-4780-bc16-b4dba20a96aa', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select ok(
  (select is_available from public.feature_modules where code = 'hardware_operations'),
  'hardware operations module is available'
);
select ok(
  (select is_enabled from public.business_feature_entitlements
   where business_id = 'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8'
     and module_code = 'hardware_operations'),
  'hardware operations is enabled for the test business'
);
select ok(
  (select relrowsecurity from pg_class where relname = 'hardware_devices'),
  'hardware devices have RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where relname = 'hardware_device_events'),
  'hardware device events have RLS enabled'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.register_hardware_device(uuid,uuid,text,text,text,text,jsonb,jsonb)',
    'execute'
  ),
  'anonymous users cannot register hardware'
);
select lives_ok(
  $$select public.register_hardware_device(
    'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8', null, 'barcode_usb', 'hid',
    'PGTAP-HW-USB', null, '{"scanner":"hid"}'::jsonb,
    '{"mode":"online_only"}'::jsonb
  )$$,
  'administrator can register an online hardware adapter'
);
select is(
  (select count(*)::integer from public.hardware_devices where display_name = 'PGTAP-HW-USB'),
  1,
  'hardware registration is tenant scoped'
);
select is(
  (select status from public.hardware_devices where display_name = 'PGTAP-HW-USB'),
  'not_configured',
  'new hardware starts not configured'
);
select is(
  (select count(*)::integer from public.hardware_device_events event
   join public.hardware_devices device on device.id = event.device_id
   where device.display_name = 'PGTAP-HW-USB'),
  1,
  'registration writes an append-only event'
);
select lives_ok(
  $$select public.record_hardware_device_test(
    'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8',
    (select id from public.hardware_devices where display_name = 'PGTAP-HW-USB'),
    'online', null, '{"transport":"hid"}'::jsonb
  )$$,
  'administrator can record an authenticated connectivity result'
);
select is(
  (select status from public.hardware_devices where display_name = 'PGTAP-HW-USB'),
  'online',
  'online connectivity result updates device status'
);
select is(
  (select count(*)::integer from public.hardware_device_events event
   join public.hardware_devices device on device.id = event.device_id
   where device.display_name = 'PGTAP-HW-USB'),
  2,
  'connectivity result creates a second event'
);
select throws_ok(
  $$select public.record_hardware_device_test(
    'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8',
    (select id from public.hardware_devices where display_name = 'PGTAP-HW-USB'),
    'connected', null, '{}'::jsonb
  )$$,
  'Invalid hardware status'
);
select throws_ok(
  $$select public.register_hardware_device(
    'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8', null, 'barcode_usb', 'hid',
    'PGTAP-HW-RAW', null, '[]'::jsonb, '{}'::jsonb
  )$$,
  'Capabilities must be a JSON object'
);
select throws_ok(
  $$select public.register_hardware_device(
    'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8', null, 'barcode_usb', 'tcp',
    'PGTAP-HW-MISMATCH', null, '{}'::jsonb, '{}'::jsonb
  )$$,
  '23514'
);

select * from finish();
rollback;
