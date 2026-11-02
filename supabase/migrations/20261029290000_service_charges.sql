-- Permission-gated POS service charges for flexpos-2 (gpbsblokhpydtpgxpwrg).
-- The checkout transport keeps backward compatibility by carrying the
-- adjustment metadata on the first payment line; the authoritative sale RPC
-- validates and persists the amount in sales.service_charge_total.

insert into public.permissions (code, category, description)
values (
  'sales.service_charge',
  'Sales',
  'Apply service charges during POS checkout'
)
on conflict (code) do update set
  category = excluded.category,
  description = excluded.description;

insert into private.feature_module_permissions (permission_code, module_code)
values ('sales.service_charge', 'sales')
on conflict (permission_code) do update set module_code = excluded.module_code;

insert into public.role_permissions (role_id, permission_code)
select r.id, 'sales.service_charge'
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
  if position('service_charge_total' in definition) > 0 then
    return;
  end if;

  definition := replace(
    definition,
    '  grand_total_amount numeric(18,2);',
    '  grand_total_amount numeric(18,2);' || E'\n' ||
    '  service_charge_amount numeric(18,2) := 0;' || E'\n' ||
    '  rounding_amount numeric(18,2) := 0;'
  );

  definition := replace(
    definition,
    '  if coalesce(order_discount, 0) < 0 then raise exception ''Order discount cannot be negative''; end if;',
    '  service_charge_amount := round(coalesce(nullif(payment_lines -> 0 ->> ''service_charge_amount'', '''')::numeric, 0), 2);' || E'\n' ||
    '  rounding_amount := round(coalesce(nullif(payment_lines -> 0 ->> ''rounding_amount'', '''')::numeric, 0), 2);' || E'\n' ||
    '  if service_charge_amount < 0 then raise exception ''Service charge cannot be negative''; end if;' || E'\n' ||
    '  if service_charge_amount > 0 and not private.has_permission(target_business_id, ''sales.service_charge'') then' || E'\n' ||
    '    raise exception ''You do not have permission to apply service charges'';' || E'\n' ||
    '  end if;' || E'\n' ||
    '  if coalesce(order_discount, 0) < 0 then raise exception ''Order discount cannot be negative''; end if;'
  );

  definition := replace(
    definition,
    '    subtotal_amount - line_discount_total - round(coalesce(order_discount, 0), 2) + tax_amount_total,',
    '    subtotal_amount - line_discount_total - round(coalesce(order_discount, 0), 2)' || E'\n' ||
    '      + tax_amount_total + service_charge_amount + rounding_amount,'
  );

  definition := replace(
    definition,
    '    tax_total, grand_total, paid_total, due_total, notes, operation_id,',
    '    tax_total, service_charge_total, rounding_amount, grand_total,' || E'\n' ||
    '    paid_total, due_total, notes, operation_id,'
  );
  definition := replace(
    definition,
    '    line_discount_total + round(coalesce(order_discount, 0), 2), tax_amount_total,' || E'\n' ||
    '    grand_total_amount, settled_total, greatest(grand_total_amount - settled_total, 0),',
    '    line_discount_total + round(coalesce(order_discount, 0), 2), tax_amount_total,' || E'\n' ||
    '    service_charge_amount, rounding_amount, grand_total_amount, settled_total,' || E'\n' ||
    '    greatest(grand_total_amount - settled_total, 0),'
  );
  definition := replace(
    definition,
    '    ''grand_total'', grand_total_amount,',
    '    ''grand_total'', grand_total_amount,' || E'\n' ||
    '    ''service_charge'', service_charge_amount,' || E'\n' ||
    '    ''rounding'', rounding_amount,'
  );

  if position('service_charge_amount' in definition) = 0
     or position('service_charge_total' in definition) = 0 then
    raise exception 'complete_sale definition did not contain all service-charge replacements';
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
