begin;

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
  available_cash numeric(18,2);
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

  if movement_type = 'cash_out' then
    select round(
      shift_record.opening_cash
      + coalesce((
          select sum(p.amount)
          from public.payments p
          join public.sales s on s.id = p.sale_id and s.business_id = p.business_id
          where s.shift_id = target_shift_id
            and p.payment_method = 'cash'
            and p.status = 'settled'
        ), 0)
      - coalesce((
          select sum(r.amount)
          from public.sale_refunds r
          join public.sales s on s.id = r.sale_id and s.business_id = r.business_id
          where s.shift_id = target_shift_id
            and r.payment_method = 'cash'
            and r.status = 'settled'
        ), 0)
      + coalesce((
          select sum(
            case when m.movement_type = 'cash_in' then m.amount else -m.amount end
          )
          from public.register_cash_movements m
          where m.shift_id = target_shift_id
        ), 0),
      2
    ) into available_cash;
    if normalized_amount > available_cash then
      raise exception 'Cash out exceeds expected drawer cash';
    end if;
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

revoke all on function public.record_register_cash_movement(uuid, uuid, text, numeric, text)
from public, anon;
grant execute on function public.record_register_cash_movement(uuid, uuid, text, numeric, text)
to authenticated;

commit;
