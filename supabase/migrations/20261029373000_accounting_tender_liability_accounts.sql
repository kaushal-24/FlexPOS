-- Map gift-card and credit-note tenders to liability accounts when settling AR.
begin;

insert into public.accounting_accounts (business_id, code, name, account_type, is_system)
select id, '2300', 'Gift card liability', 'liability', true
from public.businesses
on conflict (business_id, code) do nothing;

create or replace function public.post_sale_payment_to_ledger(target_payment_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare payment_record public.payments%rowtype; sale_record public.sales%rowtype; existing_posting public.accounting_subledger_postings%rowtype; debit_account uuid; ar_id uuid; journal_id uuid; result jsonb;
begin
  select * into payment_record from public.payments where id=target_payment_id for update;
  if not found then raise exception 'Payment is not found'; end if;
  select * into sale_record from public.sales where id=payment_record.sale_id;
  if not found or not private.has_permission(payment_record.business_id,'accounting.manage') then raise exception 'Sale payment is not accessible for accounting posting'; end if;
  if payment_record.status <> 'settled' then raise exception 'Only settled payments can be posted'; end if;
  select * into existing_posting from public.accounting_subledger_postings where business_id=payment_record.business_id and subledger_type='sale_payment' and source_id=payment_record.id;
  if found then return jsonb_build_object('payment_id',payment_record.id,'journal_entry_id',existing_posting.journal_entry_id,'idempotent',true); end if;
  ar_id := private.accounting_account_id(payment_record.business_id,'1100');
  debit_account := case payment_record.payment_method
    when 'cash' then private.accounting_account_id(payment_record.business_id,'1000')
    when 'customer_credit' then private.accounting_account_id(payment_record.business_id,'1110')
    when 'credit_note' then private.accounting_account_id(payment_record.business_id,'2200')
    when 'gift_card' then private.accounting_account_id(payment_record.business_id,'2300')
    else private.accounting_account_id(payment_record.business_id,'1010') end;
  if ar_id is null or debit_account is null then raise exception 'Settlement accounts are missing'; end if;
  result := public.create_journal_entry(payment_record.business_id,payment_record.created_at::date,'Payment for sale '||sale_record.invoice_number,'sale_payment',payment_record.id,jsonb_build_array(jsonb_build_object('account_id',debit_account,'debit',payment_record.amount,'credit',0,'branch_id',sale_record.branch_id,'description',payment_record.payment_method||' received'),jsonb_build_object('account_id',ar_id,'debit',0,'credit',payment_record.amount,'branch_id',sale_record.branch_id,'description','Reduce accounts receivable')));
  journal_id := (result->>'id')::uuid;
  insert into public.accounting_subledger_postings(business_id,subledger_type,source_id,journal_entry_id,memo) values(payment_record.business_id,'sale_payment',payment_record.id,journal_id,'Sale payment '||payment_record.id::text);
  return jsonb_build_object('payment_id',payment_record.id,'journal_entry_id',journal_id);
end;
$$;

revoke all on function public.post_sale_payment_to_ledger(uuid) from public, anon;
grant execute on function public.post_sale_payment_to_ledger(uuid) to authenticated;

commit;
