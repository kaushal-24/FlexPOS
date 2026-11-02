begin;

alter table public.integration_connections
  add constraint integration_connections_secret_ref_format_check
  check (
    secret_ref is null
    or secret_ref ~ '^(vault|secret|kms)://[A-Za-z0-9._:/-]+$'
  );

commit;
