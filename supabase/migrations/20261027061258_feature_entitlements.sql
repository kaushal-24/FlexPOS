begin;

create table public.feature_modules (
  code text primary key check (code ~ '^[a-z][a-z0-9_]{1,63}$'),
  name text not null check (char_length(trim(name)) between 2 and 80),
  description text not null check (char_length(trim(description)) between 4 and 240),
  category text not null check (category in ('core', 'operations', 'industry')),
  sort_order integer not null default 0,
  is_core boolean not null default false,
  is_available boolean not null default false,
  default_business_types text[] not null default '{}'::text[],
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.business_feature_entitlements (
  business_id uuid not null references public.businesses(id) on delete cascade,
  module_code text not null references public.feature_modules(code) on delete restrict,
  is_enabled boolean not null,
  source text not null default 'business_type'
    check (source in ('business_type', 'administrator')),
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (business_id, module_code)
);

create table private.feature_module_permissions (
  permission_code text primary key
    references public.permissions(code) on delete cascade,
  module_code text not null
    references public.feature_modules(code) on delete cascade
);

create index feature_module_permissions_module_code_idx
  on private.feature_module_permissions(module_code);

create trigger feature_modules_set_updated_at
before update on public.feature_modules
for each row execute function private.set_updated_at();

create trigger business_feature_entitlements_set_updated_at
before update on public.business_feature_entitlements
for each row execute function private.set_updated_at();

insert into public.feature_modules (
  code, name, description, category, sort_order, is_core, is_available,
  default_business_types
) values
  ('sales', 'Sales and POS', 'Core selling, order, payment, and return workflows.', 'core', 10, true, true, '{}'),
  ('catalog', 'Product catalog', 'Products, variants, categories, prices, and taxes.', 'core', 20, true, true, '{}'),
  ('customers', 'Customers', 'Customer records, purchase history, and credit accounts.', 'core', 30, true, true, '{}'),
  ('accounting', 'Expenses and credit', 'Business expenses and customer-credit accounting.', 'core', 40, true, true, '{}'),
  ('reports', 'Reports and analytics', 'Sales, inventory, customer, cash, and forecast reporting.', 'core', 50, true, true, '{}'),
  ('branches', 'Branches', 'Branch structure, warehouses, and branch access.', 'core', 60, true, true, '{}'),
  ('access_control', 'Staff and access', 'Roles, permissions, invitations, and audit visibility.', 'core', 70, true, true, '{}'),
  (
    'inventory', 'Inventory', 'Stock tracking, adjustments, valuation, ageing, and alerts.',
    'operations', 100, false, true,
    array['retail','grocery','restaurant','wholesale','fashion','electronics','hardware','auto_parts','pharmacy','warehouse','manufacturing']
  ),
  (
    'purchasing', 'Suppliers and purchasing', 'Supplier records, purchase orders, and goods receiving.',
    'operations', 110, false, true,
    array['retail','grocery','restaurant','wholesale','fashion','electronics','hardware','auto_parts','salon','service','pharmacy','warehouse','manufacturing']
  ),
  (
    'registers', 'Registers and shifts', 'Cashier registers, shifts, cash movements, and reconciliation.',
    'operations', 120, false, true,
    array['retail','grocery','restaurant','wholesale','fashion','electronics','hardware','auto_parts','salon','pharmacy','other']
  ),
  ('restaurant_operations', 'Restaurant operations', 'Tables, kitchen tickets, modifiers, split bills, and recipes.', 'industry', 200, false, false, array['restaurant']),
  ('service_repair', 'Service and repair', 'Job cards, technicians, diagnostics, warranties, and repair stages.', 'industry', 210, false, false, array['service']),
  ('wholesale_b2b', 'Wholesale and B2B', 'Dealer prices, quotations, credit terms, fulfillment, and dispatch.', 'industry', 220, false, false, array['wholesale']),
  ('grocery_operations', 'Grocery operations', 'Weight sales, unit conversion, batches, expiry, and rapid checkout.', 'industry', 230, false, false, array['grocery']),
  ('fashion_operations', 'Fashion operations', 'Size and color matrices, exchanges, and seasonal collections.', 'industry', 240, false, false, array['fashion']),
  ('electronics_operations', 'Electronics operations', 'IMEI, serial, warranty, return, and repair tracking.', 'industry', 250, false, false, array['electronics']),
  ('pharmacy_operations', 'Pharmacy operations', 'Batch, expiry, prescription, restriction, and recall workflows.', 'industry', 260, false, false, array['pharmacy']),
  ('salon_operations', 'Salon operations', 'Appointments, services, packages, schedules, and commissions.', 'industry', 270, false, false, array['salon']),
  ('manufacturing_operations', 'Manufacturing operations', 'Bills of materials, assembly, costing, and production tracking.', 'industry', 280, false, false, array['manufacturing']),
  ('rental_operations', 'Rental operations', 'Asset availability, deposits, pricing, returns, and damage charges.', 'industry', 290, false, false, '{}');

insert into private.feature_module_permissions (permission_code, module_code) values
  ('business.view', 'access_control'),
  ('business.manage', 'access_control'),
  ('branches.view', 'branches'),
  ('branches.manage', 'branches'),
  ('staff.view', 'access_control'),
  ('staff.manage', 'access_control'),
  ('roles.view', 'access_control'),
  ('roles.manage', 'access_control'),
  ('audit.view', 'access_control'),
  ('sales.view', 'sales'),
  ('sales.create', 'sales'),
  ('sales.discount', 'sales'),
  ('sales.refund', 'sales'),
  ('gift_cards.manage', 'sales'),
  ('payments.reconcile', 'sales'),
  ('products.view', 'catalog'),
  ('products.manage', 'catalog'),
  ('inventory.view', 'inventory'),
  ('inventory.manage', 'inventory'),
  ('customers.view', 'customers'),
  ('customers.manage', 'customers'),
  ('purchases.view', 'purchasing'),
  ('purchases.manage', 'purchasing'),
  ('expenses.view', 'accounting'),
  ('expenses.manage', 'accounting'),
  ('customer_credit.view', 'accounting'),
  ('customer_credit.manage', 'accounting'),
  ('reports.view', 'reports'),
  ('reports.profit', 'reports'),
  ('sales_targets.manage', 'reports'),
  ('registers.manage', 'registers');

create or replace function private.seed_feature_entitlements(
  target_business_id uuid,
  target_business_type text
)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  insert into public.business_feature_entitlements (
    business_id, module_code, is_enabled, source
  )
  select
    target_business_id,
    feature.code,
    feature.is_core or target_business_type = any(feature.default_business_types),
    'business_type'
  from public.feature_modules feature
  on conflict (business_id, module_code) do nothing;
$$;

create or replace function private.seed_feature_entitlements_after_business()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.seed_feature_entitlements(new.id, new.business_type);
  return new;
end;
$$;

create trigger businesses_seed_feature_entitlements
after insert on public.businesses
for each row execute function private.seed_feature_entitlements_after_business();

select private.seed_feature_entitlements(id, business_type)
from public.businesses;

create or replace function private.feature_enabled(
  target_business_id uuid,
  target_module_code text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.business_feature_entitlements entitlement
    join public.feature_modules feature
      on feature.code = entitlement.module_code
    where entitlement.business_id = target_business_id
      and entitlement.module_code = target_module_code
      and entitlement.is_enabled
      and feature.is_available
  );
$$;

create or replace function private.has_permission(
  target_business_id uuid,
  required_permission text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships membership
    join public.role_permissions role_permission
      on role_permission.role_id = membership.role_id
    where membership.business_id = target_business_id
      and membership.user_id = auth.uid()
      and membership.status = 'active'
      and membership.archived_at is null
      and role_permission.permission_code = required_permission
      and (
        not exists (
          select 1
          from private.feature_module_permissions mapping
          where mapping.permission_code = required_permission
        )
        or exists (
          select 1
          from private.feature_module_permissions mapping
          join public.business_feature_entitlements entitlement
            on entitlement.business_id = target_business_id
           and entitlement.module_code = mapping.module_code
          join public.feature_modules feature
            on feature.code = mapping.module_code
          where mapping.permission_code = required_permission
            and entitlement.is_enabled
            and feature.is_available
        )
      )
  );
$$;

create or replace function public.set_business_feature_entitlement(
  target_business_id uuid,
  target_module_code text,
  requested_enabled boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_feature public.feature_modules%rowtype;
begin
  if not private.has_permission(target_business_id, 'business.manage') then
    raise exception 'Business management permission required';
  end if;

  select * into target_feature
  from public.feature_modules
  where code = target_module_code;

  if not found then
    raise exception 'Unknown feature module';
  end if;
  if target_feature.is_core then
    raise exception 'Core modules cannot be disabled';
  end if;
  if not target_feature.is_available then
    raise exception 'This feature module is not available yet';
  end if;

  insert into public.business_feature_entitlements (
    business_id, module_code, is_enabled, source, updated_by
  ) values (
    target_business_id, target_module_code, requested_enabled,
    'administrator', auth.uid()
  )
  on conflict (business_id, module_code) do update
  set is_enabled = excluded.is_enabled,
      source = excluded.source,
      updated_by = excluded.updated_by,
      updated_at = now();

  perform private.write_tenant_audit(
    target_business_id,
    'feature_entitlement.updated',
    'feature_module',
    target_module_code,
    jsonb_build_object('enabled', requested_enabled)
  );

  return requested_enabled;
end;
$$;

alter table public.feature_modules enable row level security;
alter table public.business_feature_entitlements enable row level security;

create policy feature_modules_select
on public.feature_modules for select
to authenticated
using (true);

create policy business_feature_entitlements_select
on public.business_feature_entitlements for select
to authenticated
using ((select private.is_business_member(business_id)));

grant select on public.feature_modules to authenticated;
grant select on public.business_feature_entitlements to authenticated;

revoke all on table private.feature_module_permissions
  from public, anon, authenticated;
revoke all on function private.seed_feature_entitlements(uuid, text)
  from public, anon, authenticated;
revoke all on function private.seed_feature_entitlements_after_business()
  from public, anon, authenticated;
revoke all on function private.feature_enabled(uuid, text)
  from public, anon, authenticated;
revoke all on function public.set_business_feature_entitlement(uuid, text, boolean)
  from public, anon;

grant execute on function public.set_business_feature_entitlement(uuid, text, boolean)
  to authenticated;

commit;
