-- Business-scoped coupons with atomic validation and redemption tracking.

insert into public.permissions (code, category, description)
values ('promotions.manage', 'Sales', 'Create and manage coupons and promotions')
on conflict (code) do update set
  category = excluded.category,
  description = excluded.description;

insert into public.role_permissions (role_id, permission_code)
select r.id, 'promotions.manage'
from public.roles r
where r.name in ('Owner', 'Administrator')
on conflict do nothing;

create table public.promotions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid,
  code text not null check (length(btrim(code)) between 1 and 64),
  name text not null check (length(btrim(name)) between 1 and 120),
  discount_type text not null check (discount_type in ('fixed', 'percentage')),
  discount_value numeric(18,4) not null check (discount_value > 0),
  minimum_subtotal numeric(18,2) not null default 0 check (minimum_subtotal >= 0),
  usage_limit bigint check (usage_limit is null or usage_limit > 0),
  redeemed_count bigint not null default 0 check (redeemed_count >= 0),
  starts_at timestamptz,
  ends_at timestamptz,
  is_active boolean not null default true,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, code),
  constraint promotions_branch_fkey
    foreign key (branch_id, business_id)
    references public.branches(id, business_id) on delete cascade,
  constraint promotions_percentage_value_check
    check (discount_type <> 'percentage' or discount_value <= 100),
  constraint promotions_dates_check
    check (ends_at is null or starts_at is null or ends_at > starts_at)
);

create table public.promotion_redemptions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  promotion_id uuid not null,
  sale_id uuid not null,
  customer_id uuid,
  operation_id uuid not null,
  discount_amount numeric(18,2) not null check (discount_amount > 0),
  redeemed_at timestamptz not null default now(),
  unique (promotion_id, sale_id),
  unique (business_id, operation_id),
  constraint promotion_redemptions_promotion_fkey
    foreign key (promotion_id, business_id)
    references public.promotions(id, business_id) on delete restrict,
  constraint promotion_redemptions_sale_fkey
    foreign key (sale_id, business_id)
    references public.sales(id, business_id) on delete restrict,
  constraint promotion_redemptions_customer_fkey
    foreign key (customer_id, business_id)
    references public.customers(id, business_id) on delete set null
);

alter table public.sales add column if not exists promotion_id uuid;

alter table public.sales
  drop constraint if exists sales_promotion_fkey;

alter table public.sales
  add constraint sales_promotion_fkey
  foreign key (promotion_id, business_id)
  references public.promotions(id, business_id) on delete set null;

create index promotions_business_active_idx
  on public.promotions(business_id, is_active, starts_at, ends_at);
create index promotions_branch_idx
  on public.promotions(business_id, branch_id)
  where branch_id is not null;
create index promotion_redemptions_promotion_idx
  on public.promotion_redemptions(business_id, promotion_id, redeemed_at desc);

alter table public.promotions enable row level security;
alter table public.promotion_redemptions enable row level security;

create policy promotions_select
on public.promotions for select to authenticated
using ((select private.has_permission(business_id, 'sales.view')));

create policy promotions_manage
on public.promotions for all to authenticated
using ((select private.has_permission(business_id, 'promotions.manage')))
with check ((select private.has_permission(business_id, 'promotions.manage')));

create policy promotion_redemptions_select
on public.promotion_redemptions for select to authenticated
using ((select private.has_permission(business_id, 'sales.view')));

revoke all on public.promotions, public.promotion_redemptions from anon;
grant select, insert, update, delete on public.promotions to authenticated;
grant select on public.promotion_redemptions to authenticated;

create trigger promotions_set_updated_at
before update on public.promotions
for each row execute function private.set_updated_at();

create or replace function public.complete_sale_with_coupon(
  target_business_id uuid,
  target_branch_id uuid,
  target_register_id uuid,
  target_shift_id uuid,
  target_customer_id uuid,
  operation_id uuid,
  line_items jsonb,
  payment_lines jsonb,
  coupon_code text,
  sale_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  existing_result jsonb;
  promotion_record public.promotions%rowtype;
  redemption_id uuid;
  sale_result jsonb;
  sale_id uuid;
  subtotal_amount numeric(18,2);
  discount_amount numeric(18,2);
  inserted_count integer;
  now_at timestamptz := now();
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if length(btrim(coalesce(coupon_code, ''))) = 0 then
    raise exception 'Coupon code is required';
  end if;

  select ir.result into existing_result
  from public.idempotency_records ir
  where ir.business_id = target_business_id
    and ir.operation_id = complete_sale_with_coupon.operation_id
    and ir.operation_type = 'sale.complete';
  if existing_result is not null and existing_result <> '{}'::jsonb then
    return existing_result;
  end if;

  if not private.has_permission(target_business_id, 'sales.create') then
    raise exception 'You do not have permission to create sales';
  end if;
  if not private.has_branch_access(target_branch_id) then
    raise exception 'Branch access required';
  end if;
  if jsonb_typeof(line_items) <> 'array' or jsonb_array_length(line_items) = 0 then
    raise exception 'At least one sale item is required';
  end if;

  select round(coalesce(sum(item.quantity * item.unit_price), 0), 2)
  into subtotal_amount
  from jsonb_to_recordset(line_items) as item(
    variant_id uuid, warehouse_id uuid, quantity numeric, unit_price numeric,
    discount_amount numeric, tax_rate numeric, note text
  );
  if subtotal_amount <= 0 then raise exception 'Sale subtotal must be positive'; end if;

  select * into promotion_record
  from public.promotions p
  where p.business_id = target_business_id
    and lower(p.code) = lower(btrim(coupon_code))
    and p.is_active
    and (p.branch_id is null or p.branch_id = target_branch_id)
  for update;
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
  if subtotal_amount < promotion_record.minimum_subtotal then
    raise exception 'Sale does not meet the coupon minimum subtotal';
  end if;

  discount_amount := case promotion_record.discount_type
    when 'fixed' then least(subtotal_amount, round(promotion_record.discount_value, 2))
    else least(
      subtotal_amount,
      round(subtotal_amount * promotion_record.discount_value / 100, 2)
    )
  end;
  if discount_amount <= 0 then raise exception 'Coupon discount is not applicable'; end if;

  sale_result := public.complete_sale(
    target_business_id,
    target_branch_id,
    target_register_id,
    target_shift_id,
    target_customer_id,
    operation_id,
    line_items,
    payment_lines,
    discount_amount,
    sale_notes
  );
  sale_id := (sale_result ->> 'sale_id')::uuid;

  insert into public.promotion_redemptions (
    business_id, promotion_id, sale_id, customer_id, operation_id, discount_amount
  ) values (
    target_business_id, promotion_record.id, sale_id, target_customer_id,
    operation_id, discount_amount
  ) on conflict (business_id, operation_id) do nothing
  returning id into redemption_id;
  get diagnostics inserted_count = row_count;
  if inserted_count = 1 then
    update public.promotions
    set redeemed_count = redeemed_count + 1
    where id = promotion_record.id and business_id = target_business_id;
    update public.sales
    set promotion_id = promotion_record.id
    where id = sale_id and business_id = target_business_id;
  end if;

  return sale_result || jsonb_build_object(
    'promotion_id', promotion_record.id,
    'promotion_code', promotion_record.code,
    'promotion_discount', discount_amount
  );
end;
$$;

revoke all on function public.complete_sale_with_coupon(
  uuid, uuid, uuid, uuid, uuid, uuid, jsonb, jsonb, text, text
) from public, anon, authenticated;
grant execute on function public.complete_sale_with_coupon(
  uuid, uuid, uuid, uuid, uuid, uuid, jsonb, jsonb, text, text
) to authenticated;

comment on table public.promotions is
  'Business-scoped coupon and promotion definitions used by atomic POS checkout.';
comment on table public.promotion_redemptions is
  'Immutable coupon redemption ledger tied to completed sales and idempotent operations.';
