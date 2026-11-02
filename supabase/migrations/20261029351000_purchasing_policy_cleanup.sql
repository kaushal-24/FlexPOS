-- Avoid duplicate permissive SELECT policies while retaining permission-gated writes.
begin;

drop policy if exists purchase_requisitions_manage on public.purchase_requisitions;
drop policy if exists purchase_requisition_items_manage on public.purchase_requisition_items;
drop policy if exists purchase_invoices_manage on public.purchase_invoices;
drop policy if exists purchase_invoice_payments_manage on public.purchase_invoice_payments;
drop policy if exists purchase_landed_costs_manage on public.purchase_landed_costs;
drop policy if exists purchase_landed_cost_allocations_manage on public.purchase_landed_cost_allocations;

create policy purchase_requisitions_insert on public.purchase_requisitions for insert to authenticated
with check ((select private.has_permission(business_id, 'purchases.manage')));
create policy purchase_requisitions_update on public.purchase_requisitions for update to authenticated
using ((select private.has_permission(business_id, 'purchases.manage')))
with check ((select private.has_permission(business_id, 'purchases.manage')));
create policy purchase_requisitions_delete on public.purchase_requisitions for delete to authenticated
using ((select private.has_permission(business_id, 'purchases.manage')));

create policy purchase_requisition_items_insert on public.purchase_requisition_items for insert to authenticated
with check ((select private.has_permission(business_id, 'purchases.manage')));
create policy purchase_requisition_items_update on public.purchase_requisition_items for update to authenticated
using ((select private.has_permission(business_id, 'purchases.manage')))
with check ((select private.has_permission(business_id, 'purchases.manage')));
create policy purchase_requisition_items_delete on public.purchase_requisition_items for delete to authenticated
using ((select private.has_permission(business_id, 'purchases.manage')));

create policy purchase_invoices_insert on public.purchase_invoices for insert to authenticated
with check ((select private.has_permission(business_id, 'purchases.manage')));
create policy purchase_invoices_update on public.purchase_invoices for update to authenticated
using ((select private.has_permission(business_id, 'purchases.manage')))
with check ((select private.has_permission(business_id, 'purchases.manage')));
create policy purchase_invoices_delete on public.purchase_invoices for delete to authenticated
using ((select private.has_permission(business_id, 'purchases.manage')));

create policy purchase_invoice_payments_insert on public.purchase_invoice_payments for insert to authenticated
with check ((select private.has_permission(business_id, 'purchases.manage')));
create policy purchase_invoice_payments_update on public.purchase_invoice_payments for update to authenticated
using ((select private.has_permission(business_id, 'purchases.manage')))
with check ((select private.has_permission(business_id, 'purchases.manage')));
create policy purchase_invoice_payments_delete on public.purchase_invoice_payments for delete to authenticated
using ((select private.has_permission(business_id, 'purchases.manage')));

create policy purchase_landed_costs_insert on public.purchase_landed_costs for insert to authenticated
with check ((select private.has_permission(business_id, 'purchases.manage')));
create policy purchase_landed_costs_update on public.purchase_landed_costs for update to authenticated
using ((select private.has_permission(business_id, 'purchases.manage')))
with check ((select private.has_permission(business_id, 'purchases.manage')));
create policy purchase_landed_costs_delete on public.purchase_landed_costs for delete to authenticated
using ((select private.has_permission(business_id, 'purchases.manage')));

create policy purchase_landed_cost_allocations_insert on public.purchase_landed_cost_allocations for insert to authenticated
with check ((select private.has_permission(business_id, 'purchases.manage')));
create policy purchase_landed_cost_allocations_update on public.purchase_landed_cost_allocations for update to authenticated
using ((select private.has_permission(business_id, 'purchases.manage')))
with check ((select private.has_permission(business_id, 'purchases.manage')));
create policy purchase_landed_cost_allocations_delete on public.purchase_landed_cost_allocations for delete to authenticated
using ((select private.has_permission(business_id, 'purchases.manage')));

commit;
