-- UPI-only cashier confirmation for POS checkout.
-- Apply only to flexpos-2 (gpbsblokhpydtpgxpwrg).

insert into public.permissions (code, category, description)
values (
  'payments.confirm_upi',
  'Sales',
  'Confirm or fail a UPI payment during POS checkout'
)
on conflict (code) do update set
  category = excluded.category,
  description = excluded.description;

insert into public.role_permissions (role_id, permission_code)
select r.id, 'payments.confirm_upi'
from public.roles r
where r.name in ('Owner', 'Administrator', 'Branch Manager', 'Cashier')
on conflict do nothing;

create or replace function public.confirm_upi_payment(
  target_payment_id uuid,
  operation_id uuid,
  verification_status text,
  verification_reference text,
  confirmation_note text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  payment_record public.payments%rowtype;
  sale_record public.sales%rowtype;
  normalized_status text := lower(btrim(coalesce(verification_status, '')));
  normalized_reference text := btrim(coalesce(verification_reference, ''));
  normalized_note text := btrim(coalesce(confirmation_note, ''));
  existing_result jsonb;
  inserted_count integer;
  totals jsonb;
  response_result jsonb;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if normalized_status not in ('settled', 'failed') then
    raise exception 'UPI status must be settled or failed';
  end if;
  if char_length(normalized_reference) not between 4 and 200 then
    raise exception 'UPI reference must be between 4 and 200 characters';
  end if;
  if char_length(normalized_note) not between 8 and 1000 then
    raise exception 'UPI confirmation note must be between 8 and 1000 characters';
  end if;

  select * into payment_record
  from public.payments payment
  where payment.id = target_payment_id;
  if not found then raise exception 'Payment not found'; end if;

  select * into sale_record
  from public.sales sale
  where sale.id = payment_record.sale_id
    and sale.business_id = payment_record.business_id
  for update;
  if not found then raise exception 'Sale not found'; end if;
  if sale_record.status <> 'completed' then
    raise exception 'Payments cannot be confirmed after a sale return or cancellation';
  end if;
  if not private.has_permission(payment_record.business_id, 'payments.confirm_upi') then
    raise exception 'UPI confirmation permission required';
  end if;
  if not private.has_branch_access(sale_record.branch_id) then
    raise exception 'Branch is not accessible';
  end if;
  if payment_record.payment_method <> 'upi' then
    raise exception 'Only UPI payments can be confirmed with this action';
  end if;

  select record.result into existing_result
  from public.idempotency_records record
  where record.business_id = payment_record.business_id
    and record.operation_id = confirm_upi_payment.operation_id
    and record.operation_type = 'payment.upi_confirm';
  if existing_result is not null and existing_result <> '{}'::jsonb then
    if existing_result ->> 'payment_id' <> target_payment_id::text then
      raise exception 'Operation ID is already linked to another payment';
    end if;
    return existing_result;
  end if;

  select * into payment_record
  from public.payments payment
  where payment.id = target_payment_id
    and payment.business_id = sale_record.business_id
  for update;
  if payment_record.status <> 'pending' then
    raise exception 'Only pending UPI payments can be confirmed';
  end if;

  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (
    payment_record.business_id, operation_id, 'payment.upi_confirm', caller_id
  )
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select record.result into existing_result
    from public.idempotency_records record
    where record.business_id = payment_record.business_id
      and record.operation_id = confirm_upi_payment.operation_id
      and record.operation_type = 'payment.upi_confirm';
    if existing_result is not null and existing_result <> '{}'::jsonb then
      return existing_result;
    end if;
    raise exception 'UPI confirmation is already in progress';
  end if;

  update public.payments
  set status = normalized_status,
      reference = coalesce(reference, normalized_reference),
      settled_at = case when normalized_status = 'settled' then now() else null end,
      provider_payload = provider_payload || jsonb_build_object(
        'last_verification_source', 'pos_upi_confirmation',
        'last_verification_status', normalized_status
      )
  where id = payment_record.id
    and business_id = payment_record.business_id;

  insert into public.payment_verification_events (
    business_id, payment_id, source, provider, provider_payment_reference,
    reported_status, outcome, observed_amount, currency_code, evidence_note,
    operation_id, actor_user_id, applied
  ) values (
    payment_record.business_id, payment_record.id, 'manual',
    'upi_manual', normalized_reference, normalized_status, normalized_status,
    payment_record.amount, sale_record.currency_code, normalized_note,
    operation_id, caller_id, true
  );

  totals := private.refresh_sale_payment_totals(
    sale_record.id, sale_record.business_id
  );
  response_result := totals || jsonb_build_object(
    'payment_id', payment_record.id,
    'payment_status', normalized_status,
    'verification_source', 'pos_upi_confirmation'
  );

  update public.idempotency_records record
  set result = response_result
  where record.business_id = payment_record.business_id
    and record.operation_id = confirm_upi_payment.operation_id
    and record.operation_type = 'payment.upi_confirm';

  perform private.write_tenant_audit(
    payment_record.business_id,
    'payment.upi_confirmed',
    'payment',
    payment_record.id::text,
    jsonb_build_object(
      'sale_id', sale_record.id,
      'status', normalized_status,
      'reference', normalized_reference,
      'note', normalized_note,
      'source', 'pos_upi_confirmation'
    )
  );
  return response_result;
end;
$$;

revoke all on function public.confirm_upi_payment(uuid, uuid, text, text, text)
from public, anon, authenticated, service_role;
grant execute on function public.confirm_upi_payment(uuid, uuid, text, text, text)
to authenticated;
