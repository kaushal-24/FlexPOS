begin;

create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;

revoke all on schema private from public, anon, authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  full_name text,
  avatar_path text,
  preferred_locale text not null default 'en' check (preferred_locale in ('en', 'hi')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 2 and 120),
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  business_type text not null check (business_type in (
    'retail', 'grocery', 'restaurant', 'wholesale', 'fashion',
    'electronics', 'hardware', 'auto_parts', 'salon', 'service',
    'pharmacy', 'warehouse', 'manufacturing', 'other'
  )),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  timezone text not null check (char_length(timezone) between 3 and 64),
  country_code text check (country_code is null or country_code ~ '^[A-Z]{2}$'),
  tax_registration_number text,
  invoice_prefix text not null default 'INV' check (invoice_prefix ~ '^[A-Z0-9-]{1,12}$'),
  receipt_footer text,
  created_by uuid not null references auth.users(id),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.branches (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  name text not null check (char_length(trim(name)) between 2 and 120),
  code text not null check (code ~ '^[A-Z0-9-]{1,16}$'),
  email text,
  phone text,
  address_line_1 text,
  address_line_2 text,
  city text,
  state_region text,
  postal_code text,
  country_code text check (country_code is null or country_code ~ '^[A-Z]{2}$'),
  timezone text not null check (char_length(timezone) between 3 and 64),
  is_active boolean not null default true,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, code)
);

create table public.permissions (
  code text primary key check (code ~ '^[a-z][a-z0-9_.]+$'),
  category text not null,
  description text not null,
  created_at timestamptz not null default now()
);

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  name text not null check (char_length(trim(name)) between 2 and 80),
  description text,
  is_system boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, name)
);

create table public.role_permissions (
  role_id uuid not null references public.roles(id) on delete cascade,
  permission_code text not null references public.permissions(code) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (role_id, permission_code)
);

create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  role_id uuid not null references public.roles(id) on delete restrict,
  status text not null default 'active' check (status in ('invited', 'active', 'suspended', 'revoked')),
  branch_access_all boolean not null default false,
  joined_at timestamptz,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, user_id)
);

create table public.member_branch_access (
  membership_id uuid not null references public.memberships(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (membership_id, branch_id)
);

create index memberships_user_status_idx on public.memberships(user_id, status);
create index memberships_business_status_idx on public.memberships(business_id, status);
create index branches_business_active_idx on public.branches(business_id, is_active) where archived_at is null;
create index roles_business_idx on public.roles(business_id);
create index member_branch_access_branch_idx on public.member_branch_access(branch_id);

insert into public.permissions (code, category, description) values
  ('business.view', 'Business', 'View business settings'),
  ('business.manage', 'Business', 'Manage business settings'),
  ('branches.view', 'Branches', 'View assigned branches'),
  ('branches.manage', 'Branches', 'Create and manage branches'),
  ('staff.view', 'Staff', 'View staff and memberships'),
  ('staff.manage', 'Staff', 'Invite and manage staff'),
  ('roles.view', 'Access control', 'View roles and permissions'),
  ('roles.manage', 'Access control', 'Create roles and assign permissions'),
  ('sales.view', 'Sales', 'View sales'),
  ('sales.create', 'Sales', 'Create sales'),
  ('sales.discount', 'Sales', 'Apply permitted discounts'),
  ('sales.refund', 'Sales', 'Process authorized refunds'),
  ('products.view', 'Catalog', 'View products'),
  ('products.manage', 'Catalog', 'Create and manage products'),
  ('inventory.view', 'Inventory', 'View inventory'),
  ('inventory.manage', 'Inventory', 'Adjust and transfer inventory'),
  ('purchases.view', 'Purchasing', 'View purchases'),
  ('purchases.manage', 'Purchasing', 'Create and approve purchases'),
  ('customers.view', 'Customers', 'View customers'),
  ('customers.manage', 'Customers', 'Create and manage customers'),
  ('reports.view', 'Reports', 'View standard reports'),
  ('reports.profit', 'Reports', 'View cost and profit information'),
  ('audit.view', 'Security', 'View audit logs')
on conflict (code) do update set
  category = excluded.category,
  description = excluded.description;

create or replace function private.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function private.set_updated_at();

create trigger businesses_set_updated_at
before update on public.businesses
for each row execute function private.set_updated_at();

create trigger branches_set_updated_at
before update on public.branches
for each row execute function private.set_updated_at();

create trigger roles_set_updated_at
before update on public.roles
for each row execute function private.set_updated_at();

create trigger memberships_set_updated_at
before update on public.memberships
for each row execute function private.set_updated_at();

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    coalesce(new.email, ''),
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), '')
  )
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert or update of email on auth.users
for each row execute function private.handle_new_user();

insert into public.profiles (id, email, full_name)
select id, coalesce(email, ''), nullif(trim(coalesce(raw_user_meta_data ->> 'full_name', '')), '')
from auth.users
on conflict (id) do update set email = excluded.email;

create or replace function private.is_business_member(target_business_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships m
    where m.business_id = target_business_id
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.archived_at is null
  );
$$;

create or replace function private.has_permission(
  target_business_id uuid,
  required_permission text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships m
    join public.role_permissions rp on rp.role_id = m.role_id
    where m.business_id = target_business_id
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.archived_at is null
      and rp.permission_code = required_permission
  );
$$;

create or replace function private.has_branch_access(target_branch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.branches b
    join public.memberships m on m.business_id = b.business_id
    where b.id = target_branch_id
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.archived_at is null
      and (
        m.branch_access_all
        or exists (
          select 1 from public.member_branch_access mba
          where mba.membership_id = m.id and mba.branch_id = b.id
        )
      )
  );
$$;

create or replace function private.shares_business_with(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships mine
    join public.memberships theirs on theirs.business_id = mine.business_id
    where mine.user_id = auth.uid()
      and mine.status = 'active'
      and mine.archived_at is null
      and theirs.user_id = target_user_id
      and theirs.status = 'active'
      and theirs.archived_at is null
      and private.has_permission(mine.business_id, 'staff.view')
  );
$$;

create or replace function private.protect_membership_update()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.business_id <> old.business_id or new.user_id <> old.user_id then
    raise exception 'Membership identity cannot be changed';
  end if;
  if old.user_id = auth.uid() and (
    new.role_id <> old.role_id or new.status <> old.status or
    new.branch_access_all <> old.branch_access_all
  ) then
    raise exception 'A user cannot escalate or revoke their own membership';
  end if;
  return new;
end;
$$;

create trigger memberships_protect_update
before update on public.memberships
for each row execute function private.protect_membership_update();

create or replace function public.create_business_with_branch(
  business_name text,
  selected_business_type text,
  selected_currency_code text,
  selected_timezone text,
  branch_name text,
  branch_code text default 'MAIN',
  selected_country_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  business_record public.businesses;
  branch_record public.branches;
  owner_role_id uuid;
  membership_id uuid;
  generated_slug text;
  normalized_code text;
begin
  if caller_id is null then
    raise exception 'Authentication required';
  end if;
  if char_length(trim(business_name)) not between 2 and 120 then
    raise exception 'Business name must be between 2 and 120 characters';
  end if;
  if char_length(trim(branch_name)) not between 2 and 120 then
    raise exception 'Branch name must be between 2 and 120 characters';
  end if;
  if selected_currency_code !~ '^[A-Z]{3}$' then
    raise exception 'Currency code must be a three-letter ISO code';
  end if;

  generated_slug := trim(both '-' from regexp_replace(lower(trim(business_name)), '[^a-z0-9]+', '-', 'g'))
    || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  normalized_code := upper(regexp_replace(trim(coalesce(branch_code, 'MAIN')), '[^A-Za-z0-9-]+', '-', 'g'));
  if normalized_code = '' then normalized_code := 'MAIN'; end if;

  insert into public.businesses (
    name, slug, business_type, currency_code, timezone, country_code, created_by
  ) values (
    trim(business_name), generated_slug, selected_business_type,
    selected_currency_code, selected_timezone, selected_country_code, caller_id
  ) returning * into business_record;

  insert into public.roles (business_id, name, description, is_system)
  values (business_record.id, 'Owner', 'Full business owner access', true)
  returning id into owner_role_id;

  insert into public.role_permissions (role_id, permission_code)
  select owner_role_id, code from public.permissions;

  insert into public.memberships (
    business_id, user_id, role_id, status, branch_access_all, joined_at
  ) values (
    business_record.id, caller_id, owner_role_id, 'active', true, now()
  ) returning id into membership_id;

  insert into public.branches (
    business_id, name, code, timezone, country_code
  ) values (
    business_record.id, trim(branch_name), normalized_code,
    selected_timezone, selected_country_code
  ) returning * into branch_record;

  return jsonb_build_object(
    'business_id', business_record.id,
    'business_name', business_record.name,
    'business_type', business_record.business_type,
    'currency_code', business_record.currency_code,
    'timezone', business_record.timezone,
    'membership_id', membership_id,
    'role_id', owner_role_id,
    'role_name', 'Owner',
    'branch_id', branch_record.id,
    'branch_name', branch_record.name,
    'branch_code', branch_record.code
  );
end;
$$;

revoke all on function public.create_business_with_branch(text, text, text, text, text, text, text) from public, anon;
grant execute on function public.create_business_with_branch(text, text, text, text, text, text, text) to authenticated;

alter table public.profiles enable row level security;
alter table public.businesses enable row level security;
alter table public.branches enable row level security;
alter table public.permissions enable row level security;
alter table public.roles enable row level security;
alter table public.role_permissions enable row level security;
alter table public.memberships enable row level security;
alter table public.member_branch_access enable row level security;

create policy profiles_select on public.profiles
for select to authenticated
using (id = auth.uid() or private.shares_business_with(id));

create policy profiles_update_self on public.profiles
for update to authenticated
using (id = auth.uid())
with check (id = auth.uid());

create policy businesses_select on public.businesses
for select to authenticated
using (private.is_business_member(id));

create policy businesses_update on public.businesses
for update to authenticated
using (private.has_permission(id, 'business.manage'))
with check (private.has_permission(id, 'business.manage'));

create policy branches_select on public.branches
for select to authenticated
using (private.has_branch_access(id));

create policy branches_insert on public.branches
for insert to authenticated
with check (private.has_permission(business_id, 'branches.manage'));

create policy branches_update on public.branches
for update to authenticated
using (private.has_permission(business_id, 'branches.manage'))
with check (private.has_permission(business_id, 'branches.manage'));

create policy permissions_select on public.permissions
for select to authenticated using (true);

create policy roles_select on public.roles
for select to authenticated
using (private.is_business_member(business_id));

create policy roles_insert on public.roles
for insert to authenticated
with check (private.has_permission(business_id, 'roles.manage') and not is_system);

create policy roles_update on public.roles
for update to authenticated
using (private.has_permission(business_id, 'roles.manage') and not is_system)
with check (private.has_permission(business_id, 'roles.manage') and not is_system);

create policy role_permissions_select on public.role_permissions
for select to authenticated
using (exists (
  select 1 from public.roles r
  where r.id = role_id and private.is_business_member(r.business_id)
));

create policy role_permissions_insert on public.role_permissions
for insert to authenticated
with check (exists (
  select 1 from public.roles r
  where r.id = role_id and not r.is_system
    and private.has_permission(r.business_id, 'roles.manage')
));

create policy role_permissions_delete on public.role_permissions
for delete to authenticated
using (exists (
  select 1 from public.roles r
  where r.id = role_id and not r.is_system
    and private.has_permission(r.business_id, 'roles.manage')
));

create policy memberships_select on public.memberships
for select to authenticated
using (
  user_id = auth.uid()
  or private.has_permission(business_id, 'staff.view')
);

create policy memberships_update on public.memberships
for update to authenticated
using (user_id <> auth.uid() and private.has_permission(business_id, 'staff.manage'))
with check (user_id <> auth.uid() and private.has_permission(business_id, 'staff.manage'));

create policy member_branch_access_select on public.member_branch_access
for select to authenticated
using (exists (
  select 1 from public.memberships m
  where m.id = membership_id
    and (m.user_id = auth.uid() or private.has_permission(m.business_id, 'staff.view'))
));

create policy member_branch_access_insert on public.member_branch_access
for insert to authenticated
with check (exists (
  select 1 from public.memberships m
  join public.branches b on b.id = branch_id and b.business_id = m.business_id
  where m.id = membership_id and m.user_id <> auth.uid()
    and private.has_permission(m.business_id, 'staff.manage')
));

create policy member_branch_access_delete on public.member_branch_access
for delete to authenticated
using (exists (
  select 1 from public.memberships m
  where m.id = membership_id and m.user_id <> auth.uid()
    and private.has_permission(m.business_id, 'staff.manage')
));

grant usage on schema public to authenticated;
grant select, update on public.profiles to authenticated;
grant select, update on public.businesses to authenticated;
grant select, insert, update on public.branches to authenticated;
grant select on public.permissions to authenticated;
grant select, insert, update on public.roles to authenticated;
grant select, insert, delete on public.role_permissions to authenticated;
grant select, update on public.memberships to authenticated;
grant select, insert, delete on public.member_branch_access to authenticated;

commit;
