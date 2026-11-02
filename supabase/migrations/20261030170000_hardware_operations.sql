begin;

insert into public.feature_modules (
  code, name, description, category, sort_order, is_core, is_available,
  default_business_types
) values (
  'hardware_operations',
  'Hardware operations',
  'Online device registration, scanner, printer, scale, display, and cash-drawer connectivity.',
  'operations',
  150,
  false,
  true,
  array['retail','grocery','restaurant','wholesale','fashion','electronics','hardware','auto_parts','salon','service','pharmacy','warehouse','manufacturing','other']
)
on conflict (code) do update
set name = excluded.name,
    description = excluded.description,
    category = excluded.category,
    sort_order = excluded.sort_order,
    is_available = excluded.is_available,
    default_business_types = excluded.default_business_types,
    updated_at = now();

insert into public.permissions (code, category, description) values
  ('hardware.view', 'operations', 'View registered hardware and online connectivity status.'),
  ('hardware.manage', 'operations', 'Register hardware and record online connectivity tests.')
on conflict (code) do update
set category = excluded.category,
    description = excluded.description;

insert into private.feature_module_permissions (permission_code, module_code) values
  ('hardware.view', 'hardware_operations'),
  ('hardware.manage', 'hardware_operations')
on conflict (permission_code) do update set module_code = excluded.module_code;

insert into public.role_permissions (role_id, permission_code)
select role.id, permission.code
from public.roles role
cross join public.permissions permission
where role.name in ('Owner', 'Administrator', 'Branch Manager')
  and permission.code in ('hardware.view', 'hardware.manage')
on conflict do nothing;

select private.seed_feature_entitlements(id, business_type)
from public.businesses;

create table public.hardware_devices (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  device_kind text not null check (device_kind in (
    'barcode_camera', 'barcode_bluetooth', 'barcode_usb',
    'thermal_bluetooth', 'thermal_usb', 'thermal_network',
    'cash_drawer', 'label_printer', 'weighing_scale', 'customer_display'
  )),
  connection_type text not null check (connection_type in (
    'camera', 'hid', 'bluetooth', 'usb', 'tcp', 'system_print', 'serial'
  )),
  display_name text not null check (char_length(trim(display_name)) between 2 and 120),
  endpoint text check (endpoint is null or char_length(trim(endpoint)) between 2 and 240),
  status text not null default 'not_configured' check (status in (
    'not_configured', 'testing', 'online', 'offline', 'error', 'disabled'
  )),
  capabilities jsonb not null default '{}'::jsonb check (jsonb_typeof(capabilities) = 'object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  last_seen_at timestamptz,
  last_tested_at timestamptz,
  last_error text,
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, display_name)
);

create index hardware_devices_business_kind_idx
  on public.hardware_devices (business_id, device_kind, updated_at desc);
create index hardware_devices_branch_idx
  on public.hardware_devices (branch_id);
create index hardware_devices_status_idx
  on public.hardware_devices (business_id, status, updated_at desc);
create index hardware_devices_created_by_idx
  on public.hardware_devices (created_by);
create index hardware_devices_updated_by_idx
  on public.hardware_devices (updated_by);

create table public.hardware_device_events (
  id bigint generated always as identity primary key,
  business_id uuid not null references public.businesses(id) on delete cascade,
  device_id uuid not null references public.hardware_devices(id) on delete cascade,
  event_type text not null check (event_type in ('registered', 'connectivity_test', 'status_changed')),
  status text not null,
  error_message text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  actor_user_id uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create index hardware_device_events_device_idx
  on public.hardware_device_events (device_id, created_at desc);
create index hardware_device_events_business_idx
  on public.hardware_device_events (business_id, created_at desc);
create index hardware_device_events_actor_idx
  on public.hardware_device_events (actor_user_id);

create trigger hardware_devices_set_updated_at
before update on public.hardware_devices
for each row execute function private.set_updated_at();

create or replace function private.hardware_device_authorized(
  target_business_id uuid,
  target_branch_id uuid,
  required_permission text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.feature_enabled(target_business_id, 'hardware_operations')
    and private.has_permission(target_business_id, required_permission)
    and (
      target_branch_id is null
      or exists (
        select 1
        from public.branches branch
        where branch.id = target_branch_id
          and branch.business_id = target_business_id
          and private.has_branch_access(branch.id)
      )
    );
$$;

create or replace function public.register_hardware_device(
  target_business_id uuid,
  target_branch_id uuid,
  target_device_kind text,
  target_connection_type text,
  target_display_name text,
  target_endpoint text,
  target_capabilities jsonb,
  target_metadata jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  device_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not private.hardware_device_authorized(target_business_id, target_branch_id, 'hardware.manage') then
    raise exception 'Hardware management permission and module entitlement required';
  end if;
  if target_capabilities is null or jsonb_typeof(target_capabilities) <> 'object' then
    raise exception 'Capabilities must be a JSON object';
  end if;
  if target_metadata is null or jsonb_typeof(target_metadata) <> 'object' then
    raise exception 'Metadata must be a JSON object';
  end if;

  insert into public.hardware_devices (
    business_id, branch_id, device_kind, connection_type, display_name,
    endpoint, capabilities, metadata, status, created_by, updated_by
  ) values (
    target_business_id, target_branch_id, trim(target_device_kind),
    trim(target_connection_type), trim(target_display_name),
    nullif(trim(target_endpoint), ''), target_capabilities, target_metadata,
    'not_configured', auth.uid(), auth.uid()
  )
  on conflict (business_id, display_name) do update
  set branch_id = excluded.branch_id,
      device_kind = excluded.device_kind,
      connection_type = excluded.connection_type,
      endpoint = excluded.endpoint,
      capabilities = excluded.capabilities,
      metadata = excluded.metadata,
      status = 'not_configured',
      last_error = null,
      updated_by = auth.uid(),
      updated_at = now()
  returning id into device_id;

  insert into public.hardware_device_events (
    business_id, device_id, event_type, status, metadata, actor_user_id
  ) values (
    target_business_id, device_id, 'registered', 'not_configured',
    jsonb_build_object('connection_type', target_connection_type), auth.uid()
  );

  perform private.write_tenant_audit(
    target_business_id,
    'hardware_device.registered',
    'hardware_device',
    device_id::text,
    jsonb_build_object('device_kind', target_device_kind, 'connection_type', target_connection_type)
  );
  return device_id;
end;
$$;

create or replace function public.record_hardware_device_test(
  target_business_id uuid,
  target_device_id uuid,
  target_status text,
  target_error text,
  target_metadata jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  device_row public.hardware_devices%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  select * into device_row
  from public.hardware_devices
  where id = target_device_id and business_id = target_business_id;
  if not found then
    raise exception 'Hardware device not found';
  end if;
  if not private.hardware_device_authorized(target_business_id, device_row.branch_id, 'hardware.manage') then
    raise exception 'Hardware management permission and module entitlement required';
  end if;
  if target_status not in ('testing', 'online', 'offline', 'error', 'disabled') then
    raise exception 'Invalid hardware status';
  end if;
  if target_metadata is null or jsonb_typeof(target_metadata) <> 'object' then
    raise exception 'Metadata must be a JSON object';
  end if;

  update public.hardware_devices
  set status = target_status,
      last_tested_at = now(),
      last_seen_at = case when target_status = 'online' then now() else last_seen_at end,
      last_error = nullif(trim(target_error), ''),
      updated_by = auth.uid(),
      updated_at = now()
  where id = device_row.id;

  insert into public.hardware_device_events (
    business_id, device_id, event_type, status, error_message, metadata, actor_user_id
  ) values (
    target_business_id, device_row.id, 'connectivity_test', target_status,
    nullif(trim(target_error), ''), target_metadata, auth.uid()
  );

  perform private.write_tenant_audit(
    target_business_id,
    'hardware_device.connectivity_tested',
    'hardware_device',
    device_row.id::text,
    jsonb_build_object('status', target_status, 'error', nullif(trim(target_error), ''))
  );
end;
$$;

alter table public.hardware_devices enable row level security;
alter table public.hardware_device_events enable row level security;

create policy hardware_devices_select
on public.hardware_devices for select
to authenticated
using ((select private.hardware_device_authorized(business_id, branch_id, 'hardware.view')));

create policy hardware_devices_manage
on public.hardware_devices for all
to authenticated
using ((select private.hardware_device_authorized(business_id, branch_id, 'hardware.manage')))
with check ((select private.hardware_device_authorized(business_id, branch_id, 'hardware.manage')));

create policy hardware_device_events_select
on public.hardware_device_events for select
to authenticated
using (
  exists (
    select 1
    from public.hardware_devices device
    where device.id = device_id
      and private.hardware_device_authorized(device.business_id, device.branch_id, 'hardware.view')
  )
);

revoke all on table public.hardware_devices, public.hardware_device_events
  from anon, authenticated;
grant select on table public.hardware_devices, public.hardware_device_events
  to authenticated;

revoke all on function private.hardware_device_authorized(uuid, uuid, text)
  from public, anon, authenticated;
revoke all on function public.register_hardware_device(uuid, uuid, text, text, text, text, jsonb, jsonb)
  from public, anon;
revoke all on function public.record_hardware_device_test(uuid, uuid, text, text, jsonb)
  from public, anon;
grant execute on function public.register_hardware_device(uuid, uuid, text, text, text, text, jsonb, jsonb)
  to authenticated;
grant execute on function public.record_hardware_device_test(uuid, uuid, text, text, jsonb)
  to authenticated;
grant execute on function private.hardware_device_authorized(uuid, uuid, text)
  to authenticated;

commit;
