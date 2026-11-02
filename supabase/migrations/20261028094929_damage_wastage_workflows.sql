-- Immutable, atomic stock-loss records for damaged and wasted inventory.

create table public.stock_loss_events (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  warehouse_id uuid not null,
  variant_id uuid not null,
  event_number text not null,
  loss_type text not null check (loss_type in ('damage', 'wastage')),
  product_name text not null,
  variant_name text not null,
  sku text not null,
  quantity numeric(20,6) not null check (quantity > 0),
  unit_cost numeric(18,4) not null check (unit_cost >= 0),
  loss_value numeric(18,2) not null check (loss_value >= 0),
  reason text not null check (length(btrim(reason)) between 3 and 500),
  notes text,
  operation_id uuid not null,
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, event_number),
  unique (business_id, operation_id),
  constraint stock_loss_events_warehouse_fkey
    foreign key (warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete restrict,
  constraint stock_loss_events_variant_fkey
    foreign key (variant_id, business_id)
    references public.product_variants(id, business_id) on delete restrict,
  check (loss_value = round(quantity * unit_cost, 2))
);

create index stock_loss_events_business_recorded_idx
  on public.stock_loss_events(business_id, recorded_at desc);
create index stock_loss_events_warehouse_business_fk_idx
  on public.stock_loss_events(warehouse_id, business_id);
create index stock_loss_events_variant_business_fk_idx
  on public.stock_loss_events(variant_id, business_id);
create index stock_loss_events_recorded_by_idx
  on public.stock_loss_events(recorded_by);

create trigger stock_loss_events_immutable
before update or delete on public.stock_loss_events
for each row execute function private.prevent_immutable_change();

alter table public.stock_loss_events enable row level security;

create policy stock_loss_events_select
on public.stock_loss_events for select to authenticated
using (
  (select private.has_permission(business_id, 'inventory.view'))
  and (select private.can_access_warehouse(warehouse_id))
);

grant select on public.stock_loss_events to authenticated;
revoke all on public.stock_loss_events from anon;

create or replace function public.record_stock_loss(
  target_business_id uuid,
  target_warehouse_id uuid,
  target_variant_id uuid,
  selected_loss_type text,
  loss_quantity numeric,
  loss_reason text,
  operation_id uuid,
  loss_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  variant_record record;
  balance_record public.inventory_balances%rowtype;
  next_quantity numeric(20,6);
  event_id uuid := gen_random_uuid();
  event_no text;
  normalized_quantity numeric(20,6);
  loss_total numeric(18,2);
  existing_result jsonb;
  inserted_count integer;
begin
  if caller_id is null then
    raise exception 'Authentication required';
  end if;
  if operation_id is null then
    raise exception 'Operation ID is required';
  end if;
  if selected_loss_type is null
     or selected_loss_type not in ('damage', 'wastage') then
    raise exception 'Loss type must be damage or wastage';
  end if;
  if loss_quantity is null or loss_quantity <= 0 then
    raise exception 'Loss quantity must be positive';
  end if;
  if length(btrim(coalesce(loss_reason, ''))) < 3 then
    raise exception 'A meaningful loss reason is required';
  end if;
  if length(btrim(loss_reason)) > 500 then
    raise exception 'Loss reason cannot exceed 500 characters';
  end if;
  if not private.has_permission(target_business_id, 'inventory.manage') then
    raise exception 'You do not have permission to record stock loss';
  end if;
  if not exists (
    select 1
    from public.warehouses w
    where w.id = target_warehouse_id
      and w.business_id = target_business_id
      and w.is_active
      and private.has_branch_access(w.branch_id)
  ) then
    raise exception 'Warehouse is not accessible';
  end if;

  select v.id, v.name as variant_name, v.sku, p.name as product_name,
         p.allow_fractional_quantity
  into variant_record
  from public.product_variants v
  join public.products p
    on p.id = v.product_id and p.business_id = v.business_id
  where v.id = target_variant_id
    and v.business_id = target_business_id
    and v.is_active
    and v.archived_at is null
    and p.is_active
    and p.archived_at is null
    and p.track_inventory;
  if not found then
    raise exception 'Variant is not stock tracked or is inactive';
  end if;
  normalized_quantity := round(loss_quantity, 6);
  if normalized_quantity <= 0 then
    raise exception 'Loss quantity is too small';
  end if;
  if not variant_record.allow_fractional_quantity
     and normalized_quantity <> trunc(normalized_quantity) then
    raise exception 'Fractional quantity is not allowed for SKU %', variant_record.sku;
  end if;

  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (
    target_business_id, operation_id, 'inventory.loss', caller_id
  )
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select result into existing_result
    from public.idempotency_records i
    where i.business_id = target_business_id
      and i.operation_id = record_stock_loss.operation_id
      and i.operation_type = 'inventory.loss';
    if existing_result <> '{}'::jsonb then
      return existing_result;
    end if;
    raise exception 'Stock loss operation is already in progress';
  end if;

  select * into balance_record
  from public.inventory_balances b
  where b.warehouse_id = target_warehouse_id
    and b.variant_id = target_variant_id
  for update;
  if not found then
    raise exception 'No inventory balance exists for SKU %', variant_record.sku;
  end if;
  next_quantity := balance_record.quantity_on_hand - normalized_quantity;
  if next_quantity < 0 then
    raise exception 'Stock loss exceeds quantity on hand for SKU %', variant_record.sku;
  end if;
  if next_quantity < balance_record.quantity_reserved then
    raise exception 'Stock loss would reduce SKU % below reserved quantity', variant_record.sku;
  end if;

  loss_total := round(normalized_quantity * balance_record.average_cost, 2);
  event_no := case selected_loss_type
    when 'damage' then 'DMG-'
    else 'WST-'
  end || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS') || '-'
    || upper(substr(replace(event_id::text, '-', ''), 1, 8));

  insert into public.stock_loss_events (
    id, business_id, warehouse_id, variant_id, event_number, loss_type,
    product_name, variant_name, sku, quantity, unit_cost, loss_value,
    reason, notes, operation_id, recorded_by
  ) values (
    event_id, target_business_id, target_warehouse_id, target_variant_id,
    event_no, selected_loss_type, variant_record.product_name,
    variant_record.variant_name, variant_record.sku, normalized_quantity,
    balance_record.average_cost, loss_total, btrim(loss_reason),
    nullif(btrim(loss_notes), ''), operation_id, caller_id
  );

  update public.inventory_balances
  set quantity_on_hand = next_quantity,
      updated_at = now()
  where warehouse_id = target_warehouse_id
    and variant_id = target_variant_id;

  insert into public.inventory_movements (
    business_id, warehouse_id, variant_id, movement_type, quantity_delta,
    quantity_before, quantity_after, unit_cost, reference_type, reference_id,
    reason, operation_id, created_by
  ) values (
    target_business_id, target_warehouse_id, target_variant_id,
    selected_loss_type, -normalized_quantity, balance_record.quantity_on_hand,
    next_quantity, balance_record.average_cost, 'stock_loss_event', event_id,
    btrim(loss_reason), operation_id, caller_id
  );

  existing_result := jsonb_build_object(
    'stock_loss_event_id', event_id,
    'event_number', event_no,
    'loss_type', selected_loss_type,
    'quantity_before', balance_record.quantity_on_hand,
    'quantity_after', next_quantity,
    'loss_value', loss_total
  );
  update public.idempotency_records
  set result = existing_result
  where business_id = target_business_id
    and idempotency_records.operation_id = record_stock_loss.operation_id
    and operation_type = 'inventory.loss';
  perform private.write_tenant_audit(
    target_business_id,
    'inventory.' || selected_loss_type || '_recorded',
    'stock_loss_event',
    event_id::text,
    existing_result || jsonb_build_object(
      'warehouse_id', target_warehouse_id,
      'variant_id', target_variant_id,
      'reason', btrim(loss_reason)
    )
  );
  return existing_result;
end;
$$;

revoke all on function public.record_stock_loss(
  uuid, uuid, uuid, text, numeric, text, uuid, text
) from public, anon;
grant execute on function public.record_stock_loss(
  uuid, uuid, uuid, text, numeric, text, uuid, text
) to authenticated;
