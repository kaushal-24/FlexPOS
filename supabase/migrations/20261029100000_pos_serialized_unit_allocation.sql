-- Link serialized inventory units to POS sale lines.

create table public.sale_item_serialized_units (
  business_id uuid not null references public.businesses(id) on delete cascade,
  sale_item_id uuid not null,
  serialized_unit_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (sale_item_id, serialized_unit_id),
  unique (business_id, serialized_unit_id),
  constraint sale_item_serialized_units_sale_item_fkey
    foreign key (sale_item_id, business_id)
    references public.sale_items(id, business_id) on delete restrict,
  constraint sale_item_serialized_units_unit_fkey
    foreign key (serialized_unit_id, business_id)
    references public.serialized_inventory_units(id, business_id) on delete restrict
);

create index sale_item_serialized_units_unit_idx
  on public.sale_item_serialized_units(business_id, serialized_unit_id);

alter table public.sale_item_serialized_units enable row level security;

create policy sale_item_serialized_units_select
  on public.sale_item_serialized_units for select to authenticated
using (
  exists (
    select 1
    from public.sale_items si
    join public.sales s on s.id = si.sale_id and s.business_id = si.business_id
    where si.id = sale_item_id
      and si.business_id = sale_item_serialized_units.business_id
      and (select private.has_permission(s.business_id, 'sales.view'))
      and (select private.has_branch_access(s.branch_id))
  )
);

grant select on public.sale_item_serialized_units to authenticated;
revoke insert, update, delete on public.sale_item_serialized_units from public, anon, authenticated;
