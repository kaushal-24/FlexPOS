-- Extended showcase data for optional operational screens.
-- Run after 20261103_showcase_dataset_core.sql and
-- 20261103_showcase_dataset_activity.sql.
-- All records are synthetic and limited to the two showcase businesses.

begin;
select set_config('request.jwt.claim.sub', '01331716-1fbd-4780-bc16-b4dba20a96aa', true);

do $$
declare
  b record;
  v_admin constant uuid := '01331716-1fbd-4780-bc16-b4dba20a96aa';
  v_cashier constant uuid := 'b19328a2-ac43-4291-8ff1-615d153b0b0f';
  v_manager constant uuid := '73558bcb-8f47-4e36-9c3e-2ff4f7f16d98';
begin
  for b in
    select * from (values
      ('7b000000-0000-4000-8000-000000000001'::uuid, 'Retail'),
      ('7b000000-0000-4000-8000-000000000002'::uuid, 'Cafe')
    ) as x(id, label)
  loop
    -- Branch price lists: every showcase variant has a visible retail price.
    insert into public.product_prices (
      id, business_id, variant_id, branch_id, price_type, amount,
      minimum_quantity, valid_from, valid_to, customer_group_id
    )
    select
      md5(b.id::text || '|price|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|variant|' || i::text)::uuid,
      case when i % 4 = 0 then null else md5(b.id::text || '|branch|' || (((i - 1) % 4) + 1)::text)::uuid end,
      case when i % 10 = 0 then 'customer_group' else 'retail' end,
      round((75 + ((i * 37) % 920))::numeric * case when i % 10 = 0 then 0.92 else 1 end, 2),
      case when i % 10 = 0 then 6 else 1 end,
      now() - interval '30 days',
      null,
      case when i % 10 = 0 then md5(b.id::text || '|group|' || (((i - 1) % 4) + 1)::text)::uuid else null end
    from generate_series(1, 124) as s(i)
    on conflict (id) do update set amount = excluded.amount, valid_from = excluded.valid_from;

    insert into public.unit_conversions (id, business_id, from_unit_id, to_unit_id, multiplier)
    select
      md5(b.id::text || '|conversion|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|unit|' || i::text)::uuid,
      md5(b.id::text || '|unit|' || (i + 1)::text)::uuid,
      case i when 1 then 1000 when 2 then 100 when 3 then 12 when 4 then 24 when 5 then 60 when 6 then 30 else 1 end
    from generate_series(1, 7) as s(i)
    on conflict (id) do update set multiplier = excluded.multiplier;

    -- Make the first catalog item a bundle parent so bundle-component screens
    -- have a valid, non-nested bundle to display.
    update public.products
    set product_type = 'bundle', track_inventory = false, updated_at = now()
    where business_id = b.id
      and id = md5(b.id::text || '|product|1')::uuid;

    insert into public.product_bundle_components (
      id, business_id, bundle_variant_id, component_variant_id, quantity
    )
    select
      md5(b.id::text || '|bundle-component|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|variant|1')::uuid,
      md5(b.id::text || '|variant|' || (i + 1)::text)::uuid,
      case when i % 3 = 0 then 2 else 1 end
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set quantity = excluded.quantity;

    -- Customer receipts and ledger entries demonstrate account-credit workflows.
    insert into public.customer_receipts (
      id, business_id, branch_id, customer_id, receipt_number, amount,
      payment_method, reference, notes, operation_id, received_by, received_at
    )
    select
      md5(b.id::text || '|customer-receipt|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|branch|' || (((i - 1) % 4) + 1)::text)::uuid,
      md5(b.id::text || '|customer|' || i::text)::uuid,
      format('%s-CR-%06s', upper(left(b.label, 3)), i),
      250 + (i * 15),
      case when i % 3 = 0 then 'upi' when i % 3 = 1 then 'cash' else 'bank_transfer' end,
      format('SHOWCASE-RECEIPT-%06s', i),
      'Synthetic customer credit repayment for review.',
      md5(b.id::text || '|customer-receipt-op|' || i::text)::uuid,
      case when i % 2 = 0 then v_cashier else v_admin end,
      now() - make_interval(days => i)
    from generate_series(1, 16) as s(i)
    on conflict (id) do update set amount = excluded.amount, notes = excluded.notes;

    insert into public.customer_receipt_allocations (
      id, business_id, receipt_id, sale_id, payment_id, amount
    )
    select
      md5(b.id::text || '|customer-receipt-allocation|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|customer-receipt|' || i::text)::uuid,
      md5(b.id::text || '|sale|' || i::text)::uuid,
      md5(b.id::text || '|payment|' || i::text)::uuid,
      250 + (i * 15)
    from generate_series(1, 16) as s(i)
    on conflict (id) do update set amount = excluded.amount;

    insert into public.customer_ledger_entries (
      id, business_id, branch_id, customer_id, entry_type, direction,
      amount, receipt_id, description, operation_id, created_by, occurred_at
    )
    select
      md5(b.id::text || '|customer-ledger|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|branch|' || (((i - 1) % 4) + 1)::text)::uuid,
      md5(b.id::text || '|customer|' || i::text)::uuid,
      'repayment', 'credit',
      250 + (i * 15),
      md5(b.id::text || '|customer-receipt|' || i::text)::uuid,
      format('Synthetic repayment for customer %s.', i),
      md5(b.id::text || '|customer-ledger-op|' || i::text)::uuid,
      v_admin,
      now() - make_interval(days => i)
    from generate_series(1, 16) as s(i)
    on conflict (id) do update set amount = excluded.amount;

    -- Returns, refunds, and exchanges make sales review screens demonstrable.
    insert into public.sale_returns (
      id, business_id, branch_id, sale_id, return_number, status,
      subtotal, discount_total, tax_total, refund_total, cost_total,
      reason, operation_id, returned_by, returned_at
    )
    select
      md5(b.id::text || '|return|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|branch|' || (((i - 1) % 4) + 1)::text)::uuid,
      md5(b.id::text || '|sale|' || (16 + i)::text)::uuid,
      format('%s-RET-%06s', upper(left(b.label, 3)), i),
      'completed', 100, 0, 18, 118, 60,
      case when i % 2 = 0 then 'Customer changed quantity' else 'Damaged packaging' end,
      md5(b.id::text || '|return-op|' || i::text)::uuid,
      case when i % 2 = 0 then v_manager else v_admin end,
      now() - make_interval(days => i)
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set reason = excluded.reason, refund_total = excluded.refund_total;

    insert into public.sale_return_items (
      id, business_id, return_id, sale_item_id, warehouse_id, variant_id,
      product_name, variant_name, sku, quantity, restocked, subtotal,
      discount_amount, tax_amount, line_total, unit_cost, cost_total
    )
    select
      md5(b.id::text || '|return-item|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|return|' || i::text)::uuid,
      md5(b.id::text || '|sale-item|' || (16 + i)::text)::uuid,
      md5(b.id::text || '|warehouse|1')::uuid,
      md5(b.id::text || '|variant|' || (16 + i)::text)::uuid,
      format('%s Showcase Product %s', b.label, 16 + i),
      'Standard',
      format('%s-SKU-%04s', upper(left(b.label, 3)), 16 + i),
      1, true, 100, 0, 18, 118, 60, 60
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set restocked = excluded.restocked, line_total = excluded.line_total;

    insert into public.sale_refunds (
      id, business_id, sale_id, return_id, payment_method, status,
      amount, reference, processed_by, processed_at
    )
    select
      md5(b.id::text || '|refund|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|sale|' || (16 + i)::text)::uuid,
      md5(b.id::text || '|return|' || i::text)::uuid,
      'cash', 'settled', 118,
      format('SHOWCASE-REFUND-%06s', i),
      v_admin,
      now() - make_interval(days => i)
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set status = excluded.status, amount = excluded.amount;

    insert into public.sale_exchanges (
      id, business_id, original_sale_id, sale_return_id, replacement_sale_id,
      exchange_number, refund_total, replacement_total, cash_difference,
      operation_id, reason, processed_by
    )
    select
      md5(b.id::text || '|exchange|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|sale|' || (16 + i)::text)::uuid,
      md5(b.id::text || '|return|' || i::text)::uuid,
      md5(b.id::text || '|sale|' || (32 + i)::text)::uuid,
      format('%s-EX-%06s', upper(left(b.label, 3)), i),
      118, 150, 32,
      md5(b.id::text || '|exchange-op|' || i::text)::uuid,
      'Synthetic exchange for demo review.',
      v_manager
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set cash_difference = excluded.cash_difference;

    -- POS working-state examples.
    insert into public.held_pos_carts (
      id, business_id, branch_id, warehouse_id, customer_id, label,
      payment_method, order_discount, operation_id, created_by, updated_by
    )
    select
      md5(b.id::text || '|held-cart|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|branch|' || (((i - 1) % 4) + 1)::text)::uuid,
      md5(b.id::text || '|warehouse|1')::uuid,
      md5(b.id::text || '|customer|' || i::text)::uuid,
      format('Held cart %s - %s', i, b.label),
      case when i % 2 = 0 then 'upi' else 'cash' end,
      case when i % 3 = 0 then 25 else 0 end,
      md5(b.id::text || '|held-cart-op|' || i::text)::uuid,
      v_cashier, v_cashier
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set label = excluded.label;

    insert into public.held_pos_cart_items (held_cart_id, business_id, variant_id, quantity)
    select
      md5(b.id::text || '|held-cart|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|variant|' || (i + 4)::text)::uuid,
      1 + (i % 3)
    from generate_series(1, 8) as s(i)
    on conflict (held_cart_id, variant_id) do update set quantity = excluded.quantity;

    insert into public.pos_drafts (
      id, business_id, branch_id, warehouse_id, customer_id, title,
      payment_method, order_discount, operation_id, created_by, updated_by
    )
    select
      md5(b.id::text || '|pos-draft|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|branch|' || (((i - 1) % 4) + 1)::text)::uuid,
      md5(b.id::text || '|warehouse|1')::uuid,
      md5(b.id::text || '|customer|' || (20 + i)::text)::uuid,
      format('Draft sale %s - %s', i, b.label),
      'cash', 0,
      md5(b.id::text || '|pos-draft-op|' || i::text)::uuid,
      v_cashier, v_cashier
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set title = excluded.title;

    insert into public.pos_draft_items (draft_id, business_id, variant_id, quantity)
    select
      md5(b.id::text || '|pos-draft|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|variant|' || (i + 12)::text)::uuid,
      1 + (i % 2)
    from generate_series(1, 8) as s(i)
    on conflict (draft_id, variant_id) do update set quantity = excluded.quantity;

    -- Quotes and orders are intentionally non-posting documents.
    insert into public.sales_quotes (
      id, business_id, branch_id, warehouse_id, customer_id, quote_number,
      title, status, valid_until, subtotal, discount_total, tax_total,
      grand_total, operation_id, created_by, updated_by
    )
    select
      md5(b.id::text || '|sales-quote|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|branch|' || (((i - 1) % 4) + 1)::text)::uuid,
      md5(b.id::text || '|warehouse|1')::uuid,
      md5(b.id::text || '|customer|' || (32 + i)::text)::uuid,
      format('%s-Q-%06s', upper(left(b.label, 3)), i),
      format('%s showcase quote %s', b.label, i),
      case when i % 9 = 0 then 'converted' when i % 7 = 0 then 'expired' when i % 5 = 0 then 'cancelled' else 'open' end,
      current_date + (15 + i), 500, 25, 85, 560,
      md5(b.id::text || '|sales-quote-op|' || i::text)::uuid,
      v_manager, v_manager
    from generate_series(1, 16) as s(i)
    on conflict (id) do update set status = excluded.status, grand_total = excluded.grand_total;

    insert into public.sales_quote_items (
      id, business_id, quote_id, variant_id, product_name, variant_name,
      sku, quantity, unit_price, discount_amount, tax_rate, tax_amount, line_total
    )
    select
      md5(b.id::text || '|sales-quote-item|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|sales-quote|' || i::text)::uuid,
      md5(b.id::text || '|variant|' || (40 + i)::text)::uuid,
      format('%s Showcase Product %s', b.label, 40 + i), 'Standard',
      format('%s-SKU-%04s', upper(left(b.label, 3)), 40 + i),
      2, 250, 25, 18, 85, 560
    from generate_series(1, 16) as s(i)
    on conflict (id) do update set line_total = excluded.line_total;

    insert into public.sales_orders (
      id, business_id, branch_id, warehouse_id, customer_id, order_number,
      title, status, requested_delivery_on, subtotal, order_discount,
      discount_total, tax_total, grand_total, operation_id, created_by, updated_by
    )
    select
      md5(b.id::text || '|sales-order|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|branch|' || (((i - 1) % 4) + 1)::text)::uuid,
      md5(b.id::text || '|warehouse|1')::uuid,
      md5(b.id::text || '|customer|' || (48 + i)::text)::uuid,
      format('%s-O-%06s', upper(left(b.label, 3)), i),
      format('%s showcase order %s', b.label, i),
      case when i % 5 = 0 then 'cancelled' else 'open' end,
      current_date + i, 800, 40, 40, 136, 896,
      md5(b.id::text || '|sales-order-op|' || i::text)::uuid,
      v_manager, v_manager
    from generate_series(1, 16) as s(i)
    on conflict (id) do update set status = excluded.status, grand_total = excluded.grand_total;

    insert into public.sales_order_items (
      id, business_id, order_id, variant_id, product_name, variant_name,
      sku, quantity, reserved_quantity, track_inventory, unit_price,
      discount_amount, tax_rate, tax_amount, line_total
    )
    select
      md5(b.id::text || '|sales-order-item|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|sales-order|' || i::text)::uuid,
      md5(b.id::text || '|variant|' || (60 + i)::text)::uuid,
      format('%s Showcase Product %s', b.label, 60 + i), 'Standard',
      format('%s-SKU-%04s', upper(left(b.label, 3)), 60 + i),
      2, case when (60 + i) % 10 = 0 then 0 else 2 end,
      case when (60 + i) % 10 = 0 then false else true end,
      400, 40, 18, 136, 896
    from generate_series(1, 16) as s(i)
    on conflict (id) do update set reserved_quantity = excluded.reserved_quantity;

    -- Gift cards are issued but not tied to real payment credentials.
    insert into public.gift_cards (
      id, business_id, issuing_branch_id, customer_id, code_hash, code_last_four,
      currency_code, initial_balance, current_balance, status, expires_at,
      operation_id, issued_by, issued_at, updated_at
    )
    select
      md5(b.id::text || '|gift-card|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|branch|' || (((i - 1) % 4) + 1)::text)::uuid,
      md5(b.id::text || '|customer|' || (70 + i)::text)::uuid,
      encode(digest(b.id::text || '|gift-card|' || i::text, 'sha256'), 'hex'),
      lpad(i::text, 4, '0'), 'INR', 1000, 1000, 'active', now() + interval '180 days',
      md5(b.id::text || '|gift-card-op|' || i::text)::uuid,
      v_admin, now() - make_interval(days => i), now()
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set current_balance = excluded.current_balance, status = excluded.status;

    insert into public.gift_card_transactions (
      id, business_id, gift_card_id, transaction_type, amount, balance_after,
      operation_id, actor_user_id
    )
    select
      md5(b.id::text || '|gift-card-tx|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|gift-card|' || i::text)::uuid,
      'issue', 1000, 1000,
      md5(b.id::text || '|gift-card-tx-op|' || i::text)::uuid,
      v_admin
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set balance_after = excluded.balance_after;

    insert into public.promotion_redemptions (
      id, business_id, promotion_id, sale_id, customer_id, operation_id,
      discount_amount, redeemed_at
    )
    select
      md5(b.id::text || '|promotion-redemption|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|promotion|' || i::text)::uuid,
      md5(b.id::text || '|sale|' || i::text)::uuid,
      md5(b.id::text || '|customer|' || i::text)::uuid,
      md5(b.id::text || '|promotion-redemption-op|' || i::text)::uuid,
      25 + i, now() - make_interval(days => i)
    from generate_series(1, 16) as s(i)
    on conflict (id) do update set discount_amount = excluded.discount_amount;
  end loop;
end $$;

commit;
