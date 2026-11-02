-- RLS remains the row-level boundary, while table grants expose only the
-- read capability required by authenticated clients. All writes use RPCs.

revoke all on public.expense_categories, public.expenses,
  public.customer_receipts, public.customer_receipt_allocations,
  public.customer_ledger_entries from anon, authenticated;

grant select on public.expense_categories, public.expenses,
  public.customer_receipts, public.customer_receipt_allocations,
  public.customer_ledger_entries to authenticated;
