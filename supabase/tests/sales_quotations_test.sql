-- Non-posting quotation verification. All fixtures roll back.
begin;

create extension if not exists pgtap with schema extensions;
select plan(27);

create temporary table quote_test_state (
  business_id uuid,
  branch_id uuid,
  warehouse_id uuid,
  unit_id uuid,
  variant_id uuid,
  first_quote_id uuid,
  second_quote_id uuid,
  sale_id uuid
);
grant all on quote_test_state to authenticated;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '37000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'quote-owner@example.test', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '37000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'quote-outsider@example.test', '', now(), '{}', '{}', now(), now());

set local role authenticated;
select set_config('request.jwt.claim.sub', '37000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'quote-owner@example.test', true);

select lives_ok(
  $$select public.create_business_with_branch('Quotation Test Business', 'retail', 'INR', 'Asia/Kolkata', 'Main Branch', 'MAIN', 'IN')$$,
  'owner creates a quotation test tenant'
);

insert into quote_test_state (business_id, branch_id, warehouse_id, unit_id)
select business.id, branch.id, warehouse.id, unit_record.id
from public.businesses business
join public.branches branch on branch.business_id = business.id
join public.warehouses warehouse
  on warehouse.business_id = business.id and warehouse.branch_id = branch.id
join public.units unit_record
  on unit_record.business_id = business.id and unit_record.name = 'Piece'
where business.name = 'Quotation Test Business';

update quote_test_state set variant_id = (
  select (public.create_product_with_default_variant(
    business_id, 'Quotation Service', 'service', null, null, unit_id, null,
    '6201', false, false, 'Default', 'QUOTE-001', null, 25, 50, 0
  ) ->> 'variant_id')::uuid
  from quote_test_state
);
select is((select count(*) from public.products), 1::bigint, 'quotation product is created');

create temporary table first_quote_result (result jsonb);
grant all on first_quote_result to authenticated;
insert into first_quote_result
select public.save_sales_quote(
  business_id, branch_id, warehouse_id, null,
  '38000000-0000-0000-0000-000000000001',
  'October estimate', current_date + 30,
  jsonb_build_array(jsonb_build_object(
    'variant_id', variant_id, 'quantity', 2, 'unit_price', 50,
    'discount_amount', 0, 'tax_rate', 10
  )),
  5, null
)
from quote_test_state;
update quote_test_state
set first_quote_id = (
  select (result ->> 'quote_id')::uuid from first_quote_result
);

select ok((select result ->> 'quote_id' is not null from first_quote_result), 'saving a quotation returns its identifier');
select matches((select result ->> 'quote_number' from first_quote_result), '^QT-[0-9]{14}-[A-F0-9]{8}$', 'quotation number is generated');
select is((select count(*) from public.sales_quotes), 1::bigint, 'quotation is persisted');
select is((select count(*) from public.sales_quote_items), 1::bigint, 'quotation item is persisted');
select is((select subtotal from public.sales_quotes), 100::numeric, 'quotation subtotal is exact');
select is((select discount_total from public.sales_quotes), 5::numeric, 'quotation discount is exact');
select is((select tax_total from public.sales_quotes), 10::numeric, 'quotation tax is exact');
select is((select grand_total from public.sales_quotes), 105::numeric, 'quotation grand total is exact');
select is((select count(*) from public.inventory_movements), 0::bigint, 'quotation does not move inventory');

select lives_ok(
  format(
    $$select public.save_sales_quote(%L, %L, %L, null, %L, 'Replay ignored', current_date + 7,
      jsonb_build_array(jsonb_build_object('variant_id', %L, 'quantity', 1, 'unit_price', 1, 'tax_rate', 0)), 0, null)$$,
    (select business_id from quote_test_state),
    (select branch_id from quote_test_state),
    (select warehouse_id from quote_test_state),
    '38000000-0000-0000-0000-000000000001',
    (select variant_id from quote_test_state)
  ),
  'replaying a quotation operation is idempotent'
);
select is((select count(*) from public.sales_quotes), 1::bigint, 'quotation replay creates no duplicate');

select lives_ok(
  format(
    $$select public.save_sales_quote(%L, %L, %L, null, %L, 'Updated estimate', current_date + 45,
      jsonb_build_array(jsonb_build_object('variant_id', %L, 'quantity', 3, 'unit_price', 50, 'tax_rate', 10)), 0, %L)$$,
    (select business_id from quote_test_state),
    (select branch_id from quote_test_state),
    (select warehouse_id from quote_test_state),
    '38000000-0000-0000-0000-000000000002',
    (select variant_id from quote_test_state),
    (select first_quote_id from quote_test_state)
  ),
  'open quotation can be updated atomically'
);
select is((select title from public.sales_quotes), 'Updated estimate'::text, 'quotation title is updated');
select is((select grand_total from public.sales_quotes), 165::numeric, 'updated quotation total is exact');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '37000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'quote-outsider@example.test', true);

select is((select count(*) from public.sales_quotes), 0::bigint, 'outsider cannot read quotations');
select throws_ok(
  format(
    $$select public.save_sales_quote(%L, %L, %L, null, gen_random_uuid(), 'Unauthorized', current_date + 7,
      jsonb_build_array(jsonb_build_object('variant_id', %L, 'quantity', 1, 'unit_price', 1, 'tax_rate', 0)), 0, null)$$,
    (select business_id from quote_test_state),
    (select branch_id from quote_test_state),
    (select warehouse_id from quote_test_state),
    (select variant_id from quote_test_state)
  ),
  'P0001',
  'You do not have permission to create quotations',
  'outsider cannot create a quotation in another tenant'
);
select throws_ok(
  format($$select public.cancel_sales_quote(%L)$$, (select first_quote_id from quote_test_state)),
  'P0001',
  'You do not have permission to cancel this quotation',
  'outsider cannot cancel another tenant quotation'
);

reset role;
set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'anon', true);
select throws_ok(
  $$select public.cancel_sales_quote(gen_random_uuid())$$,
  '42501',
  null,
  'anonymous callers cannot execute quotation mutations'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '37000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'quote-owner@example.test', true);

create temporary table second_quote_result (result jsonb);
grant all on second_quote_result to authenticated;
insert into second_quote_result
select public.save_sales_quote(
  business_id, branch_id, warehouse_id, null,
  '38000000-0000-0000-0000-000000000003',
  'Convertible quote', current_date + 30,
  jsonb_build_array(jsonb_build_object(
    'variant_id', variant_id, 'quantity', 2, 'unit_price', 50,
    'discount_amount', 0, 'tax_rate', 10
  )),
  0, null
)
from quote_test_state;
update quote_test_state
set second_quote_id = (
  select (result ->> 'quote_id')::uuid from second_quote_result
);
select ok((select second_quote_id is not null from quote_test_state), 'second quotation is saved for conversion');

create temporary table quote_sale_result (result jsonb);
grant all on quote_sale_result to authenticated;
insert into quote_sale_result
select public.complete_sale(
  business_id, branch_id, null, null, null,
  '39000000-0000-0000-0000-000000000001',
  jsonb_build_array(jsonb_build_object(
    'variant_id', variant_id, 'warehouse_id', null, 'quantity', 2,
    'unit_price', 50, 'discount_amount', 0, 'tax_rate', 10
  )),
  jsonb_build_array(jsonb_build_object('payment_method', 'cash', 'amount', 110)),
  0, 'Converted quotation test'
)
from quote_test_state;
update quote_test_state
set sale_id = (select (result ->> 'sale_id')::uuid from quote_sale_result);
select ok((select sale_id is not null from quote_test_state), 'sale is completed for quotation conversion');

select lives_ok(
  format(
    $$select public.convert_sales_quote(%L, %L)$$,
    (select second_quote_id from quote_test_state),
    (select sale_id from quote_test_state)
  ),
  'open quotation converts to its completed sale'
);
select ok(
  (select status = 'converted' and converted_sale_id = sale_id
   from public.sales_quotes, quote_test_state
   where id = second_quote_id),
  'converted quotation links the completed sale'
);

select lives_ok(
  format($$select public.cancel_sales_quote(%L)$$, (select first_quote_id from quote_test_state)),
  'authorized owner cancels an open quotation'
);
select is(
  (select status from public.sales_quotes where id = (select first_quote_id from quote_test_state)),
  'cancelled'::text,
  'cancelled quotation retains its lifecycle record'
);
select is(
  (select count(*) from public.tenant_audit_logs where action like 'sales.quote_%'),
  5::bigint,
  'create, update, convert, and cancel quotation actions are audited'
);

select * from finish();
rollback;
