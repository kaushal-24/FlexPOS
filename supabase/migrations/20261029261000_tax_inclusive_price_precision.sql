-- Preserve four-decimal net precision for tax-inclusive price validation.

do $migration$
declare
  definition text;
begin
  select pg_get_functiondef(
    'private.assert_sale_line_prices(uuid, uuid, uuid, jsonb)'::regprocedure
  ) into definition;

  if definition is null
     or position('expected_price := round(expected_price * 100 / (100 + tax_rate), 2);' in definition) = 0 then
    raise exception
      'Unexpected tax-inclusive price validator; refusing precision change';
  end if;

  definition := replace(
    definition,
    'expected_price := round(expected_price * 100 / (100 + tax_rate), 2);',
    'expected_price := round(expected_price * 100 / (100 + tax_rate), 4);'
  );
  execute definition;
end;
$migration$;
