-- Rename the procedural parameter so it cannot conflict with the document
-- column when the redemption statement is planned.

drop function public.complete_sale_with_credit_note(
  uuid, uuid, uuid, uuid, uuid, uuid, jsonb, text, numeric, numeric, text
);

create or replace function public.complete_sale_with_credit_note(
  target_business_id uuid,
  target_branch_id uuid,
  target_register_id uuid,
  target_shift_id uuid,
  target_customer_id uuid,
  operation_id uuid,
  line_items jsonb,
  target_credit_note_number text,
  credit_note_amount numeric,
  order_discount numeric default 0,
  sale_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  note_record public.credit_notes%rowtype;
  redeemed_total numeric(18,2);
  available_balance numeric(18,2);
  redemption_amount numeric(18,2) := round(credit_note_amount, 2);
  nested_result jsonb;
  existing_result jsonb;
  inserted_count integer;
  redeemed_sale_id uuid;
  payment_id uuid;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if nullif(btrim(target_credit_note_number), '') is null then
    raise exception 'Credit note number is required';
  end if;
  if redemption_amount is null or redemption_amount <= 0 then
    raise exception 'Credit note redemption amount must be greater than zero';
  end if;
  if not private.has_permission(target_business_id, 'sales.create') then
    raise exception 'You do not have permission to create sales';
  end if;
  if not private.has_branch_access(target_branch_id) then
    raise exception 'Branch is not accessible';
  end if;

  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (
    target_business_id, operation_id, 'sale.credit_note_redeem', caller_id
  ) on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select result into existing_result
    from public.idempotency_records ir
    where ir.business_id = target_business_id
      and ir.operation_id = complete_sale_with_credit_note.operation_id
      and ir.operation_type = 'sale.credit_note_redeem';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Credit-note redemption is already in progress';
  end if;

  select * into note_record
  from public.credit_notes cn
  where cn.business_id = target_business_id
    and upper(cn.credit_note_number) = upper(btrim(target_credit_note_number))
  for update;
  if not found then raise exception 'Credit note not found'; end if;
  if note_record.expires_at <= now() then
    raise exception 'Credit note has expired';
  end if;
  if note_record.currency_code <> (
    select b.currency_code from public.businesses b
    where b.id = target_business_id
  ) then
    raise exception 'Credit note currency does not match the sale';
  end if;
  if note_record.customer_id is not null
     and target_customer_id is distinct from note_record.customer_id then
    raise exception 'Credit note belongs to a different customer';
  end if;

  select coalesce(sum(cnr.amount), 0)
  into redeemed_total
  from public.credit_note_redemptions cnr
  where cnr.credit_note_id = note_record.id;
  available_balance := round(note_record.issued_amount - redeemed_total, 2);
  if redemption_amount > available_balance then
    raise exception 'Credit note balance is insufficient';
  end if;

  nested_result := public.complete_sale(
    target_business_id,
    target_branch_id,
    target_register_id,
    target_shift_id,
    target_customer_id,
    gen_random_uuid(),
    line_items,
    jsonb_build_array(jsonb_build_object(
      'payment_method', 'gift_card',
      'amount', redemption_amount,
      'reference', note_record.credit_note_number,
      'provider', 'credit_note'
    )),
    order_discount,
    sale_notes
  );
  redeemed_sale_id := (nested_result ->> 'sale_id')::uuid;

  select p.id into strict payment_id
  from public.payments p
  where p.sale_id = redeemed_sale_id
    and p.business_id = target_business_id
    and p.provider = 'credit_note'
  for update;

  update public.payments
  set payment_method = 'credit_note', status = 'settled', settled_at = now()
  where id = payment_id;

  update public.sales
  set payment_status = 'paid', paid_total = grand_total, due_total = 0
  where id = redeemed_sale_id;

  insert into public.credit_note_redemptions (
    business_id, credit_note_id, sale_id, payment_id, amount, redeemed_by
  ) values (
    target_business_id, note_record.id, redeemed_sale_id, payment_id,
    redemption_amount, caller_id
  );

  existing_result := nested_result || jsonb_build_object(
    'payment_status', 'paid',
    'credit_note_id', note_record.id,
    'credit_note_number', note_record.credit_note_number,
    'credit_note_redeemed', redemption_amount,
    'credit_note_balance', round(available_balance - redemption_amount, 2)
  );
  update public.idempotency_records ir set result = existing_result
  where ir.business_id = target_business_id
    and ir.operation_id = complete_sale_with_credit_note.operation_id
    and ir.operation_type = 'sale.credit_note_redeem';
  perform private.write_tenant_audit(
    target_business_id, 'credit_note.redeemed', 'credit_note',
    note_record.id::text,
    existing_result || jsonb_build_object('sale_id', redeemed_sale_id)
  );
  return existing_result;
end;
$$;

revoke all on function public.complete_sale_with_credit_note(
  uuid, uuid, uuid, uuid, uuid, uuid, jsonb, text, numeric, numeric, text
) from public, anon, authenticated;
grant execute on function public.complete_sale_with_credit_note(
  uuid, uuid, uuid, uuid, uuid, uuid, jsonb, text, numeric, numeric, text
) to authenticated;
