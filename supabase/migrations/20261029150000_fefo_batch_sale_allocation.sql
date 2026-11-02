-- FEFO-aware depletion for non-serialized POS sales.
-- Applied only to flexpos-2 (gpbsblokhpydtpgxpwrg).

create or replace function public.complete_sale(
  target_business_id uuid,
  target_branch_id uuid,
  target_register_id uuid,
  target_shift_id uuid,
  target_customer_id uuid,
  operation_id uuid,
  line_items jsonb,
  payment_lines jsonb,
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
  business_currency text;
  existing_result jsonb;
  inserted_count integer;
  sale_id uuid := gen_random_uuid();
  invoice_no text;
  item record;
  payment record;
  variant_record record;
  balance_record public.inventory_balances%rowtype;
  batch_record public.inventory_batches%rowtype;
  batch_take_quantity numeric(20,6);
  remaining_batch_quantity numeric(20,6);
  batch_total_available numeric(20,6);
  untracked_available numeric(20,6);
  subtotal_amount numeric(18,2) := 0;
  line_discount_total numeric(18,2) := 0;
  tax_amount_total numeric(18,2) := 0;
  grand_total_amount numeric(18,2);
  payment_total numeric(18,2) := 0;
  settled_total numeric(18,2) := 0;
  calculated_tax numeric(18,2);
  calculated_line_total numeric(18,2);
  next_quantity numeric(20,6);
  all_payments_settled boolean := true;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if jsonb_typeof(line_items) <> 'array' or jsonb_array_length(line_items) = 0 then
    raise exception 'At least one sale item is required';
  end if;
  if jsonb_typeof(payment_lines) <> 'array' or jsonb_array_length(payment_lines) = 0 then
    raise exception 'At least one payment is required';
  end if;
  if coalesce(order_discount, 0) < 0 then raise exception 'Order discount cannot be negative'; end if;
  if not private.has_permission(target_business_id, 'sales.create') then
    raise exception 'You do not have permission to create sales';
  end if;
  if order_discount > 0 and not private.has_permission(target_business_id, 'sales.discount') then
    raise exception 'You do not have permission to apply discounts';
  end if;
  if not private.has_branch_access(target_branch_id) then raise exception 'Branch is not accessible'; end if;

  select currency_code into business_currency
  from public.businesses where id = target_business_id and archived_at is null;
  if not found then raise exception 'Business not found'; end if;
  if not exists (
    select 1 from public.branches b
    where b.id = target_branch_id and b.business_id = target_business_id
      and b.is_active and b.archived_at is null
  ) then raise exception 'Invalid branch'; end if;
  if target_register_id is not null and not exists (
    select 1 from public.registers r
    where r.id = target_register_id and r.business_id = target_business_id
      and r.branch_id = target_branch_id and r.is_active
  ) then raise exception 'Invalid register'; end if;
  if target_shift_id is not null and not exists (
    select 1 from public.register_shifts rs
    where rs.id = target_shift_id and rs.business_id = target_business_id
      and rs.register_id = target_register_id and rs.status = 'open'
  ) then raise exception 'A valid open register shift is required'; end if;
  if target_customer_id is not null and not exists (
    select 1 from public.customers c
    where c.id = target_customer_id and c.business_id = target_business_id
      and c.is_active and c.archived_at is null
  ) then raise exception 'Invalid customer'; end if;

  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (target_business_id, operation_id, 'sale.complete', caller_id)
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select result into existing_result
    from public.idempotency_records
    where business_id = target_business_id
      and idempotency_records.operation_id = complete_sale.operation_id
      and operation_type = 'sale.complete';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Sale operation is already in progress';
  end if;

  for item in
    select * from jsonb_to_recordset(line_items) as x(
      variant_id uuid, warehouse_id uuid, quantity numeric, unit_price numeric,
      discount_amount numeric, tax_rate numeric, note text
    ) order by variant_id, warehouse_id
  loop
    if item.variant_id is null or item.quantity is null or item.quantity <= 0
       or item.unit_price is null or item.unit_price < 0
       or coalesce(item.discount_amount, 0) < 0
       or coalesce(item.tax_rate, 0) < 0 or coalesce(item.tax_rate, 0) > 100 then
      raise exception 'Invalid sale line';
    end if;

    select v.id, v.name, v.sku, v.cost_price, p.name as product_name,
           p.track_inventory, p.allow_fractional_quantity, v.tracking_mode
    into variant_record
    from public.product_variants v
    join public.products p on p.id = v.product_id and p.business_id = v.business_id
    where v.id = item.variant_id and v.business_id = target_business_id
      and v.is_active and v.archived_at is null
      and p.is_active and p.archived_at is null;
    if not found then raise exception 'Sale variant is inactive or unavailable'; end if;
    if not variant_record.allow_fractional_quantity and item.quantity <> trunc(item.quantity) then
      raise exception 'Fractional quantity is not allowed for SKU %', variant_record.sku;
    end if;
    if coalesce(item.discount_amount, 0) > item.quantity * item.unit_price then
      raise exception 'Line discount exceeds line value';
    end if;

    if variant_record.track_inventory then
      if item.warehouse_id is null then raise exception 'Warehouse is required for stock items'; end if;
      if not exists (
        select 1 from public.warehouses w
        where w.id = item.warehouse_id and w.business_id = target_business_id
          and w.branch_id = target_branch_id and w.is_active
      ) then raise exception 'Invalid warehouse for sale branch'; end if;

      insert into public.inventory_balances (business_id, warehouse_id, variant_id)
      values (target_business_id, item.warehouse_id, item.variant_id)
      on conflict (warehouse_id, variant_id) do nothing;
      select * into balance_record
      from public.inventory_balances b
      where b.warehouse_id = item.warehouse_id and b.variant_id = item.variant_id
      for update;
      next_quantity := balance_record.quantity_on_hand - round(item.quantity, 6);
      if next_quantity < balance_record.quantity_reserved or next_quantity < 0 then
        raise exception 'Insufficient available stock for SKU %', variant_record.sku;
      end if;

      -- Non-serialized stock is depleted from the earliest active, non-expired
      -- batches first. Any remainder may use untracked stock, but recalled,
      -- blocked, and expired batch stock is never silently sold as untracked.
      if variant_record.tracking_mode = 'none'
         and exists (
           select 1
           from public.inventory_batches b
           where b.business_id = target_business_id
             and b.warehouse_id = item.warehouse_id
             and b.variant_id = item.variant_id
             and b.quantity_on_hand > b.quantity_reserved
         ) then
        remaining_batch_quantity := round(item.quantity, 6);

        for batch_record in
          select b.*
          from public.inventory_batches b
          where b.business_id = target_business_id
            and b.warehouse_id = item.warehouse_id
            and b.variant_id = item.variant_id
            and b.status = 'active'
            and b.quantity_on_hand > b.quantity_reserved
            and (b.expires_on is null or b.expires_on >= current_date)
          order by b.expires_on nulls last, b.expires_on, b.created_at, b.id
          for update
        loop
          exit when remaining_batch_quantity <= 0;
          batch_take_quantity := least(
            remaining_batch_quantity,
            batch_record.quantity_on_hand - batch_record.quantity_reserved
          );
          if batch_take_quantity <= 0 then
            continue;
          end if;

          update public.inventory_batches
          set quantity_on_hand = quantity_on_hand - batch_take_quantity,
              updated_at = now()
          where id = batch_record.id
            and business_id = target_business_id;

          insert into public.inventory_batch_movements (
            business_id, batch_id, warehouse_id, variant_id, movement_type,
            quantity_delta, quantity_before, quantity_after, unit_cost,
            reference_type, reference_id, operation_id, created_by
          ) values (
            target_business_id, batch_record.id, item.warehouse_id,
            item.variant_id, 'sale', -batch_take_quantity,
            batch_record.quantity_on_hand,
            batch_record.quantity_on_hand - batch_take_quantity,
            batch_record.average_cost, 'sale', sale_id, operation_id, caller_id
          );

          remaining_batch_quantity := remaining_batch_quantity - batch_take_quantity;
        end loop;

        if remaining_batch_quantity > 0 then
          select coalesce(sum(greatest(b.quantity_on_hand - b.quantity_reserved, 0)), 0)
          into batch_total_available
          from public.inventory_batches b
          where b.business_id = target_business_id
            and b.warehouse_id = item.warehouse_id
            and b.variant_id = item.variant_id;

          untracked_available := greatest(
            balance_record.quantity_on_hand
              - balance_record.quantity_reserved
              - batch_total_available,
            0
          );
          if remaining_batch_quantity > untracked_available then
            raise exception
              'Insufficient non-expired batch or untracked stock for SKU %',
              variant_record.sku;
          end if;
        end if;
      end if;

      update public.inventory_balances as ib
      set quantity_on_hand = next_quantity, updated_at = now()
      where ib.warehouse_id = item.warehouse_id
        and ib.variant_id = item.variant_id;
      insert into public.inventory_movements (
        business_id, warehouse_id, variant_id, movement_type, quantity_delta,
        quantity_before, quantity_after, unit_cost, reference_type, reference_id,
        reason, operation_id, created_by
      ) values (
        target_business_id, item.warehouse_id, item.variant_id, 'sale',
        -round(item.quantity, 6), balance_record.quantity_on_hand, next_quantity,
        variant_record.cost_price, 'sale', sale_id, 'POS sale', operation_id, caller_id
      );
    end if;

    calculated_tax := round(
      ((item.quantity * item.unit_price) - coalesce(item.discount_amount, 0))
      * coalesce(item.tax_rate, 0) / 100, 2
    );
    calculated_line_total := round(
      (item.quantity * item.unit_price) - coalesce(item.discount_amount, 0) + calculated_tax, 2
    );
    subtotal_amount := subtotal_amount + round(item.quantity * item.unit_price, 2);
    line_discount_total := line_discount_total + round(coalesce(item.discount_amount, 0), 2);
    tax_amount_total := tax_amount_total + calculated_tax;

    insert into public.sale_items (
      id, business_id, sale_id, variant_id, warehouse_id, product_name, variant_name,
      sku, quantity, unit_price, unit_cost, discount_amount, tax_rate, tax_amount,
      line_total, note
    ) values (
      gen_random_uuid(), target_business_id, sale_id, item.variant_id, item.warehouse_id,
      variant_record.product_name, variant_record.name, variant_record.sku,
      round(item.quantity, 6), round(item.unit_price, 4), variant_record.cost_price,
      round(coalesce(item.discount_amount, 0), 2), round(coalesce(item.tax_rate, 0), 4),
      calculated_tax, calculated_line_total, nullif(btrim(item.note), '')
    );
  end loop;

  if round(coalesce(order_discount, 0), 2) > subtotal_amount - line_discount_total then
    raise exception 'Order discount exceeds sale value';
  end if;
  grand_total_amount := round(
    subtotal_amount - line_discount_total - round(coalesce(order_discount, 0), 2) + tax_amount_total,
    2
  );

  for payment in
    select * from jsonb_to_recordset(payment_lines) as x(
      payment_method text, amount numeric, reference text, provider text
    )
  loop
    if payment.payment_method not in ('cash', 'upi', 'card', 'bank_transfer', 'wallet', 'gift_card', 'customer_credit')
       or payment.amount is null or payment.amount <= 0 then
      raise exception 'Invalid payment line';
    end if;
    payment_total := payment_total + round(payment.amount, 2);
    if payment.payment_method = 'cash' then
      settled_total := settled_total + round(payment.amount, 2);
    else
      all_payments_settled := false;
    end if;
  end loop;
  if payment_total <> grand_total_amount then
    raise exception 'Payments (%) must equal sale total (%)', payment_total, grand_total_amount;
  end if;

  invoice_no := 'FP-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS') || '-' || upper(substr(replace(sale_id::text, '-', ''), 1, 8));
  insert into public.sales (
    id, business_id, branch_id, register_id, shift_id, customer_id, invoice_number,
    sale_type, status, payment_status, currency_code, subtotal, discount_total,
    tax_total, grand_total, paid_total, due_total, notes, operation_id,
    completed_by, completed_at
  ) values (
    sale_id, target_business_id, target_branch_id, target_register_id, target_shift_id,
    target_customer_id, invoice_no, 'invoice', 'completed',
    case when all_payments_settled then 'paid' else 'pending' end,
    business_currency, subtotal_amount,
    line_discount_total + round(coalesce(order_discount, 0), 2), tax_amount_total,
    grand_total_amount, settled_total, greatest(grand_total_amount - settled_total, 0),
    nullif(btrim(sale_notes), ''), operation_id, caller_id, now()
  );

  for payment in
    select * from jsonb_to_recordset(payment_lines) as x(
      payment_method text, amount numeric, reference text, provider text
    )
  loop
    insert into public.payments (
      business_id, sale_id, payment_method, status, amount, reference, provider,
      received_by, settled_at
    ) values (
      target_business_id, sale_id, payment.payment_method,
      case when payment.payment_method = 'cash' then 'settled' else 'pending' end,
      round(payment.amount, 2), nullif(btrim(payment.reference), ''),
      nullif(btrim(payment.provider), ''), caller_id,
      case when payment.payment_method = 'cash' then now() else null end
    );
  end loop;

  existing_result := jsonb_build_object(
    'sale_id', sale_id, 'invoice_number', invoice_no,
    'grand_total', grand_total_amount,
    'payment_status', case when all_payments_settled then 'paid' else 'pending' end
  );
  update public.idempotency_records set result = existing_result
  where business_id = target_business_id
    and idempotency_records.operation_id = complete_sale.operation_id
    and operation_type = 'sale.complete';
  perform private.write_tenant_audit(
    target_business_id, 'sale.completed', 'sale', sale_id::text, existing_result
  );
  return existing_result;
end;
$$;


revoke all on function public.complete_sale(
  uuid, uuid, uuid, uuid, uuid, uuid, jsonb, jsonb, numeric, text
) from public, anon;
grant execute on function public.complete_sale(
  uuid, uuid, uuid, uuid, uuid, uuid, jsonb, jsonb, numeric, text
) to authenticated;

