do $$
declare
  current_definition text;
  replacement_definition text;
begin
  select pg_get_functiondef(
    'public.record_stock_loss(uuid, uuid, uuid, text, numeric, text, uuid, text, jsonb)'::regprocedure
  ) into current_definition;
  replacement_definition := replace(
    current_definition,
    E'  loss_event_id uuid;\n  result jsonb;',
    E'  loss_event_id uuid;\n  terminal_status text;\n  result jsonb;'
  );
  replacement_definition := replace(
    replacement_definition,
    E'  loss_event_id := (result ->> ''stock_loss_event_id'')::uuid;\n\n  if selected_count > 0 then',
    E'  loss_event_id := (result ->> ''stock_loss_event_id'')::uuid;\n  terminal_status := case selected_loss_type when ''damage'' then ''damaged'' else ''wastage'' end;\n\n  if selected_count > 0 then'
  );
  replacement_definition := replace(
    replacement_definition,
    'set status = selected_loss_type',
    'set status = terminal_status'
  );
  replacement_definition := replace(
    replacement_definition,
    'selected_loss_type, selected_loss_type, ''stock_loss_event''',
    'terminal_status, terminal_status, ''stock_loss_event'''
  );
  if replacement_definition = current_definition then
    raise exception 'Serialized loss terminal status correction did not match the deployed definition';
  end if;
  execute replacement_definition;
end;
$$;
