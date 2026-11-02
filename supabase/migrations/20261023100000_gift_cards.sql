-- FlexPOS gift cards: hashed bearer codes, immutable value ledger, and
-- concurrency-safe sale redemption. Apply only to project gpbsblokhpydtpgxpwrg.

insert into public.permissions (code, category, description) values
  ('gift_cards.manage', 'Sales', 'Issue and administer gift cards')
on conflict (code) do update set
  category = excluded.category,
  description = excluded.description;

insert into public.role_permissions (role_id, permission_code)
select r.id, 'gift_cards.manage'
from public.roles r
where r.name in ('Owner', 'Administrator')
on conflict do nothing;

create table public.gift_cards (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  issuing_branch_id uuid not null,
  customer_id uuid,
  code_hash text not null check (code_hash ~ '^[0-9a-f]{64}$'),
  code_last_four text not null check (code_last_four ~ '^[A-Z0-9]{4}$'),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  initial_balance numeric(18,2) not null check (initial_balance > 0),
  current_balance numeric(18,2) not null check (
    current_balance >= 0 and current_balance <= initial_balance
  ),
  status text not null default 'active' check (status in ('active', 'redeemed')),
  expires_at timestamptz,
  operation_id uuid not null,
  issued_by uuid not null references auth.users(id) on delete restrict,
  issued_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, code_hash),
  unique (business_id, operation_id),
  constraint gift_cards_branch_fkey foreign key (issuing_branch_id, business_id)
    references public.branches(id, business_id) on delete restrict,
  constraint gift_cards_customer_fkey foreign key (customer_id, business_id)
    references public.customers(id, business_id) on delete restrict,
  check (expires_at is null or expires_at > issued_at),
  check (
    (status = 'active' and current_balance > 0)
    or (status = 'redeemed' and current_balance = 0)
  )
);

create table public.gift_card_transactions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  gift_card_id uuid not null,
  sale_id uuid,
  payment_id uuid,
  transaction_type text not null check (transaction_type in ('issue', 'redeem')),
  amount numeric(18,2) not null check (amount <> 0),
  balance_after numeric(18,2) not null check (balance_after >= 0),
  operation_id uuid not null,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (business_id, operation_id),
  unique (payment_id),
  constraint gift_card_transactions_card_fkey
    foreign key (gift_card_id, business_id)
    references public.gift_cards(id, business_id) on delete restrict,
  constraint gift_card_transactions_sale_fkey
    foreign key (sale_id, business_id)
    references public.sales(id, business_id) on delete restrict,
  constraint gift_card_transactions_payment_fkey
    foreign key (payment_id, business_id)
    references public.payments(id, business_id) on delete restrict,
  check (
    (transaction_type = 'issue' and amount > 0 and sale_id is null and payment_id is null)
    or
    (transaction_type = 'redeem' and amount < 0 and sale_id is not null and payment_id is not null)
  )
);

create index gift_cards_branch_business_idx
  on public.gift_cards(issuing_branch_id, business_id);
create index gift_cards_customer_business_idx
  on public.gift_cards(customer_id, business_id)
  where customer_id is not null;
create index gift_cards_issued_by_idx on public.gift_cards(issued_by);
create index gift_cards_business_active_expiry_idx
  on public.gift_cards(business_id, expires_at)
  where status = 'active';
create index gift_card_transactions_card_business_idx
  on public.gift_card_transactions(gift_card_id, business_id);
create index gift_card_transactions_sale_business_idx
  on public.gift_card_transactions(sale_id, business_id)
  where sale_id is not null;
create index gift_card_transactions_payment_business_idx
  on public.gift_card_transactions(payment_id, business_id)
  where payment_id is not null;
create index gift_card_transactions_actor_idx
  on public.gift_card_transactions(actor_user_id);

create trigger gift_card_transactions_immutable
before update or delete on public.gift_card_transactions
for each row execute function private.prevent_immutable_change();

create or replace function public.issue_gift_card(
  target_business_id uuid,
  target_branch_id uuid,
  target_customer_id uuid,
  operation_id uuid,
  initial_amount numeric,
  target_expires_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  existing_card public.gift_cards%rowtype;
  new_card_id uuid := gen_random_uuid();
  business_currency text;
  issued_amount numeric(18,2) := round(initial_amount, 2);
  raw_hex text;
  normalized_code text;
  display_code text;
  hashed_code text;
  result jsonb;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if issued_amount is null or issued_amount <= 0 then
    raise exception 'Gift-card value must be greater than zero';
  end if;
  if issued_amount > 1000000000 then
    raise exception 'Gift-card value exceeds the supported limit';
  end if;
  if target_expires_at is not null and target_expires_at <= now() then
    raise exception 'Gift-card expiry must be in the future';
  end if;
  if not private.has_permission(target_business_id, 'gift_cards.manage') then
    raise exception 'Gift-card management permission required';
  end if;
  if not private.has_branch_access(target_branch_id) then
    raise exception 'Branch is not accessible';
  end if;

  select * into existing_card
  from public.gift_cards gc
  where gc.business_id = target_business_id
    and gc.operation_id = issue_gift_card.operation_id;
  if found then
    raw_hex := upper(substr(replace(operation_id::text, '-', ''), 1, 20));
    display_code := 'GC-' || substr(raw_hex, 1, 4) || '-'
      || substr(raw_hex, 5, 4) || '-' || substr(raw_hex, 9, 4) || '-'
      || substr(raw_hex, 13, 4) || '-' || substr(raw_hex, 17, 4);
    return jsonb_build_object(
      'gift_card_id', existing_card.id,
      'gift_card_number', display_code,
      'balance', existing_card.current_balance,
      'currency_code', existing_card.currency_code,
      'expires_at', existing_card.expires_at,
      'customer_id', existing_card.customer_id
    );
  end if;

  select b.currency_code into business_currency
  from public.businesses b
  where b.id = target_business_id and b.archived_at is null;
  if not found then raise exception 'Business not found'; end if;
  if not exists (
    select 1 from public.branches b
    where b.id = target_branch_id and b.business_id = target_business_id
      and b.is_active and b.archived_at is null
  ) then raise exception 'Invalid branch'; end if;
  if target_customer_id is not null and not exists (
    select 1 from public.customers c
    where c.id = target_customer_id and c.business_id = target_business_id
      and c.is_active and c.archived_at is null
  ) then raise exception 'Invalid customer'; end if;

  raw_hex := upper(substr(replace(operation_id::text, '-', ''), 1, 20));
  normalized_code := 'GC' || raw_hex;
  display_code := 'GC-' || substr(raw_hex, 1, 4) || '-'
    || substr(raw_hex, 5, 4) || '-' || substr(raw_hex, 9, 4) || '-'
    || substr(raw_hex, 13, 4) || '-' || substr(raw_hex, 17, 4);
  hashed_code := encode(extensions.digest(normalized_code, 'sha256'), 'hex');

  insert into public.gift_cards (
    id, business_id, issuing_branch_id, customer_id, code_hash,
    code_last_four, currency_code, initial_balance, current_balance,
    expires_at, operation_id, issued_by
  ) values (
    new_card_id, target_business_id, target_branch_id, target_customer_id,
    hashed_code, right(raw_hex, 4), business_currency, issued_amount,
    issued_amount, target_expires_at, operation_id, caller_id
  );

  insert into public.gift_card_transactions (
    business_id, gift_card_id, transaction_type, amount, balance_after,
    operation_id, actor_user_id
  ) values (
    target_business_id, new_card_id, 'issue', issued_amount, issued_amount,
    operation_id, caller_id
  );

  result := jsonb_build_object(
    'gift_card_id', new_card_id,
    'gift_card_number', display_code,
    'balance', issued_amount,
    'currency_code', business_currency,
    'expires_at', target_expires_at,
    'customer_id', target_customer_id
  );
  perform private.write_tenant_audit(
    target_business_id, 'gift_card.issued', 'gift_card', new_card_id::text,
    (result - 'gift_card_number')
      || jsonb_build_object('last_four', right(raw_hex, 4))
  );
  return result;
end;
$$;

create or replace function public.lookup_gift_card(
  target_business_id uuid,
  target_card_number text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  caller_id uuid := auth.uid();
  normalized_code text;
  hashed_code text;
  card_record public.gift_cards%rowtype;
  effective_status text;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if not private.has_permission(target_business_id, 'sales.create') then
    raise exception 'You do not have permission to create sales';
  end if;
  normalized_code := regexp_replace(
    upper(coalesce(target_card_number, '')), '[^A-Z0-9]', '', 'g'
  );
  if length(normalized_code) <> 22 or left(normalized_code, 2) <> 'GC' then
    raise exception 'Invalid gift-card number';
  end if;
  hashed_code := encode(extensions.digest(normalized_code, 'sha256'), 'hex');
  select * into card_record
  from public.gift_cards gc
  where gc.business_id = target_business_id and gc.code_hash = hashed_code;
  if not found then raise exception 'Gift card not found'; end if;
  effective_status := case
    when card_record.expires_at is not null and card_record.expires_at <= now()
      then 'expired'
    else card_record.status
  end;
  return jsonb_build_object(
    'gift_card_id', card_record.id,
    'last_four', card_record.code_last_four,
    'balance', card_record.current_balance,
    'currency_code', card_record.currency_code,
    'status', effective_status,
    'expires_at', card_record.expires_at,
    'customer_id', card_record.customer_id
  );
end;
$$;

create or replace function public.complete_sale_with_gift_card(
  target_business_id uuid,
  target_branch_id uuid,
  target_register_id uuid,
  target_shift_id uuid,
  target_customer_id uuid,
  operation_id uuid,
  line_items jsonb,
  target_card_number text,
  gift_card_amount numeric,
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
  normalized_code text;
  hashed_code text;
  card_record public.gift_cards%rowtype;
  redemption_amount numeric(18,2) := round(gift_card_amount, 2);
  next_balance numeric(18,2);
  nested_result jsonb;
  existing_result jsonb;
  inserted_count integer;
  redeemed_sale_id uuid;
  redeemed_payment_id uuid;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if redemption_amount is null or redemption_amount <= 0 then
    raise exception 'Gift-card redemption amount must be greater than zero';
  end if;
  if not private.has_permission(target_business_id, 'sales.create') then
    raise exception 'You do not have permission to create sales';
  end if;
  if not private.has_branch_access(target_branch_id) then
    raise exception 'Branch is not accessible';
  end if;
  normalized_code := regexp_replace(
    upper(coalesce(target_card_number, '')), '[^A-Z0-9]', '', 'g'
  );
  if length(normalized_code) <> 22 or left(normalized_code, 2) <> 'GC' then
    raise exception 'Invalid gift-card number';
  end if;

  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (
    target_business_id, operation_id, 'sale.gift_card_redeem', caller_id
  ) on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select ir.result into existing_result
    from public.idempotency_records ir
    where ir.business_id = target_business_id
      and ir.operation_id = complete_sale_with_gift_card.operation_id
      and ir.operation_type = 'sale.gift_card_redeem';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Gift-card redemption is already in progress';
  end if;

  hashed_code := encode(extensions.digest(normalized_code, 'sha256'), 'hex');
  select * into card_record
  from public.gift_cards gc
  where gc.business_id = target_business_id and gc.code_hash = hashed_code
  for update;
  if not found then raise exception 'Gift card not found'; end if;
  if card_record.status <> 'active' then raise exception 'Gift card is not active'; end if;
  if card_record.expires_at is not null and card_record.expires_at <= now() then
    raise exception 'Gift card has expired';
  end if;
  if card_record.currency_code <> (
    select b.currency_code from public.businesses b
    where b.id = target_business_id
  ) then raise exception 'Gift-card currency does not match the sale'; end if;
  if card_record.customer_id is not null
     and target_customer_id is distinct from card_record.customer_id then
    raise exception 'Gift card belongs to a different customer';
  end if;
  if redemption_amount > card_record.current_balance then
    raise exception 'Gift-card balance is insufficient';
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
      'reference', 'GC-****-' || card_record.code_last_four,
      'provider', 'gift_card'
    )),
    order_discount,
    sale_notes
  );
  redeemed_sale_id := (nested_result ->> 'sale_id')::uuid;

  select p.id into strict redeemed_payment_id
  from public.payments p
  where p.sale_id = redeemed_sale_id
    and p.business_id = target_business_id
    and p.payment_method = 'gift_card'
    and p.provider = 'gift_card'
  for update;

  update public.payments
  set status = 'settled', settled_at = now()
  where id = redeemed_payment_id;
  update public.sales
  set payment_status = 'paid', paid_total = grand_total, due_total = 0
  where id = redeemed_sale_id;

  next_balance := round(card_record.current_balance - redemption_amount, 2);
  update public.gift_cards
  set current_balance = next_balance,
      status = case when next_balance = 0 then 'redeemed' else 'active' end,
      updated_at = now()
  where id = card_record.id;

  insert into public.gift_card_transactions (
    business_id, gift_card_id, sale_id, payment_id, transaction_type,
    amount, balance_after, operation_id, actor_user_id
  ) values (
    target_business_id, card_record.id, redeemed_sale_id, redeemed_payment_id,
    'redeem', -redemption_amount, next_balance, operation_id, caller_id
  );

  existing_result := nested_result || jsonb_build_object(
    'payment_status', 'paid',
    'gift_card_id', card_record.id,
    'gift_card_last_four', card_record.code_last_four,
    'gift_card_redeemed', redemption_amount,
    'gift_card_balance', next_balance
  );
  update public.idempotency_records ir set result = existing_result
  where ir.business_id = target_business_id
    and ir.operation_id = complete_sale_with_gift_card.operation_id
    and ir.operation_type = 'sale.gift_card_redeem';
  perform private.write_tenant_audit(
    target_business_id, 'gift_card.redeemed', 'gift_card', card_record.id::text,
    existing_result || jsonb_build_object('sale_id', redeemed_sale_id)
  );
  return existing_result;
end;
$$;

alter table public.gift_cards enable row level security;
alter table public.gift_card_transactions enable row level security;

revoke all on public.gift_cards, public.gift_card_transactions
  from public, anon, authenticated;

revoke all on function public.issue_gift_card(
  uuid, uuid, uuid, uuid, numeric, timestamptz
) from public, anon, authenticated;
grant execute on function public.issue_gift_card(
  uuid, uuid, uuid, uuid, numeric, timestamptz
) to authenticated;

revoke all on function public.lookup_gift_card(uuid, text)
  from public, anon, authenticated;
grant execute on function public.lookup_gift_card(uuid, text)
  to authenticated;

revoke all on function public.complete_sale_with_gift_card(
  uuid, uuid, uuid, uuid, uuid, uuid, jsonb, text, numeric, numeric, text
) from public, anon, authenticated;
grant execute on function public.complete_sale_with_gift_card(
  uuid, uuid, uuid, uuid, uuid, uuid, jsonb, text, numeric, numeric, text
) to authenticated;
