-- Transaction, purchasing, CRM, accounting, reporting, industry, and
-- enterprise data for the two showcase businesses.
-- Run after 20261103_showcase_dataset_core.sql.

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
      ('7b000000-0000-4000-8000-000000000001'::uuid, 'Retail', 'Bengaluru'),
      ('7b000000-0000-4000-8000-000000000002'::uuid, 'Cafe', 'Pune')
    ) as x(id, label, city)
  loop
    insert into public.sales (
      id, business_id, branch_id, register_id, shift_id, customer_id,
      invoice_number, sale_type, status, payment_status, currency_code,
      subtotal, discount_total, tax_total, service_charge_total,
      rounding_amount, grand_total, paid_total, due_total, notes,
      operation_id, completed_by, completed_at, promotion_id
    )
    select
      md5(b.id::text || '|sale|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|branch|' || (((i - 1) % 4) + 1)::text)::uuid,
      null,
      null,
      md5(b.id::text || '|customer|' || (((i - 1) % 124) + 1)::text)::uuid,
      format('%s-%s', case when b.label = 'Retail' then 'FSR' else 'FSC' end, lpad(i::text, 6, '0')),
      'invoice',
      case when i % 17 = 0 then 'refunded' else 'completed' end,
      case when i % 17 = 0 then 'refunded' when i % 13 = 0 then 'partially_paid' else 'paid' end,
      'INR',
      calc.subtotal,
      calc.discount,
      calc.tax,
      0,
      0,
      calc.grand_total,
      case when i % 13 = 0 then round(calc.grand_total / 2, 2) else calc.grand_total end,
      case when i % 13 = 0 then round(calc.grand_total - round(calc.grand_total / 2, 2), 2) else 0 end,
      format('Showcase sale %s for review dashboards.', i),
      md5(b.id::text || '|sale-op|' || i::text)::uuid,
      case when i % 3 = 0 then v_manager else v_cashier end,
      now() - make_interval(days => i % 120),
      null
    from generate_series(1, 124) as s(i)
    cross join lateral (
      select
        round((75 + ((i * 37) % 920))::numeric * (1 + (i % 3)), 2) as subtotal,
        case when i % 10 = 0 then 20 else 0 end::numeric as discount,
        round(((75 + ((i * 37) % 920))::numeric * (1 + (i % 3)) - case when i % 10 = 0 then 20 else 0 end) * case when i % 4 = 0 then 0.18 else 0.05 end, 2) as tax,
        round((75 + ((i * 37) % 920))::numeric * (1 + (i % 3)) - case when i % 10 = 0 then 20 else 0 end + (((75 + ((i * 37) % 920))::numeric * (1 + (i % 3)) - case when i % 10 = 0 then 20 else 0 end) * case when i % 4 = 0 then 0.18 else 0.05 end), 2) as grand_total
    ) calc
    on conflict (id) do update set
      status = excluded.status,
      payment_status = excluded.payment_status,
      grand_total = excluded.grand_total,
      paid_total = excluded.paid_total,
      due_total = excluded.due_total;

    insert into public.sale_items (
      id, business_id, sale_id, variant_id, warehouse_id, product_name,
      variant_name, sku, quantity, unit_price, unit_cost, discount_amount,
      tax_rate, tax_amount, line_total, note
    )
    select
      md5(b.id::text || '|sale-item|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|sale|' || i::text)::uuid,
      md5(b.id::text || '|variant|' || i::text)::uuid,
      md5(b.id::text || '|warehouse|1')::uuid,
      format('%s Showcase Product %s', b.label, lpad(i::text, 3, '0')),
      case when i % 10 = 0 then 'Standard service' else 'Standard pack' end,
      format('%s-%s', upper(left(b.label, 3)), lpad(i::text, 5, '0')),
      1 + (i % 3),
      75 + ((i * 37) % 920),
      35 + ((i * 17) % 420),
      case when i % 10 = 0 then 20 else 0 end,
      case when i % 4 = 0 then 18 else 5 end,
      round((((75 + ((i * 37) % 920))::numeric * (1 + (i % 3)) - case when i % 10 = 0 then 20 else 0 end) * case when i % 4 = 0 then 0.18 else 0.05 end), 2),
      round((((75 + ((i * 37) % 920))::numeric * (1 + (i % 3)) - case when i % 10 = 0 then 20 else 0 end) + (((75 + ((i * 37) % 920))::numeric * (1 + (i % 3)) - case when i % 10 = 0 then 20 else 0 end) * case when i % 4 = 0 then 0.18 else 0.05 end)), 2),
      case when i % 16 = 0 then 'Seasonal promotion applied.' else null end
    from generate_series(1, 124) as s(i)
    on conflict (id) do nothing;

    insert into public.payments (
      id, business_id, sale_id, payment_method, status, amount, reference,
      provider, provider_payload, received_by, settled_at
    )
    select
      md5(b.id::text || '|payment|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|sale|' || i::text)::uuid,
      case when i % 4 = 0 then 'upi' else 'cash' end,
      case when i % 17 = 0 then 'refunded' when i % 13 = 0 then 'pending' else 'settled' end,
      case when i % 13 = 0 then round((75 + ((i * 37) % 920))::numeric * (1 + (i % 3)) / 2, 2)
        else round((75 + ((i * 37) % 920))::numeric * (1 + (i % 3)) - case when i % 10 = 0 then 20 else 0 end + (((75 + ((i * 37) % 920))::numeric * (1 + (i % 3)) - case when i % 10 = 0 then 20 else 0 end) * case when i % 4 = 0 then 0.18 else 0.05 end), 2) end,
      format('%s-PAY-%06s', case when b.label = 'Retail' then 'FSR' else 'FSC' end, i),
      case when i % 4 = 0 then 'razorpay' else null end,
      jsonb_build_object('mode', 'test', 'provider', case when i % 4 = 0 then 'razorpay' else 'cash' end, 'showcase', true),
      case when i % 3 = 0 then v_manager else v_cashier end,
      case when i % 13 = 0 then null else now() - make_interval(days => i % 120) end
    from generate_series(1, 124) as s(i)
    on conflict (id) do nothing;

    insert into public.expense_categories (id, business_id, name, description)
    select
      md5(b.id::text || '|expense-category|' || i::text)::uuid,
      b.id,
      (array['Showcase Rent and facilities','Showcase Logistics','Showcase Marketing','Showcase People and training','Showcase Utilities','Showcase Technology'])[i],
      'Synthetic showcase expense category.'
    from generate_series(1, 6) as s(i)
    on conflict (id) do update set name = excluded.name, description = excluded.description;

    insert into public.expenses (
      id, business_id, branch_id, category_id, expense_number, entry_type,
      amount, tax_amount, payment_method, vendor_name, reference, notes,
      incurred_on, operation_id, created_by, approval_status, approved_by,
      approved_at, approval_note
    )
    select
      md5(b.id::text || '|expense|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|branch|' || (((i - 1) % 4) + 1)::text)::uuid,
      md5(b.id::text || '|expense-category|' || (((i - 1) % 6) + 1)::text)::uuid,
      format('%s-EXP-%06s', upper(left(b.label, 3)), i),
      'expense',
      round((850 + ((i * 113) % 28000))::numeric, 2),
      round((850 + ((i * 113) % 28000))::numeric * 0.05, 2),
      (array['cash','upi','bank_transfer'])[1 + ((i - 1) % 3)],
      format('%s Facilities Vendor %s', b.label, i),
      format('%s-REF-%06s', upper(left(b.label, 3)), i),
      'Synthetic operating expense for management review.',
      current_date - (i % 120),
      md5(b.id::text || '|expense-op|' || i::text)::uuid,
      v_admin,
      case when i % 7 = 0 then 'rejected' when i % 5 = 0 then 'pending' else 'approved' end,
      case when i % 7 = 0 or i % 5 = 0 then null else v_admin end,
      case when i % 7 = 0 or i % 5 = 0 then null else now() - make_interval(days => i % 60) end,
      case when i % 7 = 0 then 'Rejected for showcase workflow.' else null end
    from generate_series(1, 124) as s(i)
    on conflict (id) do nothing;

    insert into public.purchase_orders (
      id, business_id, branch_id, warehouse_id, supplier_id, order_number,
      supplier_reference, status, currency_code, subtotal, tax_total,
      grand_total, expected_at, notes, operation_id, created_by, ordered_at,
      completed_at
    )
    select
      md5(b.id::text || '|purchase-order|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|branch|' || (((i - 1) % 4) + 1)::text)::uuid,
      md5(b.id::text || '|warehouse|1')::uuid,
      md5(b.id::text || '|supplier|' || i::text)::uuid,
      format('%s-PO-%06s', upper(left(b.label, 3)), i),
      format('SUP-REF-%06s', i),
      case when i % 6 = 0 then 'received' when i % 5 = 0 then 'partially_received' when i % 11 = 0 then 'cancelled' else 'ordered' end,
      'INR',
      round((20 + (i % 70))::numeric * (35 + ((i * 17) % 420)), 2),
      round((20 + (i % 70))::numeric * (35 + ((i * 17) % 420)) * 0.05, 2),
      round((20 + (i % 70))::numeric * (35 + ((i * 17) % 420)) * 1.05, 2),
      now() + make_interval(days => (i % 25) - 8),
      'Synthetic purchase order for supplier and inventory review.',
      md5(b.id::text || '|purchase-op|' || i::text)::uuid,
      v_manager,
      now() - make_interval(days => i % 90),
      case when i % 6 = 0 then now() - make_interval(days => i % 30) else null end
    from generate_series(1, 124) as s(i)
    on conflict (id) do update set status = excluded.status, grand_total = excluded.grand_total;

    insert into public.purchase_order_items (
      id, business_id, purchase_order_id, variant_id, product_name,
      variant_name, sku, ordered_quantity, received_quantity, unit_cost,
      tax_rate, tax_amount, line_total
    )
    select
      md5(b.id::text || '|purchase-item|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|purchase-order|' || i::text)::uuid,
      md5(b.id::text || '|variant|' || i::text)::uuid,
      format('%s Showcase Product %s', b.label, lpad(i::text, 3, '0')),
      case when i % 10 = 0 then 'Standard service' else 'Standard pack' end,
      format('%s-%s', upper(left(b.label, 3)), lpad(i::text, 5, '0')),
      20 + (i % 70),
      case when i % 6 = 0 then 20 + (i % 70) when i % 5 = 0 then round((20 + (i % 70)) / 2, 0) else 0 end,
      35 + ((i * 17) % 420),
      5,
      round((20 + (i % 70))::numeric * (35 + ((i * 17) % 420)) * 0.05, 2),
      round((20 + (i % 70))::numeric * (35 + ((i * 17) % 420)) * 1.05, 2)
    from generate_series(1, 124) as s(i)
    on conflict (id) do nothing;

    insert into public.goods_receipts (
      id, business_id, purchase_order_id, warehouse_id, receipt_number,
      supplier_document_number, status, total_cost, operation_id, notes,
      received_by, received_at
    )
    select
      md5(b.id::text || '|goods-receipt|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|purchase-order|' || i::text)::uuid,
      md5(b.id::text || '|warehouse|1')::uuid,
      format('%s-GRN-%06s', upper(left(b.label, 3)), i),
      format('SUP-INV-%06s', i),
      'completed',
      round((20 + (i % 70))::numeric * (35 + ((i * 17) % 420)), 2),
      md5(b.id::text || '|goods-receipt-op|' || i::text)::uuid,
      'Synthetic receipt for supplier delivery review.',
      v_manager,
      now() - make_interval(days => i % 30)
    from generate_series(1, 124) as s(i)
    where i % 6 = 0 or i % 5 = 0
    on conflict (id) do nothing;

    insert into public.goods_receipt_items (
      id, business_id, goods_receipt_id, purchase_order_item_id, variant_id,
      quantity, unit_cost, line_total
    )
    select
      md5(b.id::text || '|goods-receipt-item|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|goods-receipt|' || i::text)::uuid,
      md5(b.id::text || '|purchase-item|' || i::text)::uuid,
      md5(b.id::text || '|variant|' || i::text)::uuid,
      case when i % 6 = 0 then 20 + (i % 70) else round((20 + (i % 70)) / 2, 0) end,
      35 + ((i * 17) % 420),
      round((case when i % 6 = 0 then 20 + (i % 70) else round((20 + (i % 70)) / 2, 0) end)::numeric * (35 + ((i * 17) % 420)), 2)
    from generate_series(1, 124) as s(i)
    where i % 6 = 0 or i % 5 = 0
    on conflict (id) do nothing;

    insert into public.crm_leads (
      id, business_id, salesperson_id, customer_id, title, source, status,
      estimated_value, expected_close_at, notes, created_by
    )
    select
      md5(b.id::text || '|lead|' || i::text)::uuid,
      b.id,
      case when i % 3 = 0 then v_manager else v_admin end,
      md5(b.id::text || '|customer|' || i::text)::uuid,
      format('%s account expansion opportunity %s', b.label, i),
      (array['website','referral','walk-in','campaign','partner'])[1 + ((i - 1) % 5)],
      (array['new','contacted','qualified','unqualified','converted','lost'])[1 + ((i - 1) % 6)],
      25000 + (i * 1750),
      current_date + (i % 60),
      'Synthetic CRM lead for pipeline review.',
      v_admin
    from generate_series(1, 124) as s(i)
    on conflict (id) do update set status = excluded.status, estimated_value = excluded.estimated_value;

    insert into public.crm_opportunities (
      id, business_id, salesperson_id, customer_id, lead_id, title, stage,
      probability, value_minor, expected_close_at, actual_close_at, notes,
      created_by
    )
    select
      md5(b.id::text || '|opportunity|' || i::text)::uuid,
      b.id,
      case when i % 3 = 0 then v_manager else v_admin end,
      md5(b.id::text || '|customer|' || i::text)::uuid,
      md5(b.id::text || '|lead|' || i::text)::uuid,
      format('%s pipeline opportunity %s', b.label, i),
      (array['prospecting','qualification','proposal','negotiation','closed_won','closed_lost'])[1 + ((i - 1) % 6)],
      (i * 7) % 101,
      350000 + (i * 24500),
      current_date + (i % 75),
      case when i % 6 = 5 then current_date - (i % 20) else null end,
      'Synthetic opportunity for CRM analytics.',
      v_admin
    from generate_series(1, 124) as s(i)
    on conflict (id) do update set stage = excluded.stage, probability = excluded.probability;

    insert into public.crm_quotations (
      id, business_id, salesperson_id, customer_id, opportunity_id,
      quotation_number, title, status, subtotal_minor, tax_minor,
      discount_minor, grand_total_minor, valid_until, notes, created_by
    )
    select
      md5(b.id::text || '|quotation|' || i::text)::uuid,
      b.id,
      case when i % 3 = 0 then v_manager else v_admin end,
      md5(b.id::text || '|customer|' || i::text)::uuid,
      md5(b.id::text || '|opportunity|' || i::text)::uuid,
      format('%s-QUO-%06s', upper(left(b.label, 3)), i),
      format('%s commercial proposal %s', b.label, i),
      (array['draft','sent','accepted','rejected','expired','converted'])[1 + ((i - 1) % 6)],
      350000 + (i * 24500),
      round((350000 + (i * 24500)) * 0.05),
      case when i % 10 = 0 then 10000 else 0 end,
      round((350000 + (i * 24500)) + ((350000 + (i * 24500)) * 0.05) - case when i % 10 = 0 then 10000 else 0 end),
      current_date + 30 + (i % 60),
      'Synthetic quotation for CRM and review presentations.',
      v_admin
    from generate_series(1, 124) as s(i)
    on conflict (id) do update set status = excluded.status, grand_total_minor = excluded.grand_total_minor;

    insert into public.crm_follow_ups (
      id, business_id, salesperson_id, lead_id, opportunity_id, quotation_id,
      title, type, due_at, completed_at, notes, created_by
    )
    select
      md5(b.id::text || '|followup|' || i::text)::uuid,
      b.id,
      case when i % 3 = 0 then v_manager else v_admin end,
      md5(b.id::text || '|lead|' || i::text)::uuid,
      md5(b.id::text || '|opportunity|' || i::text)::uuid,
      md5(b.id::text || '|quotation|' || i::text)::uuid,
      format('Follow up for showcase account %s', i),
      (array['call','email','meeting','visit','other'])[1 + ((i - 1) % 5)],
      now() + make_interval(days => (i % 30) - 8),
      case when i % 4 = 0 then now() - make_interval(days => i % 15) else null end,
      'Synthetic CRM activity note.',
      v_admin
    from generate_series(1, 124) as s(i)
    on conflict (id) do update set due_at = excluded.due_at, completed_at = excluded.completed_at;

    insert into public.crm_customer_notes (
      id, business_id, salesperson_id, customer_id, note, is_private, created_by
    )
    select
      md5(b.id::text || '|crm-note|' || i::text)::uuid,
      b.id,
      case when i % 3 = 0 then v_manager else v_admin end,
      md5(b.id::text || '|customer|' || i::text)::uuid,
      format('Customer preference and service note %s for showcase review.', i),
      i % 4 = 0,
      v_admin
    from generate_series(1, 124) as s(i)
    on conflict (id) do update set note = excluded.note, is_private = excluded.is_private;

    insert into public.crm_reminders (
      id, business_id, salesperson_id, title, description, due_at,
      is_completed, completed_at, related_table, related_id, created_by
    )
    select
      md5(b.id::text || '|crm-reminder|' || i::text)::uuid,
      b.id,
      case when i % 3 = 0 then v_manager else v_admin end,
      format('Review pipeline item %s', i),
      'Synthetic reminder for showcase review.',
      now() + make_interval(days => (i % 45) - 10),
      i % 5 = 0,
      case when i % 5 = 0 then now() - make_interval(days => i % 10) else null end,
      'opportunity',
      md5(b.id::text || '|opportunity|' || i::text)::uuid,
      v_admin
    from generate_series(1, 124) as s(i)
    on conflict (id) do update set is_completed = excluded.is_completed, completed_at = excluded.completed_at;

    insert into public.promotions (
      id, business_id, branch_id, code, name, discount_type, discount_value,
      minimum_subtotal, usage_limit, redeemed_count, starts_at, ends_at,
      is_active, created_by
    )
    select
      md5(b.id::text || '|promotion|' || i::text)::uuid,
      b.id,
      case when i % 2 = 0 then md5(b.id::text || '|branch|' || (((i - 1) % 4) + 1)::text)::uuid else null end,
      format('%s%04s', case when b.label = 'Retail' then 'RETAIL' else 'CAFE' end, i),
      format('%s Showcase Offer %s', b.label, i),
      case when i % 2 = 0 then 'percentage' else 'fixed' end,
      case when i % 2 = 0 then 5 + (i % 16) else 50 + (i * 10) end,
      250 + (i * 25),
      20 + i,
      i % 8,
      now() - interval '30 days',
      now() + interval '90 days',
      true,
      v_admin
    from generate_series(1, 124) as s(i)
    on conflict (id) do update set discount_value = excluded.discount_value, is_active = true;

    insert into public.inventory_stock_alert_notifications (
      id, business_id, warehouse_id, variant_id, severity, status,
      quantity_on_hand, quantity_reserved, available_quantity, target_stock,
      suggested_order_quantity, average_cost
    )
    select
      md5(b.id::text || '|stock-alert|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|warehouse|1')::uuid,
      md5(b.id::text || '|variant|' || i::text)::uuid,
      case when i % 13 = 0 then 'out_of_stock' when i % 3 = 0 then 'below_safety_stock' else 'reorder_point' end,
      case when i % 7 = 0 then 'acknowledged' else 'open' end,
      case when i % 13 = 0 then 0 else 4 + (i % 9) end,
      case when i % 13 = 0 then 0 else (i % 3) end,
      case when i % 13 = 0 then 0 else greatest(4 + (i % 9) - (i % 3), 0) end,
      18 + (i % 24),
      greatest(18 + (i % 24) - case when i % 13 = 0 then 0 else 4 + (i % 9) - (i % 3) end, 0),
      35 + ((i * 17) % 420)
    from generate_series(1, 124) as s(i)
    on conflict (id) do update set status = excluded.status, available_quantity = excluded.available_quantity;

    insert into public.accounting_accounts (id, business_id, code, name, account_type, is_system)
    select
      md5(b.id::text || '|account|' || i::text)::uuid,
      b.id,
      format('%s%02s', case i when 1 then '10' when 2 then '20' when 3 then '30' when 4 then '40' when 5 then '50' else '60' end, i),
      (array['Cash and bank','Accounts payable','Owner equity','Sales revenue','Cost of goods sold','Operating expenses'])[i],
      (array['asset','liability','equity','revenue','expense','expense'])[i],
      false
    from generate_series(1, 6) as s(i)
    on conflict (business_id, code) do update set name = excluded.name, account_type = excluded.account_type;

    insert into public.accounting_journal_entries (
      id, business_id, entry_number, entry_date, source_type, source_id,
      memo, status, created_by
    )
    select
      md5(b.id::text || '|journal-entry|' || i::text)::uuid,
      b.id,
      format('%s-JE-%06s', upper(left(b.label, 3)), i),
      current_date - (i % 120),
      'sale',
      md5(b.id::text || '|sale|' || i::text)::uuid,
      format('Showcase journal entry for sale %s.', i),
      'posted',
      v_admin
    from generate_series(1, 124) as s(i)
    on conflict (id) do update set memo = excluded.memo, status = excluded.status;

    insert into public.accounting_journal_lines (
      id, business_id, journal_entry_id, account_id, branch_id, description,
      debit, credit
    )
    select
      md5(b.id::text || '|journal-line|' || i::text || '|debit')::uuid,
      b.id,
      md5(b.id::text || '|journal-entry|' || i::text)::uuid,
      md5(b.id::text || '|account|1')::uuid,
      md5(b.id::text || '|branch|' || (((i - 1) % 4) + 1)::text)::uuid,
      format('Cash debit for showcase sale %s.', i),
      round(100 + (i * 37), 2),
      0
    from generate_series(1, 124) as s(i)
    on conflict (id) do nothing;

    insert into public.accounting_journal_lines (
      id, business_id, journal_entry_id, account_id, branch_id, description,
      debit, credit
    )
    select
      md5(b.id::text || '|journal-line|' || i::text || '|credit')::uuid,
      b.id,
      md5(b.id::text || '|journal-entry|' || i::text)::uuid,
      md5(b.id::text || '|account|4')::uuid,
      md5(b.id::text || '|branch|' || (((i - 1) % 4) + 1)::text)::uuid,
      format('Revenue credit for showcase sale %s.', i),
      0,
      round(100 + (i * 37), 2)
    from generate_series(1, 124) as s(i)
    on conflict (id) do nothing;

    insert into public.industry_workflows (
      id, business_id, branch_id, module_code, workflow_kind, reference_code,
      title, status, customer_id, product_id, assigned_to, scheduled_at, due_at,
      quantity, unit_price, total_amount, deposit_amount, payload, created_by,
      updated_by
    )
    select
      md5(b.id::text || '|industry|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|branch|' || (((i - 1) % 4) + 1)::text)::uuid,
      case when b.label = 'Cafe' then 'restaurant_operations' else 'grocery_operations' end,
      case when b.label = 'Cafe' then (array['restaurant_table','dine_in_order','takeaway_order','kitchen_ticket'])[1 + ((i - 1) % 4)] else (array['barcode_checkout','weight_sale','inventory_batch','customer_delivery'])[1 + ((i - 1) % 4)] end,
      format('%s-WF-%06s', upper(left(b.label, 3)), i),
      format('%s showcase workflow %s', b.label, i),
      (array['planned','open','in_progress','ready','completed','cancelled'])[1 + ((i - 1) % 6)],
      md5(b.id::text || '|customer|' || (((i - 1) % 124) + 1)::text)::uuid,
      md5(b.id::text || '|product|' || (((i - 1) % 124) + 1)::text)::uuid,
      case when i % 3 = 0 then v_manager else v_cashier end,
      now() + make_interval(days => i % 30),
      now() + make_interval(days => (i % 30) + 2),
      1 + (i % 8),
      99 + (i * 11),
      (1 + (i % 8)) * (99 + (i * 11)),
      case when i % 4 = 0 then 100 else 0 end,
      jsonb_build_object('showcase', true, 'workflow_index', i),
      v_admin,
      v_admin
    from generate_series(1, 124) as s(i)
    on conflict (id) do update set status = excluded.status, payload = excluded.payload;

    insert into public.enterprise_records (
      id, business_id, branch_id, record_type, reference_code, title, status,
      assigned_to, effective_at, due_at, amount, payload, created_by, updated_by
    )
    select
      md5(b.id::text || '|enterprise|' || i::text)::uuid,
      b.id,
      case when i % 5 = 0 then null else md5(b.id::text || '|branch|' || (((i - 1) % 4) + 1)::text)::uuid end,
      (array['demand_forecast','reorder_suggestion','staff_schedule','approval_workflow','notification_alert','import_export_job','barcode_label_job','integration_status'])[1 + ((i - 1) % 8)],
      format('%s-ENT-%06s', upper(left(b.label, 3)), i),
      format('%s enterprise record %s', b.label, i),
      (array['draft','active','approved','completed','open'])[1 + ((i - 1) % 5)],
      case when i % 3 = 0 then v_manager else v_admin end,
      now() - make_interval(days => i % 30),
      now() + make_interval(days => 30 + (i % 60)),
      5000 + (i * 275),
      jsonb_build_object('showcase', true, 'record_index', i),
      v_admin,
      v_admin
    from generate_series(1, 124) as s(i)
    on conflict (id) do update set status = excluded.status, payload = excluded.payload;

    insert into public.integration_connections (
      id, business_id, provider_code, display_name, status, secret_ref, config,
      last_checked_at, last_error, created_by, updated_by
    )
    select
      md5(b.id::text || '|integration|' || i::text)::uuid,
      b.id,
      (array['payment_gateway','sms','whatsapp','tax_service','ai'])[1 + ((i - 1) % 5)],
      format('%s Showcase Integration %s', b.label, i),
      (array['not_configured','configured','verifying','verified','disabled'])[1 + ((i - 1) % 5)],
      case when i % 4 = 0 then format('vault://flexpos/showcase/%s/%s', lower(b.label), i) else null end,
      jsonb_build_object('mode', 'test', 'showcase', true, 'index', i),
      now() - make_interval(hours => i),
      case when i % 5 = 0 then 'Synthetic verification pending.' else null end,
      v_admin,
      v_admin
    from generate_series(1, 16) as s(i)
    on conflict (id) do update set status = excluded.status, config = excluded.config;

    insert into public.hardware_devices (
      id, business_id, branch_id, device_kind, connection_type, display_name,
      endpoint, status, capabilities, metadata, last_seen_at, last_tested_at,
      created_by, updated_by
    )
    select
      md5(b.id::text || '|hardware|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|branch|' || (((i - 1) % 4) + 1)::text)::uuid,
      (array['barcode_camera','barcode_usb','barcode_bluetooth','thermal_usb','thermal_bluetooth','thermal_network','cash_drawer','weighing_scale'])[i],
      (array['camera','hid','hid','usb','bluetooth','tcp','system_print','serial'])[i],
      format('%s Showcase Device %s', b.label, i),
      format('showcase://%s/device/%s', lower(b.label), i),
      (array['online','not_configured','testing','offline'])[1 + ((i - 1) % 4)],
      jsonb_build_object('scan_formats', array['ean13','code128','qr'], 'showcase', true),
      jsonb_build_object('device_index', i, 'test_mode', true),
      case when i % 4 = 0 then null else now() - make_interval(mins => i * 5) end,
      now() - make_interval(hours => i),
      v_admin,
      v_admin
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set status = excluded.status, capabilities = excluded.capabilities;

    insert into public.tenant_audit_logs (
      business_id, actor_user_id, action, target_type, target_id, details, created_at
    )
    select
      b.id,
      case when i % 3 = 0 then v_manager else v_admin end,
      (array['login_success','product_created','sale_completed','large_discount_applied','refund_review','register_variance','stock_alert_acknowledged','export_created'])[1 + ((i - 1) % 8)],
      (array['user','product','sale','sale','sale','register_shift','inventory','report'])[1 + ((i - 1) % 8)],
      format('%s-audit-%06s', upper(left(b.label, 3)), i),
      jsonb_build_object('showcase', true, 'severity', case when i % 8 = 0 then 'warning' else 'info' end, 'sequence', i),
      now() - make_interval(days => i % 120)
    from generate_series(1, 124) as s(i);
  end loop;
end $$;

commit;
