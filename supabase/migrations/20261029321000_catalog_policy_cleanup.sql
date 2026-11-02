-- Keep catalog-management RLS policies selective so SELECT does not evaluate
-- overlapping member and manage policies.
begin;

drop policy if exists unit_conversions_manage on public.unit_conversions;
create policy unit_conversions_insert on public.unit_conversions
for insert to authenticated
with check ((select private.has_permission(business_id, 'products.manage')));
create policy unit_conversions_update on public.unit_conversions
for update to authenticated
using ((select private.has_permission(business_id, 'products.manage')))
with check ((select private.has_permission(business_id, 'products.manage')));
create policy unit_conversions_delete on public.unit_conversions
for delete to authenticated
using ((select private.has_permission(business_id, 'products.manage')));

drop policy if exists product_bundle_components_manage
on public.product_bundle_components;
create policy product_bundle_components_insert on public.product_bundle_components
for insert to authenticated
with check ((select private.has_permission(business_id, 'products.manage')));
create policy product_bundle_components_update on public.product_bundle_components
for update to authenticated
using ((select private.has_permission(business_id, 'products.manage')))
with check ((select private.has_permission(business_id, 'products.manage')));
create policy product_bundle_components_delete on public.product_bundle_components
for delete to authenticated
using ((select private.has_permission(business_id, 'products.manage')));

commit;
