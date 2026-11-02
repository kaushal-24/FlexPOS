-- CRM, accounting, analytics, industry, enterprise, hardware, and monitoring
-- demo data for the isolated FlexPOS Review Demo business.
begin;

-- CRM triggers use auth.uid() for actor fields. Seed as the demo administrator.
select set_config('request.jwt.claim.sub', '01331716-1fbd-4780-bc16-b4dba20a96aa', true);

insert into public.crm_leads (
  id, business_id, salesperson_id, customer_id, title, source, status,
  estimated_value, expected_close_at, notes, created_by
) values
  ('9a4c0000-0000-4000-8000-000000002000', '9a4c0000-0000-4000-8000-000000000001', '01331716-1fbd-4780-bc16-b4dba20a96aa', '9a4c0000-0000-4000-8000-000000000412', 'Green Bean Cafe monthly beverage contract', 'referral', 'qualified', 96000, current_date + 14, 'Cafe is reviewing a monthly cold brew and sparkling water plan.', '01331716-1fbd-4780-bc16-b4dba20a96aa'),
  ('9a4c0000-0000-4000-8000-000000002001', '9a4c0000-0000-4000-8000-000000000001', '73558bcb-8f47-4e36-9c3e-2ff4f7f16d98', '9a4c0000-0000-4000-8000-000000000413', 'Corporate pantry pilot', 'website', 'contacted', 150000, current_date + 30, 'First meeting completed; awaiting headcount confirmation.', '01331716-1fbd-4780-bc16-b4dba20a96aa'),
  ('9a4c0000-0000-4000-8000-000000002002', '9a4c0000-0000-4000-8000-000000000001', '01331716-1fbd-4780-bc16-b4dba20a96aa', '9a4c0000-0000-4000-8000-000000000414', 'Festival gift hamper inquiry', 'walk-in', 'converted', 28000, current_date - 2, 'Converted to an accepted quotation.', '01331716-1fbd-4780-bc16-b4dba20a96aa')
on conflict (id) do update set status = excluded.status, estimated_value = excluded.estimated_value;

insert into public.crm_opportunities (
  id, business_id, salesperson_id, customer_id, lead_id, title, stage,
  probability, value_minor, expected_close_at, actual_close_at, notes, created_by
) values
  ('9a4c0000-0000-4000-8000-000000002010', '9a4c0000-0000-4000-8000-000000000001', '01331716-1fbd-4780-bc16-b4dba20a96aa', '9a4c0000-0000-4000-8000-000000000412', '9a4c0000-0000-4000-8000-000000002000', 'Green Bean Cafe replenishment agreement', 'proposal', 65, 9600000, current_date + 14, null, 'Proposal includes two branch deliveries and quarterly price review.', '01331716-1fbd-4780-bc16-b4dba20a96aa'),
  ('9a4c0000-0000-4000-8000-000000002011', '9a4c0000-0000-4000-8000-000000000001', '01331716-1fbd-4780-bc16-b4dba20a96aa', '9a4c0000-0000-4000-8000-000000000414', '9a4c0000-0000-4000-8000-000000002002', 'Festival hamper order', 'closed_won', 100, 2800000, current_date - 5, current_date - 2, 'Won through seasonal quotation.', '01331716-1fbd-4780-bc16-b4dba20a96aa')
on conflict (id) do update set stage = excluded.stage, probability = excluded.probability;

insert into public.crm_quotations (
  id, business_id, salesperson_id, customer_id, opportunity_id, quotation_number,
  title, status, subtotal_minor, tax_minor, discount_minor, grand_total_minor,
  valid_until, notes, created_by
) values
  ('9a4c0000-0000-4000-8000-000000002020', '9a4c0000-0000-4000-8000-000000000001', '01331716-1fbd-4780-bc16-b4dba20a96aa', '9a4c0000-0000-4000-8000-000000000412', '9a4c0000-0000-4000-8000-000000002010', 'QUO-DEMO-001', 'Green Bean Cafe monthly supply proposal', 'sent', 9600000, 480000, 0, 10080000, current_date + 21, 'Net-15 terms requested.', '01331716-1fbd-4780-bc16-b4dba20a96aa'),
  ('9a4c0000-0000-4000-8000-000000002021', '9a4c0000-0000-4000-8000-000000000001', '01331716-1fbd-4780-bc16-b4dba20a96aa', '9a4c0000-0000-4000-8000-000000000414', '9a4c0000-0000-4000-8000-000000002011', 'QUO-DEMO-002', 'Festival gift hamper package', 'accepted', 2800000, 140000, 0, 2940000, current_date + 3, 'Accepted; conversion is ready for review.', '01331716-1fbd-4780-bc16-b4dba20a96aa')
on conflict (id) do update set status = excluded.status, grand_total_minor = excluded.grand_total_minor;

insert into public.crm_follow_ups (
  id, business_id, salesperson_id, lead_id, opportunity_id, quotation_id, title,
  type, due_at, completed_at, notes, created_by
) values
  ('9a4c0000-0000-4000-8000-000000002030', '9a4c0000-0000-4000-8000-000000000001', '01331716-1fbd-4780-bc16-b4dba20a96aa', '9a4c0000-0000-4000-8000-000000002000', '9a4c0000-0000-4000-8000-000000002010', '9a4c0000-0000-4000-8000-000000002020', 'Review beverage supply proposal', 'meeting', now() + interval '2 days', null, 'Bring delivery calendar and sample pricing.', '01331716-1fbd-4780-bc16-b4dba20a96aa'),
  ('9a4c0000-0000-4000-8000-000000002031', '9a4c0000-0000-4000-8000-000000000001', '73558bcb-8f47-4e36-9c3e-2ff4f7f16d98', '9a4c0000-0000-4000-8000-000000002001', null, null, 'Call corporate pantry contact', 'call', now() - interval '1 day', now() - interval '12 hours', 'Confirmed decision-maker and next steps.', '01331716-1fbd-4780-bc16-b4dba20a96aa')
on conflict (id) do update set due_at = excluded.due_at, completed_at = excluded.completed_at;

insert into public.crm_customer_notes (
  id, business_id, salesperson_id, customer_id, note, is_private, created_by
) values
  ('9a4c0000-0000-4000-8000-000000002040', '9a4c0000-0000-4000-8000-000000000001', '01331716-1fbd-4780-bc16-b4dba20a96aa', '9a4c0000-0000-4000-8000-000000000412', 'Prefers Monday morning deliveries and consolidated GST invoices.', false, '01331716-1fbd-4780-bc16-b4dba20a96aa'),
  ('9a4c0000-0000-4000-8000-000000002041', '9a4c0000-0000-4000-8000-000000000001', '73558bcb-8f47-4e36-9c3e-2ff4f7f16d98', '9a4c0000-0000-4000-8000-000000000414', 'Seasonal customer; verify hamper artwork before printing.', true, '01331716-1fbd-4780-bc16-b4dba20a96aa')
on conflict (id) do update set note = excluded.note, is_private = excluded.is_private;

insert into public.crm_reminders (
  id, business_id, salesperson_id, title, description, due_at,
  is_completed, completed_at, related_table, related_id, created_by
) values
  ('9a4c0000-0000-4000-8000-000000002050', '9a4c0000-0000-4000-8000-000000000001', '01331716-1fbd-4780-bc16-b4dba20a96aa', 'Send updated cafe price list', 'Include new cold brew tier pricing.', now() + interval '3 days', false, null, 'opportunity', '9a4c0000-0000-4000-8000-000000002010', '01331716-1fbd-4780-bc16-b4dba20a96aa'),
  ('9a4c0000-0000-4000-8000-000000002051', '9a4c0000-0000-4000-8000-000000000001', '73558bcb-8f47-4e36-9c3e-2ff4f7f16d98', 'Archive converted hamper lead', 'Close the lead after invoice conversion.', now() - interval '1 day', true, now() - interval '12 hours', 'lead', '9a4c0000-0000-4000-8000-000000002002', '01331716-1fbd-4780-bc16-b4dba20a96aa')
on conflict (id) do update set is_completed = excluded.is_completed, completed_at = excluded.completed_at;

insert into public.sales_targets (
  id, business_id, branch_id, starts_on, ends_on, target_amount, notes, created_by, updated_by
) values
  ('9a4c0000-0000-4000-8000-000000002100', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000002', date_trunc('month', current_date)::date, (date_trunc('month', current_date) + interval '1 month - 1 day')::date, 650000, 'Flagship monthly target for review dashboard.', '01331716-1fbd-4780-bc16-b4dba20a96aa', '01331716-1fbd-4780-bc16-b4dba20a96aa'),
  ('9a4c0000-0000-4000-8000-000000002101', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000003', date_trunc('month', current_date)::date, (date_trunc('month', current_date) + interval '1 month - 1 day')::date, 380000, 'Express branch monthly target.', '01331716-1fbd-4780-bc16-b4dba20a96aa', '01331716-1fbd-4780-bc16-b4dba20a96aa')
on conflict (id) do update set target_amount = excluded.target_amount, ends_on = excluded.ends_on;

insert into public.inventory_stock_alert_notifications (
  id, business_id, warehouse_id, variant_id, severity, status,
  quantity_on_hand, quantity_reserved, available_quantity, target_stock,
  suggested_order_quantity, average_cost
) values
  ('9a4c0000-0000-4000-8000-000000002200', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000300', '9a4c0000-0000-4000-8000-000000000212', 'below_safety_stock', 'open', 7, 0, 7, 18, 11, 105),
  ('9a4c0000-0000-4000-8000-000000002201', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000300', '9a4c0000-0000-4000-8000-000000000214', 'reorder_point', 'open', 12, 1, 11, 15, 4, 96)
on conflict (id) do update set status = excluded.status, suggested_order_quantity = excluded.suggested_order_quantity;

insert into public.customer_ledger_entries (
  id, business_id, branch_id, customer_id, entry_type, direction, amount,
  sale_id, payment_id, description, operation_id, created_by, occurred_at
) values
  ('9a4c0000-0000-4000-8000-000000002300', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000003', '9a4c0000-0000-4000-8000-000000000414', 'credit_sale', 'debit', 50, '9a4c0000-0000-4000-8000-000000001004', '9a4c0000-0000-4000-8000-000000001304', 'Deposit recorded against open customer balance.', '9a4c0000-0000-4000-8000-000000002301', '73558bcb-8f47-4e36-9c3e-2ff4f7f16d98', now() - interval '2 days')
on conflict (id) do nothing;

insert into public.accounting_accounts (id, business_id, code, name, account_type, is_system) values
  ('9a4c0000-0000-4000-8000-000000002400', '9a4c0000-0000-4000-8000-000000000001', '6100', 'Local marketing expense', 'expense', false),
  ('9a4c0000-0000-4000-8000-000000002401', '9a4c0000-0000-4000-8000-000000000001', '4200', 'Corporate supply revenue', 'revenue', false),
  ('9a4c0000-0000-4000-8000-000000002402', '9a4c0000-0000-4000-8000-000000000001', '1020', 'Razorpay clearing', 'asset', false)
on conflict (business_id, code) do update set name = excluded.name, account_type = excluded.account_type;

insert into public.accounting_cash_bank_accounts (
  id, business_id, name, account_type, account_number_masked, opening_balance, ledger_account_id
) values
  ('9a4c0000-0000-4000-8000-000000002410', '9a4c0000-0000-4000-8000-000000000001', 'Koramangala cash drawer', 'cash', null, 5000, 'f91040b4-5d18-4c20-8c23-8d7f509dc04f'),
  ('9a4c0000-0000-4000-8000-000000002411', '9a4c0000-0000-4000-8000-000000000001', 'FlexPOS operating bank', 'bank', '•••• 4421', 185000, '0d5718c9-9d70-441e-b1cf-a1d9b4b56dfa'),
  ('9a4c0000-0000-4000-8000-000000002412', '9a4c0000-0000-4000-8000-000000000001', 'Razorpay test clearing', 'bank', 'test-mode', 0, '9a4c0000-0000-4000-8000-000000002402')
on conflict (id) do update set opening_balance = excluded.opening_balance, account_number_masked = excluded.account_number_masked;

insert into public.accounting_fiscal_years (id, business_id, label, starts_on, ends_on, status) values
  ('9a4c0000-0000-4000-8000-000000002420', '9a4c0000-0000-4000-8000-000000000001', 'FY 2026-27', '2026-04-01', '2027-03-31', 'open')
on conflict (id) do update set status = excluded.status;

insert into public.accounting_periods (id, business_id, starts_on, ends_on, status, notes) values
  ('9a4c0000-0000-4000-8000-000000002421', '9a4c0000-0000-4000-8000-000000000001', date_trunc('month', current_date)::date, (date_trunc('month', current_date) + interval '1 month - 1 day')::date, 'open', 'Current review period.'),
  ('9a4c0000-0000-4000-8000-000000002422', '9a4c0000-0000-4000-8000-000000000001', (date_trunc('month', current_date) - interval '1 month')::date, (date_trunc('month', current_date) - interval '1 day')::date, 'closed', 'Prior period closed for reporting demo.')
on conflict (id) do update set status = excluded.status, notes = excluded.notes;

insert into public.accounting_tax_profiles (
  id, business_id, branch_id, legal_name, gstin, state_code,
  default_place_of_supply, effective_from, is_active, tax_regime,
  country_code, registration_number, default_tax_rate, tax_inclusive
) values
  ('9a4c0000-0000-4000-8000-000000002430', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000002', 'FlexPOS Review Demo Bengaluru Pvt Ltd', '29ABCDE1234F1Z5', '29', 'Karnataka', '2026-04-01', true, 'gst', 'IN', 'U72900KA2026PTC000001', 5, false),
  ('9a4c0000-0000-4000-8000-000000002431', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000003', 'FlexPOS Review Demo Bengaluru Pvt Ltd', '29ABCDE1234F1Z5', '29', 'Karnataka', '2026-04-01', true, 'gst', 'IN', 'U72900KA2026PTC000001', 5, false)
on conflict (id) do update set default_tax_rate = excluded.default_tax_rate, is_active = excluded.is_active;

insert into public.accounting_recurring_expenses (
  id, business_id, branch_id, category_id, description, amount, tax_amount,
  payment_method, vendor_name, frequency, next_run_on, is_active, created_by
) values
  ('9a4c0000-0000-4000-8000-000000002440', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000002', '9a4c0000-0000-4000-8000-000000000700', 'Flagship monthly rent', 48000, 8640, 'bank_transfer', 'Koramangala Commercial Realty', 'monthly', date_trunc('month', current_date + interval '1 month')::date, true, '01331716-1fbd-4780-bc16-b4dba20a96aa'),
  ('9a4c0000-0000-4000-8000-000000002441', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000003', '9a4c0000-0000-4000-8000-000000000701', 'Express courier retainer', 3000, 540, 'upi', 'QuickRoute Couriers', 'monthly', current_date + 20, true, '01331716-1fbd-4780-bc16-b4dba20a96aa')
on conflict (id) do update set amount = excluded.amount, next_run_on = excluded.next_run_on, is_active = excluded.is_active;

insert into public.accounting_journal_entries (
  id, business_id, entry_number, entry_date, source_type, source_id, memo, status, created_by
) values
  ('9a4c0000-0000-4000-8000-000000002450', '9a4c0000-0000-4000-8000-000000000001', 'JE-DEMO-001', current_date - 4, 'sale', '9a4c0000-0000-4000-8000-000000001001', 'Razorpay UPI settlement for DEMO-0002', 'posted', '01331716-1fbd-4780-bc16-b4dba20a96aa'),
  ('9a4c0000-0000-4000-8000-000000002451', '9a4c0000-0000-4000-8000-000000000001', 'JE-DEMO-002', current_date - 12, 'expense', '9a4c0000-0000-4000-8000-000000001502', 'Local marketing expense posting', 'posted', '01331716-1fbd-4780-bc16-b4dba20a96aa')
on conflict (id) do update set status = excluded.status, memo = excluded.memo;

insert into public.accounting_journal_lines (
  id, business_id, journal_entry_id, account_id, branch_id, description, debit, credit
) values
  ('9a4c0000-0000-4000-8000-000000002460', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000002450', '9a4c0000-0000-4000-8000-000000002402', '9a4c0000-0000-4000-8000-000000000002', 'Razorpay clearing debit', 276.15, 0),
  ('9a4c0000-0000-4000-8000-000000002461', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000002450', '9a4c0000-0000-4000-8000-000000002401', '9a4c0000-0000-4000-8000-000000000002', 'Corporate supply revenue credit', 0, 276.15),
  ('9a4c0000-0000-4000-8000-000000002462', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000002451', '9a4c0000-0000-4000-8000-000000002400', '9a4c0000-0000-4000-8000-000000000003', 'Marketing expense debit', 8500, 0),
  ('9a4c0000-0000-4000-8000-000000002463', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000002451', '0d5718c9-9d70-441e-b1cf-a1d9b4b56dfa', '9a4c0000-0000-4000-8000-000000000003', 'Bank payment credit', 0, 8500)
on conflict (id) do nothing;

insert into public.industry_workflows (
  id, business_id, branch_id, module_code, workflow_kind, reference_code, title,
  status, customer_id, product_id, assigned_to, scheduled_at, due_at,
  quantity, unit_price, total_amount, deposit_amount, payload, created_by, updated_by
) values
  ('9a4c0000-0000-4000-8000-000000002500', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000002', 'restaurant_operations', 'restaurant_table', 'TABLE-KOR-12', 'Table 12 reservation', 'confirmed', '9a4c0000-0000-4000-8000-000000000410', null, '73558bcb-8f47-4e36-9c3e-2ff4f7f16d98', now() + interval '1 day', now() + interval '1 day 2 hours', 4, 0, 0, 0, '{"table":"12","seats":4,"service":"dine_in"}', '01331716-1fbd-4780-bc16-b4dba20a96aa', '01331716-1fbd-4780-bc16-b4dba20a96aa'),
  ('9a4c0000-0000-4000-8000-000000002501', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000003', 'grocery_operations', 'barcode_checkout', 'SCAN-IND-001', 'Barcode scanner validation session', 'completed', '9a4c0000-0000-4000-8000-000000000411', '9a4c0000-0000-4000-8000-000000000201', 'b19328a2-ac43-4291-8ff1-615d153b0b0f', now() - interval '3 days', now() - interval '3 days', 1, 125, 125, 0, '{"barcode":"8909000000028","device":"laptop_camera"}', '01331716-1fbd-4780-bc16-b4dba20a96aa', '01331716-1fbd-4780-bc16-b4dba20a96aa')
on conflict (id) do update set status = excluded.status, payload = excluded.payload;

insert into public.enterprise_records (
  id, business_id, branch_id, record_type, reference_code, title, status,
  assigned_to, effective_at, due_at, amount, payload, created_by, updated_by
) values
  ('9a4c0000-0000-4000-8000-000000002600', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000002', 'staff_schedule', 'SCHED-KOR-W47', 'Week 47 cashier coverage', 'approved', '01331716-1fbd-4780-bc16-b4dba20a96aa', now() - interval '2 days', now() + interval '5 days', 0, '{"cashier":"pithvakaushal24+flexpos-migration@gmail.com","hours":48,"register":"KOR-REG-1"}', '01331716-1fbd-4780-bc16-b4dba20a96aa', '01331716-1fbd-4780-bc16-b4dba20a96aa'),
  ('9a4c0000-0000-4000-8000-000000002601', '9a4c0000-0000-4000-8000-000000000001', null, 'integration_status', 'RAZORPAY-TEST-001', 'Razorpay test mode readiness', 'active', '01331716-1fbd-4780-bc16-b4dba20a96aa', now() - interval '1 day', now() + interval '30 days', 0, '{"provider":"razorpay","mode":"test","webhook_required":false,"credentials_configured":false}', '01331716-1fbd-4780-bc16-b4dba20a96aa', '01331716-1fbd-4780-bc16-b4dba20a96aa'),
  ('9a4c0000-0000-4000-8000-000000002602', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000002', 'notification_alert', 'ALERT-LOW-001', 'Critical trail mix stock alert', 'open', '01331716-1fbd-4780-bc16-b4dba20a96aa', now() - interval '2 hours', now() + interval '1 day', 770, '{"severity":"critical","variant":"MAS-TRM-200","available":7,"reorder_point":18}', '01331716-1fbd-4780-bc16-b4dba20a96aa', '01331716-1fbd-4780-bc16-b4dba20a96aa')
on conflict (id) do update set status = excluded.status, payload = excluded.payload;

insert into public.integration_connections (
  id, business_id, provider_code, display_name, status, secret_ref, config,
  last_checked_at, last_error, created_by, updated_by
) values
  ('9a4c0000-0000-4000-8000-000000002700', '9a4c0000-0000-4000-8000-000000000001', 'payment_gateway', 'Razorpay Test Mode', 'not_configured', null, '{"mode":"test","key_id":"rzp_test_demo","webhook_required":false,"upi_enabled":true}', now() - interval '3 hours', 'Demo credentials intentionally not configured.', '01331716-1fbd-4780-bc16-b4dba20a96aa', '01331716-1fbd-4780-bc16-b4dba20a96aa'),
  ('9a4c0000-0000-4000-8000-000000002701', '9a4c0000-0000-4000-8000-000000000001', 'sms', 'Review SMS provider', 'not_configured', null, '{"sender_id":"FLEXPOS","test_mode":true}', null, null, '01331716-1fbd-4780-bc16-b4dba20a96aa', '01331716-1fbd-4780-bc16-b4dba20a96aa')
on conflict (id) do update set status = excluded.status, config = excluded.config, last_error = excluded.last_error;

insert into public.hardware_devices (
  id, business_id, branch_id, device_kind, connection_type, display_name,
  endpoint, status, capabilities, metadata, last_seen_at, last_tested_at,
  created_by, updated_by
) values
  ('9a4c0000-0000-4000-8000-000000002800', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000002', 'barcode_camera', 'camera', 'Koramangala laptop camera scanner', 'browser://camera/default', 'online', '{"scan_formats":["ean13","upca","code128"],"auto_focus":true,"multi_angle":true}', '{"device":"review-laptop","validated":true}', now() - interval '10 minutes', now() - interval '20 minutes', '01331716-1fbd-4780-bc16-b4dba20a96aa', '01331716-1fbd-4780-bc16-b4dba20a96aa'),
  ('9a4c0000-0000-4000-8000-000000002801', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000003', 'thermal_usb', 'usb', 'Express counter thermal printer', 'usb://thermal/demo-printer', 'not_configured', '{"paper_widths":["58mm","80mm"],"pdf_fallback":true}', '{"test_print_available":true}', null, now() - interval '1 day', '01331716-1fbd-4780-bc16-b4dba20a96aa', '01331716-1fbd-4780-bc16-b4dba20a96aa')
on conflict (id) do update set status = excluded.status, capabilities = excluded.capabilities, metadata = excluded.metadata;

insert into public.tenant_audit_logs (
  business_id, actor_user_id, action, target_type, target_id, details, created_at
) values
  ('9a4c0000-0000-4000-8000-000000000001', '01331716-1fbd-4780-bc16-b4dba20a96aa', 'login_failed', 'user', 'b19328a2-ac43-4291-8ff1-615d153b0b0f', '{"reason":"demo password retry","severity":"info"}', now() - interval '5 days'),
  ('9a4c0000-0000-4000-8000-000000000001', '01331716-1fbd-4780-bc16-b4dba20a96aa', 'large_discount_applied', 'sale', '9a4c0000-0000-4000-8000-000000001001', '{"discount_amount":20,"threshold":15,"review_required":true}', now() - interval '10 days'),
  ('9a4c0000-0000-4000-8000-000000000001', '01331716-1fbd-4780-bc16-b4dba20a96aa', 'refund_review', 'sale', '9a4c0000-0000-4000-8000-000000001005', '{"amount":154.35,"reason":"packaging_damage","status":"refunded"}', now() - interval '1 day'),
  ('9a4c0000-0000-4000-8000-000000000001', '73558bcb-8f47-4e36-9c3e-2ff4f7f16d98', 'register_variance', 'register_shift', '9a4c0000-0000-4000-8000-000000000610', '{"difference_amount":-100,"currency":"INR"}', now() - interval '12 days');

insert into public.industry_workflow_events (
  business_id, workflow_id, from_status, to_status, note, metadata, actor_user_id
)
select '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000002500', 'planned', 'confirmed', 'Reservation confirmed by branch manager.', '{"channel":"phone"}', '73558bcb-8f47-4e36-9c3e-2ff4f7f16d98'
where not exists (
  select 1 from public.industry_workflow_events
  where business_id='9a4c0000-0000-4000-8000-000000000001' and workflow_id='9a4c0000-0000-4000-8000-000000002500' and to_status='confirmed'
);

insert into public.enterprise_record_events (
  business_id, record_id, from_status, to_status, note, metadata, actor_user_id
)
select '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000002601', 'draft', 'active', 'Test-mode payment readiness reviewed.', '{"webhook_required":false}', '01331716-1fbd-4780-bc16-b4dba20a96aa'
where not exists (
  select 1 from public.enterprise_record_events
  where business_id='9a4c0000-0000-4000-8000-000000000001' and record_id='9a4c0000-0000-4000-8000-000000002601' and to_status='active'
);

insert into public.hardware_device_events (
  business_id, device_id, event_type, status, error_message, metadata, actor_user_id
)
select '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000002800', 'registered', 'online', null, '{"scan_formats":["ean13","upca","code128"]}', '01331716-1fbd-4780-bc16-b4dba20a96aa'
where not exists (
  select 1 from public.hardware_device_events
  where business_id='9a4c0000-0000-4000-8000-000000000001' and device_id='9a4c0000-0000-4000-8000-000000002800' and event_type='registered'
);

commit;
