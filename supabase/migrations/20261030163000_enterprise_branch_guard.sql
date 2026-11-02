begin;

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
      or exists (
        select 1
        from public.branches branch
        where branch.id = target_branch_id
          and branch.business_id = target_business_id
          and private.has_branch_access(branch.id)
      )
    );
$$;

grant execute on function private.enterprise_record_authorized(uuid, uuid, text)
  to authenticated;

commit;
