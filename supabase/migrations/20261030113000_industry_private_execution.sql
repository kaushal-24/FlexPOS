begin;

grant execute on function private.industry_module_for_kind(text)
  to authenticated;
grant execute on function private.industry_workflow_authorized(uuid, text, text)
  to authenticated;

commit;
