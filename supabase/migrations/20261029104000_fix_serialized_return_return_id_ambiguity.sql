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
    'where sri.return_id = return_id',
    'where sri.return_id = process_sale_return.return_id'
  );
  if replacement_definition = current_definition then
    raise exception 'Serialized return return-id correction did not match the deployed definition';
  end if;
  execute replacement_definition;
end;
$$;
