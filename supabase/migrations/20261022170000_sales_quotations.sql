-- Non-posting sales quotations/estimates. Quotes snapshot commercial terms
-- but never reserve stock, create payments, or move inventory.

create table public.sales_quotes (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  warehouse_id uuid not null,
  customer_id uuid,
  quote_number text not null,
  title text not null check (length(btrim(title)) between 1 and 120),
  status text not null default 'open'
    check (status in ('open', 'cancelled', 'converted', 'expired')),
  valid_until date not null,
  subtotal numeric(18,2) not null check (subtotal >= 0),
  discount_total numeric(18,2) not null default 0 check (discount_total >= 0),
  tax_total numeric(18,2) not null default 0 check (tax_total >= 0),
  grand_total numeric(18,2) not null check (grand_total >= 0),
  operation_id uuid not null,
  converted_sale_id uuid,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, quote_number),
  unique (business_id, operation_id),
  constraint sales_quotes_branch_fkey foreign key (branch_id, business_id)
    references public.branches(id, business_id) on delete restrict,
  constraint sales_quotes_warehouse_fkey foreign key (warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete restrict,
  constraint sales_quotes_customer_fkey foreign key (customer_id, business_id)
    references public.customers(id, business_id) on delete restrict,
  constraint sales_quotes_converted_sale_fkey
    foreign key (converted_sale_id, business_id)
    references public.sales(id, business_id) on delete restrict
);

create table public.sales_quote_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  quote_id uuid not null,
  variant_id uuid not null,
  product_name text not null,
  variant_name text not null,
  sku text not null,
  quantity numeric(20,6) not null check (quantity > 0),
  unit_price numeric(18,4) not null check (unit_price >= 0),
  discount_amount numeric(18,2) not null default 0 check (discount_amount >= 0),
  tax_rate numeric(8,4) not null default 0 check (tax_rate between 0 and 100),
  tax_amount numeric(18,2) not null default 0 check (tax_amount >= 0),
  line_total numeric(18,2) not null check (line_total >= 0),
  note text,
  created_at timestamptz not null default now(),
  unique (quote_id, variant_id),
  constraint sales_quote_items_quote_fkey
    foreign key (quote_id, business_id)
    references public.sales_quotes(id, business_id) on delete cascade,
  constraint sales_quote_items_variant_fkey
    foreign key (variant_id, business_id)
    references public.product_variants(id, business_id) on delete restrict,
  constraint sales_quote_items_total_formula_check check (
    line_total = round(
      (quantity * unit_price) - discount_amount + tax_amount,
      2
    )
  )
);

create index sales_quotes_business_status_updated_idx
  on public.sales_quotes(business_id, status, updated_at desc);
create index sales_quotes_branch_business_fk_idx
  on public.sales_quotes(branch_id, business_id);
create index sales_quotes_warehouse_business_fk_idx
  on public.sales_quotes(warehouse_id, business_id);
create index sales_quotes_customer_business_fk_idx
  on public.sales_quotes(customer_id, business_id)
  where customer_id is not null;
create index sales_quotes_converted_sale_business_fk_idx
  on public.sales_quotes(converted_sale_id, business_id)
  where converted_sale_id is not null;
create index sales_quotes_created_by_idx on public.sales_quotes(created_by);
create index sales_quotes_updated_by_idx on public.sales_quotes(updated_by);
create index sales_quote_items_quote_business_fk_idx
  on public.sales_quote_items(quote_id, business_id);
create index sales_quote_items_variant_business_fk_idx
  on public.sales_quote_items(variant_id, business_id);

alter table public.sales_quotes enable row level security;
alter table public.sales_quote_items enable row level security;

create policy sales_quotes_select on public.sales_quotes
for select to authenticated
using (
  (select private.has_permission(business_id, 'sales.create'))
  and (select private.has_branch_access(branch_id))
);

create policy sales_quote_items_select on public.sales_quote_items
for select to authenticated
using (
  exists (
    select 1 from public.sales_quotes quote
    where quote.id = quote_id
      and quote.business_id = sales_quote_items.business_id
      and (select private.has_permission(quote.business_id, 'sales.create'))
      and (select private.has_branch_access(quote.branch_id))
  )
);

revoke all on public.sales_quotes, public.sales_quote_items
from public, anon, authenticated;
grant select on public.sales_quotes, public.sales_quote_items to authenticated;

create or replace function public.save_sales_quote(
  target_business_id uuid,
  target_branch_id uuid,
  target_warehouse_id uuid,
  target_customer_id uuid,
  operation_id uuid,
  quote_title text,
  quote_valid_until date,
  line_items jsonb,
  order_discount numeric default 0,
  target_quote_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  saved_quote_id uuid;
  existing_result record;
  quote_no text;
  line_record record;
  variant_record record;
  subtotal_amount numeric(18,2) := 0;
  line_discount_total numeric(18,2) := 0;
  tax_amount_total numeric(18,2) := 0;
  calculated_tax numeric(18,2);
  calculated_line_total numeric(18,2);
  grand_total_amount numeric(18,2);
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if jsonb_typeof(line_items) <> 'array' or jsonb_array_length(line_items) = 0 then
    raise exception 'At least one quotation item is required';
  end if;
  if length(btrim(coalesce(quote_title, ''))) not between 1 and 120 then
    raise exception 'Quotation title must be between 1 and 120 characters';
  end if;
  if quote_valid_until is null or quote_valid_until < current_date then
    raise exception 'Quotation validity cannot be in the past';
  end if;
  if coalesce(order_discount, 0) < 0 then
    raise exception 'Order discount cannot be negative';
  end if;
  if not private.has_permission(target_business_id, 'sales.create') then
    raise exception 'You do not have permission to create quotations';
  end if;
  if order_discount > 0
     and not private.has_permission(target_business_id, 'sales.discount') then
    raise exception 'You do not have permission to quote a discounted sale';
  end if;
  if not private.has_branch_access(target_branch_id) then
    raise exception 'Branch is not accessible';
  end if;
  if not exists (
    select 1 from public.warehouses warehouse
    where warehouse.id = target_warehouse_id
      and warehouse.business_id = target_business_id
      and warehouse.branch_id = target_branch_id
      and warehouse.is_active
  ) then raise exception 'Invalid warehouse for quotation'; end if;
  if target_customer_id is not null and not exists (
    select 1 from public.customers customer
    where customer.id = target_customer_id
      and customer.business_id = target_business_id
      and customer.is_active
      and customer.archived_at is null
  ) then raise exception 'Invalid customer for quotation'; end if;

  if target_quote_id is not null then
    select quote.id, quote.quote_number
    into saved_quote_id, quote_no
    from public.sales_quotes quote
    where quote.id = target_quote_id
      and quote.business_id = target_business_id
      and quote.status = 'open'
    for update;
    if not found then raise exception 'Open quotation not found'; end if;

    update public.sales_quotes
    set branch_id = target_branch_id,
        warehouse_id = target_warehouse_id,
        customer_id = target_customer_id,
        title = btrim(quote_title),
        valid_until = quote_valid_until,
        operation_id = save_sales_quote.operation_id,
        updated_by = caller_id,
        updated_at = now()
    where id = saved_quote_id;
    delete from public.sales_quote_items quote_item
    where quote_item.quote_id = saved_quote_id;
  else
    select quote.id, quote.quote_number, quote.title
    into existing_result
    from public.sales_quotes quote
    where quote.business_id = target_business_id
      and quote.operation_id = save_sales_quote.operation_id;
    if found then
      return jsonb_build_object(
        'quote_id', existing_result.id,
        'quote_number', existing_result.quote_number,
        'title', existing_result.title,
        'replayed', true
      );
    end if;

    saved_quote_id := gen_random_uuid();
    quote_no := 'QT-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS') || '-' ||
      upper(substr(replace(saved_quote_id::text, '-', ''), 1, 8));
    insert into public.sales_quotes (
      id, business_id, branch_id, warehouse_id, customer_id, quote_number,
      title, valid_until, subtotal, discount_total, tax_total, grand_total,
      operation_id, created_by, updated_by
    ) values (
      saved_quote_id, target_business_id, target_branch_id, target_warehouse_id,
      target_customer_id, quote_no, btrim(quote_title), quote_valid_until,
      0, 0, 0, 0, operation_id, caller_id, caller_id
    );
  end if;

  for line_record in
    select *
    from jsonb_to_recordset(line_items) as x(
      variant_id uuid, quantity numeric, unit_price numeric,
      discount_amount numeric, tax_rate numeric, note text
    )
    order by variant_id
  loop
    if line_record.variant_id is null
       or line_record.quantity is null or line_record.quantity <= 0
       or line_record.unit_price is null or line_record.unit_price < 0
       or coalesce(line_record.discount_amount, 0) < 0
       or coalesce(line_record.tax_rate, 0) < 0
       or coalesce(line_record.tax_rate, 0) > 100 then
      raise exception 'Invalid quotation line';
    end if;
    select variant.id, variant.name, variant.sku, product.name as product_name,
           product.allow_fractional_quantity
    into variant_record
    from public.product_variants variant
    join public.products product
      on product.id = variant.product_id
     and product.business_id = variant.business_id
    where variant.id = line_record.variant_id
      and variant.business_id = target_business_id
      and variant.is_active
      and variant.archived_at is null
      and product.is_active
      and product.archived_at is null;
    if not found then raise exception 'Quotation variant is unavailable'; end if;
    if not variant_record.allow_fractional_quantity
       and line_record.quantity <> trunc(line_record.quantity) then
      raise exception 'Fractional quantity is not allowed for quotation item';
    end if;
    if coalesce(line_record.discount_amount, 0) >
       line_record.quantity * line_record.unit_price then
      raise exception 'Quotation line discount exceeds line value';
    end if;

    calculated_tax := round(
      ((line_record.quantity * line_record.unit_price) -
        coalesce(line_record.discount_amount, 0)) *
      coalesce(line_record.tax_rate, 0) / 100,
      2
    );
    calculated_line_total := round(
      (line_record.quantity * line_record.unit_price) -
      coalesce(line_record.discount_amount, 0) + calculated_tax,
      2
    );
    subtotal_amount := subtotal_amount +
      round(line_record.quantity * line_record.unit_price, 2);
    line_discount_total := line_discount_total +
      round(coalesce(line_record.discount_amount, 0), 2);
    tax_amount_total := tax_amount_total + calculated_tax;

    insert into public.sales_quote_items (
      business_id, quote_id, variant_id, product_name, variant_name, sku,
      quantity, unit_price, discount_amount, tax_rate, tax_amount, line_total,
      note
    ) values (
      target_business_id, saved_quote_id, line_record.variant_id,
      variant_record.product_name, variant_record.name, variant_record.sku,
      round(line_record.quantity, 6), round(line_record.unit_price, 4),
      round(coalesce(line_record.discount_amount, 0), 2),
      round(coalesce(line_record.tax_rate, 0), 4), calculated_tax,
      calculated_line_total, nullif(btrim(line_record.note), '')
    );
  end loop;

  if round(coalesce(order_discount, 0), 2) >
     subtotal_amount - line_discount_total then
    raise exception 'Order discount exceeds quotation value';
  end if;
  grand_total_amount := round(
    subtotal_amount - line_discount_total -
    round(coalesce(order_discount, 0), 2) + tax_amount_total,
    2
  );
  update public.sales_quotes
  set subtotal = subtotal_amount,
      discount_total = line_discount_total +
        round(coalesce(save_sales_quote.order_discount, 0), 2),
      tax_total = tax_amount_total,
      grand_total = grand_total_amount
  where id = saved_quote_id;

  perform private.write_tenant_audit(
    target_business_id,
    case when target_quote_id is null then 'sales.quote_created' else 'sales.quote_updated' end,
    'sales_quote',
    saved_quote_id::text,
    jsonb_build_object('quote_number', quote_no, 'grand_total', grand_total_amount)
  );
  return jsonb_build_object(
    'quote_id', saved_quote_id,
    'quote_number', quote_no,
    'title', btrim(quote_title),
    'grand_total', grand_total_amount,
    'replayed', false
  );
end;
$$;

create or replace function public.cancel_sales_quote(target_quote_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  quote_record record;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select quote.id, quote.business_id, quote.branch_id, quote.quote_number,
         quote.status
  into quote_record
  from public.sales_quotes quote
  where quote.id = target_quote_id
  for update;
  if not found then return jsonb_build_object('cancelled', false); end if;
  if not private.has_permission(quote_record.business_id, 'sales.create')
     or not private.has_branch_access(quote_record.branch_id) then
    raise exception 'You do not have permission to cancel this quotation';
  end if;
  if quote_record.status <> 'open' then
    raise exception 'Only open quotations can be cancelled';
  end if;
  update public.sales_quotes
  set status = 'cancelled', updated_by = caller_id, updated_at = now()
  where id = quote_record.id;
  perform private.write_tenant_audit(
    quote_record.business_id, 'sales.quote_cancelled', 'sales_quote',
    quote_record.id::text,
    jsonb_build_object('quote_number', quote_record.quote_number)
  );
  return jsonb_build_object('cancelled', true);
end;
$$;

create or replace function public.convert_sales_quote(
  target_quote_id uuid,
  target_sale_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  quote_record record;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select quote.id, quote.business_id, quote.branch_id, quote.quote_number,
         quote.status
  into quote_record
  from public.sales_quotes quote
  where quote.id = target_quote_id
  for update;
  if not found then raise exception 'Quotation not found'; end if;
  if not private.has_permission(quote_record.business_id, 'sales.create')
     or not private.has_branch_access(quote_record.branch_id) then
    raise exception 'You do not have permission to convert this quotation';
  end if;
  if quote_record.status <> 'open' then
    raise exception 'Only open quotations can be converted';
  end if;
  if not exists (
    select 1 from public.sales sale
    where sale.id = target_sale_id
      and sale.business_id = quote_record.business_id
      and sale.branch_id = quote_record.branch_id
      and sale.status in ('completed', 'partially_refunded')
  ) then raise exception 'Converted sale is invalid for quotation'; end if;

  update public.sales_quotes
  set status = 'converted', converted_sale_id = target_sale_id,
      updated_by = caller_id, updated_at = now()
  where id = quote_record.id;
  perform private.write_tenant_audit(
    quote_record.business_id, 'sales.quote_converted', 'sales_quote',
    quote_record.id::text,
    jsonb_build_object(
      'quote_number', quote_record.quote_number,
      'sale_id', target_sale_id
    )
  );
  return jsonb_build_object('converted', true, 'sale_id', target_sale_id);
end;
$$;

revoke all on function public.save_sales_quote(
  uuid, uuid, uuid, uuid, uuid, text, date, jsonb, numeric, uuid
) from public, anon, authenticated;
grant execute on function public.save_sales_quote(
  uuid, uuid, uuid, uuid, uuid, text, date, jsonb, numeric, uuid
) to authenticated;

revoke all on function public.cancel_sales_quote(uuid)
from public, anon, authenticated;
grant execute on function public.cancel_sales_quote(uuid) to authenticated;

revoke all on function public.convert_sales_quote(uuid, uuid)
from public, anon, authenticated;
grant execute on function public.convert_sales_quote(uuid, uuid)
to authenticated;
