begin;

-- The security-hardening migration revoked the service_role's table and
-- sequence privileges. Edge Functions use this role only on the server side;
-- restoring these grants does not expose privileged access to Flutter clients
-- and does not change any authenticated-user RLS policy.
grant usage on schema public to service_role;
grant select, insert, update, delete on
  public.memberships,
  public.member_branch_access,
  public.profiles,
  public.roles,
  public.role_permissions,
  public.branches,
  public.tenant_audit_logs
to service_role;
grant usage, select on sequence public.tenant_audit_logs_id_seq to service_role;

commit;
