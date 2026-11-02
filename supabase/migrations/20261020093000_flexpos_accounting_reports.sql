-- FlexPOS accounting and reporting foundation: immutable expenses, customer
-- credit ledgers, repayment allocation, and database-side dashboard metrics.

insert into public.permissions (code, category, description) values
  ('expenses.view', 'Accounting', 'View expense categories and expenses'),
  ('expenses.manage', 'Accounting', 'Record and reverse expenses'),
  ('customer_credit.view', 'Accounting', 'View customer credit statements'),
  ('customer_credit.manage', 'Accounting', 'Record customer repayments')
on conflict (code) do update set
  category = excluded.category,
  description = excluded.description;

insert into public.role_permissions (role_id, permission_code)
select r.id, p.code
from public.roles r
cross join public.permissions p
where p.code in (
  'expenses.view', 'expenses.manage',
  'customer_credit.view', 'customer_credit.manage'
)
and (
  r.name in ('Owner', 'Administrator')
  or (r.name = 'Accountant')
  or (r.name = 'Branch Manager' and p.code in ('expenses.view', 'customer_credit.view'))
)
on conflict do nothing;

create or replace function private.seed_accounting_role_permissions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- create_business_with_branch grants every current permission to the Owner
  -- immediately after inserting that role. Avoid racing that bootstrap insert.
  if new.name = 'Owner' then
    return new;
  end if;

  insert into public.role_permissions (role_id, permission_code)
  select new.id, p.code
  from public.permissions p
  where p.code in (
    'expenses.view', 'expenses.manage',
    'customer_credit.view', 'customer_credit.manage'
  )
  and (
    new.name in ('Administrator', 'Accountant')
    or (new.name = 'Branch Manager'
      and p.code in ('expenses.view', 'customer_credit.view'))
  )
  on conflict do nothing;
  return new;
end;
$$;

create trigger roles_seed_accounting_permissions
after insert on public.roles
for each row execute function private.seed_accounting_role_permissions();

alter table public.payments
  add constraint payments_id_business_unique unique (id, business_id);

create table public.expense_categories (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 100),
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, name)
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  category_id uuid not null,
  expense_number text not null,
  entry_type text not null default 'expense'
    check (entry_type in ('expense', 'reversal')),
  reverses_expense_id uuid,
  amount numeric(18,2) not null check (amount > 0),
  tax_amount numeric(18,2) not null default 0
    check (tax_amount >= 0 and tax_amount <= amount),
  payment_method text not null check (payment_method in (
    'cash', 'upi', 'card', 'bank_transfer', 'wallet'
  )),
  vendor_name text,
  reference text,
  notes text,
  incurred_on date not null default current_date,
  operation_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, expense_number),
  unique (business_id, operation_id),
  unique (reverses_expense_id),
  constraint expenses_branch_fkey foreign key (branch_id, business_id)
    references public.branches(id, business_id) on delete restrict,
  constraint expenses_category_fkey foreign key (category_id, business_id)
    references public.expense_categories(id, business_id) on delete restrict,
  constraint expenses_reversal_fkey foreign key (reverses_expense_id, business_id)
    references public.expenses(id, business_id) on delete restrict,
  check (
    (entry_type = 'expense' and reverses_expense_id is null)
    or (entry_type = 'reversal' and reverses_expense_id is not null)
  )
);

create table public.customer_receipts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  customer_id uuid not null,
  receipt_number text not null,
  amount numeric(18,2) not null check (amount > 0),
  payment_method text not null check (payment_method in (
    'cash', 'upi', 'card', 'bank_transfer', 'wallet'
  )),
  reference text,
  notes text,
  operation_id uuid not null,
  received_by uuid not null references auth.users(id) on delete restrict,
  received_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, receipt_number),
  unique (business_id, operation_id),
  constraint customer_receipts_branch_fkey foreign key (branch_id, business_id)
    references public.branches(id, business_id) on delete restrict,
  constraint customer_receipts_customer_fkey foreign key (customer_id, business_id)
    references public.customers(id, business_id) on delete restrict
);

create table public.customer_receipt_allocations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  receipt_id uuid not null,
  sale_id uuid not null,
  payment_id uuid not null,
  amount numeric(18,2) not null check (amount > 0),
  created_at timestamptz not null default now(),
  unique (receipt_id, sale_id),
  unique (payment_id),
  constraint customer_receipt_allocations_receipt_fkey
    foreign key (receipt_id, business_id)
    references public.customer_receipts(id, business_id) on delete restrict,
  constraint customer_receipt_allocations_sale_fkey
    foreign key (sale_id, business_id)
    references public.sales(id, business_id) on delete restrict,
  constraint customer_receipt_allocations_payment_fkey
    foreign key (payment_id, business_id)
    references public.payments(id, business_id) on delete restrict
);

create table public.customer_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  customer_id uuid not null,
  entry_type text not null check (entry_type in (
    'credit_sale', 'repayment', 'debit_adjustment', 'credit_adjustment'
  )),
  direction text not null check (direction in ('debit', 'credit')),
  amount numeric(18,2) not null check (amount > 0),
  sale_id uuid,
  payment_id uuid,
  receipt_id uuid,
  description text not null check (length(btrim(description)) between 1 and 240),
  operation_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (business_id, operation_id),
  unique (payment_id),
  unique (receipt_id),
  constraint customer_ledger_entries_branch_fkey foreign key (branch_id, business_id)
    references public.branches(id, business_id) on delete restrict,
  constraint customer_ledger_entries_customer_fkey foreign key (customer_id, business_id)
    references public.customers(id, business_id) on delete restrict,
  constraint customer_ledger_entries_sale_fkey foreign key (sale_id, business_id)
    references public.sales(id, business_id) on delete restrict,
  constraint customer_ledger_entries_payment_fkey foreign key (payment_id, business_id)
    references public.payments(id, business_id) on delete restrict,
  constraint customer_ledger_entries_receipt_fkey foreign key (receipt_id, business_id)
    references public.customer_receipts(id, business_id) on delete restrict,
  check (
    (entry_type = 'credit_sale' and direction = 'debit' and sale_id is not null and payment_id is not null)
    or (entry_type = 'repayment' and direction = 'credit' and receipt_id is not null)
    or entry_type in ('debit_adjustment', 'credit_adjustment')
  )
);

create index expense_categories_business_active_idx
  on public.expense_categories(business_id, name) where is_active;
create index expenses_business_incurred_idx
  on public.expenses(business_id, incurred_on desc, created_at desc);
create index expenses_branch_business_fk_idx
  on public.expenses(branch_id, business_id);
create index expenses_category_business_fk_idx
  on public.expenses(category_id, business_id);
create index expenses_reversal_business_fk_idx
  on public.expenses(reverses_expense_id, business_id)
  where reverses_expense_id is not null;
create index expenses_created_by_idx on public.expenses(created_by);
create index customer_receipts_business_received_idx
  on public.customer_receipts(business_id, received_at desc);
create index customer_receipts_branch_business_fk_idx
  on public.customer_receipts(branch_id, business_id);
create index customer_receipts_customer_business_fk_idx
  on public.customer_receipts(customer_id, business_id);
create index customer_receipts_received_by_idx on public.customer_receipts(received_by);
create index customer_receipt_allocations_business_id_idx
  on public.customer_receipt_allocations(business_id);
create index customer_receipt_allocations_receipt_business_fk_idx
  on public.customer_receipt_allocations(receipt_id, business_id);
create index customer_receipt_allocations_sale_business_fk_idx
  on public.customer_receipt_allocations(sale_id, business_id);
create index customer_receipt_allocations_payment_business_fk_idx
  on public.customer_receipt_allocations(payment_id, business_id);
create index customer_ledger_business_customer_time_idx
  on public.customer_ledger_entries(business_id, customer_id, occurred_at desc);
create index customer_ledger_branch_business_fk_idx
  on public.customer_ledger_entries(branch_id, business_id);
create index customer_ledger_customer_business_fk_idx
  on public.customer_ledger_entries(customer_id, business_id);
create index customer_ledger_sale_business_fk_idx
  on public.customer_ledger_entries(sale_id, business_id)
  where sale_id is not null;
create index customer_ledger_payment_business_fk_idx
  on public.customer_ledger_entries(payment_id, business_id)
  where payment_id is not null;
create index customer_ledger_receipt_business_fk_idx
  on public.customer_ledger_entries(receipt_id, business_id)
  where receipt_id is not null;
create index customer_ledger_created_by_idx
  on public.customer_ledger_entries(created_by);

create or replace function private.seed_accounting_defaults()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.expense_categories (business_id, name) values
    (new.id, 'Rent'),
    (new.id, 'Utilities'),
    (new.id, 'Transport'),
    (new.id, 'Repairs and maintenance'),
    (new.id, 'Office supplies'),
    (new.id, 'Marketing'),
    (new.id, 'Staff welfare'),
    (new.id, 'Other')
  on conflict do nothing;
  return new;
end;
$$;

create trigger businesses_seed_accounting_defaults
after insert on public.businesses
for each row execute function private.seed_accounting_defaults();

insert into public.expense_categories (business_id, name)
select b.id, category.name
from public.businesses b
cross join (values
  ('Rent'), ('Utilities'), ('Transport'), ('Repairs and maintenance'),
  ('Office supplies'), ('Marketing'), ('Staff welfare'), ('Other')
) as category(name)
on conflict do nothing;

create or replace function private.reject_financial_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'Financial records are immutable; create an authorized reversal instead'
    using errcode = '42501';
end;
$$;

create trigger expenses_immutable
before update or delete on public.expenses
for each row execute function private.reject_financial_mutation();
create trigger customer_receipts_immutable
before update or delete on public.customer_receipts
for each row execute function private.reject_financial_mutation();
create trigger customer_receipt_allocations_immutable
before update or delete on public.customer_receipt_allocations
for each row execute function private.reject_financial_mutation();
create trigger customer_ledger_entries_immutable
before update or delete on public.customer_ledger_entries
for each row execute function private.reject_financial_mutation();

create or replace function private.validate_customer_credit_payment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  sale_record record;
  customer_limit numeric(18,2);
  outstanding numeric(18,2);
begin
  if new.payment_method <> 'customer_credit' then
    return new;
  end if;

  select s.business_id, s.branch_id, s.customer_id
  into sale_record
  from public.sales s
  where s.id = new.sale_id and s.business_id = new.business_id
  for update;

  if sale_record.customer_id is null then
    raise exception 'Customer credit requires a selected customer';
  end if;

  select c.credit_limit into customer_limit
  from public.customers c
  where c.id = sale_record.customer_id and c.business_id = new.business_id
    and c.is_active and c.archived_at is null
  for update;

  if customer_limit is null or customer_limit <= 0 then
    raise exception 'Customer does not have an active credit limit';
  end if;

  select coalesce(sum(case when cle.direction = 'debit' then cle.amount else -cle.amount end), 0)
  into outstanding
  from public.customer_ledger_entries cle
  where cle.business_id = new.business_id
    and cle.customer_id = sale_record.customer_id;

  if outstanding + new.amount > customer_limit then
    raise exception 'Customer credit limit exceeded';
  end if;
  return new;
end;
$$;

create trigger payments_validate_customer_credit
before insert on public.payments
for each row execute function private.validate_customer_credit_payment();

create or replace function private.post_customer_credit_payment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  sale_record record;
begin
  if new.payment_method <> 'customer_credit' then
    return new;
  end if;

  select s.branch_id, s.customer_id, s.invoice_number
  into strict sale_record
  from public.sales s
  where s.id = new.sale_id and s.business_id = new.business_id;

  insert into public.customer_ledger_entries (
    business_id, branch_id, customer_id, entry_type, direction, amount,
    sale_id, payment_id, description, operation_id, created_by, occurred_at
  ) values (
    new.business_id, sale_record.branch_id, sale_record.customer_id,
    'credit_sale', 'debit', new.amount, new.sale_id, new.id,
    'Credit sale ' || sale_record.invoice_number, gen_random_uuid(),
    new.received_by, new.created_at
  );
  return new;
end;
$$;

create trigger payments_post_customer_credit
after insert on public.payments
for each row execute function private.post_customer_credit_payment();

insert into public.customer_ledger_entries (
  business_id, branch_id, customer_id, entry_type, direction, amount,
  sale_id, payment_id, description, operation_id, created_by, occurred_at
)
select
  p.business_id, s.branch_id, s.customer_id, 'credit_sale', 'debit', p.amount,
  p.sale_id, p.id, 'Credit sale ' || s.invoice_number, gen_random_uuid(),
  p.received_by, p.created_at
from public.payments p
join public.sales s on s.id = p.sale_id and s.business_id = p.business_id
where p.payment_method = 'customer_credit'
  and s.customer_id is not null
on conflict (payment_id) do nothing;

create or replace function public.create_expense(
  target_business_id uuid,
  target_branch_id uuid,
  target_category_id uuid,
  operation_id uuid,
  expense_amount numeric,
  expense_tax_amount numeric default 0,
  expense_payment_method text default 'cash',
  expense_vendor_name text default null,
  expense_reference text default null,
  expense_notes text default null,
  expense_incurred_on date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  expense_id uuid := gen_random_uuid();
  expense_no text;
  existing_result jsonb;
  inserted_count integer;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if not private.has_permission(target_business_id, 'expenses.manage') then
    raise exception 'Expense management permission required';
  end if;
  if not private.has_branch_access(target_branch_id) then
    raise exception 'Branch access required';
  end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if expense_amount is null or round(expense_amount, 2) <= 0 then
    raise exception 'Expense amount must be greater than zero';
  end if;
  if coalesce(expense_tax_amount, 0) < 0
     or round(coalesce(expense_tax_amount, 0), 2) > round(expense_amount, 2) then
    raise exception 'Invalid expense tax amount';
  end if;
  if expense_payment_method not in ('cash', 'upi', 'card', 'bank_transfer', 'wallet') then
    raise exception 'Invalid expense payment method';
  end if;
  if not exists (
    select 1 from public.expense_categories ec
    where ec.id = target_category_id and ec.business_id = target_business_id and ec.is_active
  ) then
    raise exception 'Active expense category not found';
  end if;

  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (target_business_id, operation_id, 'expense.create', caller_id)
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select ir.result into existing_result
    from public.idempotency_records ir
    where ir.business_id = target_business_id
      and ir.operation_id = create_expense.operation_id
      and ir.operation_type = 'expense.create';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Expense operation is already in progress';
  end if;

  expense_no := 'EXP-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS') || '-'
    || upper(substr(replace(expense_id::text, '-', ''), 1, 8));
  insert into public.expenses (
    id, business_id, branch_id, category_id, expense_number, amount,
    tax_amount, payment_method, vendor_name, reference, notes, incurred_on,
    operation_id, created_by
  ) values (
    expense_id, target_business_id, target_branch_id, target_category_id,
    expense_no, round(expense_amount, 2), round(coalesce(expense_tax_amount, 0), 2),
    expense_payment_method, nullif(btrim(expense_vendor_name), ''),
    nullif(btrim(expense_reference), ''), nullif(btrim(expense_notes), ''),
    coalesce(expense_incurred_on, current_date), operation_id, caller_id
  );

  existing_result := jsonb_build_object(
    'expense_id', expense_id, 'expense_number', expense_no,
    'amount', round(expense_amount, 2)
  );
  update public.idempotency_records ir set result = existing_result
  where ir.business_id = target_business_id
    and ir.operation_id = create_expense.operation_id
    and ir.operation_type = 'expense.create';
  perform private.write_tenant_audit(
    target_business_id, 'expense.created', 'expense', expense_id::text,
    existing_result
  );
  return existing_result;
end;
$$;

create or replace function public.reverse_expense(
  target_expense_id uuid,
  operation_id uuid,
  reversal_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  original public.expenses%rowtype;
  reversal_id uuid := gen_random_uuid();
  reversal_no text;
  existing_result jsonb;
  inserted_count integer;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into original from public.expenses where id = target_expense_id for update;
  if original.id is null then raise exception 'Expense not found'; end if;
  if original.entry_type <> 'expense' then raise exception 'Only an expense can be reversed'; end if;
  if not private.has_permission(original.business_id, 'expenses.manage')
     or not private.has_branch_access(original.branch_id) then
    raise exception 'Expense management permission required';
  end if;
  if nullif(btrim(reversal_reason), '') is null then
    raise exception 'Reversal reason is required';
  end if;
  if exists (select 1 from public.expenses e where e.reverses_expense_id = original.id) then
    raise exception 'Expense has already been reversed';
  end if;

  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (original.business_id, operation_id, 'expense.reverse', caller_id)
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select ir.result into existing_result from public.idempotency_records ir
    where ir.business_id = original.business_id
      and ir.operation_id = reverse_expense.operation_id
      and ir.operation_type = 'expense.reverse';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Expense reversal is already in progress';
  end if;

  reversal_no := 'EXR-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS') || '-'
    || upper(substr(replace(reversal_id::text, '-', ''), 1, 8));
  insert into public.expenses (
    id, business_id, branch_id, category_id, expense_number, entry_type,
    reverses_expense_id, amount, tax_amount, payment_method, vendor_name,
    reference, notes, incurred_on, operation_id, created_by
  ) values (
    reversal_id, original.business_id, original.branch_id, original.category_id,
    reversal_no, 'reversal', original.id, original.amount, original.tax_amount,
    original.payment_method, original.vendor_name, original.reference,
    btrim(reversal_reason), current_date, operation_id, caller_id
  );

  existing_result := jsonb_build_object(
    'reversal_id', reversal_id, 'expense_number', reversal_no,
    'reversed_expense_id', original.id
  );
  update public.idempotency_records ir set result = existing_result
  where ir.business_id = original.business_id
    and ir.operation_id = reverse_expense.operation_id
    and ir.operation_type = 'expense.reverse';
  perform private.write_tenant_audit(
    original.business_id, 'expense.reversed', 'expense', original.id::text,
    existing_result || jsonb_build_object('reason', btrim(reversal_reason))
  );
  return existing_result;
end;
$$;

create or replace function public.record_customer_repayment(
  target_business_id uuid,
  target_branch_id uuid,
  target_customer_id uuid,
  operation_id uuid,
  repayment_amount numeric,
  repayment_method text default 'cash',
  repayment_reference text default null,
  repayment_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  receipt_id uuid := gen_random_uuid();
  receipt_no text;
  payment_id uuid;
  outstanding numeric(18,2);
  remaining numeric(18,2);
  allocation_amount numeric(18,2);
  sale_record record;
  existing_result jsonb;
  inserted_count integer;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if not private.has_permission(target_business_id, 'customer_credit.manage') then
    raise exception 'Customer credit management permission required';
  end if;
  if not private.has_branch_access(target_branch_id) then
    raise exception 'Branch access required';
  end if;
  if repayment_amount is null or round(repayment_amount, 2) <= 0 then
    raise exception 'Repayment amount must be greater than zero';
  end if;
  if repayment_method not in ('cash', 'upi', 'card', 'bank_transfer', 'wallet') then
    raise exception 'Invalid repayment method';
  end if;
  if not exists (
    select 1 from public.customers c
    where c.id = target_customer_id and c.business_id = target_business_id
      and c.is_active and c.archived_at is null
  ) then
    raise exception 'Active customer not found';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(target_customer_id::text, 0));
  select coalesce(sum(case when cle.direction = 'debit' then cle.amount else -cle.amount end), 0)
  into outstanding
  from public.customer_ledger_entries cle
  where cle.business_id = target_business_id and cle.customer_id = target_customer_id;
  if round(repayment_amount, 2) > outstanding then
    raise exception 'Repayment exceeds customer outstanding balance';
  end if;

  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (target_business_id, operation_id, 'customer.repayment', caller_id)
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select ir.result into existing_result from public.idempotency_records ir
    where ir.business_id = target_business_id
      and ir.operation_id = record_customer_repayment.operation_id
      and ir.operation_type = 'customer.repayment';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Repayment operation is already in progress';
  end if;

  receipt_no := 'RCP-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS') || '-'
    || upper(substr(replace(receipt_id::text, '-', ''), 1, 8));
  insert into public.customer_receipts (
    id, business_id, branch_id, customer_id, receipt_number, amount,
    payment_method, reference, notes, operation_id, received_by
  ) values (
    receipt_id, target_business_id, target_branch_id, target_customer_id,
    receipt_no, round(repayment_amount, 2), repayment_method,
    nullif(btrim(repayment_reference), ''), nullif(btrim(repayment_notes), ''),
    operation_id, caller_id
  );

  remaining := round(repayment_amount, 2);
  for sale_record in
    select s.id, s.due_total, s.paid_total, s.grand_total
    from public.sales s
    where s.business_id = target_business_id
      and s.customer_id = target_customer_id
      and s.status = 'completed'
      and s.due_total > 0
      and private.has_branch_access(s.branch_id)
    order by s.completed_at, s.id
    for update
  loop
    exit when remaining <= 0;
    allocation_amount := least(remaining, sale_record.due_total);
    payment_id := gen_random_uuid();
    insert into public.payments (
      id, business_id, sale_id, payment_method, status, amount, reference,
      provider, received_by, settled_at
    ) values (
      payment_id, target_business_id, sale_record.id, repayment_method,
      'settled', allocation_amount, receipt_no, 'customer_repayment',
      caller_id, now()
    );
    insert into public.customer_receipt_allocations (
      business_id, receipt_id, sale_id, payment_id, amount
    ) values (
      target_business_id, receipt_id, sale_record.id, payment_id,
      allocation_amount
    );
    update public.sales set
      paid_total = least(grand_total, paid_total + allocation_amount),
      due_total = greatest(grand_total - (paid_total + allocation_amount), 0),
      payment_status = case
        when paid_total + allocation_amount >= grand_total then 'paid'
        else 'partially_paid'
      end
    where id = sale_record.id;
    remaining := remaining - allocation_amount;
  end loop;
  if remaining > 0 then
    raise exception 'Repayment exceeds accessible customer sale dues';
  end if;

  insert into public.customer_ledger_entries (
    business_id, branch_id, customer_id, entry_type, direction, amount,
    receipt_id, description, operation_id, created_by
  ) values (
    target_business_id, target_branch_id, target_customer_id, 'repayment',
    'credit', round(repayment_amount, 2), receipt_id,
    'Customer repayment ' || receipt_no, operation_id, caller_id
  );

  existing_result := jsonb_build_object(
    'receipt_id', receipt_id, 'receipt_number', receipt_no,
    'amount', round(repayment_amount, 2),
    'remaining_balance', outstanding - round(repayment_amount, 2)
  );
  update public.idempotency_records ir set result = existing_result
  where ir.business_id = target_business_id
    and ir.operation_id = record_customer_repayment.operation_id
    and ir.operation_type = 'customer.repayment';
  perform private.write_tenant_audit(
    target_business_id, 'customer.repayment_recorded', 'customer',
    target_customer_id::text, existing_result
  );
  return existing_result;
end;
$$;

create or replace function public.get_business_dashboard(
  target_business_id uuid,
  period_start timestamptz,
  period_end timestamptz
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  result jsonb;
  can_view_profit boolean;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not private.has_permission(target_business_id, 'reports.view') then
    raise exception 'Report viewing permission required';
  end if;
  if period_start is null or period_end is null or period_end <= period_start then
    raise exception 'Invalid report period';
  end if;
  can_view_profit := private.has_permission(target_business_id, 'reports.profit');

  select jsonb_build_object(
    'period_start', period_start,
    'period_end', period_end,
    'sales_total', coalesce((
      select sum(s.grand_total) from public.sales s
      where s.business_id = target_business_id and s.status = 'completed'
        and s.completed_at >= period_start and s.completed_at < period_end
        and private.has_branch_access(s.branch_id)
    ), 0),
    'tax_total', coalesce((
      select sum(s.tax_total) from public.sales s
      where s.business_id = target_business_id and s.status = 'completed'
        and s.completed_at >= period_start and s.completed_at < period_end
        and private.has_branch_access(s.branch_id)
    ), 0),
    'order_count', coalesce((
      select count(*) from public.sales s
      where s.business_id = target_business_id and s.status = 'completed'
        and s.completed_at >= period_start and s.completed_at < period_end
        and private.has_branch_access(s.branch_id)
    ), 0),
    'expenses_total', coalesce((
      select sum(case when e.entry_type = 'expense' then e.amount else -e.amount end)
      from public.expenses e
      where e.business_id = target_business_id
        and e.incurred_on >= period_start::date and e.incurred_on < period_end::date
        and private.has_branch_access(e.branch_id)
    ), 0),
    'outstanding_receivables', coalesce((
      select sum(case when cle.direction = 'debit' then cle.amount else -cle.amount end)
      from public.customer_ledger_entries cle
      where cle.business_id = target_business_id
        and private.has_branch_access(cle.branch_id)
    ), 0),
    'low_stock_count', coalesce((
      select count(*) from public.inventory_balances ib
      join public.warehouses w on w.id = ib.warehouse_id and w.business_id = ib.business_id
      where ib.business_id = target_business_id
        and ib.quantity_on_hand - ib.quantity_reserved <= ib.reorder_point
        and private.has_branch_access(w.branch_id)
    ), 0),
    'gross_profit', case when can_view_profit then coalesce((
      select sum(si.line_total - si.tax_amount - (si.quantity * si.unit_cost))
      from public.sale_items si
      join public.sales s on s.id = si.sale_id and s.business_id = si.business_id
      where s.business_id = target_business_id and s.status = 'completed'
        and s.completed_at >= period_start and s.completed_at < period_end
        and private.has_branch_access(s.branch_id)
    ), 0) else null end,
    'daily_sales', coalesce((
      select jsonb_agg(jsonb_build_object('date', daily.day, 'total', daily.total, 'orders', daily.orders) order by daily.day)
      from (
        select s.completed_at::date as day, sum(s.grand_total) as total, count(*) as orders
        from public.sales s
        where s.business_id = target_business_id and s.status = 'completed'
          and s.completed_at >= period_start and s.completed_at < period_end
          and private.has_branch_access(s.branch_id)
        group by s.completed_at::date
      ) daily
    ), '[]'::jsonb),
    'payment_breakdown', coalesce((
      select jsonb_agg(jsonb_build_object('method', paid.payment_method, 'total', paid.total) order by paid.payment_method)
      from (
        select p.payment_method, sum(p.amount) as total
        from public.payments p
        join public.sales s on s.id = p.sale_id and s.business_id = p.business_id
        where p.business_id = target_business_id and p.status = 'settled'
          and p.settled_at >= period_start and p.settled_at < period_end
          and private.has_branch_access(s.branch_id)
        group by p.payment_method
      ) paid
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

alter table public.expense_categories enable row level security;
alter table public.expenses enable row level security;
alter table public.customer_receipts enable row level security;
alter table public.customer_receipt_allocations enable row level security;
alter table public.customer_ledger_entries enable row level security;

create policy expense_categories_select on public.expense_categories
for select to authenticated
using ((select private.has_permission(business_id, 'expenses.view')));

create policy expenses_select on public.expenses
for select to authenticated
using (
  (select private.has_permission(business_id, 'expenses.view'))
  and (select private.has_branch_access(branch_id))
);

create policy customer_receipts_select on public.customer_receipts
for select to authenticated
using (
  (select private.has_permission(business_id, 'customer_credit.view'))
  and (select private.has_branch_access(branch_id))
);

create policy customer_receipt_allocations_select on public.customer_receipt_allocations
for select to authenticated
using (exists (
  select 1 from public.customer_receipts cr
  where cr.id = customer_receipt_allocations.receipt_id
    and cr.business_id = customer_receipt_allocations.business_id
    and (select private.has_permission(cr.business_id, 'customer_credit.view'))
    and (select private.has_branch_access(cr.branch_id))
));

create policy customer_ledger_entries_select on public.customer_ledger_entries
for select to authenticated
using (
  (select private.has_permission(business_id, 'customer_credit.view'))
  and (select private.has_branch_access(branch_id))
);

revoke all on public.expense_categories, public.expenses,
  public.customer_receipts, public.customer_receipt_allocations,
  public.customer_ledger_entries from anon, authenticated;
grant select on public.expense_categories, public.expenses,
  public.customer_receipts, public.customer_receipt_allocations,
  public.customer_ledger_entries to authenticated;

revoke all on function public.create_expense(
  uuid, uuid, uuid, uuid, numeric, numeric, text, text, text, text, date
) from public, anon, authenticated;
revoke all on function public.reverse_expense(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.record_customer_repayment(
  uuid, uuid, uuid, uuid, numeric, text, text, text
) from public, anon, authenticated;
revoke all on function public.get_business_dashboard(uuid, timestamptz, timestamptz)
from public, anon, authenticated;

revoke all on function private.seed_accounting_role_permissions()
from public, anon, authenticated;
revoke all on function private.seed_accounting_defaults()
from public, anon, authenticated;
revoke all on function private.reject_financial_mutation()
from public, anon, authenticated;
revoke all on function private.validate_customer_credit_payment()
from public, anon, authenticated;
revoke all on function private.post_customer_credit_payment()
from public, anon, authenticated;

grant execute on function public.create_expense(
  uuid, uuid, uuid, uuid, numeric, numeric, text, text, text, text, date
) to authenticated;
grant execute on function public.reverse_expense(uuid, uuid, text) to authenticated;
grant execute on function public.record_customer_repayment(
  uuid, uuid, uuid, uuid, numeric, text, text, text
) to authenticated;
grant execute on function public.get_business_dashboard(uuid, timestamptz, timestamptz)
to authenticated;
