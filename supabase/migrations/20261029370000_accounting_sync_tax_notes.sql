-- Include tax adjustment notes in the explicit operational-to-GL sync.
begin;

create or replace function public.sync_operational_ledger(target_business_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  r record;
  sales_count integer := 0;
  purchase_count integer := 0;
  expense_count integer := 0;
  receipt_count integer := 0;
  tax_note_count integer := 0;
begin
  if not private.has_permission(target_business_id, 'accounting.manage') then
    raise exception 'Accounting management permission required';
  end if;
  for r in select id from public.sales where business_id = target_business_id and status = 'completed' loop
    perform public.post_sale_to_ledger(r.id);
    sales_count := sales_count + 1;
  end loop;
  for r in select id from public.purchase_invoices where business_id = target_business_id and status <> 'void' loop
    perform public.post_purchase_invoice_to_ledger(r.id);
    purchase_count := purchase_count + 1;
  end loop;
  for r in select id from public.purchase_invoice_payments where business_id = target_business_id loop
    perform public.post_purchase_invoice_payment_to_ledger(r.id);
  end loop;
  for r in select id from public.expenses where business_id = target_business_id and approval_status = 'approved' loop
    perform public.post_expense_to_ledger(r.id);
    expense_count := expense_count + 1;
  end loop;
  for r in select id from public.customer_receipts where business_id = target_business_id loop
    perform public.post_customer_receipt_to_ledger(r.id);
    receipt_count := receipt_count + 1;
  end loop;
  for r in select id from public.accounting_tax_adjustment_notes where business_id = target_business_id and status = 'posted' loop
    perform public.post_tax_adjustment_note_to_ledger(r.id);
    tax_note_count := tax_note_count + 1;
  end loop;
  return jsonb_build_object(
    'sales', sales_count,
    'purchase_invoices', purchase_count,
    'expenses', expense_count,
    'customer_receipts', receipt_count,
    'tax_notes', tax_note_count
  );
end;
$$;

revoke all on function public.sync_operational_ledger(uuid) from public, anon;
grant execute on function public.sync_operational_ledger(uuid) to authenticated;

commit;
