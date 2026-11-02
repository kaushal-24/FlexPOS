-- Synthetic review dataset for FlexPOS. This is intentionally isolated in a
-- separate business and uses existing authenticated profiles as demo staff.
-- It is safe to re-run because every row uses deterministic IDs.
begin;

insert into public.businesses (
  id, name, slug, business_type, currency_code, timezone, country_code,
  tax_registration_number, invoice_prefix, receipt_footer, receipt_template,
  receipt_qr_payload, receipt_show_logo, receipt_show_qr, receipt_paper_width,
  stock_alert_email_enabled, created_by
) values (
  '9a4c0000-0000-4000-8000-000000000001',
  'FlexPOS Review Demo', 'flexpos-review-demo', 'retail', 'INR',
  'Asia/Kolkata', 'IN', '24ABCDE1234F1Z5', 'DEMO',
  'Thank you for shopping with FlexPOS Review Demo.', 'detailed',
  'upi://pay?pa=kaushal.pithva@ptaxis&pn=FlexPOS%20Review%20Demo', true, true,
  '80', false, '01331716-1fbd-4780-bc16-b4dba20a96aa'
)
on conflict (id) do update set
  name = excluded.name,
  receipt_footer = excluded.receipt_footer,
  receipt_template = excluded.receipt_template,
  receipt_qr_payload = excluded.receipt_qr_payload,
  receipt_show_logo = excluded.receipt_show_logo,
  receipt_show_qr = excluded.receipt_show_qr,
  receipt_paper_width = excluded.receipt_paper_width;

insert into public.branches (
  id, business_id, name, code, email, phone, address_line_1, city,
  state_region, postal_code, country_code, timezone
) values
  (
    '9a4c0000-0000-4000-8000-000000000002',
    '9a4c0000-0000-4000-8000-000000000001',
    'Koramangala Flagship', 'KOR', 'koramangala@flexpos.demo',
    '+91 90000 10001', '12 80 Feet Road', 'Bengaluru', 'Karnataka',
    '560034', 'IN', 'Asia/Kolkata'
  ),
  (
    '9a4c0000-0000-4000-8000-000000000003',
    '9a4c0000-0000-4000-8000-000000000001',
    'Indiranagar Express', 'IND', 'indiranagar@flexpos.demo',
    '+91 90000 10002', '44 12th Main Road', 'Bengaluru', 'Karnataka',
    '560038', 'IN', 'Asia/Kolkata'
  )
on conflict (id) do update set
  name = excluded.name,
  code = excluded.code,
  email = excluded.email,
  phone = excluded.phone;

insert into public.roles (id, business_id, name, description, is_system) values
  ('9a4c0000-0000-4000-8000-000000000010', '9a4c0000-0000-4000-8000-000000000001', 'Owner', 'Full demo business access', true),
  ('9a4c0000-0000-4000-8000-000000000011', '9a4c0000-0000-4000-8000-000000000001', 'Administrator', 'Operations and reporting administrator', true),
  ('9a4c0000-0000-4000-8000-000000000012', '9a4c0000-0000-4000-8000-000000000001', 'Cashier', 'POS and register operator', true),
  ('9a4c0000-0000-4000-8000-000000000013', '9a4c0000-0000-4000-8000-000000000001', 'Inventory Manager', 'Catalog and stock manager', true),
  ('9a4c0000-0000-4000-8000-000000000014', '9a4c0000-0000-4000-8000-000000000001', 'Purchase Manager', 'Supplier and purchasing manager', true),
  ('9a4c0000-0000-4000-8000-000000000015', '9a4c0000-0000-4000-8000-000000000001', 'Accountant', 'Accounting and expense reviewer', true),
  ('9a4c0000-0000-4000-8000-000000000016', '9a4c0000-0000-4000-8000-000000000001', 'Branch Manager', 'Branch operations manager', true)
on conflict (id) do nothing;

insert into public.role_permissions (role_id, permission_code)
select '9a4c0000-0000-4000-8000-000000000010', permission_code
from public.role_permissions rp
join public.roles r on r.id = rp.role_id
where r.business_id = 'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8'
  and r.name = 'Owner'
on conflict (role_id, permission_code) do nothing;

insert into public.role_permissions (role_id, permission_code)
select target.id, rp.permission_code
from public.roles target
join public.roles source on source.business_id = 'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8'
  and source.name = target.name
join public.role_permissions rp on rp.role_id = source.id
where target.business_id = '9a4c0000-0000-4000-8000-000000000001'
on conflict (role_id, permission_code) do nothing;

insert into public.memberships (
  id, business_id, user_id, role_id, status, branch_access_all, joined_at
) values
  ('9a4c0000-0000-4000-8000-000000000020', '9a4c0000-0000-4000-8000-000000000001', '01331716-1fbd-4780-bc16-b4dba20a96aa', '9a4c0000-0000-4000-8000-000000000010', 'active', true, now() - interval '30 days'),
  ('9a4c0000-0000-4000-8000-000000000021', '9a4c0000-0000-4000-8000-000000000001', 'b19328a2-ac43-4291-8ff1-615d153b0b0f', '9a4c0000-0000-4000-8000-000000000012', 'active', false, now() - interval '24 days'),
  ('9a4c0000-0000-4000-8000-000000000022', '9a4c0000-0000-4000-8000-000000000001', '73558bcb-8f47-4e36-9c3e-2ff4f7f16d98', '9a4c0000-0000-4000-8000-000000000016', 'active', false, now() - interval '20 days')
on conflict (id) do update set role_id = excluded.role_id, status = excluded.status;

insert into public.member_branch_access (membership_id, branch_id) values
  ('9a4c0000-0000-4000-8000-000000000021', '9a4c0000-0000-4000-8000-000000000002'),
  ('9a4c0000-0000-4000-8000-000000000022', '9a4c0000-0000-4000-8000-000000000002'),
  ('9a4c0000-0000-4000-8000-000000000022', '9a4c0000-0000-4000-8000-000000000003')
on conflict do nothing;

insert into public.business_feature_entitlements (
  business_id, module_code, is_enabled, source, updated_by
)
select '9a4c0000-0000-4000-8000-000000000001', code, true, 'business_type',
       '01331716-1fbd-4780-bc16-b4dba20a96aa'
from public.feature_modules
on conflict (business_id, module_code) do update set is_enabled = true;

insert into public.units (id, business_id, name, symbol, precision) values
  ('9a4c0000-0000-4000-8000-000000000100', '9a4c0000-0000-4000-8000-000000000001', 'Piece', 'pc', 0),
  ('9a4c0000-0000-4000-8000-000000000101', '9a4c0000-0000-4000-8000-000000000001', 'Kilogram', 'kg', 3),
  ('9a4c0000-0000-4000-8000-000000000102', '9a4c0000-0000-4000-8000-000000000001', 'Hour', 'hr', 2)
on conflict (business_id, name) do update set
  id = excluded.id,
  symbol = excluded.symbol,
  precision = excluded.precision;

insert into public.categories (id, business_id, name, color, sort_order) values
  ('9a4c0000-0000-4000-8000-000000000110', '9a4c0000-0000-4000-8000-000000000001', 'Beverages', '#2E7D32', 1),
  ('9a4c0000-0000-4000-8000-000000000111', '9a4c0000-0000-4000-8000-000000000001', 'Snacks', '#EF6C00', 2),
  ('9a4c0000-0000-4000-8000-000000000112', '9a4c0000-0000-4000-8000-000000000001', 'Personal Care', '#6A1B9A', 3),
  ('9a4c0000-0000-4000-8000-000000000113', '9a4c0000-0000-4000-8000-000000000001', 'Household', '#1565C0', 4),
  ('9a4c0000-0000-4000-8000-000000000114', '9a4c0000-0000-4000-8000-000000000001', 'Services', '#00838F', 5)
on conflict (id) do nothing;

insert into public.brands (id, business_id, name) values
  ('9a4c0000-0000-4000-8000-000000000120', '9a4c0000-0000-4000-8000-000000000001', 'Riverstone'),
  ('9a4c0000-0000-4000-8000-000000000121', '9a4c0000-0000-4000-8000-000000000001', 'Urban Harvest'),
  ('9a4c0000-0000-4000-8000-000000000122', '9a4c0000-0000-4000-8000-000000000001', 'Glow & Co.'),
  ('9a4c0000-0000-4000-8000-000000000123', '9a4c0000-0000-4000-8000-000000000001', 'FlexPOS Essentials')
on conflict (id) do nothing;

insert into public.tax_rates (id, business_id, name, rate, tax_type, is_inclusive) values
  ('9a4c0000-0000-4000-8000-000000000130', '9a4c0000-0000-4000-8000-000000000001', 'GST 0%', 0, 'gst', false),
  ('9a4c0000-0000-4000-8000-000000000131', '9a4c0000-0000-4000-8000-000000000001', 'GST 5%', 5, 'gst', false),
  ('9a4c0000-0000-4000-8000-000000000132', '9a4c0000-0000-4000-8000-000000000001', 'GST 18%', 18, 'gst', false)
on conflict (id) do nothing;

insert into public.products (
  id, business_id, category_id, brand_id, base_unit_id, tax_rate_id, name,
  description, product_type, hsn_sac, track_inventory,
  allow_fractional_quantity, is_favorite, attributes, created_by
) values
  ('9a4c0000-0000-4000-8000-000000000200', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000110', '9a4c0000-0000-4000-8000-000000000120', '9a4c0000-0000-4000-8000-000000000100', '9a4c0000-0000-4000-8000-000000000131', 'Riverstone Sparkling Water 750ml', 'Premium sparkling water for cafes and households.', 'goods', '22011010', true, false, true, '{"size":"750ml","origin":"Himalayan spring"}', '01331716-1fbd-4780-bc16-b4dba20a96aa'),
  ('9a4c0000-0000-4000-8000-000000000201', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000110', '9a4c0000-0000-4000-8000-000000000121', '9a4c0000-0000-4000-8000-000000000100', '9a4c0000-0000-4000-8000-000000000131', 'Urban Harvest Cold Brew 330ml', 'Ready-to-drink cold brew coffee.', 'goods', '22029990', true, false, true, '{"size":"330ml","caffeine":"medium"}', '01331716-1fbd-4780-bc16-b4dba20a96aa'),
  ('9a4c0000-0000-4000-8000-000000000202', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000111', '9a4c0000-0000-4000-8000-000000000121', '9a4c0000-0000-4000-8000-000000000100', '9a4c0000-0000-4000-8000-000000000131', 'Masala Trail Mix 200g', 'Roasted nuts and spices with a mild chilli finish.', 'goods', '20081990', true, false, false, '{"weight":"200g","allergens":"nuts"}', '01331716-1fbd-4780-bc16-b4dba20a96aa'),
  ('9a4c0000-0000-4000-8000-000000000203', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000111', '9a4c0000-0000-4000-8000-000000000123', '9a4c0000-0000-4000-8000-000000000100', '9a4c0000-0000-4000-8000-000000000131', 'Cocoa Oat Energy Bar', 'Oats, cocoa and dates with no refined sugar.', 'goods', '19041090', true, false, false, '{"weight":"55g","diet":"vegetarian"}', '01331716-1fbd-4780-bc16-b4dba20a96aa'),
  ('9a4c0000-0000-4000-8000-000000000204', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000112', '9a4c0000-0000-4000-8000-000000000122', '9a4c0000-0000-4000-8000-000000000100', '9a4c0000-0000-4000-8000-000000000132', 'Glow & Co. Hand Wash 300ml', 'Gentle citrus hand wash for home and office.', 'goods', '34013090', true, false, false, '{"size":"300ml","scent":"citrus"}', '01331716-1fbd-4780-bc16-b4dba20a96aa'),
  ('9a4c0000-0000-4000-8000-000000000205', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000113', '9a4c0000-0000-4000-8000-000000000123', '9a4c0000-0000-4000-8000-000000000100', '9a4c0000-0000-4000-8000-000000000132', 'FlexPOS Reusable Tote Bag', 'Branded cotton tote bag for everyday shopping.', 'goods', '42029290', true, false, false, '{"material":"cotton","color":"navy"}', '01331716-1fbd-4780-bc16-b4dba20a96aa'),
  ('9a4c0000-0000-4000-8000-000000000206', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000114', '9a4c0000-0000-4000-8000-000000000123', '9a4c0000-0000-4000-8000-000000000102', '9a4c0000-0000-4000-8000-000000000132', 'Gift Wrapping Service', 'Premium gift wrapping service.', 'service', '998599', false, true, false, '{"duration":"1 hour"}', '01331716-1fbd-4780-bc16-b4dba20a96aa'),
  ('9a4c0000-0000-4000-8000-000000000207', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000110', '9a4c0000-0000-4000-8000-000000000120', '9a4c0000-0000-4000-8000-000000000100', '9a4c0000-0000-4000-8000-000000000131', 'Riverstone Tonic 250ml', 'Botanical tonic water with quinine and lime.', 'goods', '22029990', true, false, false, '{"size":"250ml","flavor":"lime"}', '01331716-1fbd-4780-bc16-b4dba20a96aa')
on conflict (id) do nothing;

insert into public.product_variants (
  id, business_id, product_id, name, sku, cost_price, selling_price, mrp,
  attributes, tracking_mode
) values
  ('9a4c0000-0000-4000-8000-000000000210', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000200', '750ml bottle', 'RIV-WAT-750', 32, 55, 60, '{"pack":"single"}', 'none'),
  ('9a4c0000-0000-4000-8000-000000000211', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000201', '330ml can', 'URB-CBR-330', 68, 125, 135, '{"pack":"single"}', 'none'),
  ('9a4c0000-0000-4000-8000-000000000212', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000202', '200g pouch', 'MAS-TRM-200', 105, 185, 199, '{"pack":"single"}', 'none'),
  ('9a4c0000-0000-4000-8000-000000000213', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000203', '55g bar', 'COC-OAT-055', 42, 79, 89, '{"pack":"single"}', 'none'),
  ('9a4c0000-0000-4000-8000-000000000214', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000204', '300ml pump', 'GLO-HWS-300', 96, 169, 189, '{"pack":"single"}', 'none'),
  ('9a4c0000-0000-4000-8000-000000000215', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000205', 'Navy tote', 'FPO-TOT-NAV', 120, 249, 299, '{"size":"medium"}', 'none'),
  ('9a4c0000-0000-4000-8000-000000000216', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000206', 'Standard service', 'FPO-GIFT-SVC', 0, 99, 99, '{}', 'none'),
  ('9a4c0000-0000-4000-8000-000000000217', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000207', '250ml bottle', 'RIV-TON-250', 28, 49, 55, '{"pack":"single"}', 'none')
on conflict (id) do nothing;

insert into public.product_barcodes (id, business_id, variant_id, barcode, barcode_type, is_primary) values
  ('9a4c0000-0000-4000-8000-000000000220', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000210', '8909000000011', 'ean13', true),
  ('9a4c0000-0000-4000-8000-000000000221', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000211', '8909000000028', 'ean13', true),
  ('9a4c0000-0000-4000-8000-000000000222', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000212', '8909000000035', 'ean13', true),
  ('9a4c0000-0000-4000-8000-000000000223', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000213', '8909000000042', 'ean13', true),
  ('9a4c0000-0000-4000-8000-000000000224', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000214', '8909000000059', 'ean13', true),
  ('9a4c0000-0000-4000-8000-000000000225', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000215', '8909000000066', 'ean13', true),
  ('9a4c0000-0000-4000-8000-000000000226', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000217', '8909000000073', 'ean13', true)
on conflict (id) do nothing;

insert into public.warehouses (id, business_id, branch_id, name, code, is_default) values
  ('9a4c0000-0000-4000-8000-000000000300', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000002', 'Koramangala Main Warehouse', 'KOR-MAIN', false),
  ('9a4c0000-0000-4000-8000-000000000301', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000003', 'Indiranagar Backroom', 'IND-BACK', false),
  ('9a4c0000-0000-4000-8000-000000000302', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000002', 'Returns Quarantine', 'KOR-RET', false)
on conflict (business_id, code) do update set
  name = excluded.name,
  branch_id = excluded.branch_id,
  is_default = false;

update public.warehouses
set is_default = false
where business_id = '9a4c0000-0000-4000-8000-000000000001';

update public.warehouses
set is_default = true
where id in ('9a4c0000-0000-4000-8000-000000000300', '9a4c0000-0000-4000-8000-000000000301');

insert into public.inventory_balances (
  business_id, warehouse_id, variant_id, quantity_on_hand, quantity_reserved,
  reorder_point, safety_stock, average_cost
) values
  ('9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000300', '9a4c0000-0000-4000-8000-000000000210', 84, 4, 30, 20, 32),
  ('9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000300', '9a4c0000-0000-4000-8000-000000000211', 19, 2, 24, 12, 68),
  ('9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000300', '9a4c0000-0000-4000-8000-000000000212', 7, 0, 18, 10, 105),
  ('9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000300', '9a4c0000-0000-4000-8000-000000000213', 46, 3, 20, 12, 42),
  ('9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000300', '9a4c0000-0000-4000-8000-000000000214', 12, 1, 15, 8, 96),
  ('9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000300', '9a4c0000-0000-4000-8000-000000000215', 28, 0, 10, 5, 120),
  ('9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000300', '9a4c0000-0000-4000-8000-000000000217', 2, 0, 8, 4, 25),
  ('9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000301', '9a4c0000-0000-4000-8000-000000000210', 36, 0, 12, 8, 32)
on conflict (warehouse_id, variant_id) do update set
  quantity_on_hand = excluded.quantity_on_hand,
  quantity_reserved = excluded.quantity_reserved,
  reorder_point = excluded.reorder_point,
  safety_stock = excluded.safety_stock,
  average_cost = excluded.average_cost;

insert into public.customer_groups (id, business_id, name, code, description) values
  ('9a4c0000-0000-4000-8000-000000000400', '9a4c0000-0000-4000-8000-000000000001', 'Loyalty Members', 'LOYAL', 'Customers enrolled in FlexPOS loyalty benefits.'),
  ('9a4c0000-0000-4000-8000-000000000401', '9a4c0000-0000-4000-8000-000000000001', 'Cafe Partners', 'CAFE', 'Small business and cafe accounts.'),
  ('9a4c0000-0000-4000-8000-000000000402', '9a4c0000-0000-4000-8000-000000000001', 'Walk-in Customers', 'WALKIN', 'Occasional retail customers.')
on conflict (id) do nothing;

insert into public.customers (
  id, business_id, code, name, phone, email, gstin, billing_address,
  shipping_address, credit_limit, loyalty_points, group_id
) values
  ('9a4c0000-0000-4000-8000-000000000410', '9a4c0000-0000-4000-8000-000000000001', 'CUS-1001', 'Ananya Rao', '+91 98765 10001', 'ananya.rao@example.demo', null, '{"line1":"18 5th Cross","city":"Bengaluru","state":"Karnataka","postal_code":"560034"}', '{"line1":"18 5th Cross","city":"Bengaluru","state":"Karnataka","postal_code":"560034"}', 5000, 1840, '9a4c0000-0000-4000-8000-000000000400'),
  ('9a4c0000-0000-4000-8000-000000000411', '9a4c0000-0000-4000-8000-000000000001', 'CUS-1002', 'Vikram Mehta', '+91 98765 10002', 'vikram.mehta@example.demo', null, '{"line1":"90 2nd Main","city":"Bengaluru","state":"Karnataka","postal_code":"560038"}', '{"line1":"90 2nd Main","city":"Bengaluru","state":"Karnataka","postal_code":"560038"}', 8000, 960, '9a4c0000-0000-4000-8000-000000000400'),
  ('9a4c0000-0000-4000-8000-000000000412', '9a4c0000-0000-4000-8000-000000000001', 'CUS-1003', 'Green Bean Cafe', '+91 90000 20003', 'accounts@greenbean.example.demo', '29ABCDE1234G1Z2', '{"line1":"7 1st Avenue","city":"Bengaluru","state":"Karnataka","postal_code":"560038"}', '{"line1":"7 1st Avenue","city":"Bengaluru","state":"Karnataka","postal_code":"560038"}', 50000, 420, '9a4c0000-0000-4000-8000-000000000401'),
  ('9a4c0000-0000-4000-8000-000000000413', '9a4c0000-0000-4000-8000-000000000001', 'CUS-1004', 'Meera Shah', '+91 98765 10004', 'meera.shah@example.demo', null, '{"line1":"14 Palm Grove","city":"Bengaluru","state":"Karnataka","postal_code":"560034"}', '{"line1":"14 Palm Grove","city":"Bengaluru","state":"Karnataka","postal_code":"560034"}', 12000, 2750, '9a4c0000-0000-4000-8000-000000000400'),
  ('9a4c0000-0000-4000-8000-000000000414', '9a4c0000-0000-4000-8000-000000000001', 'CUS-1005', 'Studio Nineteen', '+91 90000 20005', 'hello@studionineteen.example.demo', null, '{"line1":"19 Residency Road","city":"Bengaluru","state":"Karnataka","postal_code":"560025"}', '{"line1":"19 Residency Road","city":"Bengaluru","state":"Karnataka","postal_code":"560025"}', 25000, 600, '9a4c0000-0000-4000-8000-000000000401'),
  ('9a4c0000-0000-4000-8000-000000000415', '9a4c0000-0000-4000-8000-000000000001', 'CUS-1006', 'Rohan Kapoor', '+91 98765 10006', 'rohan.kapoor@example.demo', null, '{"line1":"5 Lake View","city":"Bengaluru","state":"Karnataka","postal_code":"560103"}', '{"line1":"5 Lake View","city":"Bengaluru","state":"Karnataka","postal_code":"560103"}', 3000, 130, '9a4c0000-0000-4000-8000-000000000402'),
  ('9a4c0000-0000-4000-8000-000000000416', '9a4c0000-0000-4000-8000-000000000001', 'CUS-1007', 'Aditi Nair', '+91 98765 10007', 'aditi.nair@example.demo', null, '{"line1":"31 Market Street","city":"Bengaluru","state":"Karnataka","postal_code":"560001"}', '{"line1":"31 Market Street","city":"Bengaluru","state":"Karnataka","postal_code":"560001"}', 3000, 410, '9a4c0000-0000-4000-8000-000000000402'),
  ('9a4c0000-0000-4000-8000-000000000417', '9a4c0000-0000-4000-8000-000000000001', 'CUS-1008', 'Northstar Events', '+91 90000 20008', 'procurement@northstar.example.demo', '29ABCDE1234N1Z8', '{"line1":"102 Outer Ring Road","city":"Bengaluru","state":"Karnataka","postal_code":"560103"}', '{"line1":"102 Outer Ring Road","city":"Bengaluru","state":"Karnataka","postal_code":"560103"}', 100000, 1200, '9a4c0000-0000-4000-8000-000000000401')
on conflict (id) do nothing;

insert into public.suppliers (
  id, business_id, code, name, contact_name, phone, email, gstin,
  billing_address, credit_days, notes
) values
  ('9a4c0000-0000-4000-8000-000000000500', '9a4c0000-0000-4000-8000-000000000001', 'SUP-001', 'Southern Beverages Distribution', 'Karthik Menon', '+91 90000 30001', 'orders@southernbev.example.demo', '29AAACS1234A1Z1', '{"line1":"22 Peenya Industrial Area","city":"Bengaluru","state":"Karnataka","postal_code":"560058"}', 30, 'Primary beverages distributor.'),
  ('9a4c0000-0000-4000-8000-000000000501', '9a4c0000-0000-4000-8000-000000000001', 'SUP-002', 'Harvest Foods Wholesale', 'Nisha Kulkarni', '+91 90000 30002', 'sales@harvestfoods.example.demo', '29AAACH1234B1Z2', '{"line1":"11 APMC Yard","city":"Bengaluru","state":"Karnataka","postal_code":"560022"}', 21, 'Snacks and packaged foods.'),
  ('9a4c0000-0000-4000-8000-000000000502', '9a4c0000-0000-4000-8000-000000000001', 'SUP-003', 'Glow Essentials India', 'Ritu Malhotra', '+91 90000 30003', 'trade@glowessentials.example.demo', '29AAACG1234C1Z3', '{"line1":"9 Bommasandra Link","city":"Bengaluru","state":"Karnataka","postal_code":"560099"}', 45, 'Personal care and household.'),
  ('9a4c0000-0000-4000-8000-000000000503', '9a4c0000-0000-4000-8000-000000000001', 'SUP-004', 'Print & Pack Studio', 'Sanjay Bhat', '+91 90000 30004', 'hello@printpack.example.demo', null, '{"line1":"5 Wilson Garden","city":"Bengaluru","state":"Karnataka","postal_code":"560027"}', 15, 'Packaging and retail supplies.')
on conflict (id) do nothing;

insert into public.registers (id, business_id, branch_id, name, code, assigned_user_id) values
  ('9a4c0000-0000-4000-8000-000000000600', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000002', 'Front Counter 1', 'KOR-REG-1', 'b19328a2-ac43-4291-8ff1-615d153b0b0f'),
  ('9a4c0000-0000-4000-8000-000000000601', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000002', 'Front Counter 2', 'KOR-REG-2', null),
  ('9a4c0000-0000-4000-8000-000000000602', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000003', 'Express Counter', 'IND-REG-1', '73558bcb-8f47-4e36-9c3e-2ff4f7f16d98')
on conflict (id) do nothing;

insert into public.register_shifts (
  id, business_id, register_id, opened_by, closed_by, status, opening_cash,
  expected_cash, closing_cash, difference_amount, opened_at, closed_at, notes
) values
  ('9a4c0000-0000-4000-8000-000000000610', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000600', 'b19328a2-ac43-4291-8ff1-615d153b0b0f', '73558bcb-8f47-4e36-9c3e-2ff4f7f16d98', 'closed', 5000, 18250, 18150, -100, now() - interval '12 days', now() - interval '12 days' + interval '9 hours', 'Busy Saturday close; small cash variance recorded.'),
  ('9a4c0000-0000-4000-8000-000000000611', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000602', '73558bcb-8f47-4e36-9c3e-2ff4f7f16d98', '73558bcb-8f47-4e36-9c3e-2ff4f7f16d98', 'closed', 3000, 12100, 12100, 0, now() - interval '6 days', now() - interval '6 days' + interval '8 hours', 'Balanced close.'),
  ('9a4c0000-0000-4000-8000-000000000612', '9a4c0000-0000-4000-8000-000000000001', '9a4c0000-0000-4000-8000-000000000600', 'b19328a2-ac43-4291-8ff1-615d153b0b0f', null, 'open', 5000, null, null, null, now() - interval '2 hours', null, 'Current review shift.')
on conflict (id) do nothing;

insert into public.promotions (
  id, business_id, branch_id, code, name, discount_type, discount_value,
  minimum_subtotal, usage_limit, redeemed_count, starts_at, ends_at,
  is_active, created_by
) values (
  '9a4c0000-0000-4000-8000-000000000800',
  '9a4c0000-0000-4000-8000-000000000001', null,
  'WELCOME10', 'Welcome weekend offer', 'percentage', 10, 500, 100, 8,
  now() - interval '30 days', now() + interval '60 days', true,
  '01331716-1fbd-4780-bc16-b4dba20a96aa'
)
on conflict (id) do nothing;

commit;
