-- Cover the sales-target audit foreign keys for user-oriented joins and deletes.
create index sales_targets_created_by_idx
  on public.sales_targets (created_by);

create index sales_targets_updated_by_idx
  on public.sales_targets (updated_by);
