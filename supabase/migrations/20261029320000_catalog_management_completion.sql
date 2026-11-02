-- Catalog management completion: product images, unit conversions, and bundles.
-- Import/export and bulk editing use the existing tenant-scoped catalog RPCs and
-- direct RLS-protected master-data writes; no offline cache is introduced.
begin;

alter table public.products
  add column if not exists image_path text
    check (image_path is null or length(btrim(image_path)) between 1 and 500);

create table if not exists public.unit_conversions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  from_unit_id uuid not null,
  to_unit_id uuid not null,
  multiplier numeric(18,8) not null check (multiplier > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, from_unit_id, to_unit_id),
  unique (id, business_id),
  check (from_unit_id <> to_unit_id),
  constraint unit_conversions_from_unit_fkey foreign key (from_unit_id, business_id)
    references public.units(id, business_id) on delete restrict,
  constraint unit_conversions_to_unit_fkey foreign key (to_unit_id, business_id)
    references public.units(id, business_id) on delete restrict
);

create table if not exists public.product_bundle_components (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  bundle_variant_id uuid not null,
  component_variant_id uuid not null,
  quantity numeric(20,6) not null check (quantity > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, bundle_variant_id, component_variant_id),
  unique (id, business_id),
  check (bundle_variant_id <> component_variant_id),
  constraint product_bundle_components_bundle_fkey
    foreign key (bundle_variant_id, business_id)
    references public.product_variants(id, business_id) on delete cascade,
  constraint product_bundle_components_component_fkey
    foreign key (component_variant_id, business_id)
    references public.product_variants(id, business_id) on delete restrict
);

create or replace function private.validate_product_bundle_component()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  bundle_type text;
  component_type text;
begin
  select p.product_type into bundle_type
  from public.product_variants v
  join public.products p on p.id = v.product_id and p.business_id = v.business_id
  where v.id = new.bundle_variant_id and v.business_id = new.business_id;
  if bundle_type is distinct from 'bundle' then
    raise exception 'Bundle components require a bundle product variant';
  end if;

  select p.product_type into component_type
  from public.product_variants v
  join public.products p on p.id = v.product_id and p.business_id = v.business_id
  where v.id = new.component_variant_id and v.business_id = new.business_id;
  if component_type is null then
    raise exception 'Bundle component variant is unavailable';
  end if;
  if component_type = 'bundle' then
    raise exception 'Nested bundles are not supported';
  end if;
  return new;
end;
$$;

revoke all on function private.validate_product_bundle_component()
from public, anon, authenticated, service_role;

drop trigger if exists product_bundle_components_validate
on public.product_bundle_components;
create trigger product_bundle_components_validate
before insert or update on public.product_bundle_components
for each row execute function private.validate_product_bundle_component();

create index if not exists unit_conversions_business_idx
  on public.unit_conversions(business_id, from_unit_id, to_unit_id);
create index if not exists product_bundle_components_bundle_idx
  on public.product_bundle_components(business_id, bundle_variant_id);
create index if not exists product_bundle_components_component_idx
  on public.product_bundle_components(business_id, component_variant_id);

alter table public.unit_conversions enable row level security;
alter table public.product_bundle_components enable row level security;

drop policy if exists unit_conversions_select on public.unit_conversions;
create policy unit_conversions_select on public.unit_conversions
for select to authenticated
using ((select private.is_business_member(business_id)));

drop policy if exists unit_conversions_manage on public.unit_conversions;
create policy unit_conversions_manage on public.unit_conversions
for all to authenticated
using ((select private.has_permission(business_id, 'products.manage')))
with check ((select private.has_permission(business_id, 'products.manage')));

drop policy if exists product_bundle_components_select on public.product_bundle_components;
create policy product_bundle_components_select on public.product_bundle_components
for select to authenticated
using ((select private.has_permission(business_id, 'products.view')));

drop policy if exists product_bundle_components_manage
on public.product_bundle_components;
create policy product_bundle_components_manage on public.product_bundle_components
for all to authenticated
using ((select private.has_permission(business_id, 'products.manage')))
with check ((select private.has_permission(business_id, 'products.manage')));

grant select, insert, update, delete on public.unit_conversions,
  public.product_bundle_components to authenticated;

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
) values (
  'product-images', 'product-images', false, 5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists product_images_select on storage.objects;
create policy product_images_select on storage.objects
for select to authenticated
using (
  bucket_id = 'product-images'
  and case
    when split_part(name, '/', 1) ~* '^[0-9a-f-]{36}$'
    then (select private.has_permission(split_part(name, '/', 1)::uuid, 'products.view'))
    else false
  end
);

drop policy if exists product_images_insert on storage.objects;
create policy product_images_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'product-images'
  and case
    when split_part(name, '/', 1) ~* '^[0-9a-f-]{36}$'
    then (select private.has_permission(split_part(name, '/', 1)::uuid, 'products.manage'))
    else false
  end
);

drop policy if exists product_images_update on storage.objects;
create policy product_images_update on storage.objects
for update to authenticated
using (
  bucket_id = 'product-images'
  and case
    when split_part(name, '/', 1) ~* '^[0-9a-f-]{36}$'
    then (select private.has_permission(split_part(name, '/', 1)::uuid, 'products.manage'))
    else false
  end
)
with check (
  bucket_id = 'product-images'
  and case
    when split_part(name, '/', 1) ~* '^[0-9a-f-]{36}$'
    then (select private.has_permission(split_part(name, '/', 1)::uuid, 'products.manage'))
    else false
  end
);

drop policy if exists product_images_delete on storage.objects;
create policy product_images_delete on storage.objects
for delete to authenticated
using (
  bucket_id = 'product-images'
  and case
    when split_part(name, '/', 1) ~* '^[0-9a-f-]{36}$'
    then (select private.has_permission(split_part(name, '/', 1)::uuid, 'products.manage'))
    else false
  end
);

commit;
