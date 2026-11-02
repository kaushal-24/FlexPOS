begin;

create table public.register_cash_movements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  shift_id uuid not null references public.register_shifts(id) on delete restrict,
  movement_type text not null check (movement_type in ('cash_in', 'cash_out')),
  amount numeric(18,2) not null check (amount > 0),
  reason text not null check (length(btrim(reason)) between 3 and 250),
  operation_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (business_id, operation_id)
);

create index register_cash_movements_shift_created_idx
  on public.register_cash_movements(shift_id, created_at desc);
create index register_cash_movements_created_by_idx
  on public.register_cash_movements(created_by);

alter table public.register_cash_movements enable row level security;

create policy register_cash_movements_select
on public.register_cash_movements for select to authenticated
using (
  exists (
    select 1
    from public.register_shifts rs
    where rs.id = register_cash_movements.shift_id
      and rs.business_id = register_cash_movements.business_id
      and (select private.can_access_register(rs.register_id))
  )
);

revoke all on public.register_cash_movements from public, anon;
grant select on public.register_cash_movements to authenticated;

create or replace function public.record_register_cash_movement(
  target_shift_id uuid,
  operation_id uuid,
  movement_type text,
  movement_amount numeric,
  movement_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  shift_record public.register_shifts%rowtype;
  existing_record public.register_cash_movements%rowtype;
  movement_id uuid := gen_random_uuid();
  normalized_amount numeric(18,2);
  result jsonb;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if movement_type not in ('cash_in', 'cash_out') then
    raise exception 'Movement type must be cash_in or cash_out';
  end if;
  normalized_amount := round(movement_amount, 2);
  if normalized_amount is null or normalized_amount <= 0 then
    raise exception 'Movement amount must be greater than zero';
  end if;
  if length(btrim(coalesce(movement_reason, ''))) not between 3 and 250 then
    raise exception 'Movement reason must be between 3 and 250 characters';
  end if;

  select * into existing_record
  from public.register_cash_movements m
  where m.business_id = (
      select rs.business_id from public.register_shifts rs where rs.id = target_shift_id
    )
    and m.operation_id = record_register_cash_movement.operation_id;
  if found then
    if existing_record.created_by <> caller_id
       or existing_record.shift_id <> target_shift_id
       or existing_record.movement_type <> movement_type
       or existing_record.amount <> normalized_amount
       or existing_record.reason <> btrim(movement_reason) then
      raise exception 'Operation ID was already used for a different cash movement';
    end if;
    return jsonb_build_object(
      'movement_id', existing_record.id,
      'shift_id', existing_record.shift_id,
      'movement_type', existing_record.movement_type,
      'amount', existing_record.amount
    );
  end if;

  select * into shift_record
  from public.register_shifts rs
  where rs.id = target_shift_id
  for update;
  if not found or shift_record.status <> 'open' then
    raise exception 'Open shift not found';
  end if;
  if shift_record.opened_by <> caller_id
     and not private.has_permission(shift_record.business_id, 'registers.manage') then
    raise exception 'You do not have permission to move cash for this shift';
  end if;
  if not private.can_access_register(shift_record.register_id) then
    raise exception 'Register is not accessible';
  end if;

  insert into public.register_cash_movements (
    id, business_id, shift_id, movement_type, amount, reason,
    operation_id, created_by
  ) values (
    movement_id, shift_record.business_id, target_shift_id, movement_type,
    normalized_amount, btrim(movement_reason), operation_id, caller_id
  );

  result := jsonb_build_object(
    'movement_id', movement_id,
    'shift_id', target_shift_id,
    'movement_type', movement_type,
    'amount', normalized_amount
  );
  perform private.write_tenant_audit(
    shift_record.business_id,
    'register_shift.' || movement_type,
    'register_cash_movement',
    movement_id::text,
    result || jsonb_build_object('reason', btrim(movement_reason))
  );
  return result;
end;
$$;

create or replace function public.get_register_shift_report(target_shift_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  caller_id uuid := auth.uid();
  shift_record public.register_shifts%rowtype;
  register_record public.registers%rowtype;
  cash_sales numeric(18,2);
  cash_refunds numeric(18,2);
  cash_in numeric(18,2);
  cash_out numeric(18,2);
  total_sales numeric(18,2);
  total_refunds numeric(18,2);
  sale_count bigint;
  payment_breakdown jsonb;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;

  select * into shift_record
  from public.register_shifts rs
  where rs.id = target_shift_id;
  if not found then raise exception 'Register shift not found'; end if;
  select * into register_record
  from public.registers r
  where r.id = shift_record.register_id and r.business_id = shift_record.business_id;
  if shift_record.opened_by <> caller_id
     and not private.has_permission(shift_record.business_id, 'registers.manage') then
    raise exception 'You do not have permission to view this shift report';
  end if;
  if not private.has_branch_access(register_record.branch_id) then
    raise exception 'Register is not accessible';
  end if;

  select coalesce(sum(s.grand_total), 0), count(*)
  into total_sales, sale_count
  from public.sales s
  where s.shift_id = target_shift_id;

  select coalesce(sum(p.amount), 0)
  into cash_sales
  from public.payments p
  join public.sales s on s.id = p.sale_id and s.business_id = p.business_id
  where s.shift_id = target_shift_id
    and p.payment_method = 'cash'
    and p.status = 'settled';

  select coalesce(sum(r.amount), 0)
  into total_refunds
  from public.sale_refunds r
  join public.sales s on s.id = r.sale_id and s.business_id = r.business_id
  where s.shift_id = target_shift_id and r.status = 'settled';

  select coalesce(sum(r.amount), 0)
  into cash_refunds
  from public.sale_refunds r
  join public.sales s on s.id = r.sale_id and s.business_id = r.business_id
  where s.shift_id = target_shift_id
    and r.status = 'settled'
    and r.payment_method = 'cash';

  select
    coalesce(sum(m.amount) filter (where m.movement_type = 'cash_in'), 0),
    coalesce(sum(m.amount) filter (where m.movement_type = 'cash_out'), 0)
  into cash_in, cash_out
  from public.register_cash_movements m
  where m.shift_id = target_shift_id;

  select coalesce(jsonb_agg(
    jsonb_build_object('method', x.payment_method, 'amount', x.amount)
    order by x.payment_method
  ), '[]'::jsonb)
  into payment_breakdown
  from (
    select activity.payment_method, sum(activity.amount) amount
    from (
      select p.payment_method, p.amount
      from public.payments p
      join public.sales s on s.id = p.sale_id and s.business_id = p.business_id
      where s.shift_id = target_shift_id and p.status = 'settled'
      union all
      select r.payment_method, -r.amount
      from public.sale_refunds r
      join public.sales s on s.id = r.sale_id and s.business_id = r.business_id
      where s.shift_id = target_shift_id and r.status = 'settled'
    ) activity
    group by activity.payment_method
  ) x;

  return jsonb_build_object(
    'report_type', case when shift_record.status = 'open' then 'X' else 'Z' end,
    'shift_id', shift_record.id,
    'status', shift_record.status,
    'register_name', register_record.name,
    'register_code', register_record.code,
    'branch_id', register_record.branch_id,
    'opened_by', shift_record.opened_by,
    'closed_by', shift_record.closed_by,
    'opened_at', shift_record.opened_at,
    'closed_at', shift_record.closed_at,
    'sale_count', sale_count,
    'total_sales', round(total_sales, 2),
    'total_refunds', round(total_refunds, 2),
    'opening_cash', shift_record.opening_cash,
    'cash_sales', round(cash_sales, 2),
    'cash_refunds', round(cash_refunds, 2),
    'cash_in', round(cash_in, 2),
    'cash_out', round(cash_out, 2),
    'expected_cash', round(shift_record.opening_cash + cash_sales - cash_refunds + cash_in - cash_out, 2),
    'closing_cash', shift_record.closing_cash,
    'difference', shift_record.difference_amount,
    'payment_breakdown', payment_breakdown
  );
end;
$$;

create or replace function public.close_register_shift(
  target_shift_id uuid,
  closing_cash_amount numeric,
  shift_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  shift_record public.register_shifts%rowtype;
  cash_sales numeric(18,2);
  cash_refunds numeric(18,2);
  cash_in numeric(18,2);
  cash_out numeric(18,2);
  expected_amount numeric(18,2);
  difference numeric(18,2);
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if closing_cash_amount is null or closing_cash_amount < 0 then
    raise exception 'Closing cash cannot be negative';
  end if;

  select * into shift_record
  from public.register_shifts
  where id = target_shift_id
  for update;
  if not found or shift_record.status <> 'open' then raise exception 'Open shift not found'; end if;
  if shift_record.opened_by <> caller_id
     and not private.has_permission(shift_record.business_id, 'registers.manage') then
    raise exception 'You do not have permission to close this shift';
  end if;

  select coalesce(sum(p.amount), 0)
  into cash_sales
  from public.payments p
  join public.sales s on s.id = p.sale_id and s.business_id = p.business_id
  where s.shift_id = target_shift_id
    and p.payment_method = 'cash'
    and p.status = 'settled';

  select coalesce(sum(r.amount), 0)
  into cash_refunds
  from public.sale_refunds r
  join public.sales s on s.id = r.sale_id and s.business_id = r.business_id
  where s.shift_id = target_shift_id
    and r.payment_method = 'cash'
    and r.status = 'settled';

  select
    coalesce(sum(m.amount) filter (where m.movement_type = 'cash_in'), 0),
    coalesce(sum(m.amount) filter (where m.movement_type = 'cash_out'), 0)
  into cash_in, cash_out
  from public.register_cash_movements m
  where m.shift_id = target_shift_id;

  expected_amount := round(
    shift_record.opening_cash + cash_sales - cash_refunds + cash_in - cash_out,
    2
  );
  if expected_amount < 0 then
    raise exception 'Expected drawer cash cannot be negative';
  end if;
  difference := round(closing_cash_amount - expected_amount, 2);

  update public.register_shifts
  set status = 'closed', closed_by = caller_id, closed_at = now(),
      expected_cash = expected_amount, closing_cash = round(closing_cash_amount, 2),
      difference_amount = difference,
      notes = coalesce(nullif(btrim(shift_notes), ''), notes)
  where id = target_shift_id;

  perform private.write_tenant_audit(
    shift_record.business_id, 'register_shift.closed', 'register_shift', target_shift_id::text,
    jsonb_build_object(
      'expected_cash', expected_amount,
      'closing_cash', round(closing_cash_amount, 2),
      'difference', difference,
      'cash_sales', cash_sales,
      'cash_refunds', cash_refunds,
      'cash_in', cash_in,
      'cash_out', cash_out
    )
  );
  return jsonb_build_object(
    'shift_id', target_shift_id, 'status', 'closed',
    'expected_cash', expected_amount, 'closing_cash', round(closing_cash_amount, 2),
    'difference', difference
  );
end;
$$;

revoke all on function public.record_register_cash_movement(uuid, uuid, text, numeric, text)
from public, anon;
grant execute on function public.record_register_cash_movement(uuid, uuid, text, numeric, text)
to authenticated;

revoke all on function public.get_register_shift_report(uuid)
from public, anon;
grant execute on function public.get_register_shift_report(uuid)
to authenticated;

commit;
