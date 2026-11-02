begin;

grant execute on function private.enterprise_record_authorized(uuid, uuid, text)
  to authenticated;

commit;
