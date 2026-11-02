begin;

create table public.sale_exchanges (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  original_sale_id uuid not null,
  sale_return_id uuid not null,
  replacement_sale_id uuid not null,
  exchange_number text not null,
  refund_total numeric(18,2) not null check (refund_total > 0),
  replacement_total numeric(18,2) not null check (replacement_total > 0),
  cash_difference numeric(18,2) not null,
  operation_id uuid not null,
  reason text not null check (length(btrim(reason)) between 3 and 500),
  processed_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (business_id, exchange_number),
  unique (business_id, operation_id),
  unique (sale_return_id),
  unique (replacement_sale_id),
  constraint sale_exchanges_original_sale_fkey
    foreign key (original_sale_id, business_id)
    references public.sales(id, business_id) on delete restrict,
  constraint sale_exchanges_return_fkey
    foreign key (sale_return_id, business_id)
    references public.sale_returns(id, business_id) on delete restrict,
  constraint sale_exchanges_replacement_sale_fkey
    foreign key (replacement_sale_id, business_id)
    references public.sales(id, business_id) on delete restrict,
  check (cash_difference = round(replacement_total - refund_total, 2)),
  check (original_sale_id <> replacement_sale_id)
);

create index sale_exchanges_original_sale_business_idx
  on public.sale_exchanges(original_sale_id, business_id);
create index sale_exchanges_return_business_idx
  on public.sale_exchanges(sale_return_id, business_id);
create index sale_exchanges_replacement_sale_business_idx
  on public.sale_exchanges(replacement_sale_id, business_id);
create index sale_exchanges_processed_by_idx
  on public.sale_exchanges(processed_by);

alter table public.sale_exchanges enable row level security;

create policy sale_exchanges_select
on public.sale_exchanges for select to authenticated
using (
  (select private.has_permission(business_id, 'sales.view'))
  and exists (
    select 1
    from public.sales s
    where s.id = sale_exchanges.original_sale_id
      and s.business_id = sale_exchanges.business_id
      and (select private.has_branch_access(s.branch_id))
  )
);

create trigger sale_exchanges_immutable
before update or delete on public.sale_exchanges
for each row execute function private.prevent_immutable_change();

revoke all on public.sale_exchanges from public, anon;
grant select on public.sale_exchanges to authenticated;

create or replace function public.process_sale_exchange(
  target_sale_id uuid,
  operation_id uuid,
  target_register_id uuid,
  target_shift_id uuid,
  return_lines jsonb,
  replacement_lines jsonb,
  replacement_payment_total numeric,
  exchange_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  original_sale public.sales%rowtype;
  existing_exchange public.sale_exchanges%rowtype;
  return_result jsonb;
  replacement_result jsonb;
  exchange_id uuid := gen_random_uuid();
  exchange_no text;
  return_operation_id uuid := gen_random_uuid();
  sale_operation_id uuid := gen_random_uuid();
  refund_amount numeric(18,2);
  replacement_amount numeric(18,2);
  difference_amount numeric(18,2);
  result jsonb;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if jsonb_typeof(return_lines) <> 'array' or jsonb_array_length(return_lines) = 0 then
    raise exception 'At least one return item is required';
  end if;
  if jsonb_typeof(replacement_lines) <> 'array' or jsonb_array_length(replacement_lines) = 0 then
    raise exception 'At least one replacement item is required';
  end if;
  if replacement_payment_total is null or round(replacement_payment_total, 2) <= 0 then
    raise exception 'Replacement total must be greater than zero';
  end if;
  if length(btrim(coalesce(exchange_reason, ''))) not between 3 and 500 then
    raise exception 'Exchange reason must be between 3 and 500 characters';
  end if;

  select * into original_sale
  from public.sales s
  where s.id = target_sale_id
  for update;
  if not found then raise exception 'Original sale not found'; end if;

  select * into existing_exchange
  from public.sale_exchanges e
  where e.business_id = original_sale.business_id
    and e.operation_id = process_sale_exchange.operation_id;
  if found then
    if existing_exchange.original_sale_id <> target_sale_id
       or existing_exchange.processed_by <> caller_id then
      raise exception 'Operation ID was already used for a different exchange';
    end if;
    return jsonb_build_object(
      'exchange_id', existing_exchange.id,
      'exchange_number', existing_exchange.exchange_number,
      'original_sale_id', existing_exchange.original_sale_id,
      'return_id', existing_exchange.sale_return_id,
      'replacement_sale_id', existing_exchange.replacement_sale_id,
      'refund_total', existing_exchange.refund_total,
      'replacement_total', existing_exchange.replacement_total,
      'cash_difference', existing_exchange.cash_difference
    );
  end if;

  if not private.has_permission(original_sale.business_id, 'sales.refund')
     or not private.has_permission(original_sale.business_id, 'sales.create') then
    raise exception 'You do not have permission to process exchanges';
  end if;
  if not private.has_branch_access(original_sale.branch_id) then
    raise exception 'Sale branch is not accessible';
  end if;
  if not exists (
    select 1
    from public.registers r
    join public.register_shifts rs
      on rs.register_id = r.id and rs.business_id = r.business_id
    where r.id = target_register_id
      and r.business_id = original_sale.business_id
      and r.branch_id = original_sale.branch_id
      and r.is_active
      and rs.id = target_shift_id
      and rs.status = 'open'
  ) then
    raise exception 'An open register shift in the sale branch is required';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(replacement_lines) as line(warehouse_id uuid)
    left join public.warehouses w
      on w.id = line.warehouse_id and w.business_id = original_sale.business_id
    where w.id is null or w.branch_id <> original_sale.branch_id or not w.is_active
  ) then
    raise exception 'Replacement warehouse must be active in the sale branch';
  end if;

  return_result := public.process_sale_return(
    target_sale_id,
    return_operation_id,
    return_lines,
    'cash',
    btrim(exchange_reason)
  );
  refund_amount := round((return_result ->> 'refund_total')::numeric, 2);

  replacement_result := public.complete_sale(
    original_sale.business_id,
    original_sale.branch_id,
    target_register_id,
    target_shift_id,
    original_sale.customer_id,
    sale_operation_id,
    replacement_lines,
    jsonb_build_array(jsonb_build_object(
      'payment_method', 'cash',
      'amount', round(replacement_payment_total, 2),
      'reference', null,
      'provider', 'exchange'
    )),
    0,
    'Exchange for ' || original_sale.invoice_number
  );
  replacement_amount := round((replacement_result ->> 'grand_total')::numeric, 2);
  difference_amount := round(replacement_amount - refund_amount, 2);
  exchange_no := 'EXC-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS') || '-'
    || upper(substr(replace(exchange_id::text, '-', ''), 1, 8));

  insert into public.sale_exchanges (
    id, business_id, original_sale_id, sale_return_id, replacement_sale_id,
    exchange_number, refund_total, replacement_total, cash_difference,
    operation_id, reason, processed_by
  ) values (
    exchange_id, original_sale.business_id, target_sale_id,
    (return_result ->> 'return_id')::uuid,
    (replacement_result ->> 'sale_id')::uuid,
    exchange_no, refund_amount, replacement_amount, difference_amount,
    operation_id, btrim(exchange_reason), caller_id
  );

  result := jsonb_build_object(
    'exchange_id', exchange_id,
    'exchange_number', exchange_no,
    'original_sale_id', target_sale_id,
    'return_id', (return_result ->> 'return_id')::uuid,
    'replacement_sale_id', (replacement_result ->> 'sale_id')::uuid,
    'replacement_invoice_number', replacement_result ->> 'invoice_number',
    'refund_total', refund_amount,
    'replacement_total', replacement_amount,
    'cash_difference', difference_amount
  );
  perform private.write_tenant_audit(
    original_sale.business_id,
    'sale.exchanged',
    'sale_exchange',
    exchange_id::text,
    result || jsonb_build_object('reason', btrim(exchange_reason))
  );
  return result;
end;
$$;

revoke all on function public.process_sale_exchange(
  uuid, uuid, uuid, uuid, jsonb, jsonb, numeric, text
) from public, anon;
grant execute on function public.process_sale_exchange(
  uuid, uuid, uuid, uuid, jsonb, jsonb, numeric, text
) to authenticated;

commit;
