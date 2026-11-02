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
    'select result into existing_result',
    'select i.result into existing_result'
  );
  replacement_definition := replace(
    replacement_definition,
    'from public.idempotency_records',
    'from public.idempotency_records i'
  );
  if replacement_definition = current_definition then
    raise exception 'Serialized loss result retry correction did not match the deployed definition';
  end if;
  execute replacement_definition;
end;
$$;
