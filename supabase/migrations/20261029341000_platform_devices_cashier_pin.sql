-- SaaS administrator identity, tenant device registry, and rate-limited
-- server-side cashier PIN re-entry. PIN material never leaves the database.
begin;

create table if not exists public.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null
);

create table if not exists public.business_devices (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  device_key text not null check (length(btrim(device_key)) between 16 and 180),
  device_name text not null check (length(btrim(device_name)) between 1 and 120),
  platform text not null default 'unknown'
    check (platform in ('android', 'ios', 'macos', 'windows', 'linux', 'web', 'unknown')),
  status text not null default 'active' check (status in ('active', 'revoked')),
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  unique (business_id, user_id, device_key),
  unique (id, business_id)
);

create table if not exists public.cashier_pin_credentials (
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  pin_salt text not null,
  pin_hash text not null check (pin_hash ~ '^[0-9a-f]{64}$'),
  failed_attempts integer not null default 0 check (failed_attempts >= 0),
  locked_until timestamptz,
  last_verified_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (business_id, user_id)
);

create or replace function private.is_platform_admin()
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1 from public.platform_admins
    where user_id = auth.uid() and is_active
  );
$$;

alter table public.platform_admins enable row level security;
alter table public.business_devices enable row level security;
alter table public.cashier_pin_credentials enable row level security;

drop policy if exists platform_admins_select on public.platform_admins;
create policy platform_admins_select on public.platform_admins
for select to authenticated
using (user_id = (select auth.uid()) or (select private.is_platform_admin()));

drop policy if exists business_devices_select on public.business_devices;
create policy business_devices_select on public.business_devices
for select to authenticated
using (
  user_id = (select auth.uid())
  or (select private.has_permission(business_id, 'business.manage'))
  or (select private.is_platform_admin())
);

drop policy if exists cashier_pin_select on public.cashier_pin_credentials;
create policy cashier_pin_select on public.cashier_pin_credentials
for select to authenticated
using (user_id = (select auth.uid()));

revoke all on public.platform_admins, public.cashier_pin_credentials from anon, authenticated;
grant select on public.platform_admins, public.business_devices, public.cashier_pin_credentials to authenticated;

create or replace function public.get_platform_admin_overview()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_platform_admin() then
    raise exception 'Platform administrator access required';
  end if;
  return jsonb_build_object(
    'business_count', (select count(*) from public.businesses where archived_at is null),
    'member_count', (select count(*) from public.memberships where status = 'active'),
    'device_count', (select count(*) from public.business_devices where status = 'active'),
    'user_count', (select count(*) from auth.users)
  );
end;
$$;

create or replace function public.register_business_device(
  target_business_id uuid,
  target_device_key text,
  target_device_name text,
  target_platform text
)
returns public.business_devices
language plpgsql
security definer
set search_path = ''
as $$
declare
  result public.business_devices;
  caller_id uuid := auth.uid();
begin
  if caller_id is null or not private.is_business_member(target_business_id) then
    raise exception 'Business membership required';
  end if;
  if length(btrim(target_device_key)) not between 16 and 180 then
    raise exception 'Device key is invalid';
  end if;
  if target_platform not in ('android', 'ios', 'macos', 'windows', 'linux', 'web', 'unknown') then
    raise exception 'Device platform is invalid';
  end if;
  insert into public.business_devices (
    business_id, user_id, device_key, device_name, platform, status,
    last_seen_at, revoked_at
  ) values (
    target_business_id, caller_id, btrim(target_device_key),
    left(btrim(target_device_name), 120), target_platform, 'active', now(), null
  )
  on conflict (business_id, user_id, device_key) do update set
    device_name = excluded.device_name,
    platform = excluded.platform,
    status = 'active',
    last_seen_at = now(),
    revoked_at = null
  returning * into result;
  return result;
end;
$$;

create or replace function public.revoke_business_device(target_device_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.business_devices d
  set status = 'revoked', revoked_at = now()
  where d.id = target_device_id
    and (
      d.user_id = auth.uid()
      or private.has_permission(d.business_id, 'business.manage')
      or private.is_platform_admin()
    );
  if not found then raise exception 'Device is not accessible'; end if;
end;
$$;

create or replace function public.get_cashier_pin_status(target_business_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select private.is_business_member(target_business_id)
    and exists (
      select 1 from public.cashier_pin_credentials
      where business_id = target_business_id and user_id = auth.uid()
    );
$$;

create or replace function public.set_cashier_pin(
  target_business_id uuid,
  target_pin text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  salt text := encode(extensions.gen_random_bytes(16), 'hex');
  normalized_pin text := btrim(target_pin);
begin
  if caller_id is null or not private.has_permission(target_business_id, 'sales.create') then
    raise exception 'Sales permission required';
  end if;
  if normalized_pin !~ '^[0-9]{6,12}$' then
    raise exception 'Cashier PIN must contain 6 to 12 digits';
  end if;
  insert into public.cashier_pin_credentials (
    business_id, user_id, pin_salt, pin_hash, failed_attempts, locked_until,
    last_verified_at, updated_at
  ) values (
    target_business_id, caller_id, salt,
    encode(extensions.digest(salt || normalized_pin, 'sha256'), 'hex'),
    0, null, null, now()
  )
  on conflict (business_id, user_id) do update set
    pin_salt = excluded.pin_salt,
    pin_hash = excluded.pin_hash,
    failed_attempts = 0,
    locked_until = null,
    last_verified_at = null,
    updated_at = now();
end;
$$;

create or replace function public.verify_cashier_pin(
  target_business_id uuid,
  target_pin text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  credential public.cashier_pin_credentials;
  normalized_pin text := btrim(target_pin);
  candidate_hash text;
begin
  if not private.is_business_member(target_business_id) then return false; end if;
  select * into credential
  from public.cashier_pin_credentials
  where business_id = target_business_id and user_id = auth.uid()
  for update;
  if not found then return true; end if;
  if credential.locked_until is not null and credential.locked_until > now() then
    return false;
  end if;
  candidate_hash := encode(extensions.digest(credential.pin_salt || normalized_pin, 'sha256'), 'hex');
  if candidate_hash = credential.pin_hash then
    update public.cashier_pin_credentials
    set failed_attempts = 0, locked_until = null,
        last_verified_at = now(), updated_at = now()
    where business_id = target_business_id and user_id = auth.uid();
    return true;
  end if;
  update public.cashier_pin_credentials
  set failed_attempts = failed_attempts + 1,
      locked_until = case when failed_attempts + 1 >= 5 then now() + interval '5 minutes' else null end,
      updated_at = now()
  where business_id = target_business_id and user_id = auth.uid();
  return false;
end;
$$;

revoke all on function private.is_platform_admin() from public, anon, authenticated, service_role;
revoke all on function public.get_platform_admin_overview() from public, anon;
revoke all on function public.register_business_device(uuid, text, text, text) from public, anon;
revoke all on function public.revoke_business_device(uuid) from public, anon;
revoke all on function public.get_cashier_pin_status(uuid) from public, anon;
revoke all on function public.set_cashier_pin(uuid, text) from public, anon;
revoke all on function public.verify_cashier_pin(uuid, text) from public, anon;
grant execute on function public.get_platform_admin_overview() to authenticated;
grant execute on function public.register_business_device(uuid, text, text, text) to authenticated;
grant execute on function public.revoke_business_device(uuid) to authenticated;
grant execute on function public.get_cashier_pin_status(uuid) to authenticated;
grant execute on function public.set_cashier_pin(uuid, text) to authenticated;
grant execute on function public.verify_cashier_pin(uuid, text) to authenticated;

commit;
