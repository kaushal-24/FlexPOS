-- Complete the accounting bridge without cross-module triggers.  Operational
-- records are posted explicitly through permission-checked RPCs, making the
-- action visible, retryable, and safe for existing production data.
begin;

alter table public.accounting_tax_profiles
  add column if not exists tax_regime text not null default 'gst',
  add column if not exists country_code text not null default 'IN',
  add column if not exists registration_number text,
  add column if not exists default_tax_rate numeric(7,4) not null default 0,
  add column if not exists tax_inclusive boolean not null default false;

alter table public.accounting_tax_profiles
  drop constraint if exists accounting_tax_profiles_tax_regime_check,
  drop constraint if exists accounting_tax_profiles_country_code_check,
  drop constraint if exists accounting_tax_profiles_default_tax_rate_check;
alter table public.accounting_tax_profiles
  add constraint accounting_tax_profiles_tax_regime_check
    check (tax_regime in ('gst','vat','sales_tax','none')),
  add constraint accounting_tax_profiles_country_code_check
    check (country_code ~ '^[A-Z]{2}$'),
  add constraint accounting_tax_profiles_default_tax_rate_check
    check (default_tax_rate >= 0 and default_tax_rate <= 100);
alter table public.accounting_tax_profiles alter column state_code drop not null;
alter table public.accounting_tax_profiles alter column state_code set default '00';
update public.accounting_tax_profiles
set country_code = 'IN', tax_regime = 'gst'
where country_code is null or tax_regime is null;

insert into public.accounting_accounts (business_id, code, name, account_type, is_system)
select b.id, v.code, v.name, v.account_type, true
from public.businesses b
cross join (values
  ('1110','Customer credit clearing','asset'),
  ('2200','Credit note liability','liability')
) as v(code,name,account_type)
on conflict (business_id, code) do nothing;

create table if not exists public.accounting_subledger_postings (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  subledger_type text not null check (subledger_type in ('ar','ap','expense','tax_note','sale','sale_payment','purchase_invoice','purchase_payment','customer_receipt')),
  source_id uuid not null,
  journal_entry_id uuid not null,
  memo text not null,
  posted_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  posted_at timestamptz not null default now(),
  unique (business_id, subledger_type, source_id),
  unique (journal_entry_id, business_id),
  constraint accounting_subledger_postings_entry_fkey
    foreign key (journal_entry_id, business_id)
    references public.accounting_journal_entries(id, business_id) on delete restrict
);

create index if not exists accounting_subledger_postings_business_type_idx
  on public.accounting_subledger_postings(business_id, subledger_type, posted_at desc);
create index if not exists accounting_subledger_postings_source_idx
  on public.accounting_subledger_postings(source_id, business_id);

create table if not exists public.accounting_bank_reconciliations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  cash_bank_account_id uuid not null,
  statement_start date not null,
  statement_end date not null,
  opening_balance numeric(18,2) not null default 0,
  closing_balance numeric(18,2) not null,
  reconciled_amount numeric(18,2) not null default 0,
  difference_amount numeric(18,2) not null default 0,
  status text not null default 'draft' check (status in ('draft','completed','reopened')),
  notes text,
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  completed_by uuid references auth.users(id) on delete set null,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (id, business_id),
  constraint accounting_bank_reconciliations_account_fkey
    foreign key (cash_bank_account_id, business_id)
    references public.accounting_cash_bank_accounts(id, business_id) on delete restrict,
  check (statement_end >= statement_start)
);

create table if not exists public.accounting_bank_reconciliation_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  reconciliation_id uuid not null,
  journal_line_id uuid not null references public.accounting_journal_lines(id) on delete restrict,
  amount numeric(18,2) not null check (amount <> 0),
  note text,
  created_at timestamptz not null default now(),
  unique (reconciliation_id, journal_line_id),
  constraint accounting_bank_reconciliation_items_reconciliation_fkey
    foreign key (reconciliation_id, business_id)
    references public.accounting_bank_reconciliations(id, business_id) on delete cascade
);

create index if not exists accounting_bank_reconciliations_business_end_idx
  on public.accounting_bank_reconciliations(business_id, statement_end desc);
create index if not exists accounting_bank_reconciliation_items_reconciliation_idx
  on public.accounting_bank_reconciliation_items(reconciliation_id, created_at desc);

create table if not exists public.accounting_tax_adjustment_notes (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid,
  note_number text not null,
  note_type text not null check (note_type in ('credit','debit')),
  scope text not null check (scope in ('sales','purchase')),
  source_id uuid,
  taxable_amount numeric(18,2) not null check (taxable_amount >= 0),
  cgst_amount numeric(18,2) not null default 0 check (cgst_amount >= 0),
  sgst_amount numeric(18,2) not null default 0 check (sgst_amount >= 0),
  igst_amount numeric(18,2) not null default 0 check (igst_amount >= 0),
  reason text not null check (length(btrim(reason)) between 3 and 500),
  note_date date not null default current_date,
  status text not null default 'draft' check (status in ('draft','posted','void')),
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  posted_by uuid references auth.users(id) on delete set null,
  posted_at timestamptz,
  created_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, note_number),
  constraint accounting_tax_adjustment_notes_branch_fkey
    foreign key (branch_id, business_id)
    references public.branches(id, business_id) on delete restrict,
  check (cgst_amount + sgst_amount + igst_amount >= 0)
);

create index if not exists accounting_tax_adjustment_notes_business_date_idx
  on public.accounting_tax_adjustment_notes(business_id, note_date desc);

alter table public.accounting_subledger_postings enable row level security;
alter table public.accounting_bank_reconciliations enable row level security;
alter table public.accounting_bank_reconciliation_items enable row level security;
alter table public.accounting_tax_adjustment_notes enable row level security;

create policy accounting_subledger_postings_select on public.accounting_subledger_postings
  for select to authenticated using ((select private.has_permission(business_id, 'accounting.view')));
create policy accounting_bank_reconciliations_select on public.accounting_bank_reconciliations
  for select to authenticated using ((select private.has_permission(business_id, 'accounting.view')));
create policy accounting_bank_reconciliations_insert on public.accounting_bank_reconciliations
  for insert to authenticated with check ((select private.has_permission(business_id, 'accounting.manage')));
create policy accounting_bank_reconciliations_update on public.accounting_bank_reconciliations
  for update to authenticated using ((select private.has_permission(business_id, 'accounting.manage')))
  with check ((select private.has_permission(business_id, 'accounting.manage')));
create policy accounting_bank_reconciliation_items_select on public.accounting_bank_reconciliation_items
  for select to authenticated using ((select private.has_permission(business_id, 'accounting.view')));
create policy accounting_tax_adjustment_notes_select on public.accounting_tax_adjustment_notes
  for select to authenticated using ((select private.has_permission(business_id, 'tax.view')));
create policy accounting_tax_adjustment_notes_insert on public.accounting_tax_adjustment_notes
  for insert to authenticated with check ((select private.has_permission(business_id, 'tax.manage')));
create policy accounting_tax_adjustment_notes_update on public.accounting_tax_adjustment_notes
  for update to authenticated using ((select private.has_permission(business_id, 'tax.manage')))
  with check ((select private.has_permission(business_id, 'tax.manage')));

grant select on public.accounting_subledger_postings,
  public.accounting_bank_reconciliations,
  public.accounting_bank_reconciliation_items,
  public.accounting_tax_adjustment_notes to authenticated;
grant insert, update on public.accounting_bank_reconciliations,
  public.accounting_tax_adjustment_notes to authenticated;
revoke all on public.accounting_subledger_postings,
  public.accounting_bank_reconciliations,
  public.accounting_bank_reconciliation_items,
  public.accounting_tax_adjustment_notes from anon;

create or replace function private.accounting_account_id(target_business_id uuid, target_code text)
returns uuid language sql stable security definer set search_path = '' as $$
  select id from public.accounting_accounts
  where business_id = target_business_id and code = target_code and is_active
  limit 1
$$;
revoke all on function private.accounting_account_id(uuid,text) from public, anon, authenticated, service_role;

create or replace function public.post_sale_to_ledger(target_sale_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  sale_record public.sales%rowtype;
  existing_posting public.accounting_subledger_postings%rowtype;
  ar_id uuid; revenue_id uuid; gst_id uuid;
  journal_id uuid; lines jsonb; base_amount numeric(18,2);
  payment_record record; payment_count integer := 0;
  result jsonb;
begin
  select * into sale_record from public.sales where id = target_sale_id for update;
  if not found or not private.has_permission(sale_record.business_id, 'accounting.manage') then
    raise exception 'Sale is not accessible for accounting posting';
  end if;
  if sale_record.status <> 'completed' then raise exception 'Only completed sales can be posted'; end if;
  select * into existing_posting from public.accounting_subledger_postings
  where business_id = sale_record.business_id and subledger_type = 'sale' and source_id = sale_record.id;
  if found then return jsonb_build_object('sale_id', sale_record.id, 'journal_entry_id', existing_posting.journal_entry_id, 'idempotent', true); end if;
  ar_id := private.accounting_account_id(sale_record.business_id, '1100');
  revenue_id := private.accounting_account_id(sale_record.business_id, '4000');
  gst_id := private.accounting_account_id(sale_record.business_id, '2100');
  if ar_id is null or revenue_id is null or gst_id is null then raise exception 'Standard accounting accounts are missing'; end if;
  base_amount := round(sale_record.grand_total - sale_record.tax_total, 2);
  lines := jsonb_build_array(jsonb_build_object('account_id', ar_id, 'debit', sale_record.grand_total, 'credit', 0, 'branch_id', sale_record.branch_id, 'description', 'Accounts receivable for ' || sale_record.invoice_number));
  if base_amount > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account_id', revenue_id, 'debit', 0, 'credit', base_amount, 'branch_id', sale_record.branch_id, 'description', 'Sales revenue')); end if;
  if sale_record.tax_total > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account_id', gst_id, 'debit', 0, 'credit', sale_record.tax_total, 'branch_id', sale_record.branch_id, 'description', 'GST collected')); end if;
  result := public.create_journal_entry(sale_record.business_id, sale_record.completed_at::date, 'Sale ' || sale_record.invoice_number, 'sale', sale_record.id, lines);
  journal_id := (result->>'id')::uuid;
  insert into public.accounting_subledger_postings(business_id, subledger_type, source_id, journal_entry_id, memo)
  values (sale_record.business_id, 'sale', sale_record.id, journal_id, 'Sale invoice ' || sale_record.invoice_number);
  for payment_record in
    select id from public.payments where business_id = sale_record.business_id and sale_id = sale_record.id and status = 'settled'
      and payment_method in ('cash','upi','card','bank_transfer','wallet','gift_card','customer_credit','credit_note')
  loop
    perform public.post_sale_payment_to_ledger(payment_record.id);
    payment_count := payment_count + 1;
  end loop;
  perform private.write_tenant_audit(sale_record.business_id, 'accounting.sale_posted', 'sale', sale_record.id::text, jsonb_build_object('journal_entry_id', journal_id, 'payments_posted', payment_count));
  return jsonb_build_object('sale_id', sale_record.id, 'journal_entry_id', journal_id, 'payments_posted', payment_count);
end;
$$;

create or replace function public.post_sale_payment_to_ledger(target_payment_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  payment_record public.payments%rowtype;
  sale_record public.sales%rowtype;
  existing_posting public.accounting_subledger_postings%rowtype;
  debit_account uuid; ar_id uuid; journal_id uuid; result jsonb;
begin
  select * into payment_record from public.payments where id = target_payment_id for update;
  if not found then raise exception 'Payment is not found'; end if;
  select * into sale_record from public.sales where id = payment_record.sale_id;
  if not found or not private.has_permission(payment_record.business_id, 'accounting.manage') then raise exception 'Sale payment is not accessible for accounting posting'; end if;
  if payment_record.status <> 'settled' then raise exception 'Only settled payments can be posted'; end if;
  select * into existing_posting from public.accounting_subledger_postings where business_id = payment_record.business_id and subledger_type = 'sale_payment' and source_id = payment_record.id;
  if found then return jsonb_build_object('payment_id', payment_record.id, 'journal_entry_id', existing_posting.journal_entry_id, 'idempotent', true); end if;
  ar_id := private.accounting_account_id(payment_record.business_id, '1100');
  debit_account := case payment_record.payment_method
    when 'cash' then private.accounting_account_id(payment_record.business_id, '1000')
    when 'customer_credit' then private.accounting_account_id(payment_record.business_id, '1110')
    when 'credit_note' then private.accounting_account_id(payment_record.business_id, '2200')
    else private.accounting_account_id(payment_record.business_id, '1010') end;
  if ar_id is null or debit_account is null then raise exception 'Settlement accounts are missing'; end if;
  result := public.create_journal_entry(payment_record.business_id, payment_record.created_at::date, 'Payment for sale ' || sale_record.invoice_number, 'sale_payment', payment_record.id,
    jsonb_build_array(
      jsonb_build_object('account_id', debit_account, 'debit', payment_record.amount, 'credit', 0, 'branch_id', sale_record.branch_id, 'description', payment_record.payment_method || ' received'),
      jsonb_build_object('account_id', ar_id, 'debit', 0, 'credit', payment_record.amount, 'branch_id', sale_record.branch_id, 'description', 'Reduce accounts receivable')
    ));
  journal_id := (result->>'id')::uuid;
  insert into public.accounting_subledger_postings(business_id, subledger_type, source_id, journal_entry_id, memo)
  values (payment_record.business_id, 'sale_payment', payment_record.id, journal_id, 'Sale payment ' || payment_record.id::text);
  return jsonb_build_object('payment_id', payment_record.id, 'journal_entry_id', journal_id);
end;
$$;

create or replace function public.post_purchase_invoice_to_ledger(target_invoice_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  invoice_record public.purchase_invoices%rowtype;
  existing_posting public.accounting_subledger_postings%rowtype;
  inventory_id uuid; input_tax_id uuid; payable_id uuid; journal_id uuid; lines jsonb; result jsonb;
begin
  select * into invoice_record from public.purchase_invoices where id = target_invoice_id for update;
  if not found or not private.has_permission(invoice_record.business_id, 'accounting.manage') then raise exception 'Purchase invoice is not accessible for accounting posting'; end if;
  if invoice_record.status = 'void' then raise exception 'Void purchase invoices cannot be posted'; end if;
  select * into existing_posting from public.accounting_subledger_postings where business_id = invoice_record.business_id and subledger_type = 'purchase_invoice' and source_id = invoice_record.id;
  if found then return jsonb_build_object('invoice_id', invoice_record.id, 'journal_entry_id', existing_posting.journal_entry_id, 'idempotent', true); end if;
  inventory_id := private.accounting_account_id(invoice_record.business_id, '1200');
  input_tax_id := private.accounting_account_id(invoice_record.business_id, '1300');
  payable_id := private.accounting_account_id(invoice_record.business_id, '2000');
  if inventory_id is null or input_tax_id is null or payable_id is null then raise exception 'Purchase accounting accounts are missing'; end if;
  lines := '[]'::jsonb;
  if invoice_record.subtotal > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account_id', inventory_id, 'debit', invoice_record.subtotal, 'credit', 0, 'description', 'Inventory purchase')); end if;
  if invoice_record.tax_total > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account_id', input_tax_id, 'debit', invoice_record.tax_total, 'credit', 0, 'description', 'Input tax credit')); end if;
  lines := lines || jsonb_build_array(jsonb_build_object('account_id', payable_id, 'debit', 0, 'credit', invoice_record.total, 'description', 'Supplier payable'));
  result := public.create_journal_entry(invoice_record.business_id, invoice_record.invoice_date, 'Purchase invoice ' || invoice_record.invoice_number, 'purchase_invoice', invoice_record.id, lines);
  journal_id := (result->>'id')::uuid;
  insert into public.accounting_subledger_postings(business_id, subledger_type, source_id, journal_entry_id, memo)
  values (invoice_record.business_id, 'purchase_invoice', invoice_record.id, journal_id, 'Purchase invoice ' || invoice_record.invoice_number);
  return jsonb_build_object('invoice_id', invoice_record.id, 'journal_entry_id', journal_id);
end;
$$;

create or replace function public.post_purchase_invoice_payment_to_ledger(target_payment_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  payment_record public.purchase_invoice_payments%rowtype;
  invoice_record public.purchase_invoices%rowtype;
  existing_posting public.accounting_subledger_postings%rowtype;
  payable_id uuid; credit_account uuid; journal_id uuid; result jsonb;
begin
  select * into payment_record from public.purchase_invoice_payments where id = target_payment_id for update;
  if not found then raise exception 'Supplier payment is not found'; end if;
  select * into invoice_record from public.purchase_invoices where id = payment_record.invoice_id;
  if not found or not private.has_permission(payment_record.business_id, 'accounting.manage') then raise exception 'Supplier payment is not accessible for accounting posting'; end if;
  select * into existing_posting from public.accounting_subledger_postings where business_id = payment_record.business_id and subledger_type = 'purchase_payment' and source_id = payment_record.id;
  if found then return jsonb_build_object('payment_id', payment_record.id, 'journal_entry_id', existing_posting.journal_entry_id, 'idempotent', true); end if;
  payable_id := private.accounting_account_id(payment_record.business_id, '2000');
  credit_account := case when payment_record.payment_method = 'cash' then private.accounting_account_id(payment_record.business_id, '1000') else private.accounting_account_id(payment_record.business_id, '1010') end;
  if payable_id is null or credit_account is null then raise exception 'Supplier settlement accounts are missing'; end if;
  result := public.create_journal_entry(payment_record.business_id, payment_record.paid_at::date, 'Payment for supplier invoice ' || invoice_record.invoice_number, 'purchase_payment', payment_record.id,
    jsonb_build_array(
      jsonb_build_object('account_id', payable_id, 'debit', payment_record.amount, 'credit', 0, 'description', 'Reduce accounts payable'),
      jsonb_build_object('account_id', credit_account, 'debit', 0, 'credit', payment_record.amount, 'description', payment_record.payment_method || ' paid')
    ));
  journal_id := (result->>'id')::uuid;
  insert into public.accounting_subledger_postings(business_id, subledger_type, source_id, journal_entry_id, memo)
  values (payment_record.business_id, 'purchase_payment', payment_record.id, journal_id, 'Supplier payment ' || payment_record.id::text);
  return jsonb_build_object('payment_id', payment_record.id, 'journal_entry_id', journal_id);
end;
$$;

create or replace function public.post_expense_to_ledger(target_expense_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  expense_record public.expenses%rowtype;
  existing_posting public.accounting_subledger_postings%rowtype;
  expense_account uuid; tax_account uuid; cash_account uuid; journal_id uuid; lines jsonb := '[]'::jsonb; result jsonb; net_amount numeric(18,2); reverse_entry boolean;
begin
  select * into expense_record from public.expenses where id = target_expense_id for update;
  if not found or not private.has_permission(expense_record.business_id, 'accounting.manage') then raise exception 'Expense is not accessible for accounting posting'; end if;
  if expense_record.approval_status <> 'approved' then raise exception 'Only approved expenses can be posted'; end if;
  select * into existing_posting from public.accounting_subledger_postings where business_id = expense_record.business_id and subledger_type = 'expense' and source_id = expense_record.id;
  if found then return jsonb_build_object('expense_id', expense_record.id, 'journal_entry_id', existing_posting.journal_entry_id, 'idempotent', true); end if;
  expense_account := private.accounting_account_id(expense_record.business_id, '6000');
  tax_account := private.accounting_account_id(expense_record.business_id, '1300');
  cash_account := case when expense_record.payment_method = 'cash' then private.accounting_account_id(expense_record.business_id, '1000') else private.accounting_account_id(expense_record.business_id, '1010') end;
  if expense_account is null or tax_account is null or cash_account is null then raise exception 'Expense accounting accounts are missing'; end if;
  net_amount := round(expense_record.amount - expense_record.tax_amount, 2);
  reverse_entry := expense_record.entry_type = 'reversal';
  if not reverse_entry then
    if net_amount > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account_id', expense_account, 'debit', net_amount, 'credit', 0, 'branch_id', expense_record.branch_id, 'description', 'Operating expense')); end if;
    if expense_record.tax_amount > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account_id', tax_account, 'debit', expense_record.tax_amount, 'credit', 0, 'branch_id', expense_record.branch_id, 'description', 'Input tax on expense')); end if;
    lines := lines || jsonb_build_array(jsonb_build_object('account_id', cash_account, 'debit', 0, 'credit', expense_record.amount, 'branch_id', expense_record.branch_id, 'description', expense_record.payment_method || ' expense payment'));
  else
    lines := lines || jsonb_build_array(jsonb_build_object('account_id', cash_account, 'debit', expense_record.amount, 'credit', 0, 'branch_id', expense_record.branch_id, 'description', 'Expense reversal refund'));
    if net_amount > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account_id', expense_account, 'debit', 0, 'credit', net_amount, 'branch_id', expense_record.branch_id, 'description', 'Reversed operating expense')); end if;
    if expense_record.tax_amount > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account_id', tax_account, 'debit', 0, 'credit', expense_record.tax_amount, 'branch_id', expense_record.branch_id, 'description', 'Reversed input tax')); end if;
  end if;
  result := public.create_journal_entry(expense_record.business_id, expense_record.incurred_on, expense_record.entry_type || ' ' || expense_record.expense_number, 'expense', expense_record.id, lines);
  journal_id := (result->>'id')::uuid;
  insert into public.accounting_subledger_postings(business_id, subledger_type, source_id, journal_entry_id, memo)
  values (expense_record.business_id, 'expense', expense_record.id, journal_id, expense_record.entry_type || ' ' || expense_record.expense_number);
  return jsonb_build_object('expense_id', expense_record.id, 'journal_entry_id', journal_id);
end;
$$;

create or replace function public.post_customer_receipt_to_ledger(target_receipt_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  receipt_record public.customer_receipts%rowtype;
  existing_posting public.accounting_subledger_postings%rowtype;
  cash_account uuid; ar_id uuid; journal_id uuid; result jsonb;
begin
  select * into receipt_record from public.customer_receipts where id = target_receipt_id for update;
  if not found or not private.has_permission(receipt_record.business_id, 'accounting.manage') then raise exception 'Customer receipt is not accessible for accounting posting'; end if;
  select * into existing_posting from public.accounting_subledger_postings where business_id = receipt_record.business_id and subledger_type = 'customer_receipt' and source_id = receipt_record.id;
  if found then return jsonb_build_object('receipt_id', receipt_record.id, 'journal_entry_id', existing_posting.journal_entry_id, 'idempotent', true); end if;
  cash_account := case when receipt_record.payment_method = 'cash' then private.accounting_account_id(receipt_record.business_id, '1000') else private.accounting_account_id(receipt_record.business_id, '1010') end;
  ar_id := private.accounting_account_id(receipt_record.business_id, '1100');
  if cash_account is null or ar_id is null then raise exception 'Receipt accounting accounts are missing'; end if;
  result := public.create_journal_entry(receipt_record.business_id, receipt_record.received_at::date, 'Customer receipt ' || receipt_record.receipt_number, 'customer_receipt', receipt_record.id,
    jsonb_build_array(
      jsonb_build_object('account_id', cash_account, 'debit', receipt_record.amount, 'credit', 0, 'branch_id', receipt_record.branch_id, 'description', receipt_record.payment_method || ' customer receipt'),
      jsonb_build_object('account_id', ar_id, 'debit', 0, 'credit', receipt_record.amount, 'branch_id', receipt_record.branch_id, 'description', 'Reduce accounts receivable')
    ));
  journal_id := (result->>'id')::uuid;
  insert into public.accounting_subledger_postings(business_id, subledger_type, source_id, journal_entry_id, memo)
  values (receipt_record.business_id, 'customer_receipt', receipt_record.id, journal_id, 'Customer receipt ' || receipt_record.receipt_number);
  return jsonb_build_object('receipt_id', receipt_record.id, 'journal_entry_id', journal_id);
end;
$$;

create or replace function public.sync_operational_ledger(target_business_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r record; sales_count integer := 0; purchase_count integer := 0; expense_count integer := 0; receipt_count integer := 0;
begin
  if not private.has_permission(target_business_id, 'accounting.manage') then raise exception 'Accounting management permission required'; end if;
  for r in select id from public.sales where business_id = target_business_id and status = 'completed' loop perform public.post_sale_to_ledger(r.id); sales_count := sales_count + 1; end loop;
  for r in select id from public.purchase_invoices where business_id = target_business_id and status <> 'void' loop perform public.post_purchase_invoice_to_ledger(r.id); purchase_count := purchase_count + 1; end loop;
  for r in select id from public.purchase_invoice_payments where business_id = target_business_id loop perform public.post_purchase_invoice_payment_to_ledger(r.id); end loop;
  for r in select id from public.expenses where business_id = target_business_id and approval_status = 'approved' loop perform public.post_expense_to_ledger(r.id); expense_count := expense_count + 1; end loop;
  for r in select id from public.customer_receipts where business_id = target_business_id loop perform public.post_customer_receipt_to_ledger(r.id); receipt_count := receipt_count + 1; end loop;
  return jsonb_build_object('sales', sales_count, 'purchase_invoices', purchase_count, 'expenses', expense_count, 'customer_receipts', receipt_count);
end;
$$;

create or replace function public.create_tax_adjustment_note(
  target_business_id uuid, target_branch_id uuid, target_note_number text,
  target_note_type text, target_scope text, target_taxable_amount numeric,
  target_cgst numeric, target_sgst numeric, target_igst numeric,
  target_reason text, target_note_date date default current_date, target_source_id uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare note_id uuid;
begin
  if not private.has_permission(target_business_id, 'tax.manage') then raise exception 'Tax management permission required'; end if;
  if target_note_type not in ('credit','debit') or target_scope not in ('sales','purchase') then raise exception 'Tax note type or scope is invalid'; end if;
  if target_taxable_amount is null or target_taxable_amount < 0 or coalesce(target_cgst,0) < 0 or coalesce(target_sgst,0) < 0 or coalesce(target_igst,0) < 0 then raise exception 'Tax note amounts are invalid'; end if;
  insert into public.accounting_tax_adjustment_notes(business_id, branch_id, note_number, note_type, scope, source_id, taxable_amount, cgst_amount, sgst_amount, igst_amount, reason, note_date)
  values (target_business_id, target_branch_id, btrim(target_note_number), target_note_type, target_scope, target_source_id, round(target_taxable_amount,2), round(coalesce(target_cgst,0),2), round(coalesce(target_sgst,0),2), round(coalesce(target_igst,0),2), btrim(target_reason), coalesce(target_note_date,current_date))
  returning id into note_id;
  return jsonb_build_object('id', note_id, 'status', 'draft');
end;
$$;

create or replace function public.post_tax_adjustment_note_to_ledger(target_note_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare n public.accounting_tax_adjustment_notes%rowtype; existing_posting public.accounting_subledger_postings%rowtype; revenue_id uuid; inventory_id uuid; output_tax_id uuid; input_tax_id uuid; ar_id uuid; ap_id uuid; lines jsonb := '[]'::jsonb; total_tax numeric(18,2); total_amount numeric(18,2); journal_id uuid; result jsonb;
begin
  select * into n from public.accounting_tax_adjustment_notes where id = target_note_id for update;
  if not found or not private.has_permission(n.business_id, 'accounting.manage') then raise exception 'Tax note is not accessible for accounting posting'; end if;
  if n.status = 'void' then raise exception 'Void tax notes cannot be posted'; end if;
  select * into existing_posting from public.accounting_subledger_postings where business_id = n.business_id and subledger_type = 'tax_note' and source_id = n.id;
  if found then update public.accounting_tax_adjustment_notes set status='posted', posted_by=auth.uid(), posted_at=coalesce(posted_at,now()) where id=n.id; return jsonb_build_object('id',n.id,'journal_entry_id',existing_posting.journal_entry_id,'idempotent',true); end if;
  revenue_id := private.accounting_account_id(n.business_id, '4000'); inventory_id := private.accounting_account_id(n.business_id, '1200'); output_tax_id := private.accounting_account_id(n.business_id, '2100'); input_tax_id := private.accounting_account_id(n.business_id, '1300'); ar_id := private.accounting_account_id(n.business_id, '1100'); ap_id := private.accounting_account_id(n.business_id, '2000');
  total_tax := round(n.cgst_amount+n.sgst_amount+n.igst_amount,2); total_amount := round(n.taxable_amount+total_tax,2);
  if n.scope='sales' then
    if n.note_type='credit' then
      if n.taxable_amount>0 then lines := lines || jsonb_build_array(jsonb_build_object('account_id',revenue_id,'debit',n.taxable_amount,'credit',0,'branch_id',n.branch_id,'description','Sales credit note')); end if;
      if total_tax>0 then lines := lines || jsonb_build_array(jsonb_build_object('account_id',output_tax_id,'debit',total_tax,'credit',0,'branch_id',n.branch_id,'description','Reverse output tax')); end if;
      lines := lines || jsonb_build_array(jsonb_build_object('account_id',ar_id,'debit',0,'credit',total_amount,'branch_id',n.branch_id,'description','Customer credit note liability'));
    else
      lines := lines || jsonb_build_array(jsonb_build_object('account_id',ar_id,'debit',total_amount,'credit',0,'branch_id',n.branch_id,'description','Customer debit note')); if n.taxable_amount>0 then lines := lines || jsonb_build_array(jsonb_build_object('account_id',revenue_id,'debit',0,'credit',n.taxable_amount,'branch_id',n.branch_id,'description','Sales debit note')); end if; if total_tax>0 then lines := lines || jsonb_build_array(jsonb_build_object('account_id',output_tax_id,'debit',0,'credit',total_tax,'branch_id',n.branch_id,'description','Additional output tax')); end if;
    end if;
  else
    if n.note_type='credit' then
      lines := lines || jsonb_build_array(jsonb_build_object('account_id',ap_id,'debit',total_amount,'credit',0,'branch_id',n.branch_id,'description','Supplier credit note')); if n.taxable_amount>0 then lines := lines || jsonb_build_array(jsonb_build_object('account_id',inventory_id,'debit',0,'credit',n.taxable_amount,'branch_id',n.branch_id,'description','Reverse purchase')); end if; if total_tax>0 then lines := lines || jsonb_build_array(jsonb_build_object('account_id',input_tax_id,'debit',0,'credit',total_tax,'branch_id',n.branch_id,'description','Reverse input tax')); end if;
    else
      if n.taxable_amount>0 then lines := lines || jsonb_build_array(jsonb_build_object('account_id',inventory_id,'debit',n.taxable_amount,'credit',0,'branch_id',n.branch_id,'description','Additional purchase')); end if; if total_tax>0 then lines := lines || jsonb_build_array(jsonb_build_object('account_id',input_tax_id,'debit',total_tax,'credit',0,'branch_id',n.branch_id,'description','Additional input tax')); end if; lines := lines || jsonb_build_array(jsonb_build_object('account_id',ap_id,'debit',0,'credit',total_amount,'branch_id',n.branch_id,'description','Supplier debit note'));
    end if;
  end if;
  result := public.create_journal_entry(n.business_id,n.note_date,'Tax '||n.note_type||' note '||n.note_number,'tax_note',n.id,lines); journal_id := (result->>'id')::uuid;
  insert into public.accounting_subledger_postings(business_id,subledger_type,source_id,journal_entry_id,memo) values(n.business_id,'tax_note',n.id,journal_id,'Tax note '||n.note_number);
  update public.accounting_tax_adjustment_notes set status='posted',posted_by=auth.uid(),posted_at=now() where id=n.id;
  return jsonb_build_object('id',n.id,'journal_entry_id',journal_id);
end;
$$;

create or replace function public.create_bank_reconciliation(target_business_id uuid,target_cash_bank_account_id uuid,target_statement_start date,target_statement_end date,target_opening_balance numeric,target_closing_balance numeric,target_notes text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare reconciliation_id uuid;
begin
  if not private.has_permission(target_business_id,'accounting.manage') then raise exception 'Accounting management permission required'; end if;
  if not exists(select 1 from public.accounting_cash_bank_accounts where id=target_cash_bank_account_id and business_id=target_business_id and is_active) then raise exception 'Cash or bank account is unavailable'; end if;
  if target_statement_end<target_statement_start then raise exception 'Statement dates are invalid'; end if;
  insert into public.accounting_bank_reconciliations(business_id,cash_bank_account_id,statement_start,statement_end,opening_balance,closing_balance,notes)
  values(target_business_id,target_cash_bank_account_id,target_statement_start,target_statement_end,round(coalesce(target_opening_balance,0),2),round(target_closing_balance,2),nullif(btrim(target_notes),'')) returning id into reconciliation_id;
  return jsonb_build_object('id',reconciliation_id,'status','draft');
end;
$$;

create or replace function public.auto_reconcile_bank_reconciliation(target_reconciliation_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.accounting_bank_reconciliations%rowtype; account_id uuid; item record; total numeric(18,2); difference numeric(18,2);
begin
  select * into r from public.accounting_bank_reconciliations where id=target_reconciliation_id for update;
  if not found or not private.has_permission(r.business_id,'accounting.manage') then raise exception 'Reconciliation is not accessible'; end if;
  select ledger_account_id into account_id from public.accounting_cash_bank_accounts where id=r.cash_bank_account_id and business_id=r.business_id;
  if account_id is null then raise exception 'Bank account is not linked to a ledger account'; end if;
  delete from public.accounting_bank_reconciliation_items where reconciliation_id=r.id and business_id=r.business_id;
  for item in
    select l.id, round(l.debit-l.credit,2) as amount
    from public.accounting_journal_lines l join public.accounting_journal_entries e on e.id=l.journal_entry_id and e.business_id=l.business_id
    where l.business_id=r.business_id and l.account_id=account_id and e.status='posted' and e.entry_date between r.statement_start and r.statement_end
  loop
    if item.amount<>0 then insert into public.accounting_bank_reconciliation_items(business_id,reconciliation_id,journal_line_id,amount) values(r.business_id,r.id,item.id,item.amount) on conflict do nothing; end if;
  end loop;
  select coalesce(sum(amount),0) into total from public.accounting_bank_reconciliation_items where reconciliation_id=r.id;
  difference := round(r.closing_balance - (r.opening_balance + total),2);
  update public.accounting_bank_reconciliations set reconciled_amount=total,difference_amount=difference,status=case when difference=0 then 'completed' else 'draft' end,completed_by=case when difference=0 then auth.uid() else null end,completed_at=case when difference=0 then now() else null end where id=r.id;
  return jsonb_build_object('id',r.id,'matched_amount',total,'difference',difference,'status',case when difference=0 then 'completed' else 'draft' end);
end;
$$;

create or replace function public.reopen_bank_reconciliation(target_reconciliation_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare b uuid;
begin select business_id into b from public.accounting_bank_reconciliations where id=target_reconciliation_id; if b is null or not private.has_permission(b,'accounting.manage') then raise exception 'Reconciliation is not accessible'; end if; update public.accounting_bank_reconciliations set status='reopened',completed_by=null,completed_at=null where id=target_reconciliation_id; return jsonb_build_object('id',target_reconciliation_id,'status','reopened'); end;
$$;

revoke all on function public.post_sale_to_ledger(uuid), public.post_sale_payment_to_ledger(uuid), public.post_purchase_invoice_to_ledger(uuid), public.post_purchase_invoice_payment_to_ledger(uuid), public.post_expense_to_ledger(uuid), public.post_customer_receipt_to_ledger(uuid), public.sync_operational_ledger(uuid), public.create_tax_adjustment_note(uuid,uuid,text,text,text,numeric,numeric,numeric,numeric,text,date,uuid), public.post_tax_adjustment_note_to_ledger(uuid), public.create_bank_reconciliation(uuid,uuid,date,date,numeric,numeric,text), public.auto_reconcile_bank_reconciliation(uuid), public.reopen_bank_reconciliation(uuid) from public, anon;
grant execute on function public.post_sale_to_ledger(uuid), public.post_sale_payment_to_ledger(uuid), public.post_purchase_invoice_to_ledger(uuid), public.post_purchase_invoice_payment_to_ledger(uuid), public.post_expense_to_ledger(uuid), public.post_customer_receipt_to_ledger(uuid), public.sync_operational_ledger(uuid), public.create_tax_adjustment_note(uuid,uuid,text,text,text,numeric,numeric,numeric,numeric,text,date,uuid), public.post_tax_adjustment_note_to_ledger(uuid), public.create_bank_reconciliation(uuid,uuid,date,date,numeric,numeric,text), public.auto_reconcile_bank_reconciliation(uuid), public.reopen_bank_reconciliation(uuid) to authenticated;

commit;
