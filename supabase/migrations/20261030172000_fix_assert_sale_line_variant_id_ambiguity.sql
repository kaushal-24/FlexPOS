-- Qualify the sale-line variant variable used by price validation.
-- Without this rename, PostgreSQL can resolve variant_id to either the
-- PL/pgSQL variable or product_prices.variant_id.
do $migration$
declare
  definition text;
begin
  select pg_get_functiondef(
    'private.assert_sale_line_prices(uuid, uuid, uuid, jsonb)'::regprocedure
  ) into definition;

  if definition is null then
    raise exception 'Unexpected assert_sale_line_prices definition; refusing ambiguity fix';
  end if;

  if position('  variant_id uuid;' in definition) > 0
     and position('pp.variant_id = variant_id' in definition) > 0 then
    definition := replace(
      definition,
      '  variant_id uuid;',
      '  line_variant_id uuid;'
    );
    definition := replace(
      definition,
      'variant_id :=',
      'line_variant_id :='
    );
    definition := replace(
      definition,
      'variant_id is null',
      'line_variant_id is null'
    );
    definition := replace(
      definition,
      'pp.variant_id = variant_id',
      'pp.variant_id = line_variant_id'
    );
    definition := replace(
      definition,
      'v.id = variant_id',
      'v.id = line_variant_id'
    );
    definition := replace(
      definition,
      'pv.id = variant_id',
      'pv.id = line_variant_id'
    );
  end if;

  execute definition;
end;
$migration$;

