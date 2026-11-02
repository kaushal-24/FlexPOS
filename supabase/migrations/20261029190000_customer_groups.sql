-- Business-scoped customer groups for segmentation and future pricing rules.

create table public.customer_groups (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 80),
  code text check (code is null or length(btrim(code)) between 1 and 30),
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, name),
  unique (business_id, code)
);

alter table public.customers add column group_id uuid;

alter table public.customers
  add constraint customers_group_fkey
  foreign key (group_id, business_id)
  references public.customer_groups(id, business_id) on delete set null;

create index customers_business_group_idx
  on public.customers(business_id, group_id)
  where group_id is not null;

alter table public.customer_groups enable row level security;

create policy customer_groups_select
on public.customer_groups for select to authenticated
using ((select private.has_permission(business_id, 'customers.view')));

create policy customer_groups_manage
on public.customer_groups for all to authenticated
using ((select private.has_permission(business_id, 'customers.manage')))
with check ((select private.has_permission(business_id, 'customers.manage')));

revoke all on public.customer_groups from anon;
grant select, insert, update, delete on public.customer_groups to authenticated;

comment on table public.customer_groups is
  'Business-scoped customer segmentation groups; pricing rules can build on this membership.';
