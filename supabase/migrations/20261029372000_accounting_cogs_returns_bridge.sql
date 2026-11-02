-- Finish the operational-to-GL bridge with inventory COGS and sales returns.
begin;

alter table public.accounting_subledger_postings
  drop constraint if exists accounting_subledger_postings_subledger_type_check;
alter table public.accounting_subledger_postings
  add constraint accounting_subledger_postings_subledger_type_check
  check (subledger_type in ('ar','ap','expense','tax_note','sale','sale_payment','purchase_invoice','purchase_payment','customer_receipt','sale_return','sale_refund'));

create or replace function public.post_sale_to_ledger(target_sale_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  sale_record public.sales%rowtype;
  existing_posting public.accounting_subledger_postings%rowtype;
  ar_id uuid; revenue_id uuid; gst_id uuid; cogs_id uuid; inventory_id uuid;
  journal_id uuid; lines jsonb; base_amount numeric(18,2); cogs_amount numeric(18,2);
  payment_record record; payment_count integer := 0; result jsonb;
begin
  select * into sale_record from public.sales where id = target_sale_id for update;
  if not found or not private.has_permission(sale_record.business_id, 'accounting.manage') then raise exception 'Sale is not accessible for accounting posting'; end if;
  if sale_record.status <> 'completed' then raise exception 'Only completed sales can be posted'; end if;
  select * into existing_posting from public.accounting_subledger_postings where business_id = sale_record.business_id and subledger_type = 'sale' and source_id = sale_record.id;
  if found then return jsonb_build_object('sale_id', sale_record.id, 'journal_entry_id', existing_posting.journal_entry_id, 'idempotent', true); end if;
  ar_id := private.accounting_account_id(sale_record.business_id, '1100'); revenue_id := private.accounting_account_id(sale_record.business_id, '4000'); gst_id := private.accounting_account_id(sale_record.business_id, '2100'); cogs_id := private.accounting_account_id(sale_record.business_id, '5000'); inventory_id := private.accounting_account_id(sale_record.business_id, '1200');
  if ar_id is null or revenue_id is null or gst_id is null or cogs_id is null or inventory_id is null then raise exception 'Standard accounting accounts are missing'; end if;
  select coalesce(sum(round(quantity * unit_cost, 2)), 0) into cogs_amount from public.sale_items where business_id = sale_record.business_id and sale_id = sale_record.id;
  base_amount := round(sale_record.grand_total - sale_record.tax_total, 2);
  lines := jsonb_build_array(jsonb_build_object('account_id', ar_id, 'debit', sale_record.grand_total, 'credit', 0, 'branch_id', sale_record.branch_id, 'description', 'Accounts receivable for ' || sale_record.invoice_number));
  if base_amount > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account_id', revenue_id, 'debit', 0, 'credit', base_amount, 'branch_id', sale_record.branch_id, 'description', 'Sales revenue')); end if;
  if sale_record.tax_total > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account_id', gst_id, 'debit', 0, 'credit', sale_record.tax_total, 'branch_id', sale_record.branch_id, 'description', 'GST collected')); end if;
  if cogs_amount > 0 then
    lines := lines || jsonb_build_array(jsonb_build_object('account_id', cogs_id, 'debit', cogs_amount, 'credit', 0, 'branch_id', sale_record.branch_id, 'description', 'Cost of goods sold'));
    lines := lines || jsonb_build_array(jsonb_build_object('account_id', inventory_id, 'debit', 0, 'credit', cogs_amount, 'branch_id', sale_record.branch_id, 'description', 'Inventory relieved'));
  end if;
  result := public.create_journal_entry(sale_record.business_id, sale_record.completed_at::date, 'Sale ' || sale_record.invoice_number, 'sale', sale_record.id, lines);
  journal_id := (result->>'id')::uuid;
  insert into public.accounting_subledger_postings(business_id, subledger_type, source_id, journal_entry_id, memo) values (sale_record.business_id, 'sale', sale_record.id, journal_id, 'Sale invoice ' || sale_record.invoice_number);
  for payment_record in select id from public.payments where business_id = sale_record.business_id and sale_id = sale_record.id and status = 'settled' loop
    perform public.post_sale_payment_to_ledger(payment_record.id); payment_count := payment_count + 1;
  end loop;
  perform private.write_tenant_audit(sale_record.business_id, 'accounting.sale_posted', 'sale', sale_record.id::text, jsonb_build_object('journal_entry_id', journal_id, 'payments_posted', payment_count, 'cogs', cogs_amount));
  return jsonb_build_object('sale_id', sale_record.id, 'journal_entry_id', journal_id, 'payments_posted', payment_count, 'cogs', cogs_amount);
end;
$$;

create or replace function public.post_sale_return_to_ledger(target_return_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.sale_returns%rowtype; existing_posting public.accounting_subledger_postings%rowtype; revenue_id uuid; gst_id uuid; ar_id uuid; cogs_id uuid; inventory_id uuid; base_amount numeric(18,2); journal_id uuid; lines jsonb := '[]'::jsonb; result jsonb;
begin
  select * into r from public.sale_returns where id=target_return_id for update;
  if not found or not private.has_permission(r.business_id,'accounting.manage') then raise exception 'Sale return is not accessible for accounting posting'; end if;
  select * into existing_posting from public.accounting_subledger_postings where business_id=r.business_id and subledger_type='sale_return' and source_id=r.id;
  if found then return jsonb_build_object('return_id',r.id,'journal_entry_id',existing_posting.journal_entry_id,'idempotent',true); end if;
  revenue_id := private.accounting_account_id(r.business_id,'4000'); gst_id := private.accounting_account_id(r.business_id,'2100'); ar_id := private.accounting_account_id(r.business_id,'1100'); cogs_id := private.accounting_account_id(r.business_id,'5000'); inventory_id := private.accounting_account_id(r.business_id,'1200');
  if revenue_id is null or gst_id is null or ar_id is null or cogs_id is null or inventory_id is null then raise exception 'Return accounting accounts are missing'; end if;
  base_amount := round(r.subtotal-r.discount_total,2);
  if base_amount>0 then lines := lines || jsonb_build_array(jsonb_build_object('account_id',revenue_id,'debit',base_amount,'credit',0,'branch_id',r.branch_id,'description','Sales return revenue reversal')); end if;
  if r.tax_total>0 then lines := lines || jsonb_build_array(jsonb_build_object('account_id',gst_id,'debit',r.tax_total,'credit',0,'branch_id',r.branch_id,'description','Sales return output-tax reversal')); end if;
  lines := lines || jsonb_build_array(jsonb_build_object('account_id',ar_id,'debit',0,'credit',r.refund_total,'branch_id',r.branch_id,'description','Customer refund receivable'));
  if r.cost_total>0 then lines := lines || jsonb_build_array(jsonb_build_object('account_id',inventory_id,'debit',r.cost_total,'credit',0,'branch_id',r.branch_id,'description','Returned inventory')); lines := lines || jsonb_build_array(jsonb_build_object('account_id',cogs_id,'debit',0,'credit',r.cost_total,'branch_id',r.branch_id,'description','Reverse cost of goods sold')); end if;
  result := public.create_journal_entry(r.business_id,r.returned_at::date,'Sale return '||r.return_number,'sale_return',r.id,lines); journal_id := (result->>'id')::uuid;
  insert into public.accounting_subledger_postings(business_id,subledger_type,source_id,journal_entry_id,memo) values(r.business_id,'sale_return',r.id,journal_id,'Sale return '||r.return_number);
  return jsonb_build_object('return_id',r.id,'journal_entry_id',journal_id);
end;
$$;

create or replace function public.post_sale_refund_to_ledger(target_refund_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare f public.sale_refunds%rowtype; existing_posting public.accounting_subledger_postings%rowtype; cash_id uuid; ar_id uuid; journal_id uuid; result jsonb;
begin
  select * into f from public.sale_refunds where id=target_refund_id for update;
  if not found or not private.has_permission(f.business_id,'accounting.manage') then raise exception 'Sale refund is not accessible for accounting posting'; end if;
  if f.status <> 'settled' then raise exception 'Only settled refunds can be posted'; end if;
  select * into existing_posting from public.accounting_subledger_postings where business_id=f.business_id and subledger_type='sale_refund' and source_id=f.id;
  if found then return jsonb_build_object('refund_id',f.id,'journal_entry_id',existing_posting.journal_entry_id,'idempotent',true); end if;
  cash_id := case when f.payment_method='cash' then private.accounting_account_id(f.business_id,'1000') else private.accounting_account_id(f.business_id,'1010') end; ar_id := private.accounting_account_id(f.business_id,'1100');
  if cash_id is null or ar_id is null then raise exception 'Refund accounting accounts are missing'; end if;
  result := public.create_journal_entry(f.business_id,f.processed_at::date,'Sale refund '||f.id::text,'sale_refund',f.id,jsonb_build_array(jsonb_build_object('account_id',ar_id,'debit',f.amount,'credit',0,'description','Refund receivable settled'),jsonb_build_object('account_id',cash_id,'debit',0,'credit',f.amount,'description',f.payment_method||' refund'))); journal_id := (result->>'id')::uuid;
  insert into public.accounting_subledger_postings(business_id,subledger_type,source_id,journal_entry_id,memo) values(f.business_id,'sale_refund',f.id,journal_id,'Sale refund '||f.id::text);
  return jsonb_build_object('refund_id',f.id,'journal_entry_id',journal_id);
end;
$$;

create or replace function public.sync_operational_ledger(target_business_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r record; sales_count integer:=0; purchase_count integer:=0; expense_count integer:=0; receipt_count integer:=0; tax_note_count integer:=0; return_count integer:=0; refund_count integer:=0;
begin
  if not private.has_permission(target_business_id,'accounting.manage') then raise exception 'Accounting management permission required'; end if;
  for r in select id from public.sales where business_id=target_business_id and status='completed' loop perform public.post_sale_to_ledger(r.id); sales_count:=sales_count+1; end loop;
  for r in select id from public.purchase_invoices where business_id=target_business_id and status<>'void' loop perform public.post_purchase_invoice_to_ledger(r.id); purchase_count:=purchase_count+1; end loop;
  for r in select id from public.purchase_invoice_payments where business_id=target_business_id loop perform public.post_purchase_invoice_payment_to_ledger(r.id); end loop;
  for r in select id from public.expenses where business_id=target_business_id and approval_status='approved' loop perform public.post_expense_to_ledger(r.id); expense_count:=expense_count+1; end loop;
  for r in select id from public.customer_receipts where business_id=target_business_id loop perform public.post_customer_receipt_to_ledger(r.id); receipt_count:=receipt_count+1; end loop;
  for r in select id from public.accounting_tax_adjustment_notes where business_id=target_business_id and status='posted' loop perform public.post_tax_adjustment_note_to_ledger(r.id); tax_note_count:=tax_note_count+1; end loop;
  for r in select id from public.sale_returns where business_id=target_business_id and status='completed' loop perform public.post_sale_return_to_ledger(r.id); return_count:=return_count+1; end loop;
  for r in select id from public.sale_refunds where business_id=target_business_id and status='settled' loop perform public.post_sale_refund_to_ledger(r.id); refund_count:=refund_count+1; end loop;
  return jsonb_build_object('sales',sales_count,'purchase_invoices',purchase_count,'expenses',expense_count,'customer_receipts',receipt_count,'tax_notes',tax_note_count,'sale_returns',return_count,'sale_refunds',refund_count);
end;
$$;

revoke all on function public.post_sale_to_ledger(uuid), public.post_sale_return_to_ledger(uuid), public.post_sale_refund_to_ledger(uuid), public.sync_operational_ledger(uuid) from public, anon;
grant execute on function public.post_sale_to_ledger(uuid), public.post_sale_return_to_ledger(uuid), public.post_sale_refund_to_ledger(uuid), public.sync_operational_ledger(uuid) to authenticated;

commit;
