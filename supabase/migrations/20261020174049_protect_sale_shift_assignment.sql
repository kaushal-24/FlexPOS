begin;

create or replace function private.enforce_sale_shift_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  shift_owner uuid;
begin
  if (new.register_id is null) <> (new.shift_id is null) then
    raise exception 'Register and shift must be selected together';
  end if;

  if new.shift_id is null then
    return new;
  end if;

  if auth.uid() is null or new.completed_by <> auth.uid() then
    raise exception 'Sale cashier does not match the authenticated user';
  end if;

  select rs.opened_by
  into shift_owner
  from public.register_shifts rs
  where rs.id = new.shift_id
    and rs.business_id = new.business_id
    and rs.register_id = new.register_id
    and rs.status = 'open'
  for share;

  if not found then
    raise exception 'A valid open register shift is required';
  end if;

  if shift_owner <> new.completed_by
     and not private.has_permission(new.business_id, 'registers.manage') then
    raise exception 'Register shift belongs to another cashier';
  end if;

  return new;
end;
$$;

revoke all on function private.enforce_sale_shift_assignment()
from public, anon, authenticated;

drop trigger if exists enforce_sale_shift_assignment on public.sales;
create trigger enforce_sale_shift_assignment
before insert on public.sales
for each row execute function private.enforce_sale_shift_assignment();

commit;
