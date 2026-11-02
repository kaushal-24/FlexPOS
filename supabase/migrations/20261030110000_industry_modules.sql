begin;

-- Section 9: typed, tenant-scoped industry workflows.  The payload keeps each
-- industry extensible while the kind/module/status columns remain queryable,
-- auditable, and enforceable by RLS.
insert into public.permissions (code, category, description) values
  ('industry.view', 'Industry operations', 'View enabled industry workflows'),
  ('industry.manage', 'Industry operations', 'Create and manage enabled industry workflows')
on conflict (code) do update set
  category = excluded.category,
  description = excluded.description;

update public.feature_modules
set is_available = true,
    updated_at = now()
where code in (
  'restaurant_operations', 'service_repair', 'wholesale_b2b',
  'grocery_operations', 'fashion_operations', 'electronics_operations',
  'pharmacy_operations', 'salon_operations', 'manufacturing_operations',
  'rental_operations'
);

insert into public.role_permissions (role_id, permission_code)
select r.id, p.code
from public.roles r
cross join public.permissions p
where r.name in ('Owner', 'Administrator')
  and p.code in ('industry.view', 'industry.manage')
on conflict do nothing;

insert into public.role_permissions (role_id, permission_code)
select r.id, p.code
from public.roles r
cross join public.permissions p
where r.name in ('Restaurant Waiter', 'Kitchen Staff', 'Service Technician')
  and p.code = 'industry.view'
on conflict do nothing;

create table public.industry_workflows (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  module_code text not null references public.feature_modules(code) on delete restrict,
  workflow_kind text not null check (workflow_kind in (
    'restaurant_table','floor_plan','dine_in_order','takeaway_order','delivery_order',
    'kitchen_ticket','menu_modifier','split_bill','recipe','tip','restaurant_order',
    'service_job','serial_warranty','technician_assignment','diagnostic','repair_quote',
    'spare_part','labor','repair_stage','maintenance_contract','customer_delivery',
    'dealer_price','bulk_discount','b2b_quote','b2b_order','credit_term',
    'partial_fulfillment','challan','dispatch',
    'weight_sale','unit_conversion','inventory_batch','barcode_checkout',
    'size_color_matrix','fashion_exchange','seasonal_collection',
    'imei_unit','electronics_warranty','serialized_return_repair',
    'pharmacy_batch','prescription_reference','product_restriction','product_recall',
    'appointment','salon_service','salon_package','salon_commission',
    'bill_of_materials','assembly_order','component_consumption',
    'finished_goods_receipt','manufacturing_cost','production_run',
    'rental_asset','rental_deposit','rental_contract','rental_return','damage_charge'
  )),
  reference_code text not null,
  title text not null check (length(btrim(title)) between 1 and 160),
  status text not null default 'draft' check (status in (
    'draft','planned','open','pending','confirmed','in_progress','ready','served',
    'completed','cancelled','rejected','approved','quoted','accepted','received',
    'dispatched','returned','damaged','available','reserved','overdue','recalled',
    'closed','paid'
  )),
  customer_id uuid references public.customers(id) on delete set null,
  product_id uuid references public.products(id) on delete set null,
  assigned_to uuid references auth.users(id) on delete set null,
  scheduled_at timestamptz,
  due_at timestamptz,
  quantity numeric not null default 0 check (quantity >= 0),
  unit_price numeric not null default 0 check (unit_price >= 0),
  total_amount numeric not null default 0 check (total_amount >= 0),
  deposit_amount numeric not null default 0 check (deposit_amount >= 0),
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload) = 'object'),
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  updated_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, reference_code)
);

create table public.industry_workflow_lines (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  workflow_id uuid not null references public.industry_workflows(id) on delete cascade,
  line_kind text not null check (line_kind in ('item','modifier','component','labor','fee','tax','payment','damage')),
  product_id uuid references public.products(id) on delete set null,
  description text not null check (length(btrim(description)) between 1 and 240),
  quantity numeric not null default 1 check (quantity > 0),
  unit_price numeric not null default 0 check (unit_price >= 0),
  amount numeric generated always as (quantity * unit_price) stored,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.industry_workflow_events (
  id bigint generated always as identity primary key,
  business_id uuid not null references public.businesses(id) on delete cascade,
  workflow_id uuid not null references public.industry_workflows(id) on delete cascade,
  from_status text,
  to_status text not null,
  note text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  actor_user_id uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create index industry_workflows_business_module_status_idx
  on public.industry_workflows (business_id, module_code, status, updated_at desc);
create index industry_workflows_business_kind_idx
  on public.industry_workflows (business_id, workflow_kind, created_at desc);
create index industry_workflows_branch_due_idx
  on public.industry_workflows (branch_id, due_at)
  where due_at is not null;
create index industry_workflow_lines_workflow_idx
  on public.industry_workflow_lines (business_id, workflow_id);
create index industry_workflow_events_workflow_idx
  on public.industry_workflow_events (business_id, workflow_id, created_at desc);

create trigger industry_workflows_set_updated_at
before update on public.industry_workflows
for each row execute function private.set_updated_at();

create or replace function private.industry_module_for_kind(target_kind text)
returns text
language sql
immutable
as $$
  select case
    when target_kind in ('restaurant_table','floor_plan','dine_in_order','takeaway_order','delivery_order','kitchen_ticket','menu_modifier','split_bill','recipe','tip','restaurant_order') then 'restaurant_operations'
    when target_kind in ('service_job','serial_warranty','technician_assignment','diagnostic','repair_quote','spare_part','labor','repair_stage','maintenance_contract','customer_delivery') then 'service_repair'
    when target_kind in ('dealer_price','bulk_discount','b2b_quote','b2b_order','credit_term','partial_fulfillment','challan','dispatch') then 'wholesale_b2b'
    when target_kind in ('weight_sale','unit_conversion','inventory_batch','barcode_checkout') then 'grocery_operations'
    when target_kind in ('size_color_matrix','fashion_exchange','seasonal_collection') then 'fashion_operations'
    when target_kind in ('imei_unit','electronics_warranty','serialized_return_repair') then 'electronics_operations'
    when target_kind in ('pharmacy_batch','prescription_reference','product_restriction','product_recall') then 'pharmacy_operations'
    when target_kind in ('appointment','salon_service','salon_package','salon_commission') then 'salon_operations'
    when target_kind in ('bill_of_materials','assembly_order','component_consumption','finished_goods_receipt','manufacturing_cost','production_run') then 'manufacturing_operations'
    when target_kind in ('rental_asset','rental_deposit','rental_contract','rental_return','damage_charge') then 'rental_operations'
    else null
  end;
$$;

create or replace function private.industry_workflow_authorized(
  target_business_id uuid,
  target_module_code text,
  required_permission text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_permission(target_business_id, required_permission)
    and private.feature_enabled(target_business_id, target_module_code);
$$;

create or replace function public.create_industry_workflow(
  target_business_id uuid,
  target_branch_id uuid,
  target_kind text,
  target_reference_code text,
  target_title text,
  target_status text default 'draft',
  target_customer_id uuid default null,
  target_product_id uuid default null,
  target_assigned_to uuid default null,
  target_scheduled_at timestamptz default null,
  target_due_at timestamptz default null,
  target_quantity numeric default 0,
  target_unit_price numeric default 0,
  target_total_amount numeric default 0,
  target_deposit_amount numeric default 0,
  target_payload jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  target_module text := private.industry_module_for_kind(target_kind);
  created_id uuid;
begin
  if target_module is null then
    raise exception 'Unsupported industry workflow kind';
  end if;
  if not private.industry_workflow_authorized(target_business_id, target_module, 'industry.manage') then
    raise exception 'Industry management permission and module entitlement required';
  end if;
  if target_reference_code is null or length(btrim(target_reference_code)) < 1 then
    raise exception 'Reference code is required';
  end if;
  if target_payload is null or jsonb_typeof(target_payload) <> 'object' then
    raise exception 'Workflow payload must be a JSON object';
  end if;
  insert into public.industry_workflows (
    business_id, branch_id, module_code, workflow_kind, reference_code, title,
    status, customer_id, product_id, assigned_to, scheduled_at, due_at,
    quantity, unit_price, total_amount, deposit_amount, payload
  ) values (
    target_business_id, target_branch_id, target_module, target_kind,
    btrim(target_reference_code), btrim(target_title), target_status,
    target_customer_id, target_product_id, target_assigned_to,
    target_scheduled_at, target_due_at, greatest(coalesce(target_quantity, 0), 0),
    greatest(coalesce(target_unit_price, 0), 0), greatest(coalesce(target_total_amount, 0), 0),
    greatest(coalesce(target_deposit_amount, 0), 0), coalesce(target_payload, '{}'::jsonb)
  ) returning id into created_id;
  insert into public.industry_workflow_events (business_id, workflow_id, to_status, note)
  values (target_business_id, created_id, target_status, 'Workflow created');
  return created_id;
end;
$$;

create or replace function public.transition_industry_workflow(
  target_business_id uuid,
  target_workflow_id uuid,
  target_status text,
  target_note text default null,
  target_metadata jsonb default '{}'::jsonb
)
returns boolean
language plpgsql
security invoker
set search_path = public
as $$
declare
  workflow_row public.industry_workflows%rowtype;
begin
  select * into workflow_row
  from public.industry_workflows
  where id = target_workflow_id and business_id = target_business_id
  for update;
  if not found then raise exception 'Workflow not found'; end if;
  if not private.industry_workflow_authorized(target_business_id, workflow_row.module_code, 'industry.manage') then
    raise exception 'Industry management permission and module entitlement required';
  end if;
  update public.industry_workflows
  set status = target_status, updated_by = auth.uid(), updated_at = now()
  where id = workflow_row.id and business_id = target_business_id;
  insert into public.industry_workflow_events (
    business_id, workflow_id, from_status, to_status, note, metadata
  ) values (
    target_business_id, workflow_row.id, workflow_row.status, target_status,
    target_note, coalesce(target_metadata, '{}'::jsonb)
  );
  return true;
end;
$$;

alter table public.industry_workflows enable row level security;
alter table public.industry_workflow_lines enable row level security;
alter table public.industry_workflow_events enable row level security;

create policy industry_workflows_select on public.industry_workflows
for select to authenticated
using ((select private.industry_workflow_authorized(business_id, module_code, 'industry.view')));
create policy industry_workflows_insert on public.industry_workflows
for insert to authenticated
with check ((select private.industry_workflow_authorized(business_id, module_code, 'industry.manage')));
create policy industry_workflows_update on public.industry_workflows
for update to authenticated
using ((select private.industry_workflow_authorized(business_id, module_code, 'industry.manage')))
with check ((select private.industry_workflow_authorized(business_id, module_code, 'industry.manage')));
create policy industry_workflows_delete on public.industry_workflows
for delete to authenticated
using ((select private.industry_workflow_authorized(business_id, module_code, 'industry.manage')));

create policy industry_workflow_lines_select on public.industry_workflow_lines
for select to authenticated
using (exists (
  select 1 from public.industry_workflows workflow
  where workflow.id = industry_workflow_lines.workflow_id
    and workflow.business_id = industry_workflow_lines.business_id
    and private.industry_workflow_authorized(workflow.business_id, workflow.module_code, 'industry.view')
));
create policy industry_workflow_lines_manage on public.industry_workflow_lines
for all to authenticated
using (exists (
  select 1 from public.industry_workflows workflow
  where workflow.id = industry_workflow_lines.workflow_id
    and workflow.business_id = industry_workflow_lines.business_id
    and private.industry_workflow_authorized(workflow.business_id, workflow.module_code, 'industry.manage')
))
with check (exists (
  select 1 from public.industry_workflows workflow
  where workflow.id = industry_workflow_lines.workflow_id
    and workflow.business_id = industry_workflow_lines.business_id
    and private.industry_workflow_authorized(workflow.business_id, workflow.module_code, 'industry.manage')
));

create policy industry_workflow_events_select on public.industry_workflow_events
for select to authenticated
using (exists (
  select 1 from public.industry_workflows workflow
  where workflow.id = industry_workflow_events.workflow_id
    and workflow.business_id = industry_workflow_events.business_id
    and private.industry_workflow_authorized(workflow.business_id, workflow.module_code, 'industry.view')
));

grant select, insert, update, delete on public.industry_workflows to authenticated;
grant select, insert, update, delete on public.industry_workflow_lines to authenticated;
grant select on public.industry_workflow_events to authenticated;
grant usage, select on sequence public.industry_workflow_events_id_seq to authenticated;
grant execute on function public.create_industry_workflow(
  uuid, uuid, text, text, text, text, uuid, uuid, uuid, timestamptz, timestamptz,
  numeric, numeric, numeric, numeric, jsonb
) to authenticated;
grant execute on function public.transition_industry_workflow(uuid, uuid, text, text, jsonb) to authenticated;

commit;
