-- Cover the nullable audit foreign key used by inventory valuation settings.
create index if not exists inventory_valuation_settings_updated_by_idx
  on public.inventory_valuation_settings(updated_by);
