-- Run only against a disposable local Supabase database with `supabase test db`.
-- All fixtures and mutations are rolled back.
begin;

create extension if not exists pgtap with schema extensions;
select plan(13);

create temporary table phase2_test_state (
  business_id uuid,
  cashier_role_id uuid,
  invitation_token text,
  invitee_membership_id uuid
);
grant all on phase2_test_state to authenticated;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'owner@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'cashier@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'outsider@example.test', '', now(), '{}', '{}', now(), now());

set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'owner@example.test', true);

select lives_ok(
  $$select public.create_business_with_branch('Phase Two Tenant', 'retail', 'INR', 'Asia/Kolkata', 'Main Branch', 'MAIN', 'IN')$$,
  'owner can create the tenant atomically'
);

insert into phase2_test_state (business_id, cashier_role_id)
select b.id, r.id
from public.businesses b
join public.roles r on r.business_id = b.id and r.name = 'Cashier'
where b.name = 'Phase Two Tenant';

select is(
  (select count(*) from public.roles where business_id = (select business_id from phase2_test_state)),
  13::bigint,
  'all thirteen tenant role templates are seeded'
);

select lives_ok(
  format(
    $$select public.create_role_with_permissions(%L, 'Floor Supervisor', 'Limited supervisor', array['sales.view','sales.create'])$$,
    (select business_id from phase2_test_state)
  ),
  'owner can create a custom role with an allowed permission set'
);

select is(
  (select count(*) from public.role_permissions rp join public.roles r on r.id = rp.role_id where r.name = 'Floor Supervisor'),
  2::bigint,
  'custom role receives exactly the selected permissions'
);

update phase2_test_state set invitation_token = (
  select result ->> 'token'
  from (
    select public.create_staff_invitation(
      (select business_id from phase2_test_state),
      'cashier@example.test',
      (select cashier_role_id from phase2_test_state),
      true,
      array[]::uuid[],
      7
    ) result
  ) invitation
);

select ok(
  (select char_length(invitation_token) = 48 from phase2_test_state),
  'staff invitation returns a strong one-time token'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'cashier@example.test', true);

select lives_ok(
  format(
    $$select public.accept_staff_invitation(%L)$$,
    (select invitation_token from phase2_test_state)
  ),
  'matching authenticated email can accept the invitation'
);

update phase2_test_state set invitee_membership_id = (
  select m.id from public.memberships m
  where m.business_id = phase2_test_state.business_id
    and m.user_id = '20000000-0000-0000-0000-000000000002'
);

select is((select count(*) from public.businesses), 1::bigint, 'invitee can see the joined tenant');
select is((select count(*) from public.branches), 1::bigint, 'all-branch invite grants branch visibility');

select throws_ok(
  format(
    $$select public.create_role_with_permissions(%L, 'Escalated', 'Not allowed', array['audit.view'])$$,
    (select business_id from phase2_test_state)
  ),
  'P0001'
);

select throws_ok(
  format(
    $$select public.update_membership_access(%L, %L, 'active', true, array[]::uuid[])$$,
    (select invitee_membership_id from phase2_test_state),
    (select cashier_role_id from phase2_test_state)
  ),
  'P0001'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000003', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'outsider@example.test', true);

select is((select count(*) from public.businesses), 0::bigint, 'outsider cannot see tenant business');
select is((select count(*) from public.business_invitations), 0::bigint, 'outsider cannot see tenant invitations');

reset role;
select is(
  (select count(*) from public.tenant_audit_logs where action in ('staff.invited', 'staff.invitation_accepted')),
  2::bigint,
  'invitation lifecycle writes tenant audit records'
);

select * from finish();
rollback;
