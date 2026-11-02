-- Cover composite expense foreign keys in the approval and attachment ledgers.
begin;
create index if not exists expense_approval_events_expense_business_fk_idx
  on public.expense_approval_events(expense_id, business_id);
create index if not exists expense_attachments_expense_business_fk_idx
  on public.expense_attachments(expense_id, business_id);
commit;
