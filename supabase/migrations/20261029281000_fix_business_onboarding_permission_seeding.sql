-- Keep onboarding idempotent when role-permission defaults are seeded by a
-- trigger or a prior maintenance operation.

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
  select owner_role_id, code from public.permissions
  on conflict (role_id, permission_code) do nothing;

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

revoke all on function public.create_business_with_branch(text, text, text, text, text, text, text)
from public, anon;
grant execute on function public.create_business_with_branch(text, text, text, text, text, text, text)
to authenticated;
