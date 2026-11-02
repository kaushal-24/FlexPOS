-- Allow managers to assign a register and open a shift for a specific staff
-- member without weakening tenant or branch isolation.

alter table public.registers
  add column if not exists assigned_user_id uuid references auth.users(id) on delete set null;

create index if not exists registers_assigned_user_idx
  on public.registers(assigned_user_id)
  where assigned_user_id is not null;

create or replace function private.can_access_register(target_register_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.registers r
    where r.id = target_register_id
      and (select private.is_business_member(r.business_id))
      and (select private.has_branch_access(r.branch_id))
      and (
        r.assigned_user_id is null
        or r.assigned_user_id = auth.uid()
        or (select private.has_permission(r.business_id, 'registers.manage'))
      )
  );
$$;

create or replace function public.open_register_shift_for_staff(
  target_business_id uuid,
  target_register_id uuid,
  target_staff_id uuid,
  opening_cash_amount numeric default 0,
  shift_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  assigned_user_id uuid;
  register_branch_id uuid;
  new_shift_id uuid;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if target_staff_id is null then raise exception 'A staff member is required'; end if;
  if coalesce(opening_cash_amount, 0) < 0 then
    raise exception 'Opening cash cannot be negative';
  end if;
  if not private.has_permission(target_business_id, 'sales.create') then
    raise exception 'You do not have permission to operate a register';
  end if;
  select r.assigned_user_id, r.branch_id
    into assigned_user_id, register_branch_id
  from public.registers r
  where r.id = target_register_id
    and r.business_id = target_business_id
    and r.is_active;
  if register_branch_id is null then raise exception 'Register is not accessible'; end if;
  if target_staff_id <> caller_id
     and not private.has_permission(target_business_id, 'registers.manage') then
    raise exception 'Only a register manager can open a shift for another staff member';
  end if;
  if assigned_user_id is not null
     and assigned_user_id <> target_staff_id
     and not private.has_permission(target_business_id, 'registers.manage') then
    raise exception 'This register is assigned to another staff member';
  end if;
  if not exists (
    select 1
    from public.memberships m
    where m.business_id = target_business_id
      and m.user_id = target_staff_id
      and m.status = 'active'
      and m.archived_at is null
      and (
        m.branch_access_all
        or exists (
          select 1
          from public.member_branch_access mba
          where mba.membership_id = m.id
            and mba.branch_id = register_branch_id
        )
      )
  ) then
    raise exception 'Selected staff member is not active or lacks access to this branch';
  end if;

  insert into public.register_shifts (
    business_id, register_id, opened_by, opening_cash, notes
  ) values (
    target_business_id, target_register_id, target_staff_id,
    round(coalesce(opening_cash_amount, 0), 2), nullif(btrim(shift_notes), '')
  ) returning id into new_shift_id;

  perform private.write_tenant_audit(
    target_business_id, 'register_shift.opened', 'register_shift', new_shift_id::text,
    jsonb_build_object(
      'register_id', target_register_id,
      'opened_for', target_staff_id,
      'opening_cash', round(coalesce(opening_cash_amount, 0), 2)
    )
  );
  return jsonb_build_object('shift_id', new_shift_id, 'status', 'open');
exception
  when unique_violation then
    raise exception 'This register already has an open shift';
end;
$$;

revoke all on function public.open_register_shift_for_staff(uuid, uuid, uuid, numeric, text)
  from public, anon;
grant execute on function public.open_register_shift_for_staff(uuid, uuid, uuid, numeric, text)
  to authenticated;

