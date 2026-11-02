-- Keep the serialized-sale overload distinct from the existing sale RPC.
do $migration$
declare
  definition text;
  old_signature constant text := $old$public.complete_sale(target_business_id uuid, target_branch_id uuid, target_register_id uuid, target_shift_id uuid, target_customer_id uuid, operation_id uuid, line_items jsonb, payment_lines jsonb, order_discount numeric DEFAULT 0, sale_notes text DEFAULT NULL::text, serialized_unit_ids jsonb DEFAULT '{}'::jsonb)$old$;
  new_signature constant text := $new$public.complete_sale(target_business_id uuid, target_branch_id uuid, target_register_id uuid, target_shift_id uuid, target_customer_id uuid, operation_id uuid, line_items jsonb, payment_lines jsonb, order_discount numeric, sale_notes text, serialized_unit_ids jsonb)$new$;
begin
  select pg_get_functiondef(
    'public.complete_sale(uuid, uuid, uuid, uuid, uuid, uuid, jsonb, jsonb, numeric, text, jsonb)'::regprocedure
  ) into definition;
  if position(old_signature in definition) = 0 then
    raise exception 'Unexpected serialized complete_sale signature; refusing to change it';
  end if;
  definition := replace(definition, old_signature, new_signature);
  drop function public.complete_sale(
    uuid, uuid, uuid, uuid, uuid, uuid, jsonb, jsonb, numeric, text, jsonb
  );
  execute definition;
end;
$migration$;
