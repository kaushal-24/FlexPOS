-- Configurable receipt templates and tenant-owned business branding assets.
begin;

alter table public.businesses
  add column if not exists receipt_template text not null default 'classic'
    check (receipt_template in ('classic', 'minimal', 'detailed')),
  add column if not exists receipt_logo_path text
    check (receipt_logo_path is null or length(btrim(receipt_logo_path)) between 1 and 500),
  add column if not exists receipt_qr_payload text
    check (receipt_qr_payload is null or length(receipt_qr_payload) between 1 and 2048),
  add column if not exists receipt_show_logo boolean not null default true,
  add column if not exists receipt_show_qr boolean not null default false;

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
) values (
  'business-assets', 'business-assets', false, 5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists business_assets_select on storage.objects;
create policy business_assets_select on storage.objects
for select to authenticated
using (
  bucket_id = 'business-assets'
  and split_part(name, '/', 1) ~* '^[0-9a-f-]{36}$'
  and (select private.has_permission(split_part(name, '/', 1)::uuid, 'business.view'))
);

drop policy if exists business_assets_insert on storage.objects;
create policy business_assets_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'business-assets'
  and split_part(name, '/', 1) ~* '^[0-9a-f-]{36}$'
  and (select private.has_permission(split_part(name, '/', 1)::uuid, 'business.manage'))
);

drop policy if exists business_assets_update on storage.objects;
create policy business_assets_update on storage.objects
for update to authenticated
using (
  bucket_id = 'business-assets'
  and split_part(name, '/', 1) ~* '^[0-9a-f-]{36}$'
  and (select private.has_permission(split_part(name, '/', 1)::uuid, 'business.manage'))
)
with check (
  bucket_id = 'business-assets'
  and split_part(name, '/', 1) ~* '^[0-9a-f-]{36}$'
  and (select private.has_permission(split_part(name, '/', 1)::uuid, 'business.manage'))
);

drop policy if exists business_assets_delete on storage.objects;
create policy business_assets_delete on storage.objects
for delete to authenticated
using (
  bucket_id = 'business-assets'
  and split_part(name, '/', 1) ~* '^[0-9a-f-]{36}$'
  and (select private.has_permission(split_part(name, '/', 1)::uuid, 'business.manage'))
);

commit;
