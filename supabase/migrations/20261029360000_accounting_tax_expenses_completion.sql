-- Complete accounting, tax, and expense workflows for flexpos-2.
begin;

insert into public.permissions (code, category, description) values
  ('accounting.view', 'Accounting', 'View chart of accounts, journals, and balances'),
  ('accounting.manage', 'Accounting', 'Manage accounts, journals, periods, and cash/bank records'),
  ('expenses.approve', 'Accounting', 'Approve or reject expense records'),
  ('expenses.attachments', 'Accounting', 'Upload and view expense attachments'),
  ('tax.view', 'Tax', 'View tax profiles, GST summaries, and tax invoices'),
  ('tax.manage', 'Tax', 'Manage tax profiles and effective tax configuration')
on conflict (code) do update set category = excluded.category, description = excluded.description;

insert into public.role_permissions (role_id, permission_code)
select r.id, p.code
from public.roles r
cross join public.permissions p
where p.code in ('accounting.view','accounting.manage','expenses.approve','expenses.attachments','tax.view','tax.manage')
  and (r.name in ('Owner','Administrator','Accountant')
       or (r.name = 'Branch Manager' and p.code in ('accounting.view','expenses.approve','expenses.attachments','tax.view')))
on conflict do nothing;

create or replace function private.seed_accounting_completion_permissions()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.name = 'Owner' then return new; end if;
  insert into public.role_permissions(role_id, permission_code)
  select new.id, p.code from public.permissions p
  where p.code in ('accounting.view','accounting.manage','expenses.approve','expenses.attachments','tax.view','tax.manage')
    and (new.name in ('Administrator','Accountant')
         or (new.name = 'Branch Manager' and p.code in ('accounting.view','expenses.approve','expenses.attachments','tax.view')))
  on conflict do nothing;
  return new;
end;
$$;
drop trigger if exists roles_seed_accounting_completion_permissions on public.roles;
create trigger roles_seed_accounting_completion_permissions after insert on public.roles
for each row execute function private.seed_accounting_completion_permissions();
revoke all on function private.seed_accounting_completion_permissions() from public, anon, authenticated, service_role;

create table if not exists public.accounting_accounts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  code text not null check (length(btrim(code)) between 2 and 30),
  name text not null check (length(btrim(name)) between 1 and 120),
  account_type text not null check (account_type in ('asset','liability','equity','revenue','expense')),
  parent_id uuid,
  is_system boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, code),
  unique (id, business_id),
  constraint accounting_accounts_parent_fkey foreign key (parent_id, business_id)
    references public.accounting_accounts(id, business_id) on delete restrict
);

create table if not exists public.accounting_periods (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  starts_on date not null,
  ends_on date not null,
  status text not null default 'open' check (status in ('open','closed')),
  closed_at timestamptz,
  closed_by uuid references auth.users(id) on delete set null,
  notes text,
  created_at timestamptz not null default now(),
  unique (business_id, starts_on, ends_on),
  check (ends_on >= starts_on)
);

create table if not exists public.accounting_journal_entries (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  entry_number text not null,
  entry_date date not null default current_date,
  source_type text not null default 'manual',
  source_id uuid,
  memo text not null,
  status text not null default 'posted' check (status in ('draft','posted','void')),
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (business_id, entry_number),
  unique (id, business_id)
);

create table if not exists public.accounting_journal_lines (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  journal_entry_id uuid not null,
  account_id uuid not null,
  branch_id uuid,
  description text,
  debit numeric(18,2) not null default 0 check (debit >= 0),
  credit numeric(18,2) not null default 0 check (credit >= 0),
  created_at timestamptz not null default now(),
  constraint accounting_journal_lines_entry_fkey foreign key (journal_entry_id, business_id)
    references public.accounting_journal_entries(id, business_id) on delete cascade,
  constraint accounting_journal_lines_account_fkey foreign key (account_id, business_id)
    references public.accounting_accounts(id, business_id) on delete restrict,
  constraint accounting_journal_lines_branch_fkey foreign key (branch_id, business_id)
    references public.branches(id, business_id) on delete restrict,
  check ((debit > 0 and credit = 0) or (credit > 0 and debit = 0))
);

create table if not exists public.accounting_cash_bank_accounts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 120),
  account_type text not null check (account_type in ('cash','bank')),
  account_number_masked text,
  opening_balance numeric(18,2) not null default 0,
  ledger_account_id uuid,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, business_id),
  constraint accounting_cash_bank_ledger_fkey foreign key (ledger_account_id, business_id)
    references public.accounting_accounts(id, business_id) on delete restrict
);

create table if not exists public.accounting_recurring_expenses (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  category_id uuid not null,
  description text not null,
  amount numeric(18,2) not null check (amount > 0),
  tax_amount numeric(18,2) not null default 0 check (tax_amount >= 0 and tax_amount <= amount),
  payment_method text not null check (payment_method in ('cash','upi','card','bank_transfer','wallet')),
  vendor_name text,
  frequency text not null check (frequency in ('weekly','monthly','yearly')),
  next_run_on date not null,
  end_on date,
  is_active boolean not null default true,
  last_generated_on date,
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, business_id),
  constraint accounting_recurring_branch_fkey foreign key (branch_id, business_id)
    references public.branches(id, business_id) on delete restrict,
  constraint accounting_recurring_category_fkey foreign key (category_id, business_id)
    references public.expense_categories(id, business_id) on delete restrict,
  check (end_on is null or end_on >= next_run_on)
);

alter table public.expenses
  add column if not exists approval_status text not null default 'approved'
    check (approval_status in ('pending','approved','rejected')),
  add column if not exists approved_by uuid references auth.users(id) on delete set null,
  add column if not exists approved_at timestamptz,
  add column if not exists approval_note text;

create table if not exists public.expense_approval_events (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  expense_id uuid not null,
  status text not null check (status in ('pending','approved','rejected')),
  note text,
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint expense_approval_events_expense_fkey foreign key (expense_id, business_id)
    references public.expenses(id, business_id) on delete cascade
);

create table if not exists public.expense_attachments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  expense_id uuid not null,
  storage_path text not null,
  file_name text not null,
  mime_type text,
  file_size integer check (file_size is null or file_size > 0),
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (business_id, storage_path),
  constraint expense_attachments_expense_fkey foreign key (expense_id, business_id)
    references public.expenses(id, business_id) on delete cascade
);

create table if not exists public.accounting_tax_profiles (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid,
  legal_name text not null,
  gstin text check (gstin is null or length(btrim(gstin)) between 15 and 15),
  state_code text not null check (state_code ~ '^[0-9]{2}$'),
  default_place_of_supply text,
  effective_from date not null default current_date,
  effective_to date,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, business_id),
  constraint accounting_tax_profiles_branch_fkey foreign key (branch_id, business_id)
    references public.branches(id, business_id) on delete cascade,
  check (effective_to is null or effective_to >= effective_from)
);

create index if not exists accounting_accounts_business_type_idx on public.accounting_accounts(business_id, account_type, code);
create index if not exists accounting_journal_entries_business_date_idx on public.accounting_journal_entries(business_id, entry_date desc);
create index if not exists accounting_journal_lines_account_business_idx on public.accounting_journal_lines(account_id, business_id);
create index if not exists accounting_recurring_due_idx on public.accounting_recurring_expenses(business_id, next_run_on) where is_active;
create index if not exists expense_approval_events_expense_idx on public.expense_approval_events(expense_id, created_at desc);
create index if not exists expense_attachments_expense_idx on public.expense_attachments(expense_id, created_at desc);
create index if not exists accounting_tax_profiles_scope_idx on public.accounting_tax_profiles(business_id, branch_id, effective_from desc);

create trigger accounting_accounts_set_updated_at before update on public.accounting_accounts for each row execute function private.set_updated_at();
create trigger accounting_cash_bank_set_updated_at before update on public.accounting_cash_bank_accounts for each row execute function private.set_updated_at();
create trigger accounting_recurring_set_updated_at before update on public.accounting_recurring_expenses for each row execute function private.set_updated_at();
create trigger accounting_tax_profiles_set_updated_at before update on public.accounting_tax_profiles for each row execute function private.set_updated_at();

create or replace function private.seed_standard_accounting_accounts(target_business_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.accounting_accounts (business_id, code, name, account_type, is_system)
  values
    (target_business_id,'1000','Cash on hand','asset',true),
    (target_business_id,'1010','Bank account','asset',true),
    (target_business_id,'1100','Accounts receivable','asset',true),
    (target_business_id,'1200','Inventory','asset',true),
    (target_business_id,'2000','Accounts payable','liability',true),
    (target_business_id,'2100','GST payable','liability',true),
    (target_business_id,'3000','Owner equity','equity',true),
    (target_business_id,'4000','Sales revenue','revenue',true),
    (target_business_id,'4100','Other revenue','revenue',true),
    (target_business_id,'5000','Cost of goods sold','expense',true),
    (target_business_id,'6000','Operating expenses','expense',true)
  on conflict (business_id, code) do nothing;
end;
$$;
create or replace function private.seed_business_accounting_accounts()
returns trigger language plpgsql security definer set search_path = '' as $$
begin perform private.seed_standard_accounting_accounts(new.id); return new; end;
$$;
create trigger businesses_seed_standard_accounting_accounts after insert on public.businesses
for each row execute function private.seed_business_accounting_accounts();
do $$ declare b record; begin for b in select id from public.businesses loop perform private.seed_standard_accounting_accounts(b.id); end loop; end $$;
revoke all on function private.seed_standard_accounting_accounts(uuid), private.seed_business_accounting_accounts() from public, anon, authenticated, service_role;

alter table public.accounting_accounts enable row level security;
alter table public.accounting_periods enable row level security;
alter table public.accounting_journal_entries enable row level security;
alter table public.accounting_journal_lines enable row level security;
alter table public.accounting_cash_bank_accounts enable row level security;
alter table public.accounting_recurring_expenses enable row level security;
alter table public.expense_approval_events enable row level security;
alter table public.expense_attachments enable row level security;
alter table public.accounting_tax_profiles enable row level security;

create policy accounting_accounts_select on public.accounting_accounts for select to authenticated using ((select private.has_permission(business_id,'accounting.view')));
create policy accounting_accounts_insert on public.accounting_accounts for insert to authenticated with check ((select private.has_permission(business_id,'accounting.manage')));
create policy accounting_accounts_update on public.accounting_accounts for update to authenticated using ((select private.has_permission(business_id,'accounting.manage'))) with check ((select private.has_permission(business_id,'accounting.manage')));
create policy accounting_accounts_delete on public.accounting_accounts for delete to authenticated using ((select private.has_permission(business_id,'accounting.manage')) and not is_system);
create policy accounting_periods_select on public.accounting_periods for select to authenticated using ((select private.has_permission(business_id,'accounting.view')));
create policy accounting_periods_manage on public.accounting_periods for all to authenticated using ((select private.has_permission(business_id,'accounting.manage'))) with check ((select private.has_permission(business_id,'accounting.manage')));
create policy accounting_journal_entries_select on public.accounting_journal_entries for select to authenticated using ((select private.has_permission(business_id,'accounting.view')));
create policy accounting_journal_entries_manage on public.accounting_journal_entries for all to authenticated using ((select private.has_permission(business_id,'accounting.manage'))) with check ((select private.has_permission(business_id,'accounting.manage')));
create policy accounting_journal_lines_select on public.accounting_journal_lines for select to authenticated using ((select private.has_permission(business_id,'accounting.view')));
create policy accounting_journal_lines_manage on public.accounting_journal_lines for all to authenticated using ((select private.has_permission(business_id,'accounting.manage'))) with check ((select private.has_permission(business_id,'accounting.manage')));
create policy accounting_cash_bank_select on public.accounting_cash_bank_accounts for select to authenticated using ((select private.has_permission(business_id,'accounting.view')));
create policy accounting_cash_bank_manage on public.accounting_cash_bank_accounts for all to authenticated using ((select private.has_permission(business_id,'accounting.manage'))) with check ((select private.has_permission(business_id,'accounting.manage')));
create policy accounting_recurring_select on public.accounting_recurring_expenses for select to authenticated using ((select private.has_permission(business_id,'expenses.view')));
create policy accounting_recurring_manage on public.accounting_recurring_expenses for all to authenticated using ((select private.has_permission(business_id,'expenses.manage'))) with check ((select private.has_permission(business_id,'expenses.manage')));
create policy expense_approval_events_select on public.expense_approval_events for select to authenticated using ((select private.has_permission(business_id,'expenses.view')));
create policy expense_approval_events_manage on public.expense_approval_events for all to authenticated using ((select private.has_permission(business_id,'expenses.approve'))) with check ((select private.has_permission(business_id,'expenses.approve')));
create policy expense_attachments_select on public.expense_attachments for select to authenticated using ((select private.has_permission(business_id,'expenses.attachments')));
create policy expense_attachments_manage on public.expense_attachments for all to authenticated using ((select private.has_permission(business_id,'expenses.attachments'))) with check ((select private.has_permission(business_id,'expenses.attachments')));
create policy accounting_tax_profiles_select on public.accounting_tax_profiles for select to authenticated using ((select private.has_permission(business_id,'tax.view')));
create policy accounting_tax_profiles_manage on public.accounting_tax_profiles for all to authenticated using ((select private.has_permission(business_id,'tax.manage'))) with check ((select private.has_permission(business_id,'tax.manage')));

grant select, insert, update, delete on public.accounting_accounts, public.accounting_periods, public.accounting_journal_entries, public.accounting_journal_lines, public.accounting_cash_bank_accounts, public.accounting_recurring_expenses, public.expense_approval_events, public.expense_attachments, public.accounting_tax_profiles to authenticated;
revoke all on public.accounting_accounts, public.accounting_periods, public.accounting_journal_entries, public.accounting_journal_lines, public.accounting_cash_bank_accounts, public.accounting_recurring_expenses, public.expense_approval_events, public.expense_attachments, public.accounting_tax_profiles from anon;

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('expense-attachments','expense-attachments',false,10485760,array['application/pdf','image/jpeg','image/png','image/webp','text/plain'])
on conflict (id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists expense_attachments_storage_select on storage.objects;
create policy expense_attachments_storage_select on storage.objects for select to authenticated using (bucket_id='expense-attachments' and split_part(name,'/',1) ~* '^[0-9a-f-]{36}$' and (select private.has_permission(split_part(name,'/',1)::uuid,'expenses.attachments')));
drop policy if exists expense_attachments_storage_insert on storage.objects;
create policy expense_attachments_storage_insert on storage.objects for insert to authenticated with check (bucket_id='expense-attachments' and split_part(name,'/',1) ~* '^[0-9a-f-]{36}$' and (select private.has_permission(split_part(name,'/',1)::uuid,'expenses.attachments')));
drop policy if exists expense_attachments_storage_update on storage.objects;
create policy expense_attachments_storage_update on storage.objects for update to authenticated using (bucket_id='expense-attachments' and split_part(name,'/',1) ~* '^[0-9a-f-]{36}$' and (select private.has_permission(split_part(name,'/',1)::uuid,'expenses.attachments'))) with check (bucket_id='expense-attachments' and split_part(name,'/',1) ~* '^[0-9a-f-]{36}$' and (select private.has_permission(split_part(name,'/',1)::uuid,'expenses.attachments')));
drop policy if exists expense_attachments_storage_delete on storage.objects;
create policy expense_attachments_storage_delete on storage.objects for delete to authenticated using (bucket_id='expense-attachments' and split_part(name,'/',1) ~* '^[0-9a-f-]{36}$' and (select private.has_permission(split_part(name,'/',1)::uuid,'expenses.attachments')));

create or replace function public.create_journal_entry(target_business_id uuid,target_entry_date date,target_memo text,target_source_type text,target_source_id uuid,target_lines jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare caller_id uuid:=auth.uid(); entry_id uuid:=gen_random_uuid(); entry_no text; line jsonb; account_id uuid; debit numeric; credit numeric; total_debit numeric:=0; total_credit numeric:=0; period_record public.accounting_periods;
begin
  if caller_id is null or not private.has_permission(target_business_id,'accounting.manage') then raise exception 'Accounting management permission required'; end if;
  if jsonb_typeof(target_lines)<>'array' or jsonb_array_length(target_lines)<2 then raise exception 'At least two journal lines are required'; end if;
  select * into period_record from public.accounting_periods where business_id=target_business_id and target_entry_date between starts_on and ends_on order by starts_on desc limit 1;
  if period_record.status='closed' then raise exception 'Accounting period is closed'; end if;
  entry_no := 'JE-'||to_char(coalesce(target_entry_date,current_date),'YYYYMMDD')||'-'||upper(substr(replace(entry_id::text,'-',''),1,8));
  insert into public.accounting_journal_entries(id,business_id,entry_number,entry_date,source_type,source_id,memo,created_by) values(entry_id,target_business_id,entry_no,coalesce(target_entry_date,current_date),coalesce(nullif(btrim(target_source_type),''),'manual'),target_source_id,coalesce(nullif(btrim(target_memo),''),'Manual journal entry'),caller_id);
  for line in select * from jsonb_array_elements(target_lines) loop
    account_id := (line->>'account_id')::uuid; debit := round(coalesce((line->>'debit')::numeric,0),2); credit := round(coalesce((line->>'credit')::numeric,0),2);
    if not exists(select 1 from public.accounting_accounts where id=account_id and business_id=target_business_id and is_active) then raise exception 'Account is unavailable'; end if;
    if debit<0 or credit<0 or (debit=0 and credit=0) or (debit>0 and credit>0) then raise exception 'Each line must contain either a debit or credit'; end if;
    insert into public.accounting_journal_lines(business_id,journal_entry_id,account_id,branch_id,description,debit,credit) values(target_business_id,entry_id,account_id,nullif((line->>'branch_id')::uuid,null),nullif(btrim(line->>'description'),''),debit,credit);
    total_debit:=total_debit+debit; total_credit:=total_credit+credit;
  end loop;
  if round(total_debit,2)<>round(total_credit,2) then raise exception 'Journal entry is not balanced'; end if;
  return jsonb_build_object('id',entry_id,'entry_number',entry_no,'debit',total_debit,'credit',total_credit);
end;
$$;

create or replace function public.get_trial_balance(target_business_id uuid,target_as_of_date date default current_date)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
  if not private.has_permission(target_business_id,'accounting.view') then raise exception 'Accounting view permission required'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('account_id',a.id,'code',a.code,'name',a.name,'account_type',a.account_type,'debit',round(coalesce(sum(l.debit),0),2),'credit',round(coalesce(sum(l.credit),0),2),'balance',round(coalesce(sum(l.debit-l.credit),0),2)) order by a.code) from public.accounting_accounts a left join public.accounting_journal_lines l on l.account_id=a.id and l.business_id=a.business_id join public.accounting_journal_entries e on e.id=l.journal_entry_id and e.business_id=l.business_id and e.status='posted' and e.entry_date<=coalesce(target_as_of_date,current_date) where a.business_id=target_business_id group by a.id,a.code,a.name,a.account_type),'[]'::jsonb);
end;
$$;

create or replace function public.close_accounting_period(target_business_id uuid,target_starts_on date,target_ends_on date,target_notes text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare period_id uuid;
begin
  if not private.has_permission(target_business_id,'accounting.manage') then raise exception 'Accounting management permission required'; end if;
  if target_ends_on<target_starts_on then raise exception 'Period dates are invalid'; end if;
  insert into public.accounting_periods(business_id,starts_on,ends_on,status,closed_at,closed_by,notes) values(target_business_id,target_starts_on,target_ends_on,'closed',now(),auth.uid(),nullif(btrim(target_notes),'')) on conflict(business_id,starts_on,ends_on) do update set status='closed',closed_at=now(),closed_by=auth.uid(),notes=excluded.notes returning id into period_id;
  return jsonb_build_object('id',period_id,'status','closed');
end;
$$;

create or replace function public.reopen_accounting_period(target_period_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare b uuid;
begin select business_id into b from public.accounting_periods where id=target_period_id; if b is null or not private.has_permission(b,'accounting.manage') then raise exception 'Accounting management permission required'; end if; update public.accounting_periods set status='open',closed_at=null,closed_by=null where id=target_period_id;
end;
$$;

create or replace function public.create_recurring_expense(target_business_id uuid,target_branch_id uuid,target_category_id uuid,target_description text,target_amount numeric,target_tax_amount numeric,target_payment_method text,target_vendor_name text,target_frequency text,target_next_run_on date,target_end_on date default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare id uuid;
begin
  if not private.has_permission(target_business_id,'expenses.manage') then raise exception 'Expense management permission required'; end if;
  insert into public.accounting_recurring_expenses(business_id,branch_id,category_id,description,amount,tax_amount,payment_method,vendor_name,frequency,next_run_on,end_on) values(target_business_id,target_branch_id,target_category_id,btrim(target_description),round(target_amount,2),round(coalesce(target_tax_amount,0),2),target_payment_method,nullif(btrim(target_vendor_name),''),target_frequency,target_next_run_on,target_end_on) returning id into id;
  return id;
end;
$$;

create or replace function public.run_due_recurring_expenses(target_business_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare item record; generated integer:=0; next_date date; result jsonb;
begin
  if not private.has_permission(target_business_id,'expenses.manage') then raise exception 'Expense management permission required'; end if;
  for item in select * from public.accounting_recurring_expenses where business_id=target_business_id and is_active and next_run_on<=current_date and (end_on is null or next_run_on<=end_on) for update loop
    result:=public.create_expense(item.business_id,item.branch_id,item.category_id,gen_random_uuid(),item.amount,item.tax_amount,item.payment_method,item.vendor_name,null,item.description,item.next_run_on);
    next_date:=case item.frequency when 'weekly' then item.next_run_on+7 when 'monthly' then (item.next_run_on+interval '1 month')::date else (item.next_run_on+interval '1 year')::date end;
    update public.accounting_recurring_expenses set last_generated_on=item.next_run_on,next_run_on=next_date,is_active=case when item.end_on is not null and next_date>item.end_on then false else true end where id=item.id;
    generated:=generated+1;
  end loop;
  return jsonb_build_object('generated',generated);
end;
$$;

create or replace function public.request_expense_approval(target_expense_id uuid,target_note text default null)
returns void language plpgsql security definer set search_path='' as $$
declare e public.expenses%rowtype;
begin select * into e from public.expenses where id=target_expense_id for update; if e.id is null or not private.has_permission(e.business_id,'expenses.manage') then raise exception 'Expense is not accessible'; end if; update public.expenses set approval_status='pending',approval_note=nullif(btrim(target_note),'') where id=e.id; insert into public.expense_approval_events(business_id,expense_id,status,note) values(e.business_id,e.id,'pending',nullif(btrim(target_note),''));
end;
$$;

create or replace function public.decide_expense_approval(target_expense_id uuid,approve_request boolean,target_note text default null)
returns void language plpgsql security definer set search_path='' as $$
declare e public.expenses%rowtype; next_status text;
begin select * into e from public.expenses where id=target_expense_id for update; if e.id is null or not private.has_permission(e.business_id,'expenses.approve') then raise exception 'Expense approval permission required'; end if; if e.approval_status<>'pending' then raise exception 'Expense is not pending approval'; end if; next_status:=case when approve_request then 'approved' else 'rejected' end; update public.expenses set approval_status=next_status,approved_by=auth.uid(),approved_at=now(),approval_note=nullif(btrim(target_note),'') where id=e.id; insert into public.expense_approval_events(business_id,expense_id,status,note) values(e.business_id,e.id,next_status,nullif(btrim(target_note),''));
end;
$$;

create or replace function public.get_tax_invoice_breakdown(target_sale_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.sales%rowtype; origin_state text; destination_state text; interstate boolean; tax numeric; lines jsonb;
begin
  select * into s from public.sales where id=target_sale_id;
  if s.id is null or not private.has_permission(s.business_id,'tax.view') then raise exception 'Tax invoice is not accessible'; end if;
  select nullif(substring(b.tax_registration_number from 1 for 2),'') into origin_state from public.businesses b where b.id=s.business_id;
  select nullif(substring(c.gstin from 1 for 2),'') into destination_state from public.customers c where c.id=s.customer_id and c.business_id=s.business_id;
  destination_state:=coalesce(destination_state,origin_state); interstate:=origin_state is not null and destination_state is not null and origin_state<>destination_state;
  select coalesce(sum(tax_amount),0) into tax from public.sale_items where sale_id=s.id and business_id=s.business_id;
  select coalesce(jsonb_agg(jsonb_build_object('product_name',product_name,'sku',sku,'quantity',quantity,'tax_rate',tax_rate,'tax_amount',tax_amount,'cgst',case when interstate then 0 else round(tax_amount/2,2) end,'sgst',case when interstate then 0 else round(tax_amount-round(tax_amount/2,2),2) end,'igst',case when interstate then tax_amount else 0 end) order by created_at),'[]'::jsonb) into lines from public.sale_items where sale_id=s.id and business_id=s.business_id;
  return jsonb_build_object('invoice_number',s.invoice_number,'origin_state',origin_state,'place_of_supply',destination_state,'interstate',interstate,'subtotal',s.subtotal,'tax_total',tax,'cgst',case when interstate then 0 else round(tax/2,2) end,'sgst',case when interstate then 0 else round(tax-round(tax/2,2),2) end,'igst',case when interstate then tax else 0 end,'lines',lines);
end;
$$;

create or replace function public.get_gst_summary(target_business_id uuid,period_start timestamptz,period_end timestamptz)
returns jsonb language plpgsql security definer set search_path='' as $$
declare total_tax numeric; intra_tax numeric; inter_tax numeric;
begin
  if not private.has_permission(target_business_id,'tax.view') then raise exception 'Tax view permission required'; end if;
  with scoped as (select s.id,s.tax_total,coalesce(nullif(substring(b.tax_registration_number from 1 for 2),''), '') origin_state,coalesce(nullif(substring(c.gstin from 1 for 2),''),nullif(substring(b.tax_registration_number from 1 for 2),'')) destination_state from public.sales s join public.businesses b on b.id=s.business_id left join public.customers c on c.id=s.customer_id and c.business_id=s.business_id where s.business_id=target_business_id and s.status='completed' and s.completed_at>=period_start and s.completed_at<period_end) select coalesce(sum(tax_total),0),coalesce(sum(tax_total) filter(where origin_state=destination_state or destination_state is null),0),coalesce(sum(tax_total) filter(where origin_state<>destination_state and destination_state is not null),0) into total_tax,intra_tax,inter_tax from scoped;
  return jsonb_build_object('total_tax',total_tax,'cgst',round(intra_tax/2,2),'sgst',round(intra_tax-intra_tax/2,2),'igst',inter_tax,'period_start',period_start,'period_end',period_end);
end;
$$;

revoke all on function public.create_journal_entry(uuid,date,text,text,uuid,jsonb), public.get_trial_balance(uuid,date), public.close_accounting_period(uuid,date,date,text), public.reopen_accounting_period(uuid), public.create_recurring_expense(uuid,uuid,uuid,text,numeric,numeric,text,text,text,date,date), public.run_due_recurring_expenses(uuid), public.request_expense_approval(uuid,text), public.decide_expense_approval(uuid,boolean,text), public.get_tax_invoice_breakdown(uuid), public.get_gst_summary(uuid,timestamptz,timestamptz) from public, anon;
grant execute on function public.create_journal_entry(uuid,date,text,text,uuid,jsonb), public.get_trial_balance(uuid,date), public.close_accounting_period(uuid,date,date,text), public.reopen_accounting_period(uuid), public.create_recurring_expense(uuid,uuid,uuid,text,numeric,numeric,text,text,text,date,date), public.run_due_recurring_expenses(uuid), public.request_expense_approval(uuid,text), public.decide_expense_approval(uuid,boolean,text), public.get_tax_invoice_breakdown(uuid), public.get_gst_summary(uuid,timestamptz,timestamptz) to authenticated;

commit;
