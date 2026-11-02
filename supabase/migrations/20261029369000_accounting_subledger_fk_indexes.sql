-- Foreign-key indexes for the explicit accounting bridge.
begin;

create index if not exists accounting_subledger_postings_business_fk_idx
  on public.accounting_subledger_postings(business_id);
create index if not exists accounting_subledger_postings_posted_by_idx
  on public.accounting_subledger_postings(posted_by);

create index if not exists accounting_bank_reconciliations_account_business_fk_idx
  on public.accounting_bank_reconciliations(cash_bank_account_id, business_id);
create index if not exists accounting_bank_reconciliations_created_by_idx
  on public.accounting_bank_reconciliations(created_by);
create index if not exists accounting_bank_reconciliations_completed_by_idx
  on public.accounting_bank_reconciliations(completed_by);

create index if not exists accounting_bank_reconciliation_items_business_fk_idx
  on public.accounting_bank_reconciliation_items(business_id);
create index if not exists accounting_bank_reconciliation_items_journal_line_idx
  on public.accounting_bank_reconciliation_items(journal_line_id);
create index if not exists accounting_bank_reconciliation_items_reconciliation_business_idx
  on public.accounting_bank_reconciliation_items(reconciliation_id, business_id);

create index if not exists accounting_tax_adjustment_notes_branch_business_fk_idx
  on public.accounting_tax_adjustment_notes(branch_id, business_id);
create index if not exists accounting_tax_adjustment_notes_created_by_idx
  on public.accounting_tax_adjustment_notes(created_by);
create index if not exists accounting_tax_adjustment_notes_posted_by_idx
  on public.accounting_tax_adjustment_notes(posted_by);

commit;
