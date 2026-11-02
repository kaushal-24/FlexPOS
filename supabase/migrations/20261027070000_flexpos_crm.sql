-- FlexPOS CRM module: leads, opportunities, quotations, follow-ups,
-- customer notes, sales pipeline, reminders, and salesperson attribution.
-- All tables are tenant-scoped to public.businesses(id) and protected by RLS.

begin;

insert into public.permissions (code, category, description) values
  ('crm.view', 'CRM', 'View CRM leads, opportunities, and pipeline.'),
  ('crm.manage', 'CRM', 'Create and manage CRM records and follow-ups.'),
  ('crm.quotations.manage', 'CRM', 'Create and manage CRM quotations.')
on conflict (code) do update set
  category = excluded.category,
  description = excluded.description;

insert into public.role_permissions (role_id, permission_code)
select role.id, permission.code
from public.roles role
cross join (
  values ('crm.view'), ('crm.manage'), ('crm.quotations.manage')
) as permission(code)
where role.name in ('Owner', 'Administrator', 'Branch Manager', 'Salesperson')
on conflict do nothing;

create or replace function private.seed_crm_role_permissions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.name in ('Owner', 'Administrator', 'Branch Manager', 'Salesperson') then
    insert into public.role_permissions (role_id, permission_code)
    values
      (new.id, 'crm.view'),
      (new.id, 'crm.manage'),
      (new.id, 'crm.quotations.manage')
    on conflict do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists roles_seed_crm_permissions on public.roles;
create trigger roles_seed_crm_permissions
after insert on public.roles
for each row execute function private.seed_crm_role_permissions();

create table if not exists public.crm_leads (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  salesperson_id uuid references auth.users(id) on delete set null,
  customer_id uuid,
  title text not null check (length(btrim(title)) between 1 and 200),
  source text,
  status text not null default 'new'
    check (status in ('new','contacted','qualified','unqualified','converted','lost')),
  estimated_value numeric(14,2) check (estimated_value >= 0),
  expected_close_at date,
  notes text,
  created_by uuid not null default auth.uid()
    references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  unique (id, business_id),
  constraint crm_leads_customer_fkey foreign key (customer_id, business_id)
    references public.customers(id, business_id) on delete restrict
);

create table if not exists public.crm_opportunities (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  salesperson_id uuid references auth.users(id) on delete set null,
  customer_id uuid,
  lead_id uuid,
  title text not null check (length(btrim(title)) between 1 and 200),
  stage text not null default 'prospecting'
    check (stage in ('prospecting','qualification','proposal','negotiation','closed_won','closed_lost')),
  probability smallint not null default 0 check (probability between 0 and 100),
  value_minor bigint not null default 0 check (value_minor >= 0),
  expected_close_at date,
  actual_close_at date,
  notes text,
  created_by uuid not null default auth.uid()
    references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  unique (id, business_id),
  constraint crm_opportunities_customer_fkey foreign key (customer_id, business_id)
    references public.customers(id, business_id) on delete restrict,
  constraint crm_opportunities_lead_fkey foreign key (lead_id, business_id)
    references public.crm_leads(id, business_id) on delete restrict
);

create table if not exists public.crm_quotations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  salesperson_id uuid references auth.users(id) on delete set null,
  customer_id uuid,
  opportunity_id uuid,
  quotation_number text not null check (length(btrim(quotation_number)) between 1 and 40),
  title text not null check (length(btrim(title)) between 1 and 200),
  status text not null default 'draft'
    check (status in ('draft','sent','accepted','rejected','expired','converted')),
  subtotal_minor bigint not null default 0 check (subtotal_minor >= 0),
  tax_minor bigint not null default 0 check (tax_minor >= 0),
  discount_minor bigint not null default 0 check (discount_minor >= 0),
  grand_total_minor bigint not null default 0 check (
    grand_total_minor >= 0
    and grand_total_minor = subtotal_minor + tax_minor - discount_minor
  ),
  valid_until date,
  converted_sale_id uuid,
  notes text,
  created_by uuid not null default auth.uid()
    references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  unique (id, business_id),
  unique (business_id, quotation_number),
  constraint crm_quotations_customer_fkey foreign key (customer_id, business_id)
    references public.customers(id, business_id) on delete restrict,
  constraint crm_quotations_opportunity_fkey foreign key (opportunity_id, business_id)
    references public.crm_opportunities(id, business_id) on delete restrict,
  constraint crm_quotations_sale_fkey foreign key (converted_sale_id, business_id)
    references public.sales(id, business_id) on delete restrict
);

create table if not exists public.crm_follow_ups (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  salesperson_id uuid references auth.users(id) on delete set null,
  lead_id uuid,
  opportunity_id uuid,
  quotation_id uuid,
  title text not null check (length(btrim(title)) between 1 and 200),
  type text not null default 'call'
    check (type in ('call','email','meeting','visit','other')),
  due_at timestamptz not null,
  completed_at timestamptz,
  notes text,
  created_by uuid not null default auth.uid()
    references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, business_id),
  constraint crm_follow_ups_lead_fkey foreign key (lead_id, business_id)
    references public.crm_leads(id, business_id) on delete cascade,
  constraint crm_follow_ups_opportunity_fkey foreign key (opportunity_id, business_id)
    references public.crm_opportunities(id, business_id) on delete cascade,
  constraint crm_follow_ups_quotation_fkey foreign key (quotation_id, business_id)
    references public.crm_quotations(id, business_id) on delete cascade
);

create table if not exists public.crm_customer_notes (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  salesperson_id uuid references auth.users(id) on delete set null,
  customer_id uuid not null,
  note text not null check (length(btrim(note)) between 1 and 4000),
  is_private boolean not null default true,
  created_by uuid not null default auth.uid()
    references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, business_id),
  constraint crm_customer_notes_customer_fkey foreign key (customer_id, business_id)
    references public.customers(id, business_id) on delete restrict
);

create table if not exists public.crm_reminders (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  salesperson_id uuid references auth.users(id) on delete set null,
  title text not null check (length(btrim(title)) between 1 and 200),
  description text,
  due_at timestamptz not null,
  is_completed boolean not null default false,
  completed_at timestamptz,
  related_table text,
  related_id uuid,
  created_by uuid not null default auth.uid()
    references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, business_id),
  constraint crm_reminders_completion_check check (
    (is_completed and completed_at is not null)
    or (not is_completed and completed_at is null)
  ),
  constraint crm_reminders_relation_check check (
    (related_table is null and related_id is null)
    or (
      related_table in ('lead', 'opportunity', 'quotation', 'customer')
      and related_id is not null
    )
  )
);

create or replace function private.protect_crm_actor_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if tg_op = 'INSERT' then
    new.created_by := auth.uid();
  else
    new.created_by := old.created_by;
    if new.business_id <> old.business_id then
      raise exception 'CRM records cannot move between businesses';
    end if;
  end if;

  if new.salesperson_id is not null and not exists (
    select 1
    from public.memberships membership
    where membership.business_id = new.business_id
      and membership.user_id = new.salesperson_id
      and membership.status = 'active'
      and membership.archived_at is null
  ) then
    raise exception 'Salesperson must be an active business member';
  end if;

  return new;
end;
$$;

drop trigger if exists crm_leads_protect_actor_fields on public.crm_leads;
create trigger crm_leads_protect_actor_fields
before insert or update on public.crm_leads
for each row execute function private.protect_crm_actor_fields();
drop trigger if exists crm_opportunities_protect_actor_fields on public.crm_opportunities;
create trigger crm_opportunities_protect_actor_fields
before insert or update on public.crm_opportunities
for each row execute function private.protect_crm_actor_fields();
drop trigger if exists crm_quotations_protect_actor_fields on public.crm_quotations;
create trigger crm_quotations_protect_actor_fields
before insert or update on public.crm_quotations
for each row execute function private.protect_crm_actor_fields();
drop trigger if exists crm_follow_ups_protect_actor_fields on public.crm_follow_ups;
create trigger crm_follow_ups_protect_actor_fields
before insert or update on public.crm_follow_ups
for each row execute function private.protect_crm_actor_fields();
drop trigger if exists crm_customer_notes_protect_actor_fields on public.crm_customer_notes;
create trigger crm_customer_notes_protect_actor_fields
before insert or update on public.crm_customer_notes
for each row execute function private.protect_crm_actor_fields();
drop trigger if exists crm_reminders_protect_actor_fields on public.crm_reminders;
create trigger crm_reminders_protect_actor_fields
before insert or update on public.crm_reminders
for each row execute function private.protect_crm_actor_fields();

create index if not exists crm_leads_business_id_idx on public.crm_leads(business_id);
create index if not exists crm_leads_status_idx on public.crm_leads(status);
create index if not exists crm_leads_salesperson_id_idx on public.crm_leads(salesperson_id);
create index if not exists crm_leads_customer_business_idx
  on public.crm_leads(customer_id, business_id);
create index if not exists crm_leads_created_by_idx on public.crm_leads(created_by);
create index if not exists crm_opportunities_business_id_idx on public.crm_opportunities(business_id);
create index if not exists crm_opportunities_stage_idx on public.crm_opportunities(stage);
create index if not exists crm_opportunities_salesperson_id_idx on public.crm_opportunities(salesperson_id);
create index if not exists crm_opportunities_customer_business_idx
  on public.crm_opportunities(customer_id, business_id);
create index if not exists crm_opportunities_lead_business_idx
  on public.crm_opportunities(lead_id, business_id);
create index if not exists crm_opportunities_created_by_idx
  on public.crm_opportunities(created_by);
create index if not exists crm_quotations_business_id_idx on public.crm_quotations(business_id);
create index if not exists crm_quotations_status_idx on public.crm_quotations(status);
create index if not exists crm_quotations_salesperson_id_idx
  on public.crm_quotations(salesperson_id);
create index if not exists crm_quotations_customer_business_idx
  on public.crm_quotations(customer_id, business_id);
create index if not exists crm_quotations_opportunity_business_idx
  on public.crm_quotations(opportunity_id, business_id);
create index if not exists crm_quotations_sale_business_idx
  on public.crm_quotations(converted_sale_id, business_id);
create index if not exists crm_quotations_created_by_idx on public.crm_quotations(created_by);
create index if not exists crm_follow_ups_business_id_idx on public.crm_follow_ups(business_id);
create index if not exists crm_follow_ups_due_at_idx on public.crm_follow_ups(due_at);
create index if not exists crm_follow_ups_salesperson_id_idx
  on public.crm_follow_ups(salesperson_id);
create index if not exists crm_follow_ups_lead_business_idx
  on public.crm_follow_ups(lead_id, business_id);
create index if not exists crm_follow_ups_opportunity_business_idx
  on public.crm_follow_ups(opportunity_id, business_id);
create index if not exists crm_follow_ups_quotation_business_idx
  on public.crm_follow_ups(quotation_id, business_id);
create index if not exists crm_follow_ups_created_by_idx on public.crm_follow_ups(created_by);
create index if not exists crm_customer_notes_customer_business_idx
  on public.crm_customer_notes(customer_id, business_id);
create index if not exists crm_customer_notes_salesperson_id_idx
  on public.crm_customer_notes(salesperson_id);
create index if not exists crm_customer_notes_created_by_idx
  on public.crm_customer_notes(created_by);
create index if not exists crm_reminders_business_id_idx on public.crm_reminders(business_id);
create index if not exists crm_reminders_due_at_idx on public.crm_reminders(due_at);
create index if not exists crm_reminders_salesperson_id_idx
  on public.crm_reminders(salesperson_id);
create index if not exists crm_reminders_created_by_idx on public.crm_reminders(created_by);

alter table public.crm_leads enable row level security;
alter table public.crm_opportunities enable row level security;
alter table public.crm_quotations enable row level security;
alter table public.crm_follow_ups enable row level security;
alter table public.crm_customer_notes enable row level security;
alter table public.crm_reminders enable row level security;

drop policy if exists crm_leads_select on public.crm_leads;
drop policy if exists crm_leads_insert on public.crm_leads;
drop policy if exists crm_leads_update on public.crm_leads;
drop policy if exists crm_leads_delete on public.crm_leads;
drop policy if exists crm_opportunities_select on public.crm_opportunities;
drop policy if exists crm_opportunities_insert on public.crm_opportunities;
drop policy if exists crm_opportunities_update on public.crm_opportunities;
drop policy if exists crm_opportunities_delete on public.crm_opportunities;
drop policy if exists crm_quotations_select on public.crm_quotations;
drop policy if exists crm_quotations_insert on public.crm_quotations;
drop policy if exists crm_quotations_update on public.crm_quotations;
drop policy if exists crm_quotations_delete on public.crm_quotations;
drop policy if exists crm_follow_ups_select on public.crm_follow_ups;
drop policy if exists crm_follow_ups_insert on public.crm_follow_ups;
drop policy if exists crm_follow_ups_update on public.crm_follow_ups;
drop policy if exists crm_follow_ups_delete on public.crm_follow_ups;
drop policy if exists crm_customer_notes_select on public.crm_customer_notes;
drop policy if exists crm_customer_notes_insert on public.crm_customer_notes;
drop policy if exists crm_customer_notes_update on public.crm_customer_notes;
drop policy if exists crm_customer_notes_delete on public.crm_customer_notes;
drop policy if exists crm_reminders_select on public.crm_reminders;
drop policy if exists crm_reminders_insert on public.crm_reminders;
drop policy if exists crm_reminders_update on public.crm_reminders;
drop policy if exists crm_reminders_delete on public.crm_reminders;

create policy crm_leads_select on public.crm_leads for select to authenticated
  using ((select private.has_permission(business_id, 'crm.view')));
create policy crm_leads_insert on public.crm_leads for insert to authenticated
  with check ((select private.has_permission(business_id, 'crm.manage')));
create policy crm_leads_update on public.crm_leads for update to authenticated
  using ((select private.has_permission(business_id, 'crm.manage')))
  with check ((select private.has_permission(business_id, 'crm.manage')));
create policy crm_leads_delete on public.crm_leads for delete to authenticated
  using ((select private.has_permission(business_id, 'crm.manage')));

create policy crm_opportunities_select on public.crm_opportunities for select to authenticated
  using ((select private.has_permission(business_id, 'crm.view')));
create policy crm_opportunities_insert on public.crm_opportunities for insert to authenticated
  with check ((select private.has_permission(business_id, 'crm.manage')));
create policy crm_opportunities_update on public.crm_opportunities for update to authenticated
  using ((select private.has_permission(business_id, 'crm.manage')))
  with check ((select private.has_permission(business_id, 'crm.manage')));
create policy crm_opportunities_delete on public.crm_opportunities for delete to authenticated
  using ((select private.has_permission(business_id, 'crm.manage')));

create policy crm_quotations_select on public.crm_quotations for select to authenticated
  using ((select private.has_permission(business_id, 'crm.view')));
create policy crm_quotations_insert on public.crm_quotations for insert to authenticated
  with check ((select private.has_permission(business_id, 'crm.quotations.manage')));
create policy crm_quotations_update on public.crm_quotations for update to authenticated
  using ((select private.has_permission(business_id, 'crm.quotations.manage')))
  with check ((select private.has_permission(business_id, 'crm.quotations.manage')));
create policy crm_quotations_delete on public.crm_quotations for delete to authenticated
  using ((select private.has_permission(business_id, 'crm.quotations.manage')));

create policy crm_follow_ups_select on public.crm_follow_ups for select to authenticated
  using ((select private.has_permission(business_id, 'crm.view')));
create policy crm_follow_ups_insert on public.crm_follow_ups for insert to authenticated
  with check ((select private.has_permission(business_id, 'crm.manage')));
create policy crm_follow_ups_update on public.crm_follow_ups for update to authenticated
  using ((select private.has_permission(business_id, 'crm.manage')))
  with check ((select private.has_permission(business_id, 'crm.manage')));
create policy crm_follow_ups_delete on public.crm_follow_ups for delete to authenticated
  using ((select private.has_permission(business_id, 'crm.manage')));

create policy crm_customer_notes_select on public.crm_customer_notes for select to authenticated
  using (
    (select private.has_permission(business_id, 'crm.view'))
    and (
      not is_private
      or created_by = (select auth.uid())
      or salesperson_id = (select auth.uid())
      or (select private.has_permission(business_id, 'crm.manage'))
    )
  );
create policy crm_customer_notes_insert on public.crm_customer_notes for insert to authenticated
  with check ((select private.has_permission(business_id, 'crm.manage')));
create policy crm_customer_notes_update on public.crm_customer_notes for update to authenticated
  using ((select private.has_permission(business_id, 'crm.manage')))
  with check ((select private.has_permission(business_id, 'crm.manage')));
create policy crm_customer_notes_delete on public.crm_customer_notes for delete to authenticated
  using ((select private.has_permission(business_id, 'crm.manage')));

create policy crm_reminders_select on public.crm_reminders for select to authenticated
  using ((select private.has_permission(business_id, 'crm.view')));
create policy crm_reminders_insert on public.crm_reminders for insert to authenticated
  with check ((select private.has_permission(business_id, 'crm.manage')));
create policy crm_reminders_update on public.crm_reminders for update to authenticated
  using ((select private.has_permission(business_id, 'crm.manage')))
  with check ((select private.has_permission(business_id, 'crm.manage')));
create policy crm_reminders_delete on public.crm_reminders for delete to authenticated
  using ((select private.has_permission(business_id, 'crm.manage')));

grant select, insert, update, delete on
  public.crm_leads,
  public.crm_opportunities,
  public.crm_quotations,
  public.crm_follow_ups,
  public.crm_customer_notes,
  public.crm_reminders
to authenticated;

insert into public.feature_modules (
  code, name, description, category, sort_order, is_core, is_available,
  default_business_types
) values
  (
    'crm', 'Customer Relationship Management',
    'Leads, opportunities, quotations, follow-ups, customer notes, pipeline, and reminders.',
    'industry', 300, false, true,
    array['retail','wholesale','service','fashion','electronics','pharmacy','other']
  )
on conflict (code) do update set
  name = excluded.name,
  description = excluded.description,
  category = excluded.category,
  sort_order = excluded.sort_order,
  is_available = excluded.is_available,
  default_business_types = excluded.default_business_types;

select private.seed_feature_entitlements(id, business_type)
from public.businesses;

insert into private.feature_module_permissions (permission_code, module_code) values
  ('crm.view', 'crm'),
  ('crm.manage', 'crm'),
  ('crm.quotations.manage', 'crm')
on conflict (permission_code) do nothing;

drop trigger if exists crm_leads_set_updated_at on public.crm_leads;
create trigger crm_leads_set_updated_at
before update on public.crm_leads
for each row execute function private.set_updated_at();

drop trigger if exists crm_opportunities_set_updated_at on public.crm_opportunities;
create trigger crm_opportunities_set_updated_at
before update on public.crm_opportunities
for each row execute function private.set_updated_at();

drop trigger if exists crm_quotations_set_updated_at on public.crm_quotations;
create trigger crm_quotations_set_updated_at
before update on public.crm_quotations
for each row execute function private.set_updated_at();

drop trigger if exists crm_follow_ups_set_updated_at on public.crm_follow_ups;
create trigger crm_follow_ups_set_updated_at
before update on public.crm_follow_ups
for each row execute function private.set_updated_at();

drop trigger if exists crm_customer_notes_set_updated_at on public.crm_customer_notes;
create trigger crm_customer_notes_set_updated_at
before update on public.crm_customer_notes
for each row execute function private.set_updated_at();

drop trigger if exists crm_reminders_set_updated_at on public.crm_reminders;
create trigger crm_reminders_set_updated_at
before update on public.crm_reminders
for each row execute function private.set_updated_at();

revoke all on function private.seed_crm_role_permissions()
  from public, anon, authenticated;
revoke all on function private.protect_crm_actor_fields()
  from public, anon, authenticated;

commit;
