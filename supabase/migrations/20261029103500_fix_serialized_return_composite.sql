do $$
declare
  current_definition text;
  replacement_definition text;
begin
  select pg_get_functiondef(
    'public.process_sale_return(uuid, uuid, jsonb, jsonb, text, text)'::regprocedure
  ) into current_definition;
  replacement_definition := replace(
    current_definition,
    'sale_item_record public.sale_items%rowtype;',
    'sale_item_record record;'
  );
  replacement_definition := replace(
    replacement_definition,
    E'    select si\n    into sale_item_record',
    E'    select si.*\n    into sale_item_record'
  );
  if replacement_definition = current_definition then
    raise exception 'Serialized return function correction did not match the deployed definition';
  end if;
  execute replacement_definition;
end;
$$;
