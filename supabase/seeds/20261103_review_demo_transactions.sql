-- Transactional demo data for the isolated FlexPOS Review Demo business.
-- All people, contact details, invoices, and provider references are synthetic.
begin;

insert into public.sales (
  id, business_id, branch_id, register_id, shift_id, customer_id, invoice_number,
  sale_type, status, payment_status, currency_code, subtotal, discount_total,
  tax_total, service_charge_total, rounding_amount, grand_total, paid_total,
  due_total, notes, operation_id, completed_by, completed_at, promotion_id
) values
  ('9a4c0000-0000-4000-8000-000000001000', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000002', null, null, '9a4c0000-0000-4000-8000-000000000410', 'DEMO-0001', 'invoice', 'completed', 'paid', 'INR', 110, 0, 5.50, 0, 0, 115.50, 115.50, 0, 'Morning hydration purchase.', '9a4c0000-0000-4000-8000-000000001100', 'b19328a2-ac43-4291-8ff1-615d153b0b0f', now() - interval '12 days', null),
  ('9a4c0000-0000-4000-8000-000000001001', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000002', null, null, '9a4c0000-0000-4000-8000-000000000411', 'DEMO-0002', 'invoice', 'completed', 'paid', 'INR', 283, 20, 13.15, 0, 0, 276.15, 276.15, 0, 'Loyalty customer discount applied.', '9a4c0000-0000-4000-8000-000000001101', 'b19328a2-ac43-4291-8ff1-615d153b0b0f', now() - interval '10 days', '9a4c0000-0000-4000-8000-000000000800'),
  ('9a4c0000-0000-4000-8000-000000001002', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000003', null, null, '9a4c0000-0000-4000-8000-000000000412', 'DEMO-0003', 'invoice', 'completed', 'paid', 'INR', 354, 0, 39.67, 0, 0, 393.67, 393.67, 0, 'Cafe partner replenishment.', '9a4c0000-0000-4000-8000-000000001102', '73558bcb-8f47-4e36-9c3e-2ff4f7f16d98', now() - interval '8 days', null),
  ('9a4c0000-0000-4000-8000-000000001003', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000002', null, null, '9a4c0000-0000-4000-8000-000000000413', 'DEMO-0004', 'invoice', 'completed', 'paid', 'INR', 249, 0, 44.82, 0, 0.18, 294, 294, 0, 'Branded tote add-on.', '9a4c0000-0000-4000-8000-000000001103', 'b19328a2-ac43-4291-8ff1-615d153b0b0f', now() - interval '4 days', null),
  ('9a4c0000-0000-4000-8000-000000001004', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000003', null, null, '9a4c0000-0000-4000-8000-000000000414', 'DEMO-0005', 'invoice', 'completed', 'partially_paid', 'INR', 99, 0, 17.82, 0, 0, 116.82, 50, 66.82, 'Customer will settle balance at pickup.', '9a4c0000-0000-4000-8000-000000001104', '73558bcb-8f47-4e36-9c3e-2ff4f7f16d98', now() - interval '2 days', null),
  ('9a4c0000-0000-4000-8000-000000001005', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000002', null, null, '9a4c0000-0000-4000-8000-000000000415', 'DEMO-0006', 'invoice', 'refunded', 'refunded', 'INR', 147, 0, 7.35, 0, 0, 154.35, 154.35, 0, 'Returned after packaging damage review.', '9a4c0000-0000-4000-8000-000000001105', 'b19328a2-ac43-4291-8ff1-615d153b0b0f', now() - interval '1 day', null)
on conflict (id) do nothing;

insert into public.sale_items (
  id, business_id, sale_id, variant_id, warehouse_id, product_name, variant_name,
  sku, quantity, unit_price, unit_cost, discount_amount, tax_rate, tax_amount,
  line_total, note
) values
  ('9a4c0000-0000-4000-8000-000000001200', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000001000', '9a4c0000-0000-4000-8000-000000000210', '9a4c0000-0000-4000-8000-000000000300', 'Riverstone Sparkling Water 750ml', '750ml bottle', 'RIV-WAT-750', 2, 55, 32, 0, 5, 5.50, 115.50, null),
  ('9a4c0000-0000-4000-8000-000000001201', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000001001', '9a4c0000-0000-4000-8000-000000000211', '9a4c0000-0000-4000-8000-000000000300', 'Urban Harvest Cold Brew 330ml', '330ml can', 'URB-CBR-330', 1, 125, 68, 0, 5, 6.25, 131.25, null),
  ('9a4c0000-0000-4000-8000-000000001202', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000001001', '9a4c0000-0000-4000-8000-000000000213', '9a4c0000-0000-4000-8000-000000000300', 'Cocoa Oat Energy Bar', '55g bar', 'COC-OAT-055', 2, 79, 42, 20, 5, 6.90, 144.90, 'Bundle discount.'),
  ('9a4c0000-0000-4000-8000-000000001203', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000001002', '9a4c0000-0000-4000-8000-000000000212', '9a4c0000-0000-4000-8000-000000000301', 'Masala Trail Mix 200g', '200g pouch', 'MAS-TRM-200', 1, 185, 105, 0, 5, 9.25, 194.25, null),
  ('9a4c0000-0000-4000-8000-000000001204', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000001002', '9a4c0000-0000-4000-8000-000000000214', '9a4c0000-0000-4000-8000-000000000301', 'Glow & Co. Hand Wash 300ml', '300ml pump', 'GLO-HWS-300', 1, 169, 96, 0, 18, 30.42, 199.42, null),
  ('9a4c0000-0000-4000-8000-000000001205', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000001003', '9a4c0000-0000-4000-8000-000000000215', '9a4c0000-0000-4000-8000-000000000300', 'FlexPOS Reusable Tote Bag', 'Navy tote', 'FPO-TOT-NAV', 1, 249, 120, 0, 18, 44.82, 293.82, null),
  ('9a4c0000-0000-4000-8000-000000001206', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000001004', '9a4c0000-0000-4000-8000-000000000216', '9a4c0000-0000-4000-8000-000000000301', 'Gift Wrapping Service', 'Standard service', 'FPO-GIFT-SVC', 1, 99, 0, 0, 18, 17.82, 116.82, null),
  ('9a4c0000-0000-4000-8000-000000001207', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000001005', '9a4c0000-0000-4000-8000-000000000217', '9a4c0000-0000-4000-8000-000000000300', 'Riverstone Tonic 250ml', '250ml bottle', 'RIV-TON-250', 3, 49, 28, 0, 5, 7.35, 154.35, 'Refunded sale.' )
on conflict (id) do nothing;

insert into public.payments (
  id, business_id, sale_id, payment_method, status, amount, reference,
  provider, provider_payload, received_by, settled_at
) values
  ('9a4c0000-0000-4000-8000-000000001300', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000001000', 'cash', 'settled', 115.50, 'CASH-DEMO-0001', null, '{}', 'b19328a2-ac43-4291-8ff1-615d153b0b0f', now() - interval '12 days'),
  ('9a4c0000-0000-4000-8000-000000001301', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000001001', 'upi', 'settled', 276.15, 'pay_demo_1001', 'razorpay', '{"mode":"test","provider":"razorpay","payment_id":"pay_demo_1001"}', 'b19328a2-ac43-4291-8ff1-615d153b0b0f', now() - interval '10 days'),
  ('9a4c0000-0000-4000-8000-000000001302', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000001002', 'upi', 'settled', 393.67, 'pay_demo_1002', 'razorpay', '{"mode":"test","provider":"razorpay","payment_id":"pay_demo_1002"}', '73558bcb-8f47-4e36-9c3e-2ff4f7f16d98', now() - interval '8 days'),
  ('9a4c0000-0000-4000-8000-000000001303', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000001003', 'upi', 'settled', 294, 'pay_demo_1003', 'razorpay', '{"mode":"test","provider":"razorpay","payment_id":"pay_demo_1003"}', '01331716-1fbd-4780-bc16-b4dba20a96aa', now() - interval '4 days'),
  ('9a4c0000-0000-4000-8000-000000001304', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000001004', 'cash', 'pending', 50, 'DEP-DEMO-0005', null, '{}', '73558bcb-8f47-4e36-9c3e-2ff4f7f16d98', null),
  ('9a4c0000-0000-4000-8000-000000001305', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000001005', 'upi', 'refunded', 154.35, 'pay_demo_1005', 'razorpay', '{"mode":"test","provider":"razorpay","payment_id":"pay_demo_1005","refund_reason":"packaging_damage"}', 'b19328a2-ac43-4291-8ff1-615d153b0b0f', null)
on conflict (id) do nothing;

insert into public.register_cash_movements (
  id, business_id, shift_id, movement_type, amount, reason, operation_id, created_by
) values
  ('9a4c0000-0000-4000-8000-000000001400', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000610', 'cash_in', 2500, 'Petty cash float top-up', '9a4c0000-0000-4000-8000-000000001401', '73558bcb-8f47-4e36-9c3e-2ff4f7f16d98'),
  ('9a4c0000-0000-4000-8000-000000001401', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000610', 'cash_out', 640, 'Courier and small supplies', '9a4c0000-0000-4000-8000-000000001402', 'b19328a2-ac43-4291-8ff1-615d153b0b0f'),
  ('9a4c0000-0000-4000-8000-000000001402', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000611', 'cash_in', 1100, 'Branch float top-up', '9a4c0000-0000-4000-8000-000000001403', '73558bcb-8f47-4e36-9c3e-2ff4f7f16d98')
on conflict (id) do nothing;

insert into public.expense_categories (id, business_id, name, description) values
  ('9a4c0000-0000-4000-8000-000000000700', '9a4c0000-0000-4000-8000-000000000001', 'Rent and facilities', 'Store rent, utilities, and facility upkeep.'),
  ('9a4c0000-0000-4000-8000-000000000701', '9a4c0000-0000-4000-8000-000000000001', 'Logistics', 'Delivery, courier, and transport charges.'),
  ('9a4c0000-0000-4000-8000-000000000702', '9a4c0000-0000-4000-8000-000000000001', 'Marketing', 'Local campaigns, signage, and promotions.'),
  ('9a4c0000-0000-4000-8000-000000000703', '9a4c0000-0000-4000-8000-000000000001', 'People and training', 'Staff training and team activities.')
on conflict (business_id, name) do update set
  id = excluded.id,
  description = excluded.description,
  is_active = true;

insert into public.expenses (
  id, business_id, branch_id, category_id, expense_number, entry_type, amount,
  tax_amount, payment_method, vendor_name, reference, notes, incurred_on,
  operation_id, created_by, approval_status, approved_by, approved_at
) values
  ('9a4c0000-0000-4000-8000-000000001500', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000002', '9a4c0000-0000-4000-8000-000000000700', 'EXP-DEMO-001', 'expense', 48000, 8640, 'bank_transfer', 'Koramangala Commercial Realty', 'RENT-NOV-DEMO', 'Monthly flagship rent.', current_date - 3, '9a4c0000-0000-4000-8000-000000001500', '01331716-1fbd-4780-bc16-b4dba20a96aa', 'approved', '01331716-1fbd-4780-bc16-b4dba20a96aa', now() - interval '2 days'),
  ('9a4c0000-0000-4000-8000-000000001501', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000002', '9a4c0000-0000-4000-8000-000000000701', 'EXP-DEMO-002', 'expense', 1250, 225, 'upi', 'QuickRoute Couriers', 'QRC-4812', 'Supplier sample delivery charges.', current_date - 6, '9a4c0000-0000-4000-8000-000000001501', '01331716-1fbd-4780-bc16-b4dba20a96aa', 'approved', '01331716-1fbd-4780-bc16-b4dba20a96aa', now() - interval '5 days'),
  ('9a4c0000-0000-4000-8000-000000001502', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000003', '9a4c0000-0000-4000-8000-000000000702', 'EXP-DEMO-003', 'expense', 8500, 1530, 'card', 'Bengaluru Local Media', 'BLM-Q4-14', 'Neighbourhood launch campaign.', current_date - 12, '9a4c0000-0000-4000-8000-000000001502', '73558bcb-8f47-4e36-9c3e-2ff4f7f16d98', 'approved', '01331716-1fbd-4780-bc16-b4dba20a96aa', now() - interval '11 days'),
  ('9a4c0000-0000-4000-8000-000000001503', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000002', '9a4c0000-0000-4000-8000-000000000703', 'EXP-DEMO-004', 'expense', 3200, 576, 'cash', 'SkillSpring Training', 'TRN-2026-09', 'Cashier refresher session.', current_date - 18, '9a4c0000-0000-4000-8000-000000001503', '01331716-1fbd-4780-bc16-b4dba20a96aa', 'pending', null, null)
on conflict (id) do nothing;

insert into public.purchase_orders (
  id, business_id, branch_id, warehouse_id, supplier_id, order_number,
  supplier_reference, status, currency_code, subtotal, tax_total, grand_total,
  expected_at, notes, operation_id, created_by, ordered_at, completed_at
) values
  ('9a4c0000-0000-4000-8000-000000001600', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000002', '9a4c0000-0000-4000-8000-000000000300', '9a4c0000-0000-4000-8000-000000000500', 'PO-DEMO-001', 'SB-PO-8841', 'received', 'INR', 18240, 920, 19160, now() - interval '4 days', 'Beverage replenishment for flagship store.', '9a4c0000-0000-4000-8000-000000001600', '01331716-1fbd-4780-bc16-b4dba20a96aa', now() - interval '10 days', now() - interval '4 days'),
  ('9a4c0000-0000-4000-8000-000000001601', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000003', '9a4c0000-0000-4000-8000-000000000301', '9a4c0000-0000-4000-8000-000000000501', 'PO-DEMO-002', 'HF-PO-2117', 'partially_received', 'INR', 14700, 735, 15435, now() + interval '3 days', 'Snack restock; balance due on next delivery.', '9a4c0000-0000-4000-8000-000000001601', '01331716-1fbd-4780-bc16-b4dba20a96aa', now() - interval '2 days', null)
on conflict (id) do nothing;

insert into public.purchase_order_items (
  id, business_id, purchase_order_id, variant_id, product_name, variant_name,
  sku, ordered_quantity, received_quantity, unit_cost, tax_rate, tax_amount, line_total
) values
  ('9a4c0000-0000-4000-8000-000000001610', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000001600', '9a4c0000-0000-4000-8000-000000000210', 'Riverstone Sparkling Water 750ml', '750ml bottle', 'RIV-WAT-750', 400, 400, 32, 5, 640, 13440),
  ('9a4c0000-0000-4000-8000-000000001611', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000001600', '9a4c0000-0000-4000-8000-000000000211', 'Urban Harvest Cold Brew 330ml', '330ml can', 'URB-CBR-330', 80, 80, 68, 5, 280, 5720),
  ('9a4c0000-0000-4000-8000-000000001612', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000001601', '9a4c0000-0000-4000-8000-000000000212', 'Masala Trail Mix 200g', '200g pouch', 'MAS-TRM-200', 100, 60, 105, 5, 525, 11025),
  ('9a4c0000-0000-4000-8000-000000001613', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000001601', '9a4c0000-0000-4000-8000-000000000213', 'Cocoa Oat Energy Bar', '55g bar', 'COC-OAT-055', 100, 60, 42, 5, 210, 4410)
on conflict (id) do nothing;

insert into public.goods_receipts (
  id, business_id, purchase_order_id, warehouse_id, receipt_number,
  supplier_document_number, status, total_cost, operation_id, notes,
  received_by, received_at
) values
  ('9a4c0000-0000-4000-8000-000000001620', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000001600', '9a4c0000-0000-4000-8000-000000000300', 'GRN-DEMO-001', 'SB-INV-8841', 'completed', 18240, '9a4c0000-0000-4000-8000-000000001620', 'Received against beverage purchase order.', '01331716-1fbd-4780-bc16-b4dba20a96aa', now() - interval '4 days')
on conflict (id) do nothing;

insert into public.goods_receipt_items (
  id, business_id, goods_receipt_id, purchase_order_item_id, variant_id,
  quantity, unit_cost, line_total
) values
  ('9a4c0000-0000-4000-8000-000000001630', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000001620', '9a4c0000-0000-4000-8000-000000001610', '9a4c0000-0000-4000-8000-000000000210', 400, 32, 12800),
  ('9a4c0000-0000-4000-8000-000000001631', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000001620', '9a4c0000-0000-4000-8000-000000001611', '9a4c0000-0000-4000-8000-000000000211', 80, 68, 5440)
on conflict (id) do nothing;

commit;
