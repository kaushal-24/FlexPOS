-- Cover the foreign keys introduced by the accounting/tax/expense vertical.
begin;

create index if not exists accounting_accounts_parent_business_fk_idx on public.accounting_accounts(parent_id, business_id);
create index if not exists accounting_cash_bank_business_fk_idx on public.accounting_cash_bank_accounts(business_id);
create index if not exists accounting_cash_bank_ledger_business_fk_idx on public.accounting_cash_bank_accounts(ledger_account_id, business_id);
create index if not exists accounting_journal_entries_created_by_idx on public.accounting_journal_entries(created_by);
create index if not exists accounting_journal_lines_business_fk_idx on public.accounting_journal_lines(business_id);
create index if not exists accounting_journal_lines_entry_business_fk_idx on public.accounting_journal_lines(journal_entry_id, business_id);
create index if not exists accounting_journal_lines_branch_business_fk_idx on public.accounting_journal_lines(branch_id, business_id);
create index if not exists accounting_periods_closed_by_idx on public.accounting_periods(closed_by);
create index if not exists accounting_recurring_branch_business_fk_idx on public.accounting_recurring_expenses(branch_id, business_id);
create index if not exists accounting_recurring_category_business_fk_idx on public.accounting_recurring_expenses(category_id, business_id);
create index if not exists accounting_recurring_created_by_idx on public.accounting_recurring_expenses(created_by);
create index if not exists accounting_tax_profiles_branch_business_fk_idx on public.accounting_tax_profiles(branch_id, business_id);
create index if not exists expense_approval_events_business_fk_idx on public.expense_approval_events(business_id);
create index if not exists expense_approval_events_created_by_idx on public.expense_approval_events(created_by);
create index if not exists expense_attachments_created_by_idx on public.expense_attachments(created_by);
create index if not exists expenses_approved_by_idx on public.expenses(approved_by);

commit;
