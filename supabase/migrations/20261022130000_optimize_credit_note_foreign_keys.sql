-- Cover composite tenant foreign keys in their declared column order.

drop index public.credit_notes_branch_id_idx;
create index credit_notes_branch_id_idx
  on public.credit_notes(branch_id, business_id);

drop index public.credit_notes_customer_id_idx;
create index credit_notes_customer_id_idx
  on public.credit_notes(customer_id, business_id)
  where customer_id is not null;
