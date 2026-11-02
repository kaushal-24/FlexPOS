begin;

create index enterprise_records_branch_fk_idx
  on public.enterprise_records (branch_id);
create index enterprise_records_assigned_to_fk_idx
  on public.enterprise_records (assigned_to);
create index enterprise_records_created_by_fk_idx
  on public.enterprise_records (created_by);
create index enterprise_records_updated_by_fk_idx
  on public.enterprise_records (updated_by);

create index enterprise_record_events_business_fk_idx
  on public.enterprise_record_events (business_id);
create index enterprise_record_events_actor_fk_idx
  on public.enterprise_record_events (actor_user_id);

create index integration_connections_created_by_fk_idx
  on public.integration_connections (created_by);
create index integration_connections_updated_by_fk_idx
  on public.integration_connections (updated_by);

commit;
