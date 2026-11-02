-- Mixed-tender sales with settled cash and an outstanding balance are
-- partially paid. The sale RPC already persists exact paid_total/due_total;
-- this trigger keeps payment_status aligned without changing repayment math.

create or replace function private.mark_mixed_tender_sale_partially_paid()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  update public.sales
  set payment_status = 'partially_paid'
  where id = new.sale_id
    and business_id = new.business_id
    and status = 'completed'
    and payment_status = 'pending'
    and paid_total > 0
    and due_total > 0;

  return new;
end;
$$;

drop trigger if exists payments_mark_mixed_tender_partially_paid
on public.payments;

create trigger payments_mark_mixed_tender_partially_paid
after insert on public.payments
for each row
when (new.status = 'settled')
execute function private.mark_mixed_tender_sale_partially_paid();

revoke all on function private.mark_mixed_tender_sale_partially_paid()
from public, anon, authenticated;
