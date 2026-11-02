-- FlexPOS payment verification foundation: immutable verification events,
-- privileged manual reconciliation, and a service-only provider intake RPC.
-- Apply only to project gpbsblokhpydtpgxpwrg.

insert into public.permissions (code, category, description) values
  ('payments.reconcile', 'Sales', 'Verify and reconcile pending external payments')
on conflict (code) do update set
  category = excluded.category,
  description = excluded.description;

insert into public.role_permissions (role_id, permission_code)
select r.id, 'payments.reconcile'
from public.roles r
where r.name in ('Owner', 'Administrator')
on conflict do nothing;

create table public.payment_verification_events (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  payment_id uuid not null,
  source text not null check (source in ('provider', 'manual')),
  provider text not null check (
    provider ~ '^[a-z0-9][a-z0-9_-]{1,49}$'
  ),
  provider_event_id text,
  provider_payment_reference text not null check (
    char_length(btrim(provider_payment_reference)) between 4 and 200
  ),
  reported_status text not null check (
    reported_status in ('pending', 'settled', 'failed')
  ),
  outcome text not null check (
    outcome in ('pending', 'settled', 'failed', 'ignored')
  ),
  observed_amount numeric(18,2) not null check (observed_amount > 0),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  payload_sha256 text check (
    payload_sha256 is null or payload_sha256 ~ '^[0-9a-f]{64}$'
  ),
  evidence_note text,
  operation_id uuid,
  actor_user_id uuid references auth.users(id) on delete restrict,
  applied boolean not null default false,
  created_at timestamptz not null default now(),
  unique (id, business_id),
  constraint payment_verification_events_payment_fkey
    foreign key (payment_id, business_id)
    references public.payments(id, business_id) on delete restrict,
  check (
    (source = 'provider'
      and provider_event_id is not null
      and char_length(btrim(provider_event_id)) between 4 and 200
      and payload_sha256 is not null
      and operation_id is null
      and actor_user_id is null)
    or
    (source = 'manual'
      and provider_event_id is null
      and payload_sha256 is null
      and operation_id is not null
      and actor_user_id is not null
      and evidence_note is not null
      and char_length(btrim(evidence_note)) between 8 and 1000)
  )
);

create unique index payment_verification_provider_event_uidx
  on public.payment_verification_events(provider, provider_event_id)
  where source = 'provider';
create unique index payment_verification_operation_uidx
  on public.payment_verification_events(business_id, operation_id)
  where operation_id is not null;
create index payment_verification_payment_business_idx
  on public.payment_verification_events(payment_id, business_id);
create index payment_verification_business_created_idx
  on public.payment_verification_events(business_id, created_at desc);
create index payment_verification_actor_idx
  on public.payment_verification_events(actor_user_id)
  where actor_user_id is not null;

create trigger payment_verification_events_immutable
before update or delete on public.payment_verification_events
for each row execute function private.prevent_immutable_change();

alter table public.payment_verification_events enable row level security;

create policy payment_verification_events_select
on public.payment_verification_events
for select to authenticated
using (
  exists (
    select 1
    from public.payments payment
    join public.sales sale
      on sale.id = payment.sale_id
     and sale.business_id = payment.business_id
    where payment.id = payment_verification_events.payment_id
      and payment.business_id = payment_verification_events.business_id
      and (select private.has_permission(sale.business_id, 'sales.view'))
      and (select private.has_branch_access(sale.branch_id))
  )
);

revoke all on public.payment_verification_events
from public, anon, authenticated, service_role;
grant select on public.payment_verification_events to authenticated;

create or replace function private.refresh_sale_payment_totals(
  target_sale_id uuid,
  target_business_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  sale_record public.sales%rowtype;
  settled_total numeric(18,2);
  pending_exists boolean;
  next_status text;
begin
  select * into sale_record
  from public.sales sale
  where sale.id = target_sale_id
    and sale.business_id = target_business_id
  for update;

  if not found then raise exception 'Sale not found'; end if;
  if sale_record.status <> 'completed' then
    raise exception 'Payments cannot be reconciled after a sale return or cancellation';
  end if;

  select
    round(coalesce(sum(payment.amount) filter (
      where payment.status = 'settled'
    ), 0), 2),
    coalesce(bool_or(payment.status = 'pending'), false)
  into settled_total, pending_exists
  from public.payments payment
  where payment.sale_id = target_sale_id
    and payment.business_id = target_business_id;

  settled_total := least(settled_total, sale_record.grand_total);
  next_status := case
    when settled_total >= sale_record.grand_total then 'paid'
    when settled_total > 0 then 'partially_paid'
    when pending_exists then 'pending'
    else 'unpaid'
  end;

  update public.sales
  set paid_total = settled_total,
      due_total = greatest(grand_total - settled_total, 0),
      payment_status = next_status
  where id = target_sale_id
    and business_id = target_business_id;

  return jsonb_build_object(
    'sale_id', target_sale_id,
    'payment_status', next_status,
    'paid_total', settled_total,
    'due_total', greatest(sale_record.grand_total - settled_total, 0)
  );
end;
$$;

revoke all on function private.refresh_sale_payment_totals(uuid, uuid)
from public, anon, authenticated, service_role;

create or replace function public.reconcile_payment(
  target_payment_id uuid,
  operation_id uuid,
  verification_status text,
  verification_reference text,
  reconciliation_note text
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
  normalized_note text := btrim(coalesce(reconciliation_note, ''));
  existing_result jsonb;
  inserted_count integer;
  totals jsonb;
  response_result jsonb;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if normalized_status not in ('settled', 'failed') then
    raise exception 'Manual verification status must be settled or failed';
  end if;
  if char_length(normalized_reference) not between 4 and 200 then
    raise exception 'Verification reference must be between 4 and 200 characters';
  end if;
  if char_length(normalized_note) not between 8 and 1000 then
    raise exception 'Reconciliation note must be between 8 and 1000 characters';
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
    raise exception 'Payments cannot be reconciled after a sale return or cancellation';
  end if;
  if not private.has_permission(payment_record.business_id, 'payments.reconcile') then
    raise exception 'Payment reconciliation permission required';
  end if;
  if not private.has_branch_access(sale_record.branch_id) then
    raise exception 'Branch is not accessible';
  end if;

  select * into payment_record
  from public.payments payment
  where payment.id = target_payment_id
    and payment.business_id = sale_record.business_id
  for update;

  select record.result into existing_result
  from public.idempotency_records record
  where record.business_id = payment_record.business_id
    and record.operation_id = reconcile_payment.operation_id
    and record.operation_type = 'payment.manual_reconcile';
  if existing_result <> '{}'::jsonb then
    if existing_result ->> 'payment_id' <> target_payment_id::text then
      raise exception 'Operation ID is already linked to another payment';
    end if;
    return existing_result;
  end if;

  if payment_record.payment_method not in ('upi', 'card', 'bank_transfer', 'wallet') then
    raise exception 'Only external electronic payments can be reconciled';
  end if;
  if payment_record.status <> 'pending' then
    raise exception 'Only pending payments can be manually reconciled';
  end if;

  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (
    payment_record.business_id, operation_id, 'payment.manual_reconcile', caller_id
  )
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select record.result into existing_result
    from public.idempotency_records record
    where record.business_id = payment_record.business_id
      and record.operation_id = reconcile_payment.operation_id
      and record.operation_type = 'payment.manual_reconcile';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Payment reconciliation is already in progress';
  end if;

  update public.payments
  set status = normalized_status,
      reference = coalesce(reference, normalized_reference),
      settled_at = case when normalized_status = 'settled' then now() else null end,
      provider_payload = provider_payload || jsonb_build_object(
        'last_verification_source', 'manual',
        'last_verification_status', normalized_status
      )
  where id = payment_record.id;

  insert into public.payment_verification_events (
    business_id, payment_id, source, provider, provider_payment_reference,
    reported_status, outcome, observed_amount, currency_code, evidence_note,
    operation_id, actor_user_id, applied
  ) values (
    payment_record.business_id, payment_record.id, 'manual',
    'manual',
    normalized_reference, normalized_status, normalized_status,
    payment_record.amount, sale_record.currency_code, normalized_note,
    operation_id, caller_id, true
  );

  totals := private.refresh_sale_payment_totals(
    sale_record.id, sale_record.business_id
  );
  response_result := totals || jsonb_build_object(
    'payment_id', payment_record.id,
    'payment_status', normalized_status,
    'verification_source', 'manual'
  );

  update public.idempotency_records record
  set result = response_result
  where record.business_id = payment_record.business_id
    and record.operation_id = reconcile_payment.operation_id
    and record.operation_type = 'payment.manual_reconcile';

  perform private.write_tenant_audit(
    payment_record.business_id,
    'payment.reconciled',
    'payment',
    payment_record.id::text,
    jsonb_build_object(
      'sale_id', sale_record.id,
      'status', normalized_status,
      'reference', normalized_reference,
      'note', normalized_note,
      'source', 'manual'
    )
  );
  return response_result;
end;
$$;

revoke all on function public.reconcile_payment(uuid, uuid, text, text, text)
from public, anon, authenticated, service_role;
grant execute on function public.reconcile_payment(uuid, uuid, text, text, text)
to authenticated;

create or replace function public.record_provider_payment_verification(
  target_payment_id uuid,
  provider_name text,
  provider_event_id text,
  provider_payment_reference text,
  provider_status text,
  provider_amount numeric,
  provider_currency_code text,
  payload_sha256 text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_provider text := lower(btrim(coalesce(provider_name, '')));
  normalized_event_id text := btrim(coalesce(provider_event_id, ''));
  normalized_reference text := btrim(coalesce(provider_payment_reference, ''));
  normalized_status text := lower(btrim(coalesce(provider_status, '')));
  normalized_currency text := upper(btrim(coalesce(provider_currency_code, '')));
  normalized_hash text := lower(btrim(coalesce(payload_sha256, '')));
  payment_record public.payments%rowtype;
  sale_record public.sales%rowtype;
  existing_event public.payment_verification_events%rowtype;
  applied_event boolean := false;
  event_outcome text;
  totals jsonb;
begin
  if normalized_provider !~ '^[a-z0-9][a-z0-9_-]{1,49}$' then
    raise exception 'Invalid provider name';
  end if;
  if char_length(normalized_event_id) not between 4 and 200 then
    raise exception 'Provider event ID must be between 4 and 200 characters';
  end if;
  if char_length(normalized_reference) not between 4 and 200 then
    raise exception 'Provider payment reference must be between 4 and 200 characters';
  end if;
  if normalized_status not in ('pending', 'settled', 'failed') then
    raise exception 'Unsupported provider payment status';
  end if;
  if normalized_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Payload SHA-256 digest is required';
  end if;

  select * into existing_event
  from public.payment_verification_events event
  where event.provider = normalized_provider
    and event.provider_event_id = normalized_event_id;
  if found then
    if existing_event.payment_id <> target_payment_id then
      raise exception 'Provider event is already linked to another payment';
    end if;
    return jsonb_build_object(
      'payment_id', existing_event.payment_id,
      'provider_event_id', existing_event.provider_event_id,
      'outcome', existing_event.outcome,
      'applied', existing_event.applied,
      'duplicate', true
    );
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
    raise exception 'Payments cannot be reconciled after a sale return or cancellation';
  end if;

  select * into payment_record
  from public.payments payment
  where payment.id = target_payment_id
    and payment.business_id = sale_record.business_id
  for update;

  select * into existing_event
  from public.payment_verification_events event
  where event.provider = normalized_provider
    and event.provider_event_id = normalized_event_id;
  if found then
    if existing_event.payment_id <> target_payment_id then
      raise exception 'Provider event is already linked to another payment';
    end if;
    return jsonb_build_object(
      'payment_id', existing_event.payment_id,
      'provider_event_id', existing_event.provider_event_id,
      'outcome', existing_event.outcome,
      'applied', existing_event.applied,
      'duplicate', true
    );
  end if;

  if payment_record.payment_method not in ('upi', 'card', 'bank_transfer', 'wallet') then
    raise exception 'Only external electronic payments accept provider verification';
  end if;
  if payment_record.provider is not null
     and lower(payment_record.provider) <> normalized_provider then
    raise exception 'Provider does not match the recorded payment';
  end if;
  if provider_amount is null
     or round(provider_amount, 2) <> payment_record.amount then
    raise exception 'Provider amount does not match the recorded payment';
  end if;
  if normalized_currency <> sale_record.currency_code then
    raise exception 'Provider currency does not match the sale currency';
  end if;

  event_outcome := normalized_status;
  if normalized_status = 'settled'
     and payment_record.status in ('pending', 'failed') then
    update public.payments
    set status = 'settled',
        provider = normalized_provider,
        reference = coalesce(reference, normalized_reference),
        settled_at = now(),
        provider_payload = provider_payload || jsonb_build_object(
          'last_verification_event_id', normalized_event_id,
          'last_verification_status', normalized_status,
          'payload_sha256', normalized_hash
        )
    where id = payment_record.id;
    applied_event := true;
  elsif normalized_status = 'failed' and payment_record.status = 'pending' then
    update public.payments
    set status = 'failed',
        provider = normalized_provider,
        reference = coalesce(reference, normalized_reference),
        settled_at = null,
        provider_payload = provider_payload || jsonb_build_object(
          'last_verification_event_id', normalized_event_id,
          'last_verification_status', normalized_status,
          'payload_sha256', normalized_hash
        )
    where id = payment_record.id;
    applied_event := true;
  elsif normalized_status = 'pending' and payment_record.status = 'pending' then
    update public.payments
    set provider = normalized_provider,
        reference = coalesce(reference, normalized_reference),
        provider_payload = provider_payload || jsonb_build_object(
          'last_verification_event_id', normalized_event_id,
          'last_verification_status', normalized_status,
          'payload_sha256', normalized_hash
        )
    where id = payment_record.id;
  else
    event_outcome := 'ignored';
  end if;

  insert into public.payment_verification_events (
    business_id, payment_id, source, provider, provider_event_id,
    provider_payment_reference, reported_status, outcome, observed_amount,
    currency_code, payload_sha256, applied
  ) values (
    payment_record.business_id, payment_record.id, 'provider',
    normalized_provider, normalized_event_id, normalized_reference,
    normalized_status, event_outcome, payment_record.amount,
    sale_record.currency_code, normalized_hash, applied_event
  );

  totals := private.refresh_sale_payment_totals(
    sale_record.id, sale_record.business_id
  );
  perform private.write_tenant_audit(
    payment_record.business_id,
    'payment.provider_verified',
    'payment',
    payment_record.id::text,
    jsonb_build_object(
      'sale_id', sale_record.id,
      'provider', normalized_provider,
      'provider_event_id', normalized_event_id,
      'reported_status', normalized_status,
      'outcome', event_outcome,
      'applied', applied_event
    )
  );

  return totals || jsonb_build_object(
    'payment_id', payment_record.id,
    'provider_event_id', normalized_event_id,
    'outcome', event_outcome,
    'applied', applied_event,
    'duplicate', false
  );
end;
$$;

revoke all on function public.record_provider_payment_verification(
  uuid, text, text, text, text, numeric, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.record_provider_payment_verification(
  uuid, text, text, text, text, numeric, text, text
) to service_role;
