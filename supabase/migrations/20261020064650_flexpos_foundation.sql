-- FlexPOS foundation hardening after the clean project reset.
-- Keeps the platform automatic-RLS trigger while removing its Data API surface.

revoke execute on function public.rls_auto_enable() from public, anon, authenticated, service_role;

create index if not exists businesses_created_by_idx
  on public.businesses(created_by);
create index if not exists memberships_role_id_idx
  on public.memberships(role_id);
create index if not exists role_permissions_permission_code_idx
  on public.role_permissions(permission_code);
create index if not exists business_invitations_role_id_idx
  on public.business_invitations(role_id);
create index if not exists business_invitations_invited_by_idx
  on public.business_invitations(invited_by);
create index if not exists business_invitations_accepted_by_idx
  on public.business_invitations(accepted_by)
  where accepted_by is not null;
create index if not exists tenant_audit_logs_actor_user_id_idx
  on public.tenant_audit_logs(actor_user_id)
  where actor_user_id is not null;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
for select to authenticated
using (id = (select auth.uid()) or (select private.shares_business_with(id)));

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

drop policy if exists memberships_select on public.memberships;
create policy memberships_select on public.memberships
for select to authenticated
using (
  user_id = (select auth.uid())
  or (select private.has_permission(business_id, 'staff.view'))
);

drop policy if exists member_branch_access_select on public.member_branch_access;
create policy member_branch_access_select on public.member_branch_access
for select to authenticated
using (
  exists (
    select 1
    from public.memberships m
    where m.id = membership_id
      and (
        m.user_id = (select auth.uid())
        or (select private.has_permission(m.business_id, 'staff.view'))
      )
  )
);

drop policy if exists business_invitations_select on public.business_invitations;
create policy business_invitations_select on public.business_invitations
for select to authenticated
using (
  (select private.has_permission(business_id, 'staff.view'))
  or lower(email) = lower(coalesce((select auth.jwt() ->> 'email'), ''))
);

drop policy if exists invitation_branch_access_select on public.invitation_branch_access;
create policy invitation_branch_access_select on public.invitation_branch_access
for select to authenticated
using (
  exists (
    select 1
    from public.business_invitations i
    where i.id = invitation_id
      and (
        (select private.has_permission(i.business_id, 'staff.view'))
        or lower(i.email) = lower(coalesce((select auth.jwt() ->> 'email'), ''))
      )
  )
);

-- Data API access is opt-in and paired with RLS.
grant usage on schema public to authenticated;
grant select, update on public.profiles, public.businesses to authenticated;
grant select, insert, update on public.branches to authenticated;
grant select on public.permissions, public.roles, public.role_permissions,
  public.memberships, public.member_branch_access, public.business_invitations,
  public.invitation_branch_access, public.tenant_audit_logs to authenticated;

