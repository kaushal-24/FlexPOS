-- Cash rounding is valid only when cash is one of the tenders.

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
  if position('Cash rounding requires a cash tender' in definition) > 0 then
    return;
  end if;
  definition := replace(
    definition,
    '  if coalesce(order_discount, 0) < 0 then raise exception ''Order discount cannot be negative''; end if;',
    '  if rounding_amount <> 0 and not exists (' || E'\n' ||
    '    select 1 from jsonb_array_elements(payment_lines) payment_json' || E'\n' ||
    '    where payment_json ->> ''payment_method'' = ''cash''' || E'\n' ||
    '  ) then raise exception ''Cash rounding requires a cash tender''; end if;' || E'\n' ||
    '  if coalesce(order_discount, 0) < 0 then raise exception ''Order discount cannot be negative''; end if;'
  );
  if position('Cash rounding requires a cash tender' in definition) = 0 then
    raise exception 'complete_sale definition did not contain the cash-tender guard';
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
