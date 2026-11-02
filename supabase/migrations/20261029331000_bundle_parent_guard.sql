-- Bundle parents are priced recipe SKUs; only their component variants carry
-- inventory. Prevent direct SQL/RPC callers from enabling parent stock tracking.
begin;

create or replace function private.validate_product_catalog_configuration()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.product_type = 'bundle' and new.track_inventory then
    raise exception 'Bundle products cannot track parent inventory';
  end if;
  return new;
end;
$$;

revoke all on function private.validate_product_catalog_configuration()
from public, anon, authenticated, service_role;

drop trigger if exists products_validate_catalog_configuration on public.products;
create trigger products_validate_catalog_configuration
before insert or update of product_type, track_inventory on public.products
for each row execute function private.validate_product_catalog_configuration();

commit;
