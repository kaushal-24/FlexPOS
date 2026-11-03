-- Replace showcase product labels with a realistic, business-specific catalog.
-- Historical sale/purchase rows are intentionally preserved: only the active
-- catalog metadata and its active variants are updated in place.
-- Product images use stable public photo CDN URLs; the Flutter image widget
-- also continues to support private Supabase Storage paths.

begin;

do $$
declare
  b record;
  p record;
  v record;
  product_name text;
  product_description text;
  product_image text;
  pack_size text;
  catalog_index integer;
  pack_index integer;
  names text[];
  descriptions text[];
  sizes text[];
  images text[];
  prices numeric[];
  costs numeric[];
begin
  images := array[
    'https://images.unsplash.com/photo-1542838132-92c53300491e?auto=format&fit=crop&w=900&q=85',
    'https://images.unsplash.com/photo-1606787366850-de6330128bfc?auto=format&fit=crop&w=900&q=85',
    'https://images.unsplash.com/photo-1583258292688-d0213dc5a3a8?auto=format&fit=crop&w=900&q=85',
    'https://images.unsplash.com/photo-1498837167922-ddd27525d352?auto=format&fit=crop&w=900&q=85',
    'https://images.unsplash.com/photo-1547592180-85f173990554?auto=format&fit=crop&w=900&q=85',
    'https://images.unsplash.com/photo-1504674900247-0877df9cc836?auto=format&fit=crop&w=900&q=85',
    'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?auto=format&fit=crop&w=900&q=85',
    'https://images.unsplash.com/photo-1556228578-8c89e6adf883?auto=format&fit=crop&w=900&q=85',
    'https://images.unsplash.com/photo-1553456558-aff63285bdd1?auto=format&fit=crop&w=900&q=85',
    'https://images.unsplash.com/photo-1600891964599-f61ba0e24092?auto=format&fit=crop&w=900&q=85'
  ];

  for b in
    select id, name
    from public.businesses
    where archived_at is null
      and name in ('BigMart', 'FlexPOS', 'FlexPOS Retail', 'La Quench Cafe')
  loop
    if b.name = 'BigMart' then
      names := array[
        'Amul Taaza Homogenised Milk 1L',
        'Coca-Cola Original Taste 750ml',
        'Haldiram''s Aloo Bhujia 200g',
        'Yoga Bar Dark Chocolate Protein Bar 55g',
        'Dettol Original Handwash 250ml',
        'Kissan Fresh Tomato Ketchup 500g',
        'Nescafé Classic Instant Coffee 100g',
        'Fortune Sunflower Oil 1L'
      ];
      descriptions := array[
        'Full-cream toned milk for tea, coffee and everyday family use.',
        'Classic sparkling cola in a 750ml returnable glass bottle.',
        'Crispy Indian potato and gram-flour namkeen with mild spices.',
        'Cocoa, oats and nuts in a convenient on-the-go protein bar.',
        'Original Dettol liquid hand wash for frequent hand cleaning.',
        'Rich tomato ketchup for snacks, sandwiches and cooking.',
        'Medium-roast instant coffee with a balanced, familiar flavour.',
        'Refined sunflower oil for everyday Indian cooking.'
      ];
      prices := array[68, 55, 95, 79, 129, 165, 249, 145]::numeric[];
      costs := array[48, 39, 66, 52, 89, 112, 178, 103]::numeric[];
    elsif b.name = 'FlexPOS' then
      names := array[
        'Coca-Cola Original Taste 750ml',
        'Pepsi Black 500ml',
        'Sprite Lemon-Lime 750ml',
        'Fanta Orange 750ml',
        'Limca Lemon-Lime 750ml',
        'Thums Up Strong 750ml',
        'Mountain Dew 750ml',
        'Red Bull Energy Drink 250ml'
      ];
      descriptions := array[
        'Classic cola with a crisp finish, served chilled.',
        'Zero-sugar cola with a bold Pepsi flavour.',
        'Clear lemon-lime sparkling soft drink.',
        'Bright orange-flavoured sparkling soft drink.',
        'Refreshing lemon-lime soda with a citrus lift.',
        'Bold cola with a strong, spicy finish.',
        'Citrus energy soda for an afternoon lift.',
        'Carbonated energy drink with caffeine and taurine.'
      ];
      prices := array[55, 45, 55, 55, 55, 55, 55, 125]::numeric[];
      costs := array[39, 31, 39, 39, 39, 39, 39, 88]::numeric[];
    elsif b.name = 'FlexPOS Retail' then
      names := array[
        'Aashirvaad Sharbati Atta', 'Tata Salt Iodised',
        'Fortune Sunflower Oil', 'India Gate Basmati Rice',
        'Nestlé Maggi 2-Minute Noodles', 'Parle-G Original Biscuits',
        'Britannia Good Day Cashew Cookies', 'Oreo Original Cookies',
        'Lay''s Classic Salted Chips', 'Kurkure Masala Munch',
        'Haldiram''s Aloo Bhujia', 'Amul Taaza Toned Milk',
        'Mother Dairy Classic Curd', 'Tropicana Orange Juice',
        'Coca-Cola Original Taste', 'Pepsi Black',
        'Red Bull Energy Drink', 'Nescafé Classic Coffee',
        'Brooke Bond Red Label Tea', 'Dove Daily Shine Shampoo',
        'Dettol Original Handwash', 'Colgate Strong Teeth Toothpaste',
        'Surf Excel Matic Liquid', 'Vim Dishwash Gel',
        'Harpic Power Plus Toilet Cleaner', 'Lux Soft Touch Soap',
        'Pampers Baby Dry Diapers', 'Himalaya Neem Face Wash',
        'Reynolds Trimax Gel Pen', 'Classmate Spiral Notebook',
        'Philips LED Bulb'
      ];
      sizes := array['200g', '500g', '1kg', 'family pack'];
      descriptions := array['Genuine branded retail pack for everyday household use.'];
      prices := array[125, 89, 149, 199]::numeric[];
      costs := array[82, 58, 98, 132]::numeric[];
    else
      names := array[
        'Espresso', 'Americano', 'Cappuccino', 'Caffe Latte',
        'Mocha', 'Cold Brew', 'Iced Latte', 'Masala Chai',
        'Green Tea', 'Hot Chocolate', 'Fresh Lime Soda', 'Mango Smoothie',
        'Strawberry Shake', 'Blueberry Smoothie', 'Fresh Orange Juice',
        'Paneer Tikka Sandwich', 'Grilled Veg Panini', 'Chicken Club Sandwich',
        'Veggie Burger', 'Crispy Chicken Burger', 'Margherita Pizza',
        'Farmhouse Pizza', 'Penne Arrabbiata', 'Creamy Alfredo Pasta',
        'Masala Fries', 'Peri Peri Fries', 'Caesar Salad',
        'Chocolate Lava Cake', 'New York Cheesecake', 'Brownie Sundae',
        'Blueberry Muffin'
      ];
      sizes := array['Small', 'Regular', 'Large', 'Sharing'];
      descriptions := array['Made-to-order cafe menu item prepared with fresh ingredients.'];
      prices := array[99, 149, 199, 299]::numeric[];
      costs := array[28, 42, 58, 92]::numeric[];
    end if;

    for p in
      select id,
             row_number() over (order by created_at, id)::integer as sequence
      from public.products
      where business_id = b.id
        and is_active
      order by created_at, id
    loop
      if b.name in ('BigMart', 'FlexPOS') then
        product_name := names[p.sequence];
        product_description := descriptions[p.sequence];
        product_image := images[1 + ((p.sequence - 1) % array_length(images, 1))];
        pack_size := split_part(product_name, ' ', array_length(string_to_array(product_name, ' '), 1));
        catalog_index := p.sequence;
        pack_index := 1;
      else
        catalog_index := 1 + ((p.sequence - 1) % array_length(names, 1));
        pack_index := 1 + ((p.sequence - 1) / array_length(names, 1));
        pack_size := sizes[pack_index];
        product_name := names[catalog_index] || ' ' || pack_size;
        product_description := descriptions[1];
        product_image := images[1 + ((p.sequence - 1) % array_length(images, 1))];
      end if;

      update public.products
      set name = product_name,
          description = product_description,
          product_type = 'goods',
          track_inventory = true,
          allow_fractional_quantity = false,
          attributes = jsonb_build_object(
            'catalog_source', 'real-world showcase catalog',
            'catalog_sequence', p.sequence,
            'pack_size', pack_size,
            'business_catalog', b.name
          ),
          image_path = product_image,
          updated_at = now()
      where id = p.id;

      for v in
        select id,
               row_number() over (order by created_at, id)::integer as variant_sequence
        from public.product_variants
        where product_id = p.id
          and business_id = b.id
      loop
        update public.product_variants
        set name = pack_size,
            sku = upper(left(regexp_replace(b.name, '[^A-Za-z0-9]', '', 'g'), 3))
              || '-' || lpad(p.sequence::text, 4, '0')
              || case when v.variant_sequence > 1 then '-' || v.variant_sequence::text else '' end,
            cost_price = case
              when b.name in ('BigMart', 'FlexPOS') then costs[p.sequence]
              when b.name = 'FlexPOS Retail' then costs[1 + ((p.sequence - 1) % array_length(costs, 1))]
              else costs[1 + ((p.sequence - 1) % array_length(costs, 1))]
            end,
            selling_price = case
              when b.name in ('BigMart', 'FlexPOS') then prices[p.sequence]
              when b.name = 'FlexPOS Retail' then prices[1 + ((p.sequence - 1) % array_length(prices, 1))]
              else prices[1 + ((p.sequence - 1) % array_length(prices, 1))]
            end,
            mrp = case
              when b.name in ('BigMart', 'FlexPOS') then round(prices[p.sequence] * 1.10, 2)
              when b.name = 'FlexPOS Retail' then round(prices[1 + ((p.sequence - 1) % array_length(prices, 1))] * 1.10, 2)
              else round(prices[1 + ((p.sequence - 1) % array_length(prices, 1))] * 1.10, 2)
            end,
            attributes = jsonb_build_object('pack_size', pack_size, 'catalog_source', 'real-world showcase catalog'),
            updated_at = now()
        where id = v.id;
      end loop;
    end loop;
  end loop;
end $$;

commit;
