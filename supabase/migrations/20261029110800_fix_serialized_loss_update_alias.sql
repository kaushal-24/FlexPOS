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
    'update public.idempotency_records',
    'update public.idempotency_records i'
  );
  replacement_definition := replace(
    replacement_definition,
    'idempotency_records.operation_id = record_stock_loss.operation_id',
    'i.operation_id = record_stock_loss.operation_id'
  );
  if replacement_definition = current_definition then
    raise exception 'Serialized loss update alias correction did not match the deployed definition';
  end if;
  execute replacement_definition;
end;
$$;
