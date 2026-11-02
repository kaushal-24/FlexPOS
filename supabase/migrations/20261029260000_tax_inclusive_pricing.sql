-- Tax-inclusive catalog pricing.
--
-- Catalog prices remain gross shelf prices in the client. The Flutter client
-- converts them to tax-exclusive units before sending sale, quote, and order
-- payloads, while this guard applies the same conversion server-side when
-- validating the authoritative catalog price.

do $migration$
declare
  definition text;
begin
  select pg_get_functiondef(
    'private.assert_sale_line_prices(uuid, uuid, uuid, jsonb)'::regprocedure
  ) into definition;

  if definition is null
     or position('override_requested boolean;' in definition) = 0
     or position('if expected_price is null then' in definition) = 0 then
    raise exception
      'Unexpected assert_sale_line_prices definition; refusing tax-inclusive change';
  end if;

  definition := replace(
    definition,
    '  override_requested boolean;',
    E'  override_requested boolean;\n  tax_rate numeric;\n  tax_is_inclusive boolean;'
  );
  definition := replace(
    definition,
    '    if expected_price is null then',
    $patch$
    select coalesce(t.rate, 0), coalesce(t.is_inclusive, false)
    into tax_rate, tax_is_inclusive
    from public.product_variants pv
    join public.products p
      on p.id = pv.product_id
     and p.business_id = pv.business_id
    left join public.tax_rates t
      on t.id = p.tax_rate_id
     and t.business_id = p.business_id
    where pv.id = line_variant_id
      and pv.business_id = target_business_id;

    if tax_is_inclusive and tax_rate > 0 then
      -- The first version used the existing cent-rounded validator contract.
      -- The following precision migration upgrades this expression to four
      -- decimals before the migration sequence is complete.
      expected_price := round(expected_price * 100 / (100 + tax_rate), 2);
    end if;

    if expected_price is null then
    $patch$
  );

  execute definition;
end;
$migration$;

comment on function private.assert_sale_line_prices(uuid, uuid, uuid, jsonb)
  is 'Validates catalog prices and normalizes tax-inclusive gross prices before the precision follow-up migration.';
