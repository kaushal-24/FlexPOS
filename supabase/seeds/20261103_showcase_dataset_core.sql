-- Synthetic, presentation-ready showcase data for FlexPOS.
-- This seed is isolated to two new businesses and is safe to re-run.
-- All people, addresses, invoices, and provider references are fictional.
-- Product image paths reuse existing demo assets already in the private
-- product-images bucket so the catalog renders with real image content.

begin;

select set_config('request.jwt.claim.sub', '01331716-1fbd-4780-bc16-b4dba20a96aa', true);

insert into public.businesses (
  id, name, slug, business_type, currency_code, timezone, country_code,
  tax_registration_number, invoice_prefix, receipt_footer, receipt_template,
  receipt_qr_payload, receipt_show_logo, receipt_show_qr, receipt_paper_width,
  stock_alert_email_enabled, created_by
) values
  (
    '7b000000-0000-4000-8000-000000000001',
    'FlexPOS Showcase Retail', 'flexpos-showcase-retail', 'retail', 'INR',
    'Asia/Kolkata', 'IN', '29SHOWCASE0001Z5', 'FSR',
    'Thank you for shopping with FlexPOS Showcase Retail.', 'detailed',
    'upi://pay?pa=kaushal.pithva@ptaxis&pn=FlexPOS%20Showcase%20Retail', true,
    true, '80', false, '01331716-1fbd-4780-bc16-b4dba20a96aa'
  ),
  (
    '7b000000-0000-4000-8000-000000000002',
    'FlexPOS Showcase Cafe', 'flexpos-showcase-cafe', 'restaurant', 'INR',
    'Asia/Kolkata', 'IN', '29SHOWCASE0002Z6', 'FSC',
    'Thank you for visiting FlexPOS Showcase Cafe.', 'minimal',
    'upi://pay?pa=kaushal.pithva@ptaxis&pn=FlexPOS%20Showcase%20Cafe', true,
    true, '58', false, '01331716-1fbd-4780-bc16-b4dba20a96aa'
  )
on conflict (id) do update set
  name = excluded.name,
  slug = excluded.slug,
  business_type = excluded.business_type,
  receipt_footer = excluded.receipt_footer,
  receipt_template = excluded.receipt_template,
  receipt_qr_payload = excluded.receipt_qr_payload,
  receipt_paper_width = excluded.receipt_paper_width;

do $$
declare
  b record;
  r record;
  v_admin constant uuid := '01331716-1fbd-4780-bc16-b4dba20a96aa';
  v_cashier constant uuid := 'b19328a2-ac43-4291-8ff1-615d153b0b0f';
  v_manager constant uuid := '73558bcb-8f47-4e36-9c3e-2ff4f7f16d98';
  v_images text[] := array[
    'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8/3cab09a4-6a71-4c6a-95b0-4d1a7be56b2b/product.jpeg',
    'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8/36599c7e-52ee-4f81-87af-c4a26c1605c1/product.jpeg',
    'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8/7698bc71-d40b-4cea-9f99-4d6076d89743/product.jpeg',
    'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8/c82f6a20-e7ed-4ae7-8aa7-0d64a7426c89/product.jpeg',
    'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8/025f20f4-466c-464b-a342-6f70619f57de/product.jpeg',
    'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8/293a3801-9312-4b1a-8c49-39c4017a069b/product.jpeg',
    'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8/7157a936-4c3e-449e-9b8d-918701ccebd3/product.jpeg',
    'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8/66ca5605-f476-4c15-8cee-4b9834e396b3/product.png'
  ];
begin
  for b in
    select * from (values
      ('7b000000-0000-4000-8000-000000000001'::uuid, 'Retail', 'Bengaluru'),
      ('7b000000-0000-4000-8000-000000000002'::uuid, 'Cafe', 'Pune')
    ) as x(id, label, city)
  loop
    insert into public.branches (
      id, business_id, name, code, email, phone, address_line_1, city,
      state_region, postal_code, country_code, timezone
    )
    select
      md5(b.id::text || '|branch|' || i::text)::uuid,
      b.id,
      format('%s %s Branch %s', b.label, b.city, i),
      format('%s-%s', upper(left(b.label, 3)), lpad(i::text, 2, '0')),
      format('branch%02s@%s.flexpos.demo', i, lower(b.label)),
      format('+91 88000 %s', lpad((20000 + i)::text, 5, '0')),
      format('%s Market Road %s', b.city, i),
      b.city,
      case b.city when 'Bengaluru' then 'Karnataka' else 'Maharashtra' end,
      case b.city when 'Bengaluru' then '560034' else '411001' end,
      'IN', 'Asia/Kolkata'
    from generate_series(1, 4) as s(i)
    on conflict (id) do update set name = excluded.name, city = excluded.city;

    insert into public.roles (id, business_id, name, description, is_system)
    select
      md5(b.id::text || '|role|' || role_name)::uuid,
      b.id,
      role_name,
      description,
      true
    from (values
      ('Owner', 'Full business access'),
      ('Administrator', 'Operations and reporting administration'),
      ('Branch Manager', 'Branch operations and staff supervision'),
      ('Cashier', 'POS and register operations'),
      ('Inventory Manager', 'Catalog, stock, and adjustments'),
      ('Purchase Manager', 'Suppliers, purchasing, and receipts'),
      ('Accountant', 'Accounting, tax, and expense review')
    ) as roles(role_name, description)
    on conflict (id) do update set description = excluded.description;

    insert into public.role_permissions (role_id, permission_code)
    select
      md5(b.id::text || '|role|' || target.name)::uuid,
      rp.permission_code
    from public.roles target
    join public.roles source
      on source.business_id = 'c2c28e90-c16f-4c34-91f6-d8cc19a36ff8'
     and source.name = target.name
    join public.role_permissions rp on rp.role_id = source.id
    where target.business_id = b.id
    on conflict (role_id, permission_code) do nothing;

    insert into public.role_permissions (role_id, permission_code)
    select
      md5(b.id::text || '|role|Owner')::uuid,
      code
    from public.permissions
    on conflict (role_id, permission_code) do nothing;

    insert into public.memberships (
      id, business_id, user_id, role_id, status, branch_access_all, joined_at
    ) values
      (md5(b.id::text || '|membership|owner')::uuid, b.id, v_admin,
       md5(b.id::text || '|role|Owner')::uuid, 'active', true, now() - interval '45 days'),
      (md5(b.id::text || '|membership|cashier')::uuid, b.id, v_cashier,
       md5(b.id::text || '|role|Cashier')::uuid, 'active', false, now() - interval '31 days'),
      (md5(b.id::text || '|membership|manager')::uuid, b.id, v_manager,
       md5(b.id::text || '|role|Branch Manager')::uuid, 'active', false, now() - interval '28 days')
    on conflict (id) do update set role_id = excluded.role_id, status = excluded.status;

    insert into public.member_branch_access (membership_id, branch_id)
    select md5(b.id::text || '|membership|cashier')::uuid,
           md5(b.id::text || '|branch|' || i::text)::uuid
    from generate_series(1, 2) as s(i)
    on conflict do nothing;

    insert into public.member_branch_access (membership_id, branch_id)
    select md5(b.id::text || '|membership|manager')::uuid,
           md5(b.id::text || '|branch|' || i::text)::uuid
    from generate_series(1, 4) as s(i)
    on conflict do nothing;

    insert into public.business_feature_entitlements (
      business_id, module_code, is_enabled, source, updated_by
    )
    select b.id, code, true, 'administrator', v_admin
    from public.feature_modules
    on conflict (business_id, module_code) do update set
      is_enabled = excluded.is_enabled,
      updated_by = excluded.updated_by;

    insert into public.units (id, business_id, name, symbol, precision)
    select
      md5(b.id::text || '|unit|' || i::text)::uuid,
      b.id,
      case i when 1 then 'Piece' when 2 then 'Kilogram' when 3 then 'Gram'
        when 4 then 'Litre' when 5 then 'Millilitre' when 6 then 'Hour'
        when 7 then 'Box' else 'Pack' end,
      case i when 1 then 'pc' when 2 then 'kg' when 3 then 'g'
        when 4 then 'L' when 5 then 'ml' when 6 then 'hr'
        when 7 then 'box' else 'pk' end,
      case when i in (2, 3, 4, 5) then 3 else 0 end
    from generate_series(1, 8) as s(i)
    on conflict (business_id, name) do update set
      id = excluded.id,
      symbol = excluded.symbol,
      precision = excluded.precision;

    insert into public.categories (id, business_id, name, color, sort_order)
    select
      md5(b.id::text || '|category|' || i::text)::uuid,
      b.id,
      (array['Beverages','Breakfast','Bakery','Snacks','Fresh Produce','Pantry','Personal Care','Household','Cafe Meals','Desserts','Merchandise','Services'])[i],
      (array['#2E7D32','#1565C0','#8D6E63','#EF6C00','#43A047','#6D4C41','#6A1B9A','#00838F','#C62828','#AD1457','#283593','#546E7A'])[i],
      i
    from generate_series(1, 12) as s(i)
    on conflict (id) do update set name = excluded.name, color = excluded.color;

    insert into public.brands (id, business_id, name)
    select
      md5(b.id::text || '|brand|' || i::text)::uuid,
      b.id,
      format('%s Brand %s', b.label, i)
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set name = excluded.name;

    insert into public.tax_rates (id, business_id, name, rate, tax_type, is_inclusive)
    select
      md5(b.id::text || '|tax|' || i::text)::uuid,
      b.id,
      format('GST %s%%', rate), rate, 'gst', false
    from unnest(array[0, 5, 12, 18]::numeric[]) with ordinality as t(rate, i)
    on conflict (id) do update set rate = excluded.rate;

    insert into public.customer_groups (id, business_id, name, code, description)
    select
      md5(b.id::text || '|group|' || i::text)::uuid,
      b.id,
      (array['Loyalty Members','Wholesale Partners','Cafe Regulars','Walk-in Customers'])[i],
      (array['LOYAL','WHOLE','CAFE','WALK'])[i],
      'Synthetic showcase segment for review demonstrations.'
    from generate_series(1, 4) as s(i)
    on conflict (id) do update set name = excluded.name;

    insert into public.warehouses (id, business_id, branch_id, name, code, is_default)
    select
      md5(b.id::text || '|warehouse|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|branch|' || (((i - 1) % 4) + 1)::text)::uuid,
      format('%s Warehouse %s', b.label, i),
      format('%s-WH-%02s', upper(left(b.label, 3)), i),
      false
    from generate_series(1, 4) as s(i)
    on conflict (id) do update set name = excluded.name, is_default = excluded.is_default;

    update public.warehouses
    set name = format('%s Default Warehouse %s', b.label, branch_number),
        code = format('%s-DEFAULT-%02s', upper(left(b.label, 3)), branch_number)
    from (
      select branch_id, row_number() over (order by created_at)::integer as branch_number
      from public.warehouses
      where business_id = b.id and is_default
    ) defaults
    where public.warehouses.branch_id = defaults.branch_id
      and public.warehouses.business_id = b.id
      and public.warehouses.is_default;

    insert into public.products (
      id, business_id, category_id, brand_id, base_unit_id, tax_rate_id,
      name, description, product_type, hsn_sac, track_inventory,
      allow_fractional_quantity, is_favorite, is_active, attributes,
      created_by, image_path
    )
    select
      md5(b.id::text || '|product|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|category|' || (((i - 1) % 12) + 1)::text)::uuid,
      md5(b.id::text || '|brand|' || (((i - 1) % 8) + 1)::text)::uuid,
      md5(b.id::text || '|unit|' || case when i % 10 = 0 then '6' else '1' end)::uuid,
      md5(b.id::text || '|tax|' || (((i - 1) % 4) + 1)::text)::uuid,
      format('%s %s %s', b.label, (array['Signature','Classic','Reserve','Everyday','Seasonal','Organic'])[1 + ((i - 1) % 6)], lpad(i::text, 3, '0')),
      format('Presentation-ready synthetic %s catalogue item %s for review.', lower(b.label), i),
      case when i % 10 = 0 then 'service' else 'goods' end,
      format('%s%06s', case when b.label = 'Retail' then '2106' else '9963' end, i),
      i % 10 <> 0,
      i % 7 = 0,
      i % 11 = 0,
      true,
      jsonb_build_object('showcase', true, 'sequence', i, 'segment', b.label),
      v_admin,
      v_images[1 + ((i - 1) % array_length(v_images, 1))]
    from generate_series(1, 124) as s(i)
    on conflict (id) do update set
      name = excluded.name,
      description = excluded.description,
      image_path = excluded.image_path,
      is_active = true;

    insert into public.product_variants (
      id, business_id, product_id, name, sku, cost_price, selling_price, mrp,
      weight, attributes, tracking_mode
    )
    select
      md5(b.id::text || '|variant|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|product|' || i::text)::uuid,
      case when i % 10 = 0 then 'Standard service' else 'Standard pack' end,
      format('%s-%s', upper(left(b.label, 3)), lpad(i::text, 5, '0')),
      round((35 + ((i * 17) % 420))::numeric, 2),
      round((75 + ((i * 37) % 920))::numeric, 2),
      round((95 + ((i * 43) % 1100))::numeric, 2),
      case when i % 7 = 0 then round((0.25 + (i % 8) * 0.1)::numeric, 2) else null end,
      jsonb_build_object('pack_size', case when i % 4 = 0 then 'family' else 'single' end, 'showcase_index', i),
      'none'
    from generate_series(1, 124) as s(i)
    on conflict (id) do update set
      sku = excluded.sku,
      selling_price = excluded.selling_price,
      mrp = excluded.mrp;

    insert into public.product_barcodes (
      id, business_id, variant_id, barcode, barcode_type, is_primary
    )
    select
      md5(b.id::text || '|barcode|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|variant|' || i::text)::uuid,
      case when b.label = 'Retail'
        then '890700' || lpad(i::text, 7, '0')
        else '890800' || lpad(i::text, 7, '0') end,
      'ean13', true
    from generate_series(1, 124) as s(i)
    on conflict (id) do update set barcode = excluded.barcode;

    insert into public.inventory_balances (
      business_id, warehouse_id, variant_id, quantity_on_hand,
      quantity_reserved, reorder_point, safety_stock, average_cost
    )
    select
      b.id,
      md5(b.id::text || '|warehouse|' || w::text)::uuid,
      md5(b.id::text || '|variant|' || i::text)::uuid,
      case when i % 13 = 0 then 0 else 18 + ((i * 7) % 160) end,
      case when i % 13 = 0 then 0 when i % 9 = 0 then 2 else 0 end,
      12 + (i % 24),
      6 + (i % 12),
      round((35 + ((i * 17) % 420))::numeric, 2)
    from generate_series(1, 124) as s(i)
    cross join generate_series(1, 2) as warehouses(w)
    on conflict (warehouse_id, variant_id) do update set
      quantity_on_hand = excluded.quantity_on_hand,
      quantity_reserved = excluded.quantity_reserved,
      reorder_point = excluded.reorder_point,
      safety_stock = excluded.safety_stock,
      average_cost = excluded.average_cost;

    insert into public.inventory_balances (
      business_id, warehouse_id, variant_id, quantity_on_hand,
      quantity_reserved, reorder_point, safety_stock, average_cost
    )
    select
      b.id,
      w.id,
      md5(b.id::text || '|variant|' || i::text)::uuid,
      case when i % 13 = 0 then 0 else 24 + ((i * 5) % 120) end,
      case when i % 13 = 0 then 0 when i % 9 = 0 then 1 else 0 end,
      12 + (i % 24),
      6 + (i % 12),
      round((35 + ((i * 17) % 420))::numeric, 2)
    from public.warehouses w
    cross join generate_series(1, 124) as s(i)
    where w.business_id = b.id and w.is_default
    on conflict (warehouse_id, variant_id) do update set
      quantity_on_hand = excluded.quantity_on_hand,
      quantity_reserved = excluded.quantity_reserved,
      reorder_point = excluded.reorder_point,
      safety_stock = excluded.safety_stock,
      average_cost = excluded.average_cost;

    insert into public.customers (
      id, business_id, code, name, phone, email, gstin, billing_address,
      shipping_address, credit_limit, loyalty_points, group_id
    )
    select
      md5(b.id::text || '|customer|' || i::text)::uuid,
      b.id,
      format('%s-CUS-%04s', upper(left(b.label, 3)), i),
      format('%s %s %s', (array['Aarav','Ananya','Kabir','Meera','Riya','Vikram','Ishaan','Nisha','Zoya','Arjun'])[1 + ((i - 1) % 10)], (array['Shah','Rao','Mehta','Nair','Kapoor','Kulkarni','Patel','Iyer'])[1 + ((i - 1) % 8)], lpad(i::text, 3, '0')),
      format('+91 98%03s %04s', (100 + (i % 899)), i),
      format('customer%04s@showcase.flexpos.demo', i),
      case when i % 5 = 0 then format('29DEMO%07sZ5', i) else null end,
      jsonb_build_object('line1', format('%s Demo Avenue', i), 'city', b.city, 'state', case b.city when 'Bengaluru' then 'Karnataka' else 'Maharashtra' end, 'postal_code', case b.city when 'Bengaluru' then '560034' else '411001' end),
      jsonb_build_object('line1', format('%s Demo Avenue', i), 'city', b.city, 'state', case b.city when 'Bengaluru' then 'Karnataka' else 'Maharashtra' end, 'postal_code', case b.city when 'Bengaluru' then '560034' else '411001' end),
      5000 + ((i * 700) % 95000),
      (i * 37) % 4200,
      md5(b.id::text || '|group|' || (((i - 1) % 4) + 1)::text)::uuid
    from generate_series(1, 124) as s(i)
    on conflict (id) do update set name = excluded.name, phone = excluded.phone, email = excluded.email;

    insert into public.suppliers (
      id, business_id, code, name, contact_name, phone, email, gstin,
      billing_address, credit_days, notes
    )
    select
      md5(b.id::text || '|supplier|' || i::text)::uuid,
      b.id,
      format('%s-SUP-%04s', upper(left(b.label, 3)), i),
      format('%s Supply Partner %s', b.label, lpad(i::text, 3, '0')),
      format('Account Manager %s', i),
      format('+91 97%03s %04s', (100 + (i % 899)), i),
      format('supplier%04s@showcase.flexpos.demo', i),
      format('29SUP%07sZ1', i),
      jsonb_build_object('line1', format('%s Industrial Estate', i), 'city', b.city, 'state', case b.city when 'Bengaluru' then 'Karnataka' else 'Maharashtra' end, 'postal_code', case b.city when 'Bengaluru' then '560058' else '411038' end),
      7 + (i % 45),
      'Synthetic supplier record for purchasing and supplier-performance review.'
    from generate_series(1, 124) as s(i)
    on conflict (id) do update set name = excluded.name, credit_days = excluded.credit_days;

    insert into public.registers (id, business_id, branch_id, name, code, assigned_user_id)
    select
      md5(b.id::text || '|register|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|branch|' || (((i - 1) % 4) + 1)::text)::uuid,
      format('%s Counter %s', b.label, i),
      format('%s-REG-%02s', upper(left(b.label, 3)), i),
      case when i % 3 = 1 then v_cashier when i % 3 = 2 then v_manager else v_admin end
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set name = excluded.name, assigned_user_id = excluded.assigned_user_id;

    insert into public.register_shifts (
      id, business_id, register_id, opened_by, closed_by, status, opening_cash,
      expected_cash, closing_cash, difference_amount, opened_at, closed_at, notes
    )
    select
      md5(b.id::text || '|shift|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|register|' || (((i - 1) % 8) + 1)::text)::uuid,
      case when i % 3 = 1 then v_cashier when i % 3 = 2 then v_manager else v_admin end,
      case when i = 24 then null else v_manager end,
      case when i = 24 then 'open' else 'closed' end,
      3000 + (i * 250),
      case when i = 24 then null else 3000 + (i * 250) + (i * 180) end,
      case when i = 24 then null else 3000 + (i * 250) + (i * 180) + case when i % 10 = 0 then -100 else 0 end end,
      case when i = 24 then null else case when i % 10 = 0 then -100 else 0 end end,
      now() - make_interval(days => i),
      case when i = 24 then null else now() - make_interval(days => i) + interval '8 hours' end,
      case when i = 24 then 'Current showcase shift.' else 'Closed showcase shift for reporting history.' end
    from generate_series(1, 24) as s(i)
    on conflict (id) do update set status = excluded.status, closing_cash = excluded.closing_cash;
  end loop;
end $$;

commit;
