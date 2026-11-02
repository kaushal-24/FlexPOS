-- Permission-gated cash rounding for flexpos-2 (gpbsblokhpydtpgxpwrg).

insert into public.permissions (code, category, description)
values (
  'sales.cash_rounding',
  'Sales',
  'Apply cash rounding during POS checkout'
)
on conflict (code) do update set
  category = excluded.category,
  description = excluded.description;

insert into private.feature_module_permissions (permission_code, module_code)
values ('sales.cash_rounding', 'sales')
on conflict (permission_code) do update set module_code = excluded.module_code;

insert into public.role_permissions (role_id, permission_code)
select r.id, 'sales.cash_rounding'
from public.roles r
where r.name in ('Owner', 'Administrator', 'Branch Manager', 'Cashier')
on conflict do nothing;

do $migration$
declare
  definition text;
begin
  select pg_get_functiondef(
    'public.complete_sale(uuid, uuid, uuid, uuid, uuid, uuid, jsonb, jsonb, numeric, text)'::regprocedure
  ) into definition;
  if definition is null then
    raise exception 'Authoritative complete_sale function was not found';
  end if;
  if position('sales.cash_rounding' in definition) > 0 then
    return;
  end if;
  definition := replace(
    definition,
    '  if coalesce(order_discount, 0) < 0 then raise exception ''Order discount cannot be negative''; end if;',
    '  if abs(rounding_amount) > 10 then raise exception ''Cash rounding adjustment is too large''; end if;' || E'\n' ||
    '  if rounding_amount <> 0 and not private.has_permission(target_business_id, ''sales.cash_rounding'') then' || E'\n' ||
    '    raise exception ''You do not have permission to apply cash rounding'';' || E'\n' ||
    '  end if;' || E'\n' ||
    '  if coalesce(order_discount, 0) < 0 then raise exception ''Order discount cannot be negative''; end if;'
  );
  if position('sales.cash_rounding' in definition) = 0 then
    raise exception 'complete_sale definition did not contain the cash-rounding permission gate';
  end if;
  execute definition;
end;
$migration$;

revoke all on function public.complete_sale(
  uuid, uuid, uuid, uuid, uuid, uuid, jsonb, jsonb, numeric, text
) from public, anon;
grant execute on function public.complete_sale(
  uuid, uuid, uuid, uuid, uuid, uuid, jsonb, jsonb, numeric, text
) to authenticated;
