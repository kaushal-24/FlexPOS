-- Permission-gated POS price overrides.
-- The normal sale path validates the catalog price. A line may only carry a
-- different price when the cashier has the existing sales.discount permission.

create or replace function private.assert_sale_line_prices(
  target_business_id uuid,
  target_branch_id uuid,
  target_customer_id uuid,
  line_items jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  line jsonb;
  line_variant_id uuid;
  requested_price numeric;
  expected_price numeric;
  override_requested boolean;
begin
  if jsonb_typeof(line_items) <> 'array' then
    raise exception 'Sale items must be an array';
  end if;

  for line in select value from jsonb_array_elements(line_items)
  loop
    begin
      line_variant_id := (line ->> 'variant_id')::uuid;
      requested_price := (line ->> 'unit_price')::numeric;
    exception when invalid_text_representation then
      raise exception 'Invalid sale line price or variant';
    end;
    override_requested := lower(coalesce(line ->> 'price_override', 'false')) = 'true';

    if line_variant_id is null or requested_price is null or requested_price < 0 then
      raise exception 'Invalid sale line price or variant';
    end if;

    if override_requested then
      if not private.has_permission(target_business_id, 'sales.discount') then
        raise exception 'You do not have permission to override sale prices';
      end if;
      continue;
    end if;

    select coalesce(
      (
        select pp.amount
        from public.product_prices pp
        where pp.business_id = target_business_id
          and pp.variant_id = line_variant_id
          and pp.price_type = 'customer'
          and pp.customer_id = target_customer_id
          and (pp.branch_id is null or pp.branch_id = target_branch_id)
          and pp.minimum_quantity <= 1
          and (pp.valid_from is null or pp.valid_from <= now())
          and (pp.valid_to is null or pp.valid_to > now())
        order by (pp.branch_id = target_branch_id) desc,
                 pp.valid_from desc nulls last, pp.created_at desc
        limit 1
      ),
      (
        select pp.amount
        from public.product_prices pp
        where pp.business_id = target_business_id
          and pp.variant_id = line_variant_id
          and pp.price_type = 'customer_group'
          and pp.customer_group_id = (
            select c.group_id
            from public.customers c
            where c.id = target_customer_id
              and c.business_id = target_business_id
          )
          and (pp.branch_id is null or pp.branch_id = target_branch_id)
          and pp.minimum_quantity <= 1
          and (pp.valid_from is null or pp.valid_from <= now())
          and (pp.valid_to is null or pp.valid_to > now())
        order by (pp.branch_id = target_branch_id) desc,
                 pp.valid_from desc nulls last, pp.created_at desc
        limit 1
      ),
      v.selling_price
    )
    into expected_price
    from public.product_variants v
    where v.id = line_variant_id
      and v.business_id = target_business_id
      and v.is_active
      and v.archived_at is null;

    if expected_price is null then
      raise exception 'Sale variant is inactive or unavailable';
    end if;
    if round(requested_price, 4) <> round(expected_price, 4) then
      raise exception 'The catalog price changed. Refresh the products and try again.';
    end if;
  end loop;
end;
$$;

create or replace function public.complete_sale_with_price_overrides(
  target_business_id uuid,
  target_branch_id uuid,
  target_register_id uuid,
  target_shift_id uuid,
  target_customer_id uuid,
  operation_id uuid,
  line_items jsonb,
  payment_lines jsonb,
  order_discount numeric default 0,
  sale_notes text default null,
  serialized_unit_ids jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if not private.has_permission(target_business_id, 'sales.create') then
    raise exception 'You do not have permission to create sales';
  end if;
  perform private.assert_sale_line_prices(
    target_business_id,
    target_branch_id,
    target_customer_id,
    line_items
  );
  return public.complete_sale(
    target_business_id,
    target_branch_id,
    target_register_id,
    target_shift_id,
    target_customer_id,
    operation_id,
    line_items,
    payment_lines,
    order_discount,
    sale_notes,
    serialized_unit_ids
  );
end;
$$;

revoke all on function private.assert_sale_line_prices(uuid, uuid, uuid, jsonb)
  from public, anon, authenticated;
revoke all on function public.complete_sale_with_price_overrides(
  uuid, uuid, uuid, uuid, uuid, uuid, jsonb, jsonb, numeric, text, jsonb
) from public, anon;
grant execute on function public.complete_sale_with_price_overrides(
  uuid, uuid, uuid, uuid, uuid, uuid, jsonb, jsonb, numeric, text, jsonb
) to authenticated;

-- Existing sale overloads remain available for backwards compatibility. The
-- POS client routes current sales through the guarded wrapper above; a later
-- breaking-security migration can revoke the legacy grants after all clients
-- have moved to the wrapper.
