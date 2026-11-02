begin;

insert into public.feature_modules (
  code, name, description, category, sort_order, is_core, is_available,
  default_business_types
) values (
  'enterprise_operations',
  'Enterprise operations',
  'Loyalty, staffing, approvals, omnichannel requests, integrations, and enterprise controls.',
  'operations',
  140,
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
  ('enterprise.view', 'enterprise', 'View tenant-scoped enterprise operations and integration status.'),
  ('enterprise.manage', 'enterprise', 'Create, update, transition, and audit enterprise operations.'),
  ('integrations.view', 'enterprise', 'View integration provider status and health.'),
  ('integrations.manage', 'enterprise', 'Configure integration provider references and health status.'),
  ('saas.manage', 'enterprise', 'Manage tenant SaaS administration records.')
on conflict (code) do update
set category = excluded.category,
    description = excluded.description;

insert into private.feature_module_permissions (permission_code, module_code) values
  ('enterprise.view', 'enterprise_operations'),
  ('enterprise.manage', 'enterprise_operations'),
  ('integrations.view', 'enterprise_operations'),
  ('integrations.manage', 'enterprise_operations'),
  ('saas.manage', 'enterprise_operations')
on conflict (permission_code) do update set module_code = excluded.module_code;

insert into public.role_permissions (role_id, permission_code)
select role.id, permission.code
from public.roles role
cross join public.permissions permission
where role.name in ('Owner', 'Administrator')
  and permission.code in (
    'enterprise.view', 'enterprise.manage', 'integrations.view',
    'integrations.manage', 'saas.manage'
  )
on conflict do nothing;

insert into public.role_permissions (role_id, permission_code)
select role.id, permission.code
from public.roles role
cross join public.permissions permission
where role.name = 'Branch Manager'
  and permission.code in ('enterprise.view', 'enterprise.manage', 'integrations.view')
on conflict do nothing;

insert into public.role_permissions (role_id, permission_code)
select role.id, 'enterprise.view'
from public.roles role
where role.name = 'Accountant'
on conflict do nothing;

select private.seed_feature_entitlements(id, business_type)
from public.businesses;

create table public.enterprise_records (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  record_type text not null check (record_type in (
    'loyalty_tier', 'staff_schedule', 'attendance', 'staff_commission',
    'multi_register_snapshot', 'multi_branch_snapshot', 'approval_workflow',
    'notification_alert', 'customer_catalog', 'online_order_request',
    'subscription_plan', 'saas_admin', 'import_export_job', 'backup_recovery_run',
    'barcode_label_job', 'gujarati_translation', 'business_rule',
    'integration_setting', 'demand_forecast', 'reorder_suggestion',
    'sms_provider', 'whatsapp_provider', 'payment_gateway', 'tax_service',
    'ai_provider', 'integration_status'
  )),
  reference_code text not null check (char_length(trim(reference_code)) between 2 and 120),
  title text not null check (char_length(trim(title)) between 2 and 240),
  status text not null default 'draft' check (char_length(trim(status)) between 2 and 64),
  assigned_to uuid references auth.users(id) on delete set null,
  effective_at timestamptz,
  due_at timestamptz,
  amount numeric(14,2) not null default 0 check (amount >= 0),
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload) = 'object'),
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, reference_code)
);

create index enterprise_records_business_type_idx
  on public.enterprise_records (business_id, record_type, updated_at desc);
create index enterprise_records_branch_idx
  on public.enterprise_records (business_id, branch_id, updated_at desc);
create index enterprise_records_status_idx
  on public.enterprise_records (business_id, status, updated_at desc);

create table public.enterprise_record_events (
  id bigint generated always as identity primary key,
  business_id uuid not null references public.businesses(id) on delete cascade,
  record_id uuid not null references public.enterprise_records(id) on delete cascade,
  from_status text,
  to_status text not null,
  note text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  actor_user_id uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create index enterprise_record_events_record_idx
  on public.enterprise_record_events (record_id, created_at desc);

create table public.integration_connections (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  provider_code text not null check (provider_code in (
    'sms', 'whatsapp', 'payment_gateway', 'tax_service', 'ai'
  )),
  display_name text not null check (char_length(trim(display_name)) between 2 and 120),
  status text not null default 'not_configured' check (status in (
    'not_configured', 'configured', 'verifying', 'verified', 'disabled', 'error'
  )),
  secret_ref text check (secret_ref is null or char_length(trim(secret_ref)) between 2 and 240),
  config jsonb not null default '{}'::jsonb check (jsonb_typeof(config) = 'object'),
  last_checked_at timestamptz,
  last_error text,
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, provider_code, display_name)
);

create index integration_connections_business_provider_idx
  on public.integration_connections (business_id, provider_code, updated_at desc);

create trigger enterprise_records_set_updated_at
before update on public.enterprise_records
for each row execute function private.set_updated_at();

create trigger integration_connections_set_updated_at
before update on public.integration_connections
for each row execute function private.set_updated_at();

create or replace function private.enterprise_record_authorized(
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
  select private.feature_enabled(target_business_id, 'enterprise_operations')
    and private.has_permission(target_business_id, required_permission)
    and (
      target_branch_id is null
      or private.has_branch_access(target_branch_id)
    );
$$;

create or replace function public.create_enterprise_record(
  target_business_id uuid,
  target_branch_id uuid,
  target_record_type text,
  target_reference_code text,
  target_title text,
  target_status text,
  target_amount numeric,
  target_effective_at timestamptz,
  target_due_at timestamptz,
  target_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not private.enterprise_record_authorized(target_business_id, target_branch_id, 'enterprise.manage') then
    raise exception 'Enterprise management permission and module entitlement required';
  end if;
  if target_payload is null or jsonb_typeof(target_payload) <> 'object' then
    raise exception 'Payload must be a JSON object';
  end if;

  insert into public.enterprise_records (
    business_id, branch_id, record_type, reference_code, title, status,
    amount, effective_at, due_at, payload, created_by, updated_by
  ) values (
    target_business_id, target_branch_id, target_record_type,
    trim(target_reference_code), trim(target_title), trim(target_status),
    coalesce(target_amount, 0), target_effective_at, target_due_at,
    target_payload, auth.uid(), auth.uid()
  ) returning id into new_id;

  insert into public.enterprise_record_events (
    business_id, record_id, from_status, to_status, metadata, actor_user_id
  ) values (
    target_business_id, new_id, null, trim(target_status), '{}'::jsonb, auth.uid()
  );

  perform private.write_tenant_audit(
    target_business_id,
    'enterprise_record.created',
    'enterprise_record',
    new_id::text,
    jsonb_build_object('record_type', target_record_type, 'status', target_status)
  );
  return new_id;
end;
$$;

create or replace function public.transition_enterprise_record(
  target_business_id uuid,
  target_record_id uuid,
  target_status text,
  target_note text,
  target_metadata jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  record_row public.enterprise_records%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  select * into record_row
  from public.enterprise_records
  where id = target_record_id and business_id = target_business_id;
  if not found then
    raise exception 'Enterprise record not found';
  end if;
  if not private.enterprise_record_authorized(target_business_id, record_row.branch_id, 'enterprise.manage') then
    raise exception 'Enterprise management permission and module entitlement required';
  end if;
  if target_metadata is null or jsonb_typeof(target_metadata) <> 'object' then
    raise exception 'Metadata must be a JSON object';
  end if;
  if char_length(trim(target_status)) < 2 or char_length(trim(target_status)) > 64 then
    raise exception 'Invalid status';
  end if;

  update public.enterprise_records
  set status = trim(target_status), updated_by = auth.uid(), updated_at = now()
  where id = record_row.id;

  insert into public.enterprise_record_events (
    business_id, record_id, from_status, to_status, note, metadata, actor_user_id
  ) values (
    target_business_id, record_row.id, record_row.status, trim(target_status),
    nullif(trim(target_note), ''), target_metadata, auth.uid()
  );

  perform private.write_tenant_audit(
    target_business_id,
    'enterprise_record.status_changed',
    'enterprise_record',
    record_row.id::text,
    jsonb_build_object('from_status', record_row.status, 'to_status', trim(target_status))
  );
end;
$$;

create or replace function public.upsert_integration_connection(
  target_business_id uuid,
  target_provider_code text,
  target_display_name text,
  target_status text,
  target_secret_ref text,
  target_config jsonb,
  target_last_error text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  connection_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not private.enterprise_record_authorized(target_business_id, null, 'integrations.manage') then
    raise exception 'Integration management permission and module entitlement required';
  end if;
  if target_config is null or jsonb_typeof(target_config) <> 'object' then
    raise exception 'Configuration must be a JSON object';
  end if;
  insert into public.integration_connections (
    business_id, provider_code, display_name, status, secret_ref, config,
    last_checked_at, last_error, created_by, updated_by
  ) values (
    target_business_id, trim(target_provider_code), trim(target_display_name),
    trim(target_status), nullif(trim(target_secret_ref), ''), target_config,
    case when trim(target_status) in ('verified', 'error') then now() else null end,
    nullif(trim(target_last_error), ''), auth.uid(), auth.uid()
  )
  on conflict (business_id, provider_code, display_name) do update
  set status = excluded.status,
      secret_ref = excluded.secret_ref,
      config = excluded.config,
      last_checked_at = excluded.last_checked_at,
      last_error = excluded.last_error,
      updated_by = auth.uid(),
      updated_at = now()
  returning id into connection_id;

  perform private.write_tenant_audit(
    target_business_id,
    'integration_connection.updated',
    'integration_connection',
    connection_id::text,
    jsonb_build_object('provider_code', target_provider_code, 'status', target_status)
  );
  return connection_id;
end;
$$;

alter table public.enterprise_records enable row level security;
alter table public.enterprise_record_events enable row level security;
alter table public.integration_connections enable row level security;

create policy enterprise_records_select
on public.enterprise_records for select
to authenticated
using ((select private.enterprise_record_authorized(business_id, branch_id, 'enterprise.view')));

create policy enterprise_records_manage
on public.enterprise_records for all
to authenticated
using ((select private.enterprise_record_authorized(business_id, branch_id, 'enterprise.manage')))
with check ((select private.enterprise_record_authorized(business_id, branch_id, 'enterprise.manage')));

create policy enterprise_record_events_select
on public.enterprise_record_events for select
to authenticated
using (
  exists (
    select 1
    from public.enterprise_records record_row
    where record_row.id = record_id
      and private.enterprise_record_authorized(record_row.business_id, record_row.branch_id, 'enterprise.view')
  )
);

create policy integration_connections_select
on public.integration_connections for select
to authenticated
using ((select private.enterprise_record_authorized(business_id, null, 'integrations.view')));

revoke all on table public.enterprise_records, public.enterprise_record_events, public.integration_connections
  from anon, authenticated;
grant select on table public.enterprise_records, public.enterprise_record_events, public.integration_connections
  to authenticated;

revoke all on function private.enterprise_record_authorized(uuid, uuid, text)
  from public, anon, authenticated;
revoke all on function public.create_enterprise_record(uuid, uuid, text, text, text, text, numeric, timestamptz, timestamptz, jsonb)
  from public, anon;
revoke all on function public.transition_enterprise_record(uuid, uuid, text, text, jsonb)
  from public, anon;
revoke all on function public.upsert_integration_connection(uuid, text, text, text, text, jsonb, text)
  from public, anon;
grant execute on function public.create_enterprise_record(uuid, uuid, text, text, text, text, numeric, timestamptz, timestamptz, jsonb)
  to authenticated;
grant execute on function public.transition_enterprise_record(uuid, uuid, text, text, jsonb)
  to authenticated;
grant execute on function public.upsert_integration_connection(uuid, text, text, text, text, jsonb, text)
  to authenticated;

commit;
