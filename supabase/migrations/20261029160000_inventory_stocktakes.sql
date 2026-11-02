-- Auditable physical stocktake and cycle-count workflow.

create table public.inventory_stocktakes (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  warehouse_id uuid not null,
  stocktake_number text not null,
  status text not null default 'counting'
    check (status in ('counting', 'finalized', 'cancelled')),
  reason text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  created_by uuid not null references auth.users(id) on delete restrict,
  finalized_by uuid references auth.users(id) on delete restrict,
  unique (id, business_id),
  unique (business_id, stocktake_number),
  constraint inventory_stocktakes_warehouse_fkey
    foreign key (warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete restrict,
  check (completed_at is null or completed_at >= started_at)
);

create table public.inventory_stocktake_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  stocktake_id uuid not null,
  warehouse_id uuid not null,
  variant_id uuid not null,
  batch_id uuid,
  system_quantity numeric(20,6) not null check (system_quantity >= 0),
  counted_quantity numeric(20,6) check (counted_quantity is null or counted_quantity >= 0),
  note text,
  counted_by uuid references auth.users(id) on delete restrict,
  counted_at timestamptz,
  created_at timestamptz not null default now(),
  unique (id, business_id),
  constraint inventory_stocktake_items_stocktake_fkey
    foreign key (stocktake_id, business_id)
    references public.inventory_stocktakes(id, business_id) on delete cascade,
  constraint inventory_stocktake_items_warehouse_fkey
    foreign key (warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete restrict,
  constraint inventory_stocktake_items_variant_fkey
    foreign key (variant_id, business_id)
    references public.product_variants(id, business_id) on delete restrict,
  constraint inventory_stocktake_items_batch_fkey
    foreign key (batch_id, business_id)
    references public.inventory_batches(id, business_id) on delete restrict
);

create unique index inventory_stocktake_items_scope_uidx
  on public.inventory_stocktake_items(
    stocktake_id,
    variant_id,
    coalesce(batch_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );
create index inventory_stocktakes_business_started_idx
  on public.inventory_stocktakes(business_id, started_at desc);
create index inventory_stocktakes_warehouse_status_idx
  on public.inventory_stocktakes(warehouse_id, status, started_at desc);
create index inventory_stocktake_items_stocktake_idx
  on public.inventory_stocktake_items(stocktake_id, variant_id);

alter table public.inventory_stocktakes enable row level security;
alter table public.inventory_stocktake_items enable row level security;

create policy inventory_stocktakes_select
on public.inventory_stocktakes for select to authenticated
using (
  (select private.has_permission(business_id, 'inventory.view'))
  and (select private.can_access_warehouse(warehouse_id))
);

create policy inventory_stocktake_items_select
on public.inventory_stocktake_items for select to authenticated
using (
  exists (
    select 1
    from public.inventory_stocktakes s
    where s.id = inventory_stocktake_items.stocktake_id
      and s.business_id = inventory_stocktake_items.business_id
      and (select private.has_permission(s.business_id, 'inventory.view'))
      and (select private.can_access_warehouse(s.warehouse_id))
  )
);

grant select on public.inventory_stocktakes, public.inventory_stocktake_items to authenticated;
revoke all on public.inventory_stocktakes, public.inventory_stocktake_items from anon;

create or replace function public.start_inventory_stocktake(
  target_business_id uuid,
  target_warehouse_id uuid,
  operation_id uuid,
  stocktake_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  inserted_count integer;
  existing_result jsonb;
  stocktake_id uuid := gen_random_uuid();
  stocktake_number text;
  item_count integer := 0;
  variant_record record;
  batch_record record;
  batch_total numeric(20,6);
  untracked_quantity numeric(20,6);
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if not private.has_permission(target_business_id, 'inventory.manage') then
    raise exception 'You do not have permission to start a stocktake';
  end if;
  if not exists (
    select 1 from public.warehouses w
    where w.id = target_warehouse_id and w.business_id = target_business_id
      and w.is_active and private.can_access_warehouse(w.id)
  ) then raise exception 'Warehouse is not accessible'; end if;

  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (target_business_id, operation_id, 'inventory.stocktake.start', caller_id)
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select result into existing_result
    from public.idempotency_records
    where business_id = target_business_id
      and idempotency_records.operation_id = start_inventory_stocktake.operation_id
      and operation_type = 'inventory.stocktake.start';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Stocktake operation is already in progress';
  end if;

  stocktake_number := 'ST-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS')
    || '-' || upper(substr(replace(stocktake_id::text, '-', ''), 1, 8));
  insert into public.inventory_stocktakes (
    id, business_id, warehouse_id, stocktake_number, status, reason, created_by
  ) values (
    stocktake_id, target_business_id, target_warehouse_id, stocktake_number,
    'counting', nullif(btrim(stocktake_reason), ''), caller_id
  );

  for variant_record in
    select v.id as variant_id,
           coalesce(ib.quantity_on_hand, 0)::numeric(20,6) as balance_quantity
    from public.product_variants v
    join public.products p
      on p.id = v.product_id and p.business_id = v.business_id
    left join public.inventory_balances ib
      on ib.business_id = v.business_id
     and ib.warehouse_id = target_warehouse_id
     and ib.variant_id = v.id
    where v.business_id = target_business_id
      and v.is_active and v.archived_at is null
      and p.is_active and p.archived_at is null
      and p.track_inventory
    order by v.id
  loop
    batch_total := 0;
    for batch_record in
      select b.id, b.quantity_on_hand
      from public.inventory_batches b
      where b.business_id = target_business_id
        and b.warehouse_id = target_warehouse_id
        and b.variant_id = variant_record.variant_id
      order by b.created_at, b.id
    loop
      insert into public.inventory_stocktake_items (
        business_id, stocktake_id, warehouse_id, variant_id, batch_id,
        system_quantity
      ) values (
        target_business_id, stocktake_id, target_warehouse_id,
        variant_record.variant_id, batch_record.id, batch_record.quantity_on_hand
      );
      batch_total := batch_total + batch_record.quantity_on_hand;
      item_count := item_count + 1;
    end loop;

    untracked_quantity := greatest(variant_record.balance_quantity - batch_total, 0);
    if batch_total = 0 or untracked_quantity > 0 then
      insert into public.inventory_stocktake_items (
        business_id, stocktake_id, warehouse_id, variant_id, batch_id,
        system_quantity
      ) values (
        target_business_id, stocktake_id, target_warehouse_id,
        variant_record.variant_id, null, untracked_quantity
      );
      item_count := item_count + 1;
    end if;
  end loop;

  existing_result := jsonb_build_object(
    'stocktake_id', stocktake_id,
    'stocktake_number', stocktake_number,
    'status', 'counting',
    'item_count', item_count
  );
  update public.idempotency_records set result = existing_result
  where business_id = target_business_id
    and idempotency_records.operation_id = start_inventory_stocktake.operation_id
    and operation_type = 'inventory.stocktake.start';
  perform private.write_tenant_audit(
    target_business_id, 'inventory.stocktake.started', 'inventory_stocktake',
    stocktake_id::text, existing_result
  );
  return existing_result;
end;
$$;

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

  update public.inventory_stocktake_items
  set counted_quantity = round(counted_quantity, 6),
      note = nullif(btrim(count_note), ''),
      counted_by = caller_id,
      counted_at = now()
  where id = item_record.id;

  return jsonb_build_object(
    'item_id', item_record.id,
    'stocktake_id', target_stocktake_id,
    'counted_quantity', round(counted_quantity, 6)
  );
end;
$$;

create or replace function public.finalize_inventory_stocktake(
  target_stocktake_id uuid,
  operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  stocktake_record public.inventory_stocktakes%rowtype;
  variant_record record;
  batch_record record;
  balance_record public.inventory_balances%rowtype;
  next_quantity numeric(20,6);
  variance_total numeric(20,6) := 0;
  movement_id bigint;
  existing_result jsonb;
  inserted_count integer;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  select * into stocktake_record
  from public.inventory_stocktakes s
  where s.id = target_stocktake_id
  for update;
  if not found then raise exception 'Stocktake not found'; end if;
  if not private.has_permission(stocktake_record.business_id, 'inventory.manage') then
    raise exception 'You do not have permission to finalize a stocktake';
  end if;
  if not private.can_access_warehouse(stocktake_record.warehouse_id) then
    raise exception 'Warehouse is not accessible';
  end if;
  if stocktake_record.status <> 'counting' then
    if stocktake_record.status = 'finalized' then
      select result into existing_result
      from public.idempotency_records
      where business_id = stocktake_record.business_id
        and operation_type = 'inventory.stocktake.finalize'
        and result ->> 'stocktake_id' = target_stocktake_id::text
      order by created_at desc limit 1;
      if existing_result is not null then return existing_result; end if;
    end if;
    raise exception 'Only an active stocktake can be finalized';
  end if;
  if exists (
    select 1 from public.inventory_stocktake_items i
    where i.stocktake_id = target_stocktake_id and i.counted_quantity is null
  ) then raise exception 'Every stocktake item must be counted before finalization'; end if;

  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (stocktake_record.business_id, operation_id, 'inventory.stocktake.finalize', caller_id)
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select result into existing_result
    from public.idempotency_records
    where business_id = stocktake_record.business_id
      and idempotency_records.operation_id = finalize_inventory_stocktake.operation_id
      and operation_type = 'inventory.stocktake.finalize';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Stocktake finalization is already in progress';
  end if;

  for variant_record in
    select i.variant_id,
           round(sum(i.counted_quantity - i.system_quantity), 6) as variance
    from public.inventory_stocktake_items i
    where i.stocktake_id = target_stocktake_id
    group by i.variant_id
    order by i.variant_id
  loop
    insert into public.inventory_balances (business_id, warehouse_id, variant_id)
    values (stocktake_record.business_id, stocktake_record.warehouse_id, variant_record.variant_id)
    on conflict (warehouse_id, variant_id) do nothing;
    select * into balance_record
    from public.inventory_balances b
    where b.business_id = stocktake_record.business_id
      and b.warehouse_id = stocktake_record.warehouse_id
      and b.variant_id = variant_record.variant_id
    for update;
    next_quantity := balance_record.quantity_on_hand + variant_record.variance;
    if next_quantity < balance_record.quantity_reserved or next_quantity < 0 then
      raise exception 'Stocktake would reduce stock below reserved quantity';
    end if;
    update public.inventory_balances
    set quantity_on_hand = next_quantity, updated_at = now()
    where id = balance_record.id;
    if variant_record.variance <> 0 then
      insert into public.inventory_movements (
        business_id, warehouse_id, variant_id, movement_type, quantity_delta,
        quantity_before, quantity_after, unit_cost, reference_type, reference_id,
        reason, operation_id, created_by
      ) values (
        stocktake_record.business_id, stocktake_record.warehouse_id,
        variant_record.variant_id, 'stocktake', variant_record.variance,
        balance_record.quantity_on_hand, next_quantity, balance_record.average_cost,
        'inventory_stocktake', target_stocktake_id, 'Physical stocktake', operation_id, caller_id
      ) returning id into movement_id;
      variance_total := variance_total + variant_record.variance;
    end if;
  end loop;

  for batch_record in
    select i.batch_id,
           round(sum(i.counted_quantity - i.system_quantity), 6) as variance
    from public.inventory_stocktake_items i
    where i.stocktake_id = target_stocktake_id and i.batch_id is not null
    group by i.batch_id
    order by i.batch_id
  loop
    update public.inventory_batches b
    set quantity_on_hand = b.quantity_on_hand + batch_record.variance,
        updated_at = now()
    where b.id = batch_record.batch_id
      and b.business_id = stocktake_record.business_id
      and b.quantity_on_hand + batch_record.variance >= b.quantity_reserved;
    if not found then raise exception 'Stocktake batch variance is invalid'; end if;
    if batch_record.variance <> 0 then
      insert into public.inventory_batch_movements (
        business_id, batch_id, warehouse_id, variant_id, movement_type,
        quantity_delta, quantity_before, quantity_after, unit_cost,
        reference_type, reference_id, operation_id, created_by
      )
      select stocktake_record.business_id, b.id, b.warehouse_id, b.variant_id,
             'stocktake', batch_record.variance, b.quantity_on_hand - batch_record.variance,
             b.quantity_on_hand, b.average_cost, 'inventory_stocktake',
             target_stocktake_id, operation_id, caller_id
      from public.inventory_batches b
      where b.id = batch_record.batch_id;
    end if;
  end loop;

  update public.inventory_stocktakes
  set status = 'finalized', completed_at = now(), finalized_by = caller_id
  where id = target_stocktake_id;
  existing_result := jsonb_build_object(
    'stocktake_id', target_stocktake_id,
    'stocktake_number', stocktake_record.stocktake_number,
    'status', 'finalized',
    'variance_total', variance_total
  );
  update public.idempotency_records set result = existing_result
  where business_id = stocktake_record.business_id
    and idempotency_records.operation_id = finalize_inventory_stocktake.operation_id
    and operation_type = 'inventory.stocktake.finalize';
  perform private.write_tenant_audit(
    stocktake_record.business_id, 'inventory.stocktake.finalized',
    'inventory_stocktake', target_stocktake_id::text, existing_result
  );
  return existing_result;
end;
$$;

create or replace function public.cancel_inventory_stocktake(
  target_stocktake_id uuid,
  operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  stocktake_record public.inventory_stocktakes%rowtype;
  existing_result jsonb;
  inserted_count integer;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  select * into stocktake_record from public.inventory_stocktakes s
  where s.id = target_stocktake_id for update;
  if not found then raise exception 'Stocktake not found'; end if;
  if not private.has_permission(stocktake_record.business_id, 'inventory.manage') then
    raise exception 'You do not have permission to cancel a stocktake';
  end if;
  if stocktake_record.status <> 'counting' then
    raise exception 'Only an active stocktake can be cancelled';
  end if;
  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (stocktake_record.business_id, operation_id, 'inventory.stocktake.cancel', caller_id)
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select result into existing_result from public.idempotency_records
    where business_id = stocktake_record.business_id
      and idempotency_records.operation_id = cancel_inventory_stocktake.operation_id
      and operation_type = 'inventory.stocktake.cancel';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Stocktake cancellation is already in progress';
  end if;
  update public.inventory_stocktakes set status = 'cancelled', completed_at = now()
  where id = target_stocktake_id;
  existing_result := jsonb_build_object(
    'stocktake_id', target_stocktake_id,
    'stocktake_number', stocktake_record.stocktake_number,
    'status', 'cancelled'
  );
  update public.idempotency_records set result = existing_result
  where business_id = stocktake_record.business_id
    and idempotency_records.operation_id = cancel_inventory_stocktake.operation_id
    and operation_type = 'inventory.stocktake.cancel';
  return existing_result;
end;
$$;

revoke all on function public.start_inventory_stocktake(uuid, uuid, uuid, text)
from public, anon;
revoke all on function public.record_inventory_stocktake_count(uuid, uuid, numeric, uuid, text)
from public, anon;
revoke all on function public.finalize_inventory_stocktake(uuid, uuid)
from public, anon;
revoke all on function public.cancel_inventory_stocktake(uuid, uuid)
from public, anon;
grant execute on function public.start_inventory_stocktake(uuid, uuid, uuid, text) to authenticated;
grant execute on function public.record_inventory_stocktake_count(uuid, uuid, numeric, uuid, text) to authenticated;
grant execute on function public.finalize_inventory_stocktake(uuid, uuid) to authenticated;
grant execute on function public.cancel_inventory_stocktake(uuid, uuid) to authenticated;
