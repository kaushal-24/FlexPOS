begin;

create or replace function private.industry_module_for_kind(target_kind text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when target_kind in ('restaurant_table','floor_plan','dine_in_order','takeaway_order','delivery_order','kitchen_ticket','menu_modifier','split_bill','recipe','tip','restaurant_order') then 'restaurant_operations'
    when target_kind in ('service_job','serial_warranty','technician_assignment','diagnostic','repair_quote','spare_part','labor','repair_stage','maintenance_contract','customer_delivery') then 'service_repair'
    when target_kind in ('dealer_price','bulk_discount','b2b_quote','b2b_order','credit_term','partial_fulfillment','challan','dispatch') then 'wholesale_b2b'
    when target_kind in ('weight_sale','unit_conversion','inventory_batch','barcode_checkout') then 'grocery_operations'
    when target_kind in ('size_color_matrix','fashion_exchange','seasonal_collection') then 'fashion_operations'
    when target_kind in ('imei_unit','electronics_warranty','serialized_return_repair') then 'electronics_operations'
    when target_kind in ('pharmacy_batch','prescription_reference','product_restriction','product_recall') then 'pharmacy_operations'
    when target_kind in ('appointment','salon_service','salon_package','salon_commission') then 'salon_operations'
    when target_kind in ('bill_of_materials','assembly_order','component_consumption','finished_goods_receipt','manufacturing_cost','production_run') then 'manufacturing_operations'
    when target_kind in ('rental_asset','rental_deposit','rental_contract','rental_return','damage_charge') then 'rental_operations'
    else null
  end;
$$;

commit;
