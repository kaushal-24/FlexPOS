-- Resolve the count parameter/column ambiguity in stocktake counting.

create or replace function public.record_inventory_stocktake_count(
  target_stocktake_id uuid,
  target_variant_id uuid,
  counted_quantity numeric,
  target_batch_id uuid default null,
  count_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  stocktake_record public.inventory_stocktakes%rowtype;
  item_record public.inventory_stocktake_items%rowtype;
  allow_fractional boolean;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if counted_quantity is null or counted_quantity < 0 then
    raise exception 'Counted quantity cannot be negative';
  end if;
  select * into stocktake_record
  from public.inventory_stocktakes s
  where s.id = target_stocktake_id
  for update;
  if not found then raise exception 'Stocktake not found'; end if;
  if not private.has_permission(stocktake_record.business_id, 'inventory.manage') then
    raise exception 'You do not have permission to record a stocktake count';
  end if;
  if not private.can_access_warehouse(stocktake_record.warehouse_id) then
    raise exception 'Warehouse is not accessible';
  end if;
  if stocktake_record.status <> 'counting' then
    raise exception 'Only an active stocktake can be counted';
  end if;

  select p.allow_fractional_quantity into allow_fractional
  from public.product_variants v
  join public.products p on p.id = v.product_id and p.business_id = v.business_id
  where v.id = target_variant_id and v.business_id = stocktake_record.business_id;
  if not found then raise exception 'Stocktake variant is unavailable'; end if;
  if not allow_fractional and counted_quantity <> trunc(counted_quantity) then
    raise exception 'Fractional quantity is not allowed for this SKU';
  end if;

  select * into item_record
  from public.inventory_stocktake_items i
  where i.stocktake_id = target_stocktake_id
    and i.business_id = stocktake_record.business_id
    and i.variant_id = target_variant_id
    and i.batch_id is not distinct from target_batch_id
  for update;
  if not found then raise exception 'Stocktake item was not found'; end if;

  update public.inventory_stocktake_items i
  set counted_quantity = round(record_inventory_stocktake_count.counted_quantity, 6),
      note = nullif(btrim(record_inventory_stocktake_count.count_note), ''),
      counted_by = caller_id,
      counted_at = now()
  where i.id = item_record.id;

  return jsonb_build_object(
    'item_id', item_record.id,
    'stocktake_id', target_stocktake_id,
    'counted_quantity', round(record_inventory_stocktake_count.counted_quantity, 6)
  );
end;
$$;

revoke all on function public.record_inventory_stocktake_count(uuid, uuid, numeric, uuid, text)
from public, anon;
grant execute on function public.record_inventory_stocktake_count(uuid, uuid, numeric, uuid, text)
to authenticated;
