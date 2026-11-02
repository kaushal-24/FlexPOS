# FlexPOS backup and recovery runbook

FlexPOS stores production tenant data in the `flexpos-2` Supabase project. The application never stores a provider API key in the public database or in Flutter configuration.

## Backup policy

1. Keep Supabase point-in-time recovery and scheduled database backups enabled for the production project.
2. Export a tenant-safe evidence snapshot before a schema migration: businesses, branches, products, inventory balances, orders, payments, customers, audit events, and `enterprise_records`.
3. Store exports in an access-controlled location with retention and encryption defined by the operator. Do not commit exports, SQL dumps, API keys, or secret values to this repository.
4. Record each backup or restore rehearsal in the Enterprise operations screen as a `backup_recovery_run` record with the operator, timestamp, scope, outcome, and evidence reference.

## Recovery procedure

1. Confirm the incident scope and stop writes only when required by the incident commander.
2. Identify the recovery timestamp and restore to a separate Supabase project or branch first. Never overwrite the production project during investigation.
3. Verify authentication, RLS, business membership, branch access, inventory totals, payment reconciliation, and audit-log continuity on the restored environment.
4. Exercise a login, POS sale, UPI manual-success/manual-failure path, receipt rendering, inventory adjustment, and enterprise workflow transition.
5. Capture validation evidence as a `backup_recovery_run`, then promote or cut over using the operator's approved change process.

Provider secrets are restored through the secret manager using their opaque `secret_ref`; they are not recovered from `integration_connections.config`.
