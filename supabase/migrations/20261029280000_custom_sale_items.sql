-- POS custom service items for flexpos-2 (gpbsblokhpydtpgxpwrg).

insert into public.permissions (code, category, description)
values (
  'sales.custom_item',
  'Sales',
  'Create a one-off service item directly from POS checkout'
)
on conflict (code) do update set
  category = excluded.category,
  description = excluded.description;

insert into public.role_permissions (role_id, permission_code)
select r.id, 'sales.custom_item'
from public.roles r
where r.name in ('Owner', 'Administrator', 'Branch Manager', 'Cashier')
on conflict do nothing;

create or replace function public.create_custom_sale_item(
  target_business_id uuid,
  target_unit_id uuid,
  target_tax_rate_id uuid,
  item_name text,
  item_price numeric,
  operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  normalized_name text := btrim(coalesce(item_name, ''));
  normalized_price numeric := round(coalesce(item_price, 0), 4);
  existing_result jsonb;
  inserted_count integer;
  new_product_id uuid := gen_random_uuid();
  new_variant_id uuid := gen_random_uuid();
  generated_sku text := 'CUSTOM-' || upper(substr(replace(new_variant_id::text, '-', ''), 1, 12));
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if not private.has_permission(target_business_id, 'sales.custom_item') then
    raise exception 'Custom sale item permission required';
  end if;
  if char_length(normalized_name) not between 1 and 180 then
    raise exception 'Custom item name must be between 1 and 180 characters';
  end if;
  if normalized_price <= 0 or normalized_price > 1000000000 then
    raise exception 'Custom item price must be greater than zero';
  end if;
  if not exists (
    select 1 from public.businesses b
    where b.id = target_business_id and b.archived_at is null
  ) then
    raise exception 'Business not found';
  end if;
  if not exists (
    select 1 from public.units u
    where u.id = target_unit_id and u.business_id = target_business_id and u.is_active
  ) then
    raise exception 'Invalid unit';
  end if;
  if target_tax_rate_id is not null and not exists (
    select 1 from public.tax_rates t
    where t.id = target_tax_rate_id and t.business_id = target_business_id
      and t.is_active
  ) then
    raise exception 'Invalid tax rate';
  end if;

  select record.result into existing_result
  from public.idempotency_records record
  where record.business_id = target_business_id
    and record.operation_id = create_custom_sale_item.operation_id
    and record.operation_type = 'sale.custom_item';
  if existing_result is not null and existing_result <> '{}'::jsonb then
    return existing_result;
  end if;

  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (
    target_business_id, operation_id, 'sale.custom_item', caller_id
  )
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select record.result into existing_result
    from public.idempotency_records record
    where record.business_id = target_business_id
      and record.operation_id = create_custom_sale_item.operation_id
      and record.operation_type = 'sale.custom_item';
    if existing_result is not null and existing_result <> '{}'::jsonb then
      return existing_result;
    end if;
    raise exception 'Custom item operation is already in progress';
  end if;

  insert into public.products (
    id, business_id, base_unit_id, tax_rate_id, name, product_type,
    track_inventory, allow_fractional_quantity, created_by
  ) values (
    new_product_id, target_business_id, target_unit_id, target_tax_rate_id,
    normalized_name, 'service', false, false, caller_id
  );

  insert into public.product_variants (
    id, business_id, product_id, name, sku, cost_price, selling_price
  ) values (
    new_variant_id, target_business_id, new_product_id, 'Custom', generated_sku,
    0, normalized_price
  );

  existing_result := jsonb_build_object(
    'product_id', new_product_id,
    'variant_id', new_variant_id,
    'sku', generated_sku,
    'name', normalized_name,
    'price', normalized_price
  );
  update public.idempotency_records record
  set result = existing_result
  where record.business_id = target_business_id
    and record.operation_id = create_custom_sale_item.operation_id
    and record.operation_type = 'sale.custom_item';

  perform private.write_tenant_audit(
    target_business_id,
    'sale.custom_item_created',
    'product',
    new_product_id::text,
    existing_result
  );
  return existing_result;
end;
$$;

revoke all on function public.create_custom_sale_item(uuid, uuid, uuid, text, numeric, uuid)
from public, anon, authenticated, service_role;
grant execute on function public.create_custom_sale_item(uuid, uuid, uuid, text, numeric, uuid)
to authenticated;
