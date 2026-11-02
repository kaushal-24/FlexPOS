-- Cover every composite foreign key in the purchasing domain.
create index goods_receipt_items_business_id_idx
  on public.goods_receipt_items(business_id);
create index goods_receipt_items_receipt_business_fk_idx
  on public.goods_receipt_items(goods_receipt_id, business_id);
create index goods_receipt_items_order_item_business_fk_idx
  on public.goods_receipt_items(purchase_order_item_id, business_id);
create index goods_receipt_items_variant_business_fk_idx
  on public.goods_receipt_items(variant_id, business_id);
create index goods_receipts_order_business_fk_idx
  on public.goods_receipts(purchase_order_id, business_id);
create index goods_receipts_warehouse_business_fk_idx
  on public.goods_receipts(warehouse_id, business_id);
create index purchase_order_items_business_id_idx
  on public.purchase_order_items(business_id);
create index purchase_order_items_order_business_fk_idx
  on public.purchase_order_items(purchase_order_id, business_id);
create index purchase_order_items_variant_business_fk_idx
  on public.purchase_order_items(variant_id, business_id);
create index purchase_orders_branch_business_fk_idx
  on public.purchase_orders(branch_id, business_id);
create index purchase_orders_supplier_business_fk_idx
  on public.purchase_orders(supplier_id, business_id);
create index purchase_orders_warehouse_business_fk_idx
  on public.purchase_orders(warehouse_id, business_id);

-- FOR ALL also applies to SELECT and duplicates the dedicated read policies.
-- Split write access by operation so each action evaluates one policy.
drop policy units_manage on public.units;
create policy units_insert on public.units for insert to authenticated
with check ((select private.has_permission(business_id, 'products.manage')));
create policy units_update on public.units for update to authenticated
using ((select private.has_permission(business_id, 'products.manage')))
with check ((select private.has_permission(business_id, 'products.manage')));

drop policy categories_manage on public.categories;
create policy categories_insert on public.categories for insert to authenticated
with check ((select private.has_permission(business_id, 'products.manage')));
create policy categories_update on public.categories for update to authenticated
using ((select private.has_permission(business_id, 'products.manage')))
with check ((select private.has_permission(business_id, 'products.manage')));

drop policy brands_manage on public.brands;
create policy brands_insert on public.brands for insert to authenticated
with check ((select private.has_permission(business_id, 'products.manage')));
create policy brands_update on public.brands for update to authenticated
using ((select private.has_permission(business_id, 'products.manage')))
with check ((select private.has_permission(business_id, 'products.manage')));

drop policy tax_rates_manage on public.tax_rates;
create policy tax_rates_insert on public.tax_rates for insert to authenticated
with check ((select private.has_permission(business_id, 'business.manage')));
create policy tax_rates_update on public.tax_rates for update to authenticated
using ((select private.has_permission(business_id, 'business.manage')))
with check ((select private.has_permission(business_id, 'business.manage')));

drop policy product_variants_manage on public.product_variants;
create policy product_variants_insert on public.product_variants for insert to authenticated
with check ((select private.has_permission(business_id, 'products.manage')));
create policy product_variants_update on public.product_variants for update to authenticated
using ((select private.has_permission(business_id, 'products.manage')))
with check ((select private.has_permission(business_id, 'products.manage')));

drop policy product_barcodes_manage on public.product_barcodes;
create policy product_barcodes_insert on public.product_barcodes for insert to authenticated
with check ((select private.has_permission(business_id, 'products.manage')));
create policy product_barcodes_update on public.product_barcodes for update to authenticated
using ((select private.has_permission(business_id, 'products.manage')))
with check ((select private.has_permission(business_id, 'products.manage')));
create policy product_barcodes_delete on public.product_barcodes for delete to authenticated
using ((select private.has_permission(business_id, 'products.manage')));

drop policy product_prices_manage on public.product_prices;
create policy product_prices_insert on public.product_prices for insert to authenticated
with check (
  (select private.has_permission(business_id, 'products.manage'))
  and (branch_id is null or (select private.has_branch_access(branch_id)))
);
create policy product_prices_update on public.product_prices for update to authenticated
using ((select private.has_permission(business_id, 'products.manage')))
with check (
  (select private.has_permission(business_id, 'products.manage'))
  and (branch_id is null or (select private.has_branch_access(branch_id)))
);
create policy product_prices_delete on public.product_prices for delete to authenticated
using ((select private.has_permission(business_id, 'products.manage')));

drop policy warehouses_manage on public.warehouses;
create policy warehouses_insert on public.warehouses for insert to authenticated
with check (
  (select private.has_permission(business_id, 'inventory.manage'))
  and (select private.has_branch_access(branch_id))
);
create policy warehouses_update on public.warehouses for update to authenticated
using ((select private.has_permission(business_id, 'inventory.manage')))
with check (
  (select private.has_permission(business_id, 'inventory.manage'))
  and (select private.has_branch_access(branch_id))
);

drop policy customers_manage on public.customers;
create policy customers_insert on public.customers for insert to authenticated
with check ((select private.has_permission(business_id, 'customers.manage')));
create policy customers_update on public.customers for update to authenticated
using ((select private.has_permission(business_id, 'customers.manage')))
with check ((select private.has_permission(business_id, 'customers.manage')));

drop policy registers_manage on public.registers;
create policy registers_insert on public.registers for insert to authenticated
with check (
  (select private.has_permission(business_id, 'registers.manage'))
  and (select private.has_branch_access(branch_id))
);
create policy registers_update on public.registers for update to authenticated
using ((select private.has_permission(business_id, 'registers.manage')))
with check (
  (select private.has_permission(business_id, 'registers.manage'))
  and (select private.has_branch_access(branch_id))
);

drop policy suppliers_manage on public.suppliers;
create policy suppliers_insert on public.suppliers for insert to authenticated
with check ((select private.has_permission(business_id, 'purchases.manage')));
create policy suppliers_update on public.suppliers for update to authenticated
using ((select private.has_permission(business_id, 'purchases.manage')))
with check ((select private.has_permission(business_id, 'purchases.manage')));
