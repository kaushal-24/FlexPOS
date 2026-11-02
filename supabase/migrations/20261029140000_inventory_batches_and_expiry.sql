-- Batch/lot metadata and expiry-aware inventory receipts.

create table public.inventory_batches (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  warehouse_id uuid not null,
  variant_id uuid not null,
  batch_number text not null check (length(btrim(batch_number)) between 1 and 120),
  lot_number text not null default '' check (length(lot_number) <= 120),
  manufactured_on date,
  expires_on date,
  status text not null default 'active'
    check (status in ('active', 'expired', 'recalled', 'blocked')),
  quantity_on_hand numeric(20,6) not null default 0 check (quantity_on_hand >= 0),
  quantity_reserved numeric(20,6) not null default 0
    check (quantity_reserved >= 0 and quantity_reserved <= quantity_on_hand),
  average_cost numeric(18,4) not null default 0 check (average_cost >= 0),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, warehouse_id, variant_id, batch_number, lot_number),
  constraint inventory_batches_warehouse_fkey
    foreign key (warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete restrict,
  constraint inventory_batches_variant_fkey
    foreign key (variant_id, business_id)
    references public.product_variants(id, business_id) on delete restrict,
  check (manufactured_on is null or expires_on is null or expires_on >= manufactured_on)
);

create table public.inventory_batch_movements (
  id bigint generated always as identity primary key,
  business_id uuid not null references public.businesses(id) on delete cascade,
  batch_id uuid not null,
  warehouse_id uuid not null,
  variant_id uuid not null,
  movement_type text not null check (movement_type in (
    'purchase', 'sale', 'sale_return', 'purchase_return', 'adjustment',
    'transfer_in', 'transfer_out', 'damage', 'wastage', 'stocktake'
  )),
  quantity_delta numeric(20,6) not null check (quantity_delta <> 0),
  quantity_before numeric(20,6) not null,
  quantity_after numeric(20,6) not null check (quantity_after >= 0),
  unit_cost numeric(18,4) check (unit_cost is null or unit_cost >= 0),
  reference_type text,
  reference_id uuid,
  operation_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint inventory_batch_movements_batch_fkey
    foreign key (batch_id, business_id)
    references public.inventory_batches(id, business_id) on delete restrict,
  constraint inventory_batch_movements_warehouse_fkey
    foreign key (warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete restrict,
  constraint inventory_batch_movements_variant_fkey
    foreign key (variant_id, business_id)
    references public.product_variants(id, business_id) on delete restrict,
  unique (business_id, operation_id, batch_id, movement_type)
);

alter table public.goods_receipt_items
  add column batch_id uuid;

alter table public.goods_receipt_items
  add constraint goods_receipt_items_batch_fkey
  foreign key (batch_id, business_id)
  references public.inventory_batches(id, business_id) on delete restrict;

create index inventory_batches_business_expiry_idx
  on public.inventory_batches(business_id, expires_on)
  where status = 'active' and expires_on is not null;
create index inventory_batches_warehouse_variant_idx
  on public.inventory_batches(warehouse_id, variant_id, expires_on);
create index inventory_batch_movements_batch_created_idx
  on public.inventory_batch_movements(batch_id, created_at desc);
create index inventory_batch_movements_business_created_idx
  on public.inventory_batch_movements(business_id, created_at desc);
create index goods_receipt_items_batch_id_idx
  on public.goods_receipt_items(batch_id)
  where batch_id is not null;

alter table public.inventory_batches enable row level security;
alter table public.inventory_batch_movements enable row level security;

create policy inventory_batches_select
on public.inventory_batches for select to authenticated
using (
  (select private.has_permission(business_id, 'inventory.view'))
  and (select private.can_access_warehouse(warehouse_id))
);

create policy inventory_batch_movements_select
on public.inventory_batch_movements for select to authenticated
using (
  (select private.has_permission(business_id, 'inventory.view'))
  and (select private.can_access_warehouse(warehouse_id))
);

grant select on public.inventory_batches, public.inventory_batch_movements to authenticated;
revoke all on public.inventory_batches, public.inventory_batch_movements from anon;
