-- Promotion campaign reporting verification. All fixtures roll back.
begin;

create extension if not exists pgtap with schema extensions;
select plan(6);

create temporary table promotion_report_test_state (
  business_id uuid,
  branch_id uuid
);
grant all on promotion_report_test_state to authenticated;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000',
   '53000000-0000-0000-0000-000000000001',
   'authenticated', 'authenticated', 'promotion-owner@example.test', '',
   now(), '{}', '{}', now(), now());

set local role authenticated;
select set_config('request.jwt.claim.sub', '53000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'promotion-owner@example.test', true);

select lives_ok(
  $$select public.create_business_with_branch(
    'Promotion Report Test Business', 'retail', 'INR', 'Asia/Kolkata',
    'Main Branch', 'MAIN', 'IN'
  )$$,
  'owner creates a promotion reporting tenant'
);

insert into promotion_report_test_state (business_id, branch_id)
select b.id, br.id
from public.businesses b
join public.branches br on br.business_id = b.id
where b.name = 'Promotion Report Test Business';

select lives_ok(
  $$insert into public.promotions (
    business_id, branch_id, code, name, discount_type, discount_value,
    minimum_subtotal, created_by
  ) values (
    (select business_id from promotion_report_test_state),
    (select branch_id from promotion_report_test_state),
    'TEST10', 'Test ten percent', 'percentage', 10, 0,
    '53000000-0000-0000-0000-000000000001'
  )$$,
  'owner creates a campaign visible to reporting'
);

select is(
  (public.get_promotion_performance_report(
    (select business_id from promotion_report_test_state),
    now() - interval '1 day', now() + interval '1 day'
  ) ->> 'promotion_count')::integer,
  1,
  'promotion report includes campaigns with no redemptions'
);

select is(
  jsonb_array_length(public.get_promotion_performance_report(
    (select business_id from promotion_report_test_state),
    now() - interval '1 day', now() + interval '1 day'
  ) -> 'campaigns'),
  1,
  'promotion report returns campaign analytics rows'
);

select is(
  (public.get_promotion_performance_report(
    (select business_id from promotion_report_test_state),
    now() - interval '1 day', now() + interval '1 day'
  ) ->> 'redemption_count')::integer,
  0,
  'empty campaign report has zero redemptions'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '53000000-0000-0000-0000-000000000099', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select public.get_promotion_performance_report(
    (select business_id from promotion_report_test_state),
    now() - interval '1 day', now() + interval '1 day'
  )$$,
  'P0001',
  null,
  'outsider cannot read promotion analytics'
);

select * from finish();
rollback;
