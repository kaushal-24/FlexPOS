-- Avoid duplicate permission rows while create_business_with_branch bootstraps
-- a new Owner role. The onboarding RPC itself grants all current permissions.

create or replace function private.seed_accounting_role_permissions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.name = 'Owner' then
    return new;
  end if;

  insert into public.role_permissions (role_id, permission_code)
  select new.id, p.code
  from public.permissions p
  where p.code in (
    'expenses.view', 'expenses.manage',
    'customer_credit.view', 'customer_credit.manage'
  )
  and (
    new.name in ('Administrator', 'Accountant')
    or (new.name = 'Branch Manager'
      and p.code in ('expenses.view', 'customer_credit.view'))
  )
  on conflict do nothing;
  return new;
end;
$$;

revoke all on function private.seed_accounting_role_permissions()
from public, anon, authenticated;
