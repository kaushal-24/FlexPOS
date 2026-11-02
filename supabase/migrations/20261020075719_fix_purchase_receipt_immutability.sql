-- Existing deployments initially inserted a zero receipt total and finalized it
-- after inserting immutable receipt lines. Permit exactly that one calculated
-- transition while continuing to reject all other updates and every delete.

create or replace function private.protect_goods_receipt()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  calculated_total numeric(18,2);
begin
  if tg_op = 'DELETE' then
    raise exception 'goods_receipts records are immutable';
  end if;

  select coalesce(sum(gri.line_total), 0)
  into calculated_total
  from public.goods_receipt_items gri
  where gri.goods_receipt_id = old.id;

  if old.total_cost = 0
     and new.total_cost = calculated_total
     and (to_jsonb(new) - 'total_cost') = (to_jsonb(old) - 'total_cost') then
    return new;
  end if;
  raise exception 'goods_receipts records are immutable';
end;
$$;

revoke all on function private.protect_goods_receipt() from public, anon,
  authenticated, service_role;

drop trigger goods_receipts_immutable on public.goods_receipts;
create trigger goods_receipts_immutable
before update or delete on public.goods_receipts
for each row execute function private.protect_goods_receipt();
