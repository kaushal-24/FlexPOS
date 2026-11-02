-- Cover every accounting foreign key in constraint-column order. These
-- indexes keep parent updates/deletes and ledger joins predictable at scale.

create index if not exists expenses_branch_business_fk_idx
  on public.expenses(branch_id, business_id);
create index if not exists expenses_category_business_fk_idx
  on public.expenses(category_id, business_id);
create index if not exists expenses_reversal_business_fk_idx
  on public.expenses(reverses_expense_id, business_id)
  where reverses_expense_id is not null;

create index if not exists customer_receipts_branch_business_fk_idx
  on public.customer_receipts(branch_id, business_id);
create index if not exists customer_receipts_customer_business_fk_idx
  on public.customer_receipts(customer_id, business_id);

create index if not exists customer_receipt_allocations_business_id_idx
  on public.customer_receipt_allocations(business_id);
create index if not exists customer_receipt_allocations_receipt_business_fk_idx
  on public.customer_receipt_allocations(receipt_id, business_id);
create index if not exists customer_receipt_allocations_sale_business_fk_idx
  on public.customer_receipt_allocations(sale_id, business_id);
create index if not exists customer_receipt_allocations_payment_business_fk_idx
  on public.customer_receipt_allocations(payment_id, business_id);

create index if not exists customer_ledger_branch_business_fk_idx
  on public.customer_ledger_entries(branch_id, business_id);
create index if not exists customer_ledger_customer_business_fk_idx
  on public.customer_ledger_entries(customer_id, business_id);
create index if not exists customer_ledger_sale_business_fk_idx
  on public.customer_ledger_entries(sale_id, business_id)
  where sale_id is not null;
create index if not exists customer_ledger_payment_business_fk_idx
  on public.customer_ledger_entries(payment_id, business_id)
  where payment_id is not null;
create index if not exists customer_ledger_receipt_business_fk_idx
  on public.customer_ledger_entries(receipt_id, business_id)
  where receipt_id is not null;
create index if not exists customer_ledger_created_by_idx
  on public.customer_ledger_entries(created_by);
