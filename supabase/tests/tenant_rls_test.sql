-- Run against a disposable local Supabase database with:
--   supabase test db
-- The transaction rolls back all fixtures.
begin;

create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'owner-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'member-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'outsider@example.test', '', now(), '{}', '{}', now(), now());

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select lives_ok(
  $$select public.create_business_with_branch('Tenant A', 'retail', 'INR', 'Asia/Kolkata', 'Main Branch', 'MAIN', 'IN')$$,
  'an authenticated user can atomically create a business and branch'
);

select is((select count(*) from public.businesses), 1::bigint, 'owner sees their business');
select is((select count(*) from public.branches), 1::bigint, 'owner sees their branch');
select ok(
  exists (
    select 1 from public.roles r
    join public.role_permissions rp on rp.role_id = r.id
    where r.name = 'Owner' and rp.permission_code = 'roles.manage'
  ),
  'owner receives role-management permission'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select is((select count(*) from public.businesses), 0::bigint, 'outsider cannot see another tenant');
select is((select count(*) from public.branches), 0::bigint, 'outsider cannot see another tenant branches');
select is((select count(*) from public.roles), 0::bigint, 'outsider cannot see another tenant roles');
select is((select count(*) from public.memberships), 0::bigint, 'outsider cannot see another tenant memberships');

select * from finish();
rollback;
