drop policy if exists serialized_inventory_units_sale_return_select
  on public.serialized_inventory_units;
drop policy if exists serialized_inventory_units_select
  on public.serialized_inventory_units;

create policy serialized_inventory_units_select
on public.serialized_inventory_units for select to authenticated
using (
  (
    (select private.has_permission(business_id, 'inventory.view'))
    and (select private.can_access_warehouse(warehouse_id))
  )
  or (
    (select private.has_permission(business_id, 'sales.refund'))
    and exists (
      select 1
      from public.sale_item_serialized_units link
      join public.sale_items si
        on si.id = link.sale_item_id
       and si.business_id = link.business_id
      join public.sales sale_record
        on sale_record.id = si.sale_id
       and sale_record.business_id = si.business_id
      where link.business_id = serialized_inventory_units.business_id
        and link.serialized_unit_id = serialized_inventory_units.id
        and private.has_branch_access(sale_record.branch_id)
    )
  )
);

revoke all on function public.complete_sale(
  uuid, uuid, uuid, uuid, uuid, uuid, jsonb, jsonb, numeric, text
) from anon;
revoke all on function public.complete_sale(
  uuid, uuid, uuid, uuid, uuid, uuid, jsonb, jsonb, numeric, text, jsonb
) from public, anon;
revoke all on function public.complete_sale(
  uuid, uuid, uuid, uuid, uuid, uuid, jsonb, jsonb, numeric, text, jsonb
) from anon;
