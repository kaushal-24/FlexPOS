-- Transactional service-charge verification. All fixtures roll back.
begin;

create extension if not exists pgtap with schema extensions;
select plan(12);

create temporary table service_charge_test_state (
  business_id uuid,
  branch_id uuid,
  unit_id uuid,
  warehouse_id uuid,
  register_id uuid,
  variant_id uuid,
  shift_id uuid,
  sale_id uuid
);
grant all on service_charge_test_state to authenticated;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  '56000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
  'service-charge-owner@example.test', '', now(), '{}', '{}', now(), now()
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '56000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.email', 'service-charge-owner@example.test', true);

select lives_ok(
  $$select public.create_business_with_branch(
    'Service Charge Test Business', 'retail', 'INR', 'Asia/Kolkata',
    'Main Branch', 'MAIN', 'IN'
  )$$,
  'owner creates a service-charge test tenant'
);

insert into service_charge_test_state (
  business_id, branch_id, unit_id, warehouse_id, register_id
)
select b.id, br.id, u.id, w.id, r.id
from public.businesses b
join public.branches br on br.business_id = b.id
join public.units u on u.business_id = b.id and u.name = 'Piece'
join public.warehouses w on w.business_id = b.id and w.branch_id = br.id and w.is_default
join public.registers r on r.business_id = b.id and r.branch_id = br.id
where b.name = 'Service Charge Test Business';

select ok(
  (select business_id is not null and branch_id is not null and warehouse_id is not null
   from service_charge_test_state),
  'onboarding creates the service-charge test scope'
);

update service_charge_test_state set variant_id = (
  select (result ->> 'variant_id')::uuid
  from (
    select public.create_product_with_default_variant(
      (select business_id from service_charge_test_state),
      'Service Charge Item', 'goods', null, null,
      (select unit_id from service_charge_test_state), null, 'SC-001', true, false,
      'Default', 'SC-001', '890000000002', 60, 100, 118
    ) result
  ) created
);

select lives_ok(
  format(
    $$select public.adjust_inventory(%L, %L, %L, 5, 'Opening stock', %L, 60)$$,
    (select business_id from service_charge_test_state),
    (select warehouse_id from service_charge_test_state),
    (select variant_id from service_charge_test_state),
    '56100000-0000-0000-0000-000000000001'::uuid
  ),
  'test item has stock'
);

update service_charge_test_state set shift_id = (
  select (result ->> 'shift_id')::uuid
  from (
    select public.open_register_shift(
      (select business_id from service_charge_test_state),
      (select register_id from service_charge_test_state), 500, 'Service charge shift'
    ) result
  ) opened
);

update service_charge_test_state set sale_id = (
  select (result ->> 'sale_id')::uuid
  from (
    select public.complete_sale(
      (select business_id from service_charge_test_state),
      (select branch_id from service_charge_test_state),
      (select register_id from service_charge_test_state),
      (select shift_id from service_charge_test_state), null,
      '56100000-0000-0000-0000-000000000002'::uuid,
      jsonb_build_array(jsonb_build_object(
        'variant_id', (select variant_id from service_charge_test_state),
        'warehouse_id', (select warehouse_id from service_charge_test_state),
        'quantity', 1, 'unit_price', 100, 'discount_amount', 0, 'tax_rate', 18
      )),
      jsonb_build_array(jsonb_build_object(
        'payment_method', 'cash', 'amount', 128, 'service_charge_amount', 10
      )),
      0, 'Service charge sale'
    ) result
  ) completed
);

select is(
  (select grand_total from public.sales where id = (select sale_id from service_charge_test_state)),
  128.00::numeric,
  'service charge is included in the authoritative grand total'
);
select is(
  (select service_charge_total from public.sales where id = (select sale_id from service_charge_test_state)),
  10.00::numeric,
  'service charge is persisted in the sale'
);
select is(
  (select sum(amount) from public.payments where sale_id = (select sale_id from service_charge_test_state)),
  128.00::numeric,
  'payment total includes the service charge'
);
select is(
  (select payment_status from public.sales where id = (select sale_id from service_charge_test_state)),
  'paid'::text,
  'cash sale with service charge is settled'
);
select is(
  (select quantity_on_hand from public.inventory_balances
   where warehouse_id = (select warehouse_id from service_charge_test_state)
     and variant_id = (select variant_id from service_charge_test_state)),
  4::numeric,
  'service charge does not affect item stock quantity'
);

update service_charge_test_state set sale_id = (
  select (result ->> 'sale_id')::uuid
  from (
    select public.complete_sale(
      (select business_id from service_charge_test_state),
      (select branch_id from service_charge_test_state),
      (select register_id from service_charge_test_state),
      (select shift_id from service_charge_test_state), null,
      '56100000-0000-0000-0000-000000000004'::uuid,
      jsonb_build_array(jsonb_build_object(
        'variant_id', (select variant_id from service_charge_test_state),
        'warehouse_id', (select warehouse_id from service_charge_test_state),
        'quantity', 1, 'unit_price', 100, 'discount_amount', 0, 'tax_rate', 18
      )),
      jsonb_build_array(jsonb_build_object(
        'payment_method', 'cash', 'amount', 116, 'rounding_amount', -2
      )),
      0, 'Cash rounding sale'
    ) result
  ) completed
);

select is(
  (select grand_total from public.sales where id = (select sale_id from service_charge_test_state)),
  116.00::numeric,
  'cash rounding adjusts the authoritative grand total'
);
select is(
  (select rounding_amount from public.sales where id = (select sale_id from service_charge_test_state)),
  -2.00::numeric,
  'cash rounding is persisted on the sale'
);
select is(
  (select sum(amount) from public.payments where sale_id = (select sale_id from service_charge_test_state)),
  116.00::numeric,
  'cash payment matches the rounded total'
);

select ok(
  (select count(*) = 1
   from public.role_permissions rp
   join public.roles r on r.id = rp.role_id
   where r.business_id = (select business_id from service_charge_test_state)
     and r.name = 'Owner'
     and rp.permission_code = 'sales.service_charge'),
  'onboarding grants the service-charge permission to the owner role'
);

select * from finish();
rollback;
