begin;

create table public.business_invitations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  email text not null check (email = lower(trim(email)) and position('@' in email) > 1),
  role_id uuid not null references public.roles(id) on delete restrict,
  branch_access_all boolean not null default false,
  token_hash text not null unique,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'revoked', 'expired')),
  invited_by uuid not null references auth.users(id) on delete restrict,
  accepted_by uuid references auth.users(id) on delete restrict,
  expires_at timestamptz not null,
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.invitation_branch_access (
  invitation_id uuid not null references public.business_invitations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (invitation_id, branch_id)
);

create table public.tenant_audit_logs (
  id bigint generated always as identity primary key,
  business_id uuid not null references public.businesses(id) on delete restrict,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null check (action ~ '^[a-z][a-z0-9_.]+$'),
  target_type text not null,
  target_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create unique index business_invitations_pending_email_idx
  on public.business_invitations (business_id, email)
  where status = 'pending';
create index business_invitations_email_status_idx
  on public.business_invitations (email, status, expires_at);
create index invitation_branch_access_branch_idx
  on public.invitation_branch_access (branch_id);
create index tenant_audit_logs_business_created_idx
  on public.tenant_audit_logs (business_id, created_at desc);

create trigger business_invitations_set_updated_at
before update on public.business_invitations
for each row execute function private.set_updated_at();

create or replace function private.seed_default_roles(target_business_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.roles (business_id, name, description, is_system) values
    (target_business_id, 'Owner', 'Full business owner access', true),
    (target_business_id, 'Administrator', 'Business administration without ownership', true),
    (target_business_id, 'Branch Manager', 'Manage assigned branch operations', true),
    (target_business_id, 'Cashier', 'Create sales and serve customers', true),
    (target_business_id, 'Inventory Manager', 'Manage products and inventory', true),
    (target_business_id, 'Purchase Manager', 'Manage purchasing workflows', true),
    (target_business_id, 'Accountant', 'View reports, purchases, and financial activity', true),
    (target_business_id, 'Salesperson', 'Create sales and manage customers', true),
    (target_business_id, 'Warehouse Staff', 'View and process inventory work', true),
    (target_business_id, 'Restaurant Waiter', 'Create restaurant sales and serve customers', true),
    (target_business_id, 'Kitchen Staff', 'View sales required for kitchen operations', true),
    (target_business_id, 'Service Technician', 'Manage service customers and assigned products', true),
    (target_business_id, 'Read-only Auditor', 'Read-only operational and audit access', true)
  on conflict (business_id, name) do update set
    description = excluded.description,
    is_system = true;

  insert into public.role_permissions (role_id, permission_code)
  select r.id, p.code
  from public.roles r
  cross join public.permissions p
  where r.business_id = target_business_id
    and (
      r.name in ('Owner', 'Administrator')
      or (r.name = 'Branch Manager' and p.code = any(array[
        'business.view','branches.view','branches.manage','staff.view',
        'sales.view','sales.create','sales.discount','sales.refund',
        'products.view','products.manage','inventory.view','inventory.manage',
        'customers.view','customers.manage','reports.view'
      ]))
      or (r.name = 'Cashier' and p.code = any(array[
        'branches.view','sales.view','sales.create','sales.discount',
        'products.view','inventory.view','customers.view','customers.manage'
      ]))
      or (r.name = 'Inventory Manager' and p.code = any(array[
        'branches.view','products.view','products.manage','inventory.view',
        'inventory.manage','purchases.view','reports.view'
      ]))
      or (r.name = 'Purchase Manager' and p.code = any(array[
        'branches.view','products.view','inventory.view','purchases.view',
        'purchases.manage','reports.view'
      ]))
      or (r.name = 'Accountant' and p.code = any(array[
        'business.view','branches.view','sales.view','purchases.view',
        'customers.view','reports.view','reports.profit','audit.view'
      ]))
      or (r.name = 'Salesperson' and p.code = any(array[
        'branches.view','sales.view','sales.create','products.view',
        'inventory.view','customers.view','customers.manage'
      ]))
      or (r.name = 'Warehouse Staff' and p.code = any(array[
        'branches.view','products.view','inventory.view','inventory.manage',
        'purchases.view'
      ]))
      or (r.name = 'Restaurant Waiter' and p.code = any(array[
        'branches.view','sales.view','sales.create','sales.discount',
        'products.view','customers.view','customers.manage'
      ]))
      or (r.name = 'Kitchen Staff' and p.code = any(array[
        'branches.view','sales.view','products.view','inventory.view'
      ]))
      or (r.name = 'Service Technician' and p.code = any(array[
        'branches.view','sales.view','products.view','inventory.view',
        'customers.view','customers.manage'
      ]))
      or (r.name = 'Read-only Auditor' and p.code = any(array[
        'business.view','branches.view','staff.view','roles.view','sales.view',
        'products.view','inventory.view','purchases.view','customers.view',
        'reports.view','reports.profit','audit.view'
      ]))
    )
  on conflict do nothing;
end;
$$;

select private.seed_default_roles(id) from public.businesses;

create or replace function private.seed_roles_after_owner_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.seed_default_roles(new.business_id);
  return new;
end;
$$;

create trigger memberships_seed_default_roles
after insert on public.memberships
for each row execute function private.seed_roles_after_owner_membership();

create or replace function private.role_permissions_within_actor(
  target_business_id uuid,
  target_role_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
      select 1 from public.roles r
      where r.id = target_role_id and r.business_id = target_business_id
    )
    and not exists (
      select 1
      from public.role_permissions target_permission
      where target_permission.role_id = target_role_id
        and not exists (
          select 1
          from public.memberships actor_membership
          join public.role_permissions actor_permission
            on actor_permission.role_id = actor_membership.role_id
           and actor_permission.permission_code = target_permission.permission_code
          where actor_membership.business_id = target_business_id
            and actor_membership.user_id = auth.uid()
            and actor_membership.status = 'active'
            and actor_membership.archived_at is null
        )
    );
$$;

create or replace function private.role_is_assignable(
  target_business_id uuid,
  target_role_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_permission(target_business_id, 'staff.manage')
    and private.role_permissions_within_actor(target_business_id, target_role_id);
$$;

create or replace function private.protect_custom_role_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not old.is_system and not private.role_permissions_within_actor(
    old.business_id,
    old.id
  ) then
    raise exception 'You cannot edit a role with permissions above your own';
  end if;
  return new;
end;
$$;

create trigger roles_protect_permission_ceiling
before update on public.roles
for each row execute function private.protect_custom_role_update();

create or replace function private.write_tenant_audit(
  target_business_id uuid,
  audit_action text,
  audit_target_type text,
  audit_target_id text,
  audit_details jsonb default '{}'::jsonb
)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  insert into public.tenant_audit_logs (
    business_id, actor_user_id, action, target_type, target_id, details
  ) values (
    target_business_id, auth.uid(), audit_action, audit_target_type,
    audit_target_id, coalesce(audit_details, '{}'::jsonb)
  );
$$;

create or replace function public.create_role_with_permissions(
  target_business_id uuid,
  role_name text,
  role_description text,
  permission_codes text[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_role_id uuid;
begin
  if not private.has_permission(target_business_id, 'roles.manage') then
    raise exception 'You do not have permission to manage roles';
  end if;
  if char_length(trim(role_name)) not between 2 and 80 then
    raise exception 'Role name must be between 2 and 80 characters';
  end if;
  if exists (
    select 1 from unnest(coalesce(permission_codes, array[]::text[])) as requested(code)
    where not private.has_permission(target_business_id, requested.code)
  ) then
    raise exception 'A role cannot receive permissions you do not hold';
  end if;
  if exists (
    select 1 from unnest(coalesce(permission_codes, array[]::text[])) as requested(code)
    where not exists (select 1 from public.permissions p where p.code = requested.code)
  ) then
    raise exception 'Unknown permission code';
  end if;

  insert into public.roles (business_id, name, description, is_system)
  values (target_business_id, trim(role_name), nullif(trim(role_description), ''), false)
  returning id into new_role_id;

  insert into public.role_permissions (role_id, permission_code)
  select new_role_id, requested.code
  from unnest(coalesce(permission_codes, array[]::text[])) as requested(code)
  on conflict do nothing;

  perform private.write_tenant_audit(
    target_business_id, 'role.created', 'role', new_role_id::text,
    jsonb_build_object('name', trim(role_name), 'permissions', permission_codes)
  );
  return new_role_id;
end;
$$;

create or replace function public.update_role_with_permissions(
  target_role_id uuid,
  role_name text,
  role_description text,
  permission_codes text[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_role public.roles;
begin
  select * into target_role from public.roles where id = target_role_id;
  if target_role.id is null or target_role.is_system then
    raise exception 'Only custom roles can be edited';
  end if;
  if not private.has_permission(target_role.business_id, 'roles.manage') then
    raise exception 'You do not have permission to manage roles';
  end if;
  if not private.role_permissions_within_actor(
    target_role.business_id,
    target_role_id
  ) then
    raise exception 'You cannot edit a role with permissions above your own';
  end if;
  if char_length(trim(role_name)) not between 2 and 80 then
    raise exception 'Role name must be between 2 and 80 characters';
  end if;
  if exists (
    select 1 from unnest(coalesce(permission_codes, array[]::text[])) as requested(code)
    where not private.has_permission(target_role.business_id, requested.code)
      or not exists (select 1 from public.permissions p where p.code = requested.code)
  ) then
    raise exception 'Invalid or unauthorized permission code';
  end if;

  update public.roles set
    name = trim(role_name), description = nullif(trim(role_description), '')
  where id = target_role_id;
  delete from public.role_permissions where role_id = target_role_id;
  insert into public.role_permissions (role_id, permission_code)
  select target_role_id, requested.code
  from unnest(coalesce(permission_codes, array[]::text[])) as requested(code)
  on conflict do nothing;

  perform private.write_tenant_audit(
    target_role.business_id, 'role.updated', 'role', target_role_id::text,
    jsonb_build_object('name', trim(role_name), 'permissions', permission_codes)
  );
end;
$$;

create or replace function public.create_staff_invitation(
  target_business_id uuid,
  target_email text,
  target_role_id uuid,
  grants_all_branches boolean default false,
  target_branch_ids uuid[] default array[]::uuid[],
  valid_days integer default 7
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_email text := lower(trim(target_email));
  invitation_token text := encode(extensions.gen_random_bytes(24), 'hex');
  invitation_record public.business_invitations;
begin
  if normalized_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'Enter a valid email address';
  end if;
  if valid_days not between 1 and 30 then
    raise exception 'Invitation validity must be between 1 and 30 days';
  end if;
  if not private.role_is_assignable(target_business_id, target_role_id) then
    raise exception 'This role cannot be assigned by the current user';
  end if;
  if exists (
    select 1 from public.memberships m
    join public.profiles p on p.id = m.user_id
    where m.business_id = target_business_id
      and lower(p.email) = normalized_email
      and m.status = 'active' and m.archived_at is null
  ) then
    raise exception 'This user is already an active member';
  end if;
  if not grants_all_branches and cardinality(target_branch_ids) = 0 then
    raise exception 'Select at least one branch or grant all-branch access';
  end if;
  if exists (
    select 1 from unnest(coalesce(target_branch_ids, array[]::uuid[])) as requested(branch_id)
    where not exists (
      select 1 from public.branches b
      where b.id = requested.branch_id and b.business_id = target_business_id
        and b.archived_at is null
    )
  ) then
    raise exception 'An assigned branch does not belong to this business';
  end if;

  update public.business_invitations set status = 'revoked', revoked_at = now()
  where business_id = target_business_id and email = normalized_email
    and status = 'pending';

  insert into public.business_invitations (
    business_id, email, role_id, branch_access_all, token_hash,
    invited_by, expires_at
  ) values (
    target_business_id, normalized_email, target_role_id, grants_all_branches,
    encode(extensions.digest(invitation_token, 'sha256'), 'hex'), auth.uid(),
    now() + make_interval(days => valid_days)
  ) returning * into invitation_record;

  if not grants_all_branches then
    insert into public.invitation_branch_access (invitation_id, branch_id)
    select invitation_record.id, requested.branch_id
    from unnest(target_branch_ids) as requested(branch_id)
    on conflict do nothing;
  end if;

  perform private.write_tenant_audit(
    target_business_id, 'staff.invited', 'business_invitation',
    invitation_record.id::text,
    jsonb_build_object('email', normalized_email, 'role_id', target_role_id)
  );

  return jsonb_build_object(
    'invitation_id', invitation_record.id,
    'token', invitation_token,
    'email', normalized_email,
    'expires_at', invitation_record.expires_at
  );
end;
$$;

create or replace function public.accept_staff_invitation(invitation_token text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  caller_email text;
  invitation_record public.business_invitations;
  new_membership_id uuid;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select lower(email) into caller_email from auth.users where id = caller_id;
  select * into invitation_record
  from public.business_invitations
  where token_hash = encode(extensions.digest(trim(invitation_token), 'sha256'), 'hex')
  for update;

  if invitation_record.id is null then raise exception 'Invitation is invalid'; end if;
  if invitation_record.status <> 'pending' then raise exception 'Invitation is no longer active'; end if;
  if invitation_record.expires_at <= now() then
    update public.business_invitations set status = 'expired'
    where id = invitation_record.id;
    raise exception 'Invitation has expired';
  end if;
  if caller_email is null or caller_email <> invitation_record.email then
    raise exception 'Sign in with the email address that received this invitation';
  end if;
  if exists (
    select 1 from public.memberships
    where business_id = invitation_record.business_id and user_id = caller_id
  ) then
    raise exception 'An existing membership must be managed by an administrator';
  end if;

  insert into public.memberships (
    business_id, user_id, role_id, status, branch_access_all, joined_at
  ) values (
    invitation_record.business_id, caller_id, invitation_record.role_id,
    'active', invitation_record.branch_access_all, now()
  ) returning id into new_membership_id;

  if not invitation_record.branch_access_all then
    insert into public.member_branch_access (membership_id, branch_id)
    select new_membership_id, branch_id
    from public.invitation_branch_access
    where invitation_id = invitation_record.id;
  end if;

  update public.business_invitations set
    status = 'accepted', accepted_by = caller_id, accepted_at = now()
  where id = invitation_record.id;

  perform private.write_tenant_audit(
    invitation_record.business_id, 'staff.invitation_accepted', 'membership',
    new_membership_id::text, jsonb_build_object('invitation_id', invitation_record.id)
  );
  return invitation_record.business_id;
end;
$$;

create or replace function public.revoke_staff_invitation(target_invitation_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  invitation_record public.business_invitations;
begin
  select * into invitation_record from public.business_invitations
  where id = target_invitation_id;
  if invitation_record.id is null or invitation_record.status <> 'pending' then
    raise exception 'Active invitation not found';
  end if;
  if not private.has_permission(invitation_record.business_id, 'staff.manage') then
    raise exception 'You do not have permission to revoke invitations';
  end if;
  update public.business_invitations
  set status = 'revoked', revoked_at = now()
  where id = target_invitation_id;
  perform private.write_tenant_audit(
    invitation_record.business_id, 'staff.invitation_revoked',
    'business_invitation', target_invitation_id::text
  );
end;
$$;

create or replace function public.update_membership_access(
  target_membership_id uuid,
  target_role_id uuid,
  target_status text,
  grants_all_branches boolean,
  target_branch_ids uuid[] default array[]::uuid[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  membership_record public.memberships;
  current_role_id uuid;
begin
  select * into membership_record from public.memberships
  where id = target_membership_id and archived_at is null;
  if membership_record.id is null then raise exception 'Membership not found'; end if;
  if membership_record.user_id = auth.uid() then
    raise exception 'You cannot change your own access';
  end if;
  if target_status not in ('active', 'suspended', 'revoked') then
    raise exception 'Invalid membership status';
  end if;
  current_role_id := membership_record.role_id;
  if not private.role_is_assignable(membership_record.business_id, current_role_id)
     or not private.role_is_assignable(membership_record.business_id, target_role_id) then
    raise exception 'You cannot manage a role with permissions above your own';
  end if;
  if not grants_all_branches and cardinality(target_branch_ids) = 0 then
    raise exception 'Select at least one branch or grant all-branch access';
  end if;
  if exists (
    select 1 from unnest(coalesce(target_branch_ids, array[]::uuid[])) as requested(branch_id)
    where not exists (
      select 1 from public.branches b
      where b.id = requested.branch_id and b.business_id = membership_record.business_id
        and b.archived_at is null
    )
  ) then
    raise exception 'An assigned branch does not belong to this business';
  end if;
  if target_status <> 'active' and exists (
    select 1 from public.roles r where r.id = current_role_id and r.name = 'Owner'
  ) and (
    select count(*) from public.memberships m
    join public.roles r on r.id = m.role_id
    where m.business_id = membership_record.business_id
      and m.status = 'active' and m.archived_at is null and r.name = 'Owner'
  ) <= 1 then
    raise exception 'The last active owner cannot be suspended or revoked';
  end if;

  update public.memberships set
    role_id = target_role_id, status = target_status,
    branch_access_all = grants_all_branches
  where id = target_membership_id;
  delete from public.member_branch_access where membership_id = target_membership_id;
  if not grants_all_branches then
    insert into public.member_branch_access (membership_id, branch_id)
    select target_membership_id, requested.branch_id
    from unnest(target_branch_ids) as requested(branch_id)
    on conflict do nothing;
  end if;

  perform private.write_tenant_audit(
    membership_record.business_id, 'staff.access_updated', 'membership',
    target_membership_id::text,
    jsonb_build_object('role_id', target_role_id, 'status', target_status,
      'all_branches', grants_all_branches, 'branch_ids', target_branch_ids)
  );
end;
$$;

alter table public.business_invitations enable row level security;
alter table public.invitation_branch_access enable row level security;
alter table public.tenant_audit_logs enable row level security;

create policy business_invitations_select on public.business_invitations
for select to authenticated using (
  private.has_permission(business_id, 'staff.view')
  or email = lower(coalesce(auth.jwt() ->> 'email', ''))
);

create policy invitation_branch_access_select on public.invitation_branch_access
for select to authenticated using (exists (
  select 1 from public.business_invitations i
  where i.id = invitation_id and (
    private.has_permission(i.business_id, 'staff.view')
    or i.email = lower(coalesce(auth.jwt() ->> 'email', ''))
  )
));

create policy tenant_audit_logs_select on public.tenant_audit_logs
for select to authenticated
using (private.has_permission(business_id, 'audit.view'));

drop policy roles_insert on public.roles;
drop policy roles_update on public.roles;
drop policy role_permissions_insert on public.role_permissions;
drop policy role_permissions_delete on public.role_permissions;
drop policy memberships_update on public.memberships;
drop policy member_branch_access_insert on public.member_branch_access;
drop policy member_branch_access_delete on public.member_branch_access;

create policy role_permissions_insert on public.role_permissions
for insert to authenticated
with check (exists (
  select 1 from public.roles r
  where r.id = role_id and not r.is_system
    and private.has_permission(r.business_id, 'roles.manage')
    and private.has_permission(r.business_id, permission_code)
));

create policy role_permissions_delete on public.role_permissions
for delete to authenticated
using (exists (
  select 1 from public.roles r
  where r.id = role_id and not r.is_system
    and private.has_permission(r.business_id, 'roles.manage')
    and private.role_permissions_within_actor(r.business_id, r.id)
));

grant select on public.business_invitations to authenticated;
grant select on public.invitation_branch_access to authenticated;
grant select on public.tenant_audit_logs to authenticated;
revoke insert, update on public.roles from authenticated;
revoke insert, delete on public.role_permissions from authenticated;
revoke update on public.memberships from authenticated;
revoke insert, delete on public.member_branch_access from authenticated;

revoke all on function public.create_role_with_permissions(uuid, text, text, text[]) from public, anon;
revoke all on function public.update_role_with_permissions(uuid, text, text, text[]) from public, anon;
revoke all on function public.create_staff_invitation(uuid, text, uuid, boolean, uuid[], integer) from public, anon;
revoke all on function public.accept_staff_invitation(text) from public, anon;
revoke all on function public.revoke_staff_invitation(uuid) from public, anon;
revoke all on function public.update_membership_access(uuid, uuid, text, boolean, uuid[]) from public, anon;

grant execute on function public.create_role_with_permissions(uuid, text, text, text[]) to authenticated;
grant execute on function public.update_role_with_permissions(uuid, text, text, text[]) to authenticated;
grant execute on function public.create_staff_invitation(uuid, text, uuid, boolean, uuid[], integer) to authenticated;
grant execute on function public.accept_staff_invitation(text) to authenticated;
grant execute on function public.revoke_staff_invitation(uuid) to authenticated;
grant execute on function public.update_membership_access(uuid, uuid, text, boolean, uuid[]) to authenticated;

commit;
