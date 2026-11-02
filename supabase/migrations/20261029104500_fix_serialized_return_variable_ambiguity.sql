do $$
declare
  current_definition text;
  replacement_definition text;
begin
  select pg_get_functiondef(
    'public.process_sale_return(uuid, uuid, jsonb, jsonb, text, text)'::regprocedure
  ) into current_definition;
  replacement_definition := replace(current_definition, 'return_id uuid;', 'v_return_id uuid;');
  replacement_definition := replace(
    replacement_definition,
    'return_id := (return_result ->> ''return_id'')::uuid;',
    'v_return_id := (return_result ->> ''return_id'')::uuid;'
  );
  replacement_definition := replace(
    replacement_definition,
    'where sri.return_id = process_sale_return.return_id',
    'where sri.return_id = v_return_id'
  );
  replacement_definition := replace(
    replacement_definition,
    '''returned'', ''in_stock'', ''sale_return'', return_id, operation_id, caller_id',
    '''returned'', ''in_stock'', ''sale_return'', v_return_id, operation_id, caller_id'
  );
  if replacement_definition = current_definition then
    raise exception 'Serialized return variable correction did not match the deployed definition';
  end if;
  execute replacement_definition;
end;
$$;
