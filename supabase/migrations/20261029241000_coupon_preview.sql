-- Read-only promotion preview for POS payment totals; checkout revalidates atomically.

create or replace function public.preview_coupon(
  target_business_id uuid,
  target_branch_id uuid,
  coupon_code text,
  subtotal_amount numeric
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  promotion_record public.promotions%rowtype;
  discount_amount numeric(18,2);
  now_at timestamptz := now();
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not private.has_permission(target_business_id, 'sales.create') then
    raise exception 'You do not have permission to create sales';
  end if;
  if not private.has_branch_access(target_branch_id) then
    raise exception 'Branch access required';
  end if;
  if subtotal_amount is null or subtotal_amount <= 0 then
    raise exception 'Sale subtotal must be positive';
  end if;

  select * into promotion_record
  from public.promotions p
  where p.business_id = target_business_id
    and lower(p.code) = lower(btrim(coupon_code))
    and p.is_active
    and (p.branch_id is null or p.branch_id = target_branch_id);
  if not found then raise exception 'Coupon is invalid or inactive'; end if;
  if promotion_record.starts_at is not null and now_at < promotion_record.starts_at then
    raise exception 'Coupon is not active yet';
  end if;
  if promotion_record.ends_at is not null and now_at >= promotion_record.ends_at then
    raise exception 'Coupon has expired';
  end if;
  if promotion_record.usage_limit is not null
     and promotion_record.redeemed_count >= promotion_record.usage_limit then
    raise exception 'Coupon usage limit reached';
  end if;
  if round(subtotal_amount, 2) < promotion_record.minimum_subtotal then
    raise exception 'Sale does not meet the coupon minimum subtotal';
  end if;

  discount_amount := case promotion_record.discount_type
    when 'fixed' then least(round(subtotal_amount, 2), round(promotion_record.discount_value, 2))
    else least(round(subtotal_amount, 2), round(subtotal_amount * promotion_record.discount_value / 100, 2))
  end;
  if discount_amount <= 0 then raise exception 'Coupon discount is not applicable'; end if;
  return jsonb_build_object(
    'promotion_id', promotion_record.id,
    'promotion_code', promotion_record.code,
    'promotion_name', promotion_record.name,
    'discount_type', promotion_record.discount_type,
    'discount_amount', discount_amount
  );
end;
$$;

revoke all on function public.preview_coupon(uuid, uuid, text, numeric)
from public, anon, authenticated;
grant execute on function public.preview_coupon(uuid, uuid, text, numeric)
to authenticated;
