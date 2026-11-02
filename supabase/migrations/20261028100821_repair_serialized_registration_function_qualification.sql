-- Repair parameter qualification after the implementation function was renamed.

do $repair$
declare
  function_definition text;
begin
  select pg_get_functiondef(
    'public.register_serialized_inventory_implementation(uuid,uuid,uuid,text,text[],uuid)'::regprocedure
  )
  into function_definition;
  function_definition := replace(
    function_definition,
    'register_serialized_inventory.operation_id',
    'register_serialized_inventory_implementation.operation_id'
  );
  execute function_definition;
end;
$repair$;

create or replace function public.register_serialized_inventory(
  target_business_id uuid,
  target_warehouse_id uuid,
  target_variant_id uuid,
  selected_tracking_mode text,
  identifiers text[],
  operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  request_operation_id uuid := operation_id;
  existing_result jsonb;
begin
  if caller_id is null then
    raise exception 'Authentication required';
  end if;
  if request_operation_id is null then
    raise exception 'Operation ID is required';
  end if;
  select result into existing_result
  from public.idempotency_records i
  where i.business_id = target_business_id
    and i.operation_id = request_operation_id
    and i.operation_type = 'inventory.serial.register';
  if found then
    if existing_result <> '{}'::jsonb then
      return existing_result;
    end if;
    raise exception 'Serialized inventory registration is already in progress';
  end if;
  return public.register_serialized_inventory_implementation(
    target_business_id,
    target_warehouse_id,
    target_variant_id,
    selected_tracking_mode,
    identifiers,
    request_operation_id
  );
end;
$$;

revoke all on function public.register_serialized_inventory(
  uuid, uuid, uuid, text, text[], uuid
) from public, anon;
grant execute on function public.register_serialized_inventory(
  uuid, uuid, uuid, text, text[], uuid
) to authenticated;
