-- Procurement, accounting controls, inventory lifecycle, documents, and
-- event history for the two synthetic showcase businesses.

begin;
select set_config('request.jwt.claim.sub', '01331716-1fbd-4780-bc16-b4dba20a96aa', true);

do $$
declare
  b record;
  v_admin constant uuid := '01331716-1fbd-4780-bc16-b4dba20a96aa';
  v_manager constant uuid := '73558bcb-8f47-4e36-9c3e-2ff4f7f16d98';
begin
  for b in
    select * from (values
      ('7b000000-0000-4000-8000-000000000001'::uuid, 'Retail'),
      ('7b000000-0000-4000-8000-000000000002'::uuid, 'Cafe')
    ) as x(id, label)
  loop
    -- Procurement requisitions, supplier invoices, payments, and landed costs.
    insert into public.purchase_requisitions (
      id, business_id, branch_id, status, notes, requested_by,
      approved_by, approved_at, decision_note
    )
    select
      md5(b.id::text || '|requisition|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|branch|' || (((i - 1) % 4) + 1)::text)::uuid,
      (array['draft','submitted','approved','rejected','cancelled'])[1 + ((i - 1) % 5)],
      format('Synthetic purchase requisition %s for %s.', i, b.label),
      v_manager,
      case when i % 5 in (3,4) then v_admin else null end,
      case when i % 5 in (3,4) then now() - make_interval(days => i) else null end,
      case when i % 5 = 4 then 'Approved for showcase review.' else null end
    from generate_series(1, 16) as s(i)
    on conflict (id) do update set status = excluded.status, notes = excluded.notes;

    insert into public.purchase_requisition_items (
      id, business_id, requisition_id, variant_id, product_name, sku, quantity, notes
    )
    select
      md5(b.id::text || '|requisition-item|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|requisition|' || i::text)::uuid,
      md5(b.id::text || '|variant|' || (80 + i)::text)::uuid,
      format('%s Showcase Product %s', b.label, 80 + i),
      format('%s-%s', upper(left(b.label, 3)), lpad((80 + i)::text, 5, '0')),
      8 + i,
      'Synthetic replenishment request.'
    from generate_series(1, 16) as s(i)
    on conflict (id) do update set quantity = excluded.quantity;

    insert into public.purchase_invoices (
      id, business_id, purchase_order_id, supplier_id, invoice_number,
      invoice_date, due_date, subtotal, tax_total, total, paid_total,
      status, notes, created_by
    )
    select
      md5(b.id::text || '|purchase-invoice|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|purchase-order|' || i::text)::uuid,
      md5(b.id::text || '|supplier|' || i::text)::uuid,
      format('%s-PINV-%06s', upper(left(b.label, 3)), i),
      current_date - i,
      current_date + 30,
      1000, 180, 1180,
      case when i % 4 = 0 then 1180 when i % 3 = 0 then 590 else 0 end,
      case when i % 7 = 0 then 'void' when i % 4 = 0 then 'paid' when i % 3 = 0 then 'partially_paid' else 'posted' end,
      'Synthetic supplier invoice for accounting review.',
      v_admin
    from generate_series(1, 16) as s(i)
    on conflict (id) do update set status = excluded.status, paid_total = excluded.paid_total;

    insert into public.purchase_invoice_payments (
      id, business_id, invoice_id, amount, payment_method, reference,
      notes, operation_id, paid_at, paid_by
    )
    select
      md5(b.id::text || '|purchase-invoice-payment|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|purchase-invoice|' || i::text)::uuid,
      case when i % 3 = 0 then 590 else 1180 end,
      case when i % 2 = 0 then 'bank_transfer' else 'upi' end,
      format('SHOWCASE-AP-PAY-%06s', i),
      'Synthetic supplier payment.',
      md5(b.id::text || '|purchase-invoice-payment-op|' || i::text)::uuid,
      now() - make_interval(days => i),
      v_admin
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set amount = excluded.amount;

    insert into public.purchase_landed_costs (
      id, business_id, purchase_order_id, amount, allocation_method,
      notes, operation_id, created_by
    )
    select
      md5(b.id::text || '|landed-cost|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|purchase-order|' || i::text)::uuid,
      75 + (i * 10),
      case when i % 2 = 0 then 'by_quantity' else 'by_value' end,
      'Synthetic freight and handling cost.',
      md5(b.id::text || '|landed-cost-op|' || i::text)::uuid,
      v_admin
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set amount = excluded.amount;

    insert into public.purchase_landed_cost_allocations (
      id, business_id, landed_cost_id, purchase_order_item_id, amount
    )
    select
      md5(b.id::text || '|landed-cost-allocation|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|landed-cost|' || i::text)::uuid,
      md5(b.id::text || '|purchase-item|' || i::text)::uuid,
      75 + (i * 10)
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set amount = excluded.amount;

    -- Approval history and attachments for expense review.
    insert into public.expense_approval_events (
      id, business_id, expense_id, status, note, created_by
    )
    select
      md5(b.id::text || '|expense-approval|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|expense|' || i::text)::uuid,
      case when i % 4 = 0 then 'rejected' when i % 3 = 0 then 'pending' else 'approved' end,
      'Synthetic approval event for review.',
      case when i % 2 = 0 then v_manager else v_admin end
    from generate_series(1, 16) as s(i)
    on conflict (id) do update set status = excluded.status, note = excluded.note;

    insert into public.expense_attachments (
      id, business_id, expense_id, storage_path, file_name, mime_type,
      file_size, created_by
    )
    select
      md5(b.id::text || '|expense-attachment|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|expense|' || i::text)::uuid,
      format('showcase/%s/expenses/%s.pdf', lower(b.label), i),
      format('expense-receipt-%06s.pdf', i),
      'application/pdf',
      48000 + (i * 1200),
      v_manager
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set file_name = excluded.file_name;

    -- Cash/bank accounts, fiscal controls, and reconciliation examples.
    insert into public.accounting_cash_bank_accounts (
      id, business_id, name, account_type, account_number_masked,
      opening_balance, ledger_account_id, is_active
    )
    values
      (md5(b.id::text || '|cash-account')::uuid, b.id, 'Main Till', 'cash', 'CASH-****-1001', 25000,
       md5(b.id::text || '|account|1')::uuid, true),
      (md5(b.id::text || '|bank-account')::uuid, b.id, 'Showcase Bank Account', 'bank', 'XXXX-XXXX-4821', 125000,
       md5(b.id::text || '|account|2')::uuid, true)
    on conflict (id) do update set opening_balance = excluded.opening_balance, is_active = true;

    insert into public.accounting_fiscal_years (
      id, business_id, label, starts_on, ends_on, status, closed_at, closed_by
    )
    values
      (md5(b.id::text || '|fiscal-year|2026')::uuid, b.id, 'FY 2026-27', date '2026-04-01', date '2027-03-31', 'open', null, null)
    on conflict (id) do update set status = 'open', closed_at = null, closed_by = null;

    insert into public.accounting_periods (
      id, business_id, starts_on, ends_on, status, closed_at, closed_by, notes
    )
    values
      (md5(b.id::text || '|period|2026-11')::uuid, b.id, date '2026-11-01', date '2026-11-30', 'open', null, null, 'Showcase review accounting period.')
    on conflict (id) do update set status = 'open', notes = excluded.notes;

    insert into public.accounting_bank_reconciliations (
      id, business_id, cash_bank_account_id, statement_start, statement_end,
      opening_balance, closing_balance, reconciled_amount, difference_amount,
      status, notes, created_by
    )
    values
      (md5(b.id::text || '|reconciliation|1')::uuid, b.id,
       md5(b.id::text || '|bank-account')::uuid, current_date - 30, current_date,
       125000, 138500, 13500, 0, 'completed', 'Synthetic month-end reconciliation.', v_admin)
    on conflict (id) do update set status = excluded.status, difference_amount = excluded.difference_amount;

    insert into public.accounting_bank_reconciliation_items (
      id, business_id, reconciliation_id, journal_line_id, amount, note
    )
    select
      md5(b.id::text || '|reconciliation-item|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|reconciliation|1')::uuid,
      md5(b.id::text || '|journal-line|' || i::text || '|debit')::uuid,
      1000 + (i * 250),
      'Synthetic matched bank statement line.'
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set amount = excluded.amount;

    insert into public.accounting_tax_profiles (
      id, business_id, branch_id, legal_name, gstin, state_code,
      default_place_of_supply, effective_from, is_active, tax_regime,
      country_code, registration_number, default_tax_rate, tax_inclusive
    )
    values
      (md5(b.id::text || '|tax-profile')::uuid, b.id,
       md5(b.id::text || '|branch|1')::uuid,
       format('%s Showcase Trading Co.', b.label),
       case when b.label = 'Retail' then '29ABCDE1234F1Z5' else '27ABCDE1234G2Z6' end,
       case when b.label = 'Retail' then '29' else '27' end,
       case when b.label = 'Retail' then 'Karnataka' else 'Maharashtra' end,
       date '2026-04-01', true, 'gst', 'IN',
       format('SHOWCASE-%s', upper(left(b.label, 3))), 18, false)
    on conflict (id) do update set legal_name = excluded.legal_name, default_tax_rate = excluded.default_tax_rate;

    insert into public.accounting_tax_adjustment_notes (
      id, business_id, branch_id, note_number, note_type, scope, source_id,
      taxable_amount, cgst_amount, sgst_amount, igst_amount, reason,
      note_date, status, created_by, posted_by, posted_at
    )
    select
      md5(b.id::text || '|tax-note|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|branch|' || (((i - 1) % 4) + 1)::text)::uuid,
      format('%s-TN-%06s', upper(left(b.label, 3)), i),
      case when i % 2 = 0 then 'credit' else 'debit' end,
      case when i % 2 = 0 then 'sales' else 'purchase' end,
      case when i % 2 = 0 then md5(b.id::text || '|sale|' || i::text)::uuid else md5(b.id::text || '|purchase-order|' || i::text)::uuid end,
      1000, 90, 90, 0,
      'Synthetic GST adjustment note for review.', current_date - i,
      case when i % 3 = 0 then 'posted' else 'draft' end,
      v_admin,
      case when i % 3 = 0 then v_admin else null end,
      case when i % 3 = 0 then now() - make_interval(days => i) else null end
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set status = excluded.status, taxable_amount = excluded.taxable_amount;

    -- Invoice documents render the same sales as printable receipt/invoice records.
    insert into public.invoice_documents (
      id, business_id, sale_id, branch_id, customer_id, invoice_number,
      document_type, template, currency_code, subtotal, discount_total,
      tax_total, service_charge_total, rounding_amount, grand_total,
      paid_total, due_total, snapshot, issued_at, created_by
    )
    select
      md5(b.id::text || '|invoice-document|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|sale|' || i::text)::uuid,
      md5(b.id::text || '|branch|' || (((i - 1) % 4) + 1)::text)::uuid,
      md5(b.id::text || '|customer|' || i::text)::uuid,
      format('%s-INV-%06s', upper(left(b.label, 3)), i),
      'sale_invoice',
      case when i % 3 = 0 then 'detailed' when i % 3 = 1 then 'minimal' else 'classic' end,
      'INR', 1000, 0, 180, 0, 0, 1180, 1180, 0,
      jsonb_build_object('showcase', true, 'business', b.label, 'sale_index', i),
      now() - make_interval(days => i), v_admin
    from generate_series(1, 16) as s(i)
    on conflict (id) do update set template = excluded.template, snapshot = excluded.snapshot;
  end loop;
end $$;

commit;
