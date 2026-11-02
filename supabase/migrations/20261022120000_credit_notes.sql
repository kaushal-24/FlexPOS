-- FlexPOS credit notes: atomic return issuance and concurrency-safe redemption.

alter table public.payments
  drop constraint if exists payments_payment_method_check;
alter table public.payments
  add constraint payments_payment_method_check check (payment_method in (
    'cash', 'upi', 'card', 'bank_transfer', 'wallet', 'gift_card',
    'customer_credit', 'credit_note'
  ));

create table public.credit_notes (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  customer_id uuid,
  original_sale_id uuid not null,
  return_id uuid not null,
  credit_note_number text not null,
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  issued_amount numeric(18,2) not null check (issued_amount > 0),
  reason text not null check (length(btrim(reason)) between 3 and 500),
  operation_id uuid not null,
  issued_by uuid not null references auth.users(id) on delete restrict,
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '365 days'),
  created_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, credit_note_number),
  unique (business_id, operation_id),
  unique (return_id),
  constraint credit_notes_branch_fkey foreign key (branch_id, business_id)
    references public.branches(id, business_id) on delete restrict,
  constraint credit_notes_customer_fkey foreign key (customer_id, business_id)
    references public.customers(id, business_id) on delete restrict,
  constraint credit_notes_sale_fkey foreign key (original_sale_id, business_id)
    references public.sales(id, business_id) on delete restrict,
  constraint credit_notes_return_fkey foreign key (return_id, business_id)
    references public.sale_returns(id, business_id) on delete restrict,
  check (expires_at > issued_at)
);

create table public.credit_note_redemptions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  credit_note_id uuid not null,
  sale_id uuid not null,
  payment_id uuid not null references public.payments(id) on delete restrict,
  amount numeric(18,2) not null check (amount > 0),
  redeemed_by uuid not null references auth.users(id) on delete restrict,
  redeemed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (payment_id),
  constraint credit_note_redemptions_note_fkey
    foreign key (credit_note_id, business_id)
    references public.credit_notes(id, business_id) on delete restrict,
  constraint credit_note_redemptions_sale_fkey
    foreign key (sale_id, business_id)
    references public.sales(id, business_id) on delete restrict
);

create index credit_notes_branch_id_idx
  on public.credit_notes(branch_id, business_id);
create index credit_notes_customer_id_idx
  on public.credit_notes(customer_id, business_id)
  where customer_id is not null;
create index credit_notes_original_sale_business_idx
  on public.credit_notes(original_sale_id, business_id);
create index credit_notes_return_business_idx
  on public.credit_notes(return_id, business_id);
create index credit_notes_issued_by_idx on public.credit_notes(issued_by);
create index credit_notes_business_expiry_idx
  on public.credit_notes(business_id, expires_at, issued_at desc);
create index credit_note_redemptions_business_id_idx
  on public.credit_note_redemptions(business_id);
create index credit_note_redemptions_note_business_idx
  on public.credit_note_redemptions(credit_note_id, business_id);
create index credit_note_redemptions_sale_business_idx
  on public.credit_note_redemptions(sale_id, business_id);
create index credit_note_redemptions_redeemed_by_idx
  on public.credit_note_redemptions(redeemed_by);

create trigger credit_notes_immutable
before update or delete on public.credit_notes
for each row execute function private.prevent_immutable_change();

create trigger credit_note_redemptions_immutable
before update or delete on public.credit_note_redemptions
for each row execute function private.prevent_immutable_change();

create or replace function public.process_sale_credit_note_return(
  target_sale_id uuid,
  operation_id uuid,
  return_lines jsonb,
  return_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  sale_record public.sales%rowtype;
  item record;
  sale_item_record public.sale_items%rowtype;
  balance_record public.inventory_balances%rowtype;
  existing_result jsonb;
  inserted_count integer;
  return_id uuid := gen_random_uuid();
  credit_note_id uuid := gen_random_uuid();
  return_item_id uuid;
  return_no text;
  credit_note_no text;
  previously_returned numeric(20,6);
  previously_returned_subtotal numeric(18,2);
  previously_returned_discount numeric(18,2);
  previously_returned_tax numeric(18,2);
  previously_returned_cost numeric(18,2);
  quantity_to_return numeric(20,6);
  next_quantity numeric(20,6);
  line_ratio numeric;
  line_subtotal numeric(18,2);
  line_discount numeric(18,2);
  line_tax numeric(18,2);
  line_total_amount numeric(18,2);
  line_cost numeric(18,2);
  subtotal_amount numeric(18,2) := 0;
  line_discount_total numeric(18,2) := 0;
  tax_amount_total numeric(18,2) := 0;
  pre_order_total numeric(18,2) := 0;
  cost_amount_total numeric(18,2) := 0;
  original_line_discounts numeric(18,2);
  original_order_discount numeric(18,2);
  previously_allocated_order_discount numeric(18,2);
  order_discount_allocation numeric(18,2);
  remaining_order_discount numeric(18,2);
  original_pre_order_total numeric(18,2);
  credit_amount numeric(18,2);
  all_items_returned boolean := true;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if jsonb_typeof(return_lines) <> 'array' or jsonb_array_length(return_lines) = 0 then
    raise exception 'At least one return line is required';
  end if;
  if length(btrim(coalesce(return_reason, ''))) < 3 then
    raise exception 'A meaningful return reason is required';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(return_lines) as x(
      sale_item_id uuid, quantity numeric, restock boolean
    )
    group by x.sale_item_id
    having x.sale_item_id is null or count(*) > 1
  ) then
    raise exception 'Return lines must contain distinct sale items';
  end if;

  select * into sale_record
  from public.sales
  where id = target_sale_id
  for update;
  if not found then raise exception 'Sale not found'; end if;
  if not private.has_permission(sale_record.business_id, 'sales.refund') then
    raise exception 'Refund permission required';
  end if;
  if not private.has_branch_access(sale_record.branch_id) then
    raise exception 'Branch access required';
  end if;

  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (
    sale_record.business_id, operation_id, 'sale.credit_note', caller_id
  ) on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select result into existing_result
    from public.idempotency_records
    where business_id = sale_record.business_id
      and idempotency_records.operation_id = process_sale_credit_note_return.operation_id
      and operation_type = 'sale.credit_note';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Credit-note return is already in progress';
  end if;
  if sale_record.status not in ('completed', 'partially_refunded') then
    raise exception 'Sale is not eligible for return';
  end if;

  select coalesce(sum(si.discount_amount), 0),
         coalesce(sum((si.quantity * si.unit_price) - si.discount_amount), 0)
  into original_line_discounts, original_pre_order_total
  from public.sale_items si
  where si.sale_id = sale_record.id;
  original_order_discount := greatest(
    sale_record.discount_total - original_line_discounts, 0
  );
  select coalesce(sum(sr.discount_total - line_discounts.total), 0)
  into previously_allocated_order_discount
  from public.sale_returns sr
  cross join lateral (
    select coalesce(sum(sri.discount_amount), 0) as total
    from public.sale_return_items sri
    where sri.return_id = sr.id
  ) line_discounts
  where sr.sale_id = sale_record.id;
  remaining_order_discount := greatest(
    original_order_discount - previously_allocated_order_discount, 0
  );

  return_no := 'RT-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS') || '-'
    || upper(substr(replace(return_id::text, '-', ''), 1, 8));
  credit_note_no := 'CN-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS') || '-'
    || upper(substr(replace(credit_note_id::text, '-', ''), 1, 8));

  for item in
    select *
    from jsonb_to_recordset(return_lines) as x(
      sale_item_id uuid, quantity numeric, restock boolean
    )
    order by sale_item_id
  loop
    quantity_to_return := round(item.quantity, 6);
    if item.sale_item_id is null or quantity_to_return is null
       or quantity_to_return <= 0 then
      raise exception 'Invalid return line';
    end if;

    select * into sale_item_record
    from public.sale_items
    where id = item.sale_item_id and sale_id = sale_record.id
    for share;
    if not found then raise exception 'Sale item is not part of this sale'; end if;

    select coalesce(sum(sri.quantity), 0),
           coalesce(sum(sri.subtotal), 0),
           coalesce(sum(sri.discount_amount), 0),
           coalesce(sum(sri.tax_amount), 0),
           coalesce(sum(sri.cost_total), 0)
    into previously_returned, previously_returned_subtotal,
         previously_returned_discount, previously_returned_tax,
         previously_returned_cost
    from public.sale_return_items sri
    join public.sale_returns sr on sr.id = sri.return_id
    where sri.sale_item_id = sale_item_record.id
      and sr.status = 'completed';
    if quantity_to_return > sale_item_record.quantity - previously_returned then
      raise exception 'Return quantity exceeds the remaining quantity for SKU %',
        sale_item_record.sku;
    end if;
    if previously_returned + quantity_to_return < sale_item_record.quantity then
      all_items_returned := false;
    end if;

    if quantity_to_return = sale_item_record.quantity - previously_returned then
      line_subtotal := round(
        sale_item_record.quantity * sale_item_record.unit_price, 2
      ) - previously_returned_subtotal;
      line_discount := sale_item_record.discount_amount - previously_returned_discount;
      line_tax := sale_item_record.tax_amount - previously_returned_tax;
      line_cost := round(
        sale_item_record.quantity * sale_item_record.unit_cost, 2
      ) - previously_returned_cost;
    else
      line_ratio := quantity_to_return / sale_item_record.quantity;
      line_subtotal := round(
        sale_item_record.quantity * sale_item_record.unit_price * line_ratio, 2
      );
      line_discount := round(sale_item_record.discount_amount * line_ratio, 2);
      line_tax := round(sale_item_record.tax_amount * line_ratio, 2);
      line_cost := round(quantity_to_return * sale_item_record.unit_cost, 2);
    end if;
    line_total_amount := round(line_subtotal - line_discount + line_tax, 2);
    return_item_id := gen_random_uuid();

    insert into public.sale_return_items (
      id, business_id, return_id, sale_item_id, warehouse_id, variant_id,
      product_name, variant_name, sku, quantity, restocked, subtotal,
      discount_amount, tax_amount, line_total, unit_cost, cost_total
    ) values (
      return_item_id, sale_record.business_id, return_id, sale_item_record.id,
      sale_item_record.warehouse_id, sale_item_record.variant_id,
      sale_item_record.product_name, sale_item_record.variant_name,
      sale_item_record.sku, quantity_to_return, coalesce(item.restock, true),
      line_subtotal, line_discount, line_tax, line_total_amount,
      sale_item_record.unit_cost, line_cost
    );

    subtotal_amount := subtotal_amount + line_subtotal;
    line_discount_total := line_discount_total + line_discount;
    tax_amount_total := tax_amount_total + line_tax;
    pre_order_total := pre_order_total + line_subtotal - line_discount;
    cost_amount_total := cost_amount_total + line_cost;

    if coalesce(item.restock, true)
       and sale_item_record.warehouse_id is not null then
      select * into balance_record
      from public.inventory_balances ib
      where ib.warehouse_id = sale_item_record.warehouse_id
        and ib.variant_id = sale_item_record.variant_id
      for update;
      if not found then
        raise exception 'Inventory balance not found for returned item';
      end if;
      next_quantity := balance_record.quantity_on_hand + quantity_to_return;
      update public.inventory_balances
      set quantity_on_hand = next_quantity, updated_at = now()
      where warehouse_id = sale_item_record.warehouse_id
        and variant_id = sale_item_record.variant_id;
      insert into public.inventory_movements (
        business_id, warehouse_id, variant_id, movement_type, quantity_delta,
        quantity_before, quantity_after, unit_cost, reference_type, reference_id,
        reason, operation_id, created_by
      ) values (
        sale_record.business_id, sale_item_record.warehouse_id,
        sale_item_record.variant_id, 'sale_return', quantity_to_return,
        balance_record.quantity_on_hand, next_quantity,
        sale_item_record.unit_cost, 'sale_return', return_id,
        btrim(return_reason), return_item_id, caller_id
      );
    end if;
  end loop;

  if exists (
    select 1
    from public.sale_items si
    where si.sale_id = sale_record.id
      and si.id not in (
        select x.sale_item_id
        from jsonb_to_recordset(return_lines) as x(
          sale_item_id uuid, quantity numeric, restock boolean
        )
      )
      and coalesce((
        select sum(sri.quantity)
        from public.sale_return_items sri
        join public.sale_returns sr on sr.id = sri.return_id
        where sri.sale_item_id = si.id and sr.status = 'completed'
      ), 0) < si.quantity
  ) then
    all_items_returned := false;
  end if;

  order_discount_allocation := case
    when all_items_returned then remaining_order_discount
    when original_pre_order_total = 0 then 0
    else least(
      remaining_order_discount,
      round(original_order_discount * pre_order_total / original_pre_order_total, 2)
    )
  end;
  credit_amount := round(
    subtotal_amount - line_discount_total - order_discount_allocation
      + tax_amount_total,
    2
  );
  if credit_amount <= 0 then
    raise exception 'Return has no credit-note value';
  end if;

  insert into public.sale_returns (
    id, business_id, branch_id, sale_id, return_number,
    subtotal, discount_total, tax_total, refund_total, cost_total,
    reason, operation_id, returned_by
  ) values (
    return_id, sale_record.business_id, sale_record.branch_id, sale_record.id,
    return_no, subtotal_amount,
    line_discount_total + order_discount_allocation, tax_amount_total,
    credit_amount, cost_amount_total, btrim(return_reason), operation_id,
    caller_id
  );

  insert into public.credit_notes (
    id, business_id, branch_id, customer_id, original_sale_id, return_id,
    credit_note_number, currency_code, issued_amount, reason, operation_id,
    issued_by
  ) values (
    credit_note_id, sale_record.business_id, sale_record.branch_id,
    sale_record.customer_id, sale_record.id, return_id, credit_note_no,
    sale_record.currency_code, credit_amount, btrim(return_reason), operation_id,
    caller_id
  );

  update public.sales
  set status = case
        when all_items_returned then 'refunded' else 'partially_refunded'
      end,
      payment_status = case
        when all_items_returned then 'refunded' else 'partially_refunded'
      end
  where id = sale_record.id;

  existing_result := jsonb_build_object(
    'return_id', return_id,
    'return_number', return_no,
    'sale_id', sale_record.id,
    'refund_total', credit_amount,
    'credit_note_id', credit_note_id,
    'credit_note_number', credit_note_no,
    'credit_note_amount', credit_amount,
    'credit_note_expires_at', now() + interval '365 days',
    'settlement_method', 'credit_note',
    'sale_status', case
      when all_items_returned then 'refunded' else 'partially_refunded'
    end
  );
  update public.idempotency_records set result = existing_result
  where business_id = sale_record.business_id
    and idempotency_records.operation_id = process_sale_credit_note_return.operation_id
    and operation_type = 'sale.credit_note';
  perform private.write_tenant_audit(
    sale_record.business_id, 'sale.credit_note_issued', 'credit_note',
    credit_note_id::text,
    existing_result || jsonb_build_object('reason', btrim(return_reason))
  );
  return existing_result;
end;
$$;

create or replace function public.complete_sale_with_credit_note(
  target_business_id uuid,
  target_branch_id uuid,
  target_register_id uuid,
  target_shift_id uuid,
  target_customer_id uuid,
  operation_id uuid,
  line_items jsonb,
  target_credit_note_number text,
  credit_note_amount numeric,
  order_discount numeric default 0,
  sale_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  note_record public.credit_notes%rowtype;
  redeemed_total numeric(18,2);
  available_balance numeric(18,2);
  redemption_amount numeric(18,2) := round(credit_note_amount, 2);
  nested_result jsonb;
  existing_result jsonb;
  inserted_count integer;
  redeemed_sale_id uuid;
  payment_id uuid;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if nullif(btrim(target_credit_note_number), '') is null then
    raise exception 'Credit note number is required';
  end if;
  if redemption_amount is null or redemption_amount <= 0 then
    raise exception 'Credit note redemption amount must be greater than zero';
  end if;
  if not private.has_permission(target_business_id, 'sales.create') then
    raise exception 'You do not have permission to create sales';
  end if;
  if not private.has_branch_access(target_branch_id) then
    raise exception 'Branch is not accessible';
  end if;

  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (
    target_business_id, operation_id, 'sale.credit_note_redeem', caller_id
  ) on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select result into existing_result
    from public.idempotency_records ir
    where ir.business_id = target_business_id
      and ir.operation_id = complete_sale_with_credit_note.operation_id
      and ir.operation_type = 'sale.credit_note_redeem';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Credit-note redemption is already in progress';
  end if;

  select * into note_record
  from public.credit_notes cn
  where cn.business_id = target_business_id
    and upper(cn.credit_note_number) = upper(btrim(target_credit_note_number))
  for update;
  if not found then raise exception 'Credit note not found'; end if;
  if note_record.expires_at <= now() then raise exception 'Credit note has expired'; end if;
  if note_record.currency_code <> (
    select b.currency_code from public.businesses b
    where b.id = target_business_id
  ) then raise exception 'Credit note currency does not match the sale'; end if;
  if note_record.customer_id is not null
     and target_customer_id is distinct from note_record.customer_id then
    raise exception 'Credit note belongs to a different customer';
  end if;

  select coalesce(sum(cnr.amount), 0)
  into redeemed_total
  from public.credit_note_redemptions cnr
  where cnr.credit_note_id = note_record.id;
  available_balance := round(note_record.issued_amount - redeemed_total, 2);
  if redemption_amount > available_balance then
    raise exception 'Credit note balance is insufficient';
  end if;

  nested_result := public.complete_sale(
    target_business_id,
    target_branch_id,
    target_register_id,
    target_shift_id,
    target_customer_id,
    gen_random_uuid(),
    line_items,
    jsonb_build_array(jsonb_build_object(
      'payment_method', 'gift_card',
      'amount', redemption_amount,
      'reference', note_record.credit_note_number,
      'provider', 'credit_note'
    )),
    order_discount,
    sale_notes
  );
  redeemed_sale_id := (nested_result ->> 'sale_id')::uuid;

  select p.id into strict payment_id
  from public.payments p
  where p.sale_id = redeemed_sale_id
    and p.business_id = target_business_id
    and p.provider = 'credit_note'
  for update;

  update public.payments
  set payment_method = 'credit_note', status = 'settled', settled_at = now()
  where id = payment_id;

  update public.sales
  set payment_status = 'paid', paid_total = grand_total, due_total = 0
  where id = redeemed_sale_id;

  insert into public.credit_note_redemptions (
    business_id, credit_note_id, sale_id, payment_id, amount, redeemed_by
  ) values (
    target_business_id, note_record.id, redeemed_sale_id, payment_id,
    redemption_amount, caller_id
  );

  existing_result := nested_result || jsonb_build_object(
    'payment_status', 'paid',
    'credit_note_id', note_record.id,
    'credit_note_number', note_record.credit_note_number,
    'credit_note_redeemed', redemption_amount,
    'credit_note_balance', round(available_balance - redemption_amount, 2)
  );
  update public.idempotency_records ir set result = existing_result
  where ir.business_id = target_business_id
    and ir.operation_id = complete_sale_with_credit_note.operation_id
    and ir.operation_type = 'sale.credit_note_redeem';
  perform private.write_tenant_audit(
    target_business_id, 'credit_note.redeemed', 'credit_note',
    note_record.id::text,
    existing_result || jsonb_build_object('sale_id', redeemed_sale_id)
  );
  return existing_result;
end;
$$;

alter table public.credit_notes enable row level security;
alter table public.credit_note_redemptions enable row level security;

create policy credit_notes_select on public.credit_notes
for select to authenticated
using (
  (select private.has_permission(business_id, 'sales.view'))
  and (select private.has_branch_access(branch_id))
);

create policy credit_note_redemptions_select
on public.credit_note_redemptions
for select to authenticated
using (
  exists (
    select 1
    from public.credit_notes cn
    where cn.id = credit_note_redemptions.credit_note_id
      and cn.business_id = credit_note_redemptions.business_id
      and (select private.has_permission(cn.business_id, 'sales.view'))
      and (select private.has_branch_access(cn.branch_id))
  )
);

revoke all on public.credit_notes, public.credit_note_redemptions
  from public, anon, authenticated;
grant select on public.credit_notes, public.credit_note_redemptions
  to authenticated;

revoke all on function public.process_sale_credit_note_return(
  uuid, uuid, jsonb, text
) from public, anon, authenticated;
grant execute on function public.process_sale_credit_note_return(
  uuid, uuid, jsonb, text
) to authenticated;

revoke all on function public.complete_sale_with_credit_note(
  uuid, uuid, uuid, uuid, uuid, uuid, jsonb, text, numeric, numeric, text
) from public, anon, authenticated;
grant execute on function public.complete_sale_with_credit_note(
  uuid, uuid, uuid, uuid, uuid, uuid, jsonb, text, numeric, numeric, text
) to authenticated;
