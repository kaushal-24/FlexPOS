-- Allow authorized administrators to remove unused custom roles.
-- System roles and roles currently assigned to memberships are protected.

create or replace function public.delete_role(target_role_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_role public.roles;
begin
  select * into target_role
  from public.roles
  where id = target_role_id;

  if target_role.id is null or target_role.is_system then
    raise exception 'Only unused custom roles can be deleted';
  end if;
  if not private.has_permission(target_role.business_id, 'roles.manage') then
    raise exception 'You do not have permission to manage roles';
  end if;
  if not private.role_permissions_within_actor(
    target_role.business_id,
    target_role_id
  ) then
    raise exception 'You cannot delete a role with permissions above your own';
  end if;
  if exists (
    select 1 from public.memberships m where m.role_id = target_role_id
  ) then
    raise exception 'Reassign every member before deleting this role';
  end if;

  delete from public.roles where id = target_role_id;

  perform private.write_tenant_audit(
    target_role.business_id,
    'role.deleted',
    'role',
    target_role_id::text,
    jsonb_build_object('name', target_role.name)
  );
end;
$$;

revoke all on function public.delete_role(uuid) from public, anon;
grant execute on function public.delete_role(uuid) to authenticated;
