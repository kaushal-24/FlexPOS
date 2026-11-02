-- Use the business invoice prefix when authoritative checkout creates an invoice.
-- The deployed complete_sale function has accumulated later fixes, so patch its
-- current definition in place instead of replaying an earlier full function.
begin;

do $$
declare
  definition text;
  old_declaration text := $find$  business_currency text;$find$;
  old_business_select text := $find$
  select currency_code into business_currency
  from public.businesses where id = target_business_id and archived_at is null;$find$;
  old_invoice_assignment text := $find$  invoice_no := 'FP-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS') || '-' || upper(substr(replace(sale_id::text, '-', ''), 1, 8));$find$;
begin
  select pg_get_functiondef(p.oid)
  into definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'complete_sale'
    and p.pronargs = 10;

  if definition is null then
    raise exception 'Authoritative complete_sale function was not found';
  end if;
  if position(old_declaration in definition) = 0
     or position(old_business_select in definition) = 0
     or position(old_invoice_assignment in definition) = 0 then
    raise exception 'complete_sale definition did not match the expected patch anchors';
  end if;

  definition := replace(
    definition,
    old_declaration,
    $replace$  business_currency text;
  invoice_prefix text;$replace$
  );
  definition := replace(
    definition,
    old_business_select,
    $replace$
  select currency_code, invoice_prefix
  into business_currency, invoice_prefix
  from public.businesses where id = target_business_id and archived_at is null;$replace$
  );
  definition := replace(
    definition,
    old_invoice_assignment,
    $replace$  invoice_no := coalesce(nullif(invoice_prefix, ''), 'FP') || '-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS') || '-' || upper(substr(replace(sale_id::text, '-', ''), 1, 8));$replace$
  );

  execute definition;
end;
$$;

commit;
