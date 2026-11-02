-- Avoid a procedural sale_id variable colliding with sale_items.sale_id.
do $migration$
declare
  definition text;
begin
  select pg_get_functiondef(
    'public.complete_sale(uuid, uuid, uuid, uuid, uuid, uuid, jsonb, jsonb, numeric, text, jsonb)'::regprocedure
  ) into definition;
  definition := replace(definition, '  sale_id uuid;', '  v_sale_id uuid;');
  definition := replace(definition, '  sale_id := (result ->> ''sale_id'')::uuid;', '  v_sale_id := (result ->> ''sale_id'')::uuid;');
  definition := replace(definition, 'si.sale_id = sale_id', 'si.sale_id = v_sale_id');
  definition := replace(definition, '''sale'', sale_id, operation_id', '''sale'', v_sale_id, operation_id');
  execute definition;
end;
$migration$;
