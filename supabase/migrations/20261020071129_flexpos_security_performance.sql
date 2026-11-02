-- Opt in to explicit Data API exposure and complete composite FK indexes.

alter default privileges for role postgres in schema public
  revoke select, insert, update, delete on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke execute on functions from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke usage, select on sequences from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke execute on functions from public;

revoke all on all tables in schema public from anon;
revoke usage, select on all sequences in schema public from anon;
revoke execute on all functions in schema public from public, anon;

drop policy if exists business_invitations_select on public.business_invitations;
create policy business_invitations_select on public.business_invitations
for select to authenticated
using (
  (select private.has_permission(business_id, 'staff.view'))
  or lower(email) = lower(coalesce((select auth.jwt()) ->> 'email', ''))
);

drop policy if exists invitation_branch_access_select on public.invitation_branch_access;
create policy invitation_branch_access_select on public.invitation_branch_access
for select to authenticated
using (
  exists (
    select 1
    from public.business_invitations i
    where i.id = invitation_id
      and (
        (select private.has_permission(i.business_id, 'staff.view'))
        or lower(i.email) = lower(coalesce((select auth.jwt()) ->> 'email', ''))
      )
  )
);

create policy idempotency_records_no_direct_access
on public.idempotency_records
as restrictive for all to authenticated
using (false)
with check (false);

create index categories_parent_business_fk_idx
  on public.categories(parent_id, business_id) where parent_id is not null;
create index inventory_balances_variant_business_fk_idx
  on public.inventory_balances(variant_id, business_id);
create index inventory_balances_warehouse_business_fk_idx
  on public.inventory_balances(warehouse_id, business_id);
create index inventory_movements_variant_business_fk_idx
  on public.inventory_movements(variant_id, business_id);
create index inventory_movements_warehouse_business_fk_idx
  on public.inventory_movements(warehouse_id, business_id);
create index payments_business_id_idx on public.payments(business_id);
create index payments_sale_business_fk_idx on public.payments(sale_id, business_id);
create index product_barcodes_variant_business_fk_idx
  on public.product_barcodes(variant_id, business_id);
create index product_prices_branch_business_fk_idx
  on public.product_prices(branch_id, business_id) where branch_id is not null;
create index product_prices_variant_business_fk_idx
  on public.product_prices(variant_id, business_id);
create index product_variants_product_business_fk_idx
  on public.product_variants(product_id, business_id);
create index products_brand_business_fk_idx
  on public.products(brand_id, business_id) where brand_id is not null;
create index products_category_business_fk_idx
  on public.products(category_id, business_id) where category_id is not null;
create index products_tax_rate_business_fk_idx
  on public.products(tax_rate_id, business_id) where tax_rate_id is not null;
create index products_unit_business_fk_idx
  on public.products(base_unit_id, business_id);
create index register_shifts_register_business_fk_idx
  on public.register_shifts(register_id, business_id);
create index registers_branch_business_fk_idx
  on public.registers(branch_id, business_id);
create index sale_items_business_id_idx on public.sale_items(business_id);
create index sale_items_sale_business_fk_idx
  on public.sale_items(sale_id, business_id);
create index sale_items_variant_business_fk_idx
  on public.sale_items(variant_id, business_id);
create index sale_items_warehouse_business_fk_idx
  on public.sale_items(warehouse_id, business_id) where warehouse_id is not null;
create index sales_branch_business_fk_idx
  on public.sales(branch_id, business_id);
create index sales_customer_business_fk_idx
  on public.sales(customer_id, business_id) where customer_id is not null;
create index sales_register_business_fk_idx
  on public.sales(register_id, business_id) where register_id is not null;
create index warehouses_branch_business_fk_idx
  on public.warehouses(branch_id, business_id);

