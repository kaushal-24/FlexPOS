-- Serialized-unit links used by sale, return, and transfer detail screens.

begin;
select set_config('request.jwt.claim.sub', '01331716-1fbd-4780-bc16-b4dba20a96aa', true);

do $$
declare
  b record;
begin
  for b in
    select * from (values
      ('7b000000-0000-4000-8000-000000000001'::uuid),
      ('7b000000-0000-4000-8000-000000000002'::uuid)
    ) as x(id)
  loop
    insert into public.sale_item_serialized_units (business_id, sale_item_id, serialized_unit_id)
    select
      b.id,
      md5(b.id::text || '|sale-item|2')::uuid,
      md5(b.id::text || '|serial-unit|' || i::text)::uuid
    from generate_series(1, 8) as s(i)
    on conflict do nothing;

    insert into public.sale_return_item_serialized_units (
      id, business_id, return_item_id, serialized_unit_id
    )
    select
      md5(b.id::text || '|return-serial-link|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|return-item|1')::uuid,
      md5(b.id::text || '|serial-unit|' || i::text)::uuid
    from generate_series(1, 8) as s(i)
    on conflict (id) do nothing;

    insert into public.inventory_transfer_serialized_units (
      business_id, transfer_id, serialized_unit_id, identifier,
      source_warehouse_id, destination_warehouse_id
    )
    select
      b.id,
      md5(b.id::text || '|transfer|1')::uuid,
      md5(b.id::text || '|serial-unit|' || i::text)::uuid,
      format('SN-%s-%06s', upper(left(case when b.id::text like '%001' then 'Retail' else 'Cafe' end, 3)), i),
      md5(b.id::text || '|warehouse|1')::uuid,
      md5(b.id::text || '|warehouse|2')::uuid
    from generate_series(1, 8) as s(i)
    on conflict do nothing;

    insert into public.inventory_transfer_request_serialized_units (
      business_id, request_id, serialized_unit_id, identifier,
      source_warehouse_id, destination_warehouse_id
    )
    select
      b.id,
      md5(b.id::text || '|transfer-request|1')::uuid,
      md5(b.id::text || '|serial-unit|' || i::text)::uuid,
      format('SN-%s-%06s', upper(left(case when b.id::text like '%001' then 'Retail' else 'Cafe' end, 3)), i),
      md5(b.id::text || '|warehouse|1')::uuid,
      md5(b.id::text || '|warehouse|2')::uuid
    from generate_series(1, 8) as s(i)
    on conflict do nothing;
  end loop;
end $$;

commit;
