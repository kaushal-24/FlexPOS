-- Persistent POS draft verification. All fixtures roll back.
begin;

create extension if not exists pgtap with schema extensions;
select plan(23);

create temporary table draft_test_state (
  business_id uuid,
  branch_id uuid,
  warehouse_id uuid,
  unit_id uuid,
  variant_id uuid,
  draft_id uuid
);
grant all on draft_test_state to authenticated;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '35000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'draft-owner@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '35000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'draft-outsider@example.test', '', now(), '{}', '{}', now(), now());

set local role authenticated;
select set_config('request.jwt.claim.sub', '35000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'draft-owner@example.test', true);

select lives_ok(
  $$select public.create_business_with_branch('POS Draft Test Business', 'retail', 'INR', 'Asia/Kolkata', 'Main Branch', 'MAIN', 'IN')$$,
  'owner creates a draft test tenant'
);

insert into draft_test_state (business_id, branch_id, warehouse_id, unit_id)
select business.id, branch.id, warehouse.id, unit_record.id
from public.businesses business
join public.branches branch on branch.business_id = business.id
join public.warehouses warehouse
  on warehouse.business_id = business.id and warehouse.branch_id = branch.id
join public.units unit_record
  on unit_record.business_id = business.id and unit_record.name = 'Piece'
where business.name = 'POS Draft Test Business';

update draft_test_state set variant_id = (
  select (public.create_product_with_default_variant(
    business_id, 'Draft Product', 'goods', null, null, unit_id, null,
    '6101', true, false, 'Default', 'DRAFT-001', null, 25, 50, 0
  ) ->> 'variant_id')::uuid
  from draft_test_state
);
select is((select count(*) from public.products), 1::bigint, 'draft product is created');

create temporary table first_draft_result (result jsonb);
grant all on first_draft_result to authenticated;
insert into first_draft_result
select public.save_pos_draft(
  business_id, branch_id, warehouse_id, null,
  '36000000-0000-0000-0000-000000000001',
  'Tomorrow order', 'cash', 5,
  jsonb_build_array(jsonb_build_object('variant_id', variant_id, 'quantity', 2)),
  null
)
from draft_test_state;
update draft_test_state
set draft_id = (select (result ->> 'draft_id')::uuid from first_draft_result);

select ok(
  (select result ->> 'draft_id' is not null from first_draft_result),
  'saving a draft returns its identifier'
);
select is((select count(*) from public.pos_drafts), 1::bigint, 'sales draft is persisted');
select is((select count(*) from public.pos_draft_items), 1::bigint, 'draft item is persisted');
select is((select quantity from public.pos_draft_items), 2::numeric, 'draft quantity remains exact');
select is((select count(*) from public.inventory_movements), 0::bigint, 'saving a draft does not move stock');

select lives_ok(
  format(
    $$select public.save_pos_draft(%L, %L, %L, null, %L, 'Replay ignored', 'cash', 0,
      jsonb_build_array(jsonb_build_object('variant_id', %L, 'quantity', 1)), null)$$,
    (select business_id from draft_test_state),
    (select branch_id from draft_test_state),
    (select warehouse_id from draft_test_state),
    '36000000-0000-0000-0000-000000000001',
    (select variant_id from draft_test_state)
  ),
  'replaying the draft operation is idempotent'
);
select is((select count(*) from public.pos_drafts), 1::bigint, 'draft replay creates no duplicate');
select is((select quantity from public.pos_draft_items), 2::numeric, 'draft replay preserves original items');

select lives_ok(
  format(
    $$select public.save_pos_draft(%L, %L, %L, null, %L, 'Updated draft', 'wallet', 0,
      jsonb_build_array(jsonb_build_object('variant_id', %L, 'quantity', 3)), %L)$$,
    (select business_id from draft_test_state),
    (select branch_id from draft_test_state),
    (select warehouse_id from draft_test_state),
    '36000000-0000-0000-0000-000000000002',
    (select variant_id from draft_test_state),
    (select draft_id from draft_test_state)
  ),
  'an opened draft can be saved again atomically'
);
select is((select title from public.pos_drafts), 'Updated draft'::text, 'draft title is updated');
select is((select payment_method from public.pos_drafts), 'wallet'::text, 'draft payment method is updated');
select is((select quantity from public.pos_draft_items), 3::numeric, 'draft items are replaced atomically');
select is((select count(*) from public.inventory_movements), 0::bigint, 'updating a draft still does not move stock');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '35000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'draft-outsider@example.test', true);

select is((select count(*) from public.pos_drafts), 0::bigint, 'outsider cannot read drafts');
select throws_ok(
  format(
    $$select public.save_pos_draft(%L, %L, %L, null, gen_random_uuid(), 'Unauthorized', 'cash', 0,
      jsonb_build_array(jsonb_build_object('variant_id', %L, 'quantity', 1)), null)$$,
    (select business_id from draft_test_state),
    (select branch_id from draft_test_state),
    (select warehouse_id from draft_test_state),
    (select variant_id from draft_test_state)
  ),
  'P0001',
  'You do not have permission to save sales drafts',
  'outsider cannot save a draft in another tenant'
);
select throws_ok(
  format($$select public.delete_pos_draft(%L)$$, (select draft_id from draft_test_state)),
  'P0001',
  'You do not have permission to delete this sales draft',
  'outsider cannot delete another tenant draft'
);

reset role;
set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'anon', true);
select throws_ok(
  $$select public.delete_pos_draft(gen_random_uuid())$$,
  '42501',
  null,
  'anonymous callers cannot execute draft mutations'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '35000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'draft-owner@example.test', true);

select lives_ok(
  format($$select public.delete_pos_draft(%L)$$, (select draft_id from draft_test_state)),
  'authorized owner deletes a sales draft'
);
select is((select count(*) from public.pos_drafts), 0::bigint, 'delete removes the sales draft');
select is((select count(*) from public.pos_draft_items), 0::bigint, 'delete cascades to draft items');
select is(
  (select count(*) from public.tenant_audit_logs where action like 'pos.draft_%'),
  3::bigint,
  'save, update, and delete draft actions are audited'
);

select * from finish();
rollback;
