begin;

revoke execute on function public.create_industry_workflow(
  uuid, uuid, text, text, text, text, uuid, uuid, uuid, timestamptz, timestamptz,
  numeric, numeric, numeric, numeric, jsonb
) from public, anon;
revoke execute on function public.transition_industry_workflow(
  uuid, uuid, text, text, jsonb
) from public, anon;
grant execute on function public.create_industry_workflow(
  uuid, uuid, text, text, text, text, uuid, uuid, uuid, timestamptz, timestamptz,
  numeric, numeric, numeric, numeric, jsonb
) to authenticated;
grant execute on function public.transition_industry_workflow(
  uuid, uuid, text, text, jsonb
) to authenticated;

revoke all on function private.industry_module_for_kind(text)
  from public, anon, authenticated;
revoke all on function private.industry_workflow_authorized(uuid, text, text)
  from public, anon, authenticated;

commit;
