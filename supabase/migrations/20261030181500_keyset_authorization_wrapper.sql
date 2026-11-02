begin;

-- Keep keyset readers SECURITY INVOKER (and therefore subject to table RLS)
-- while exposing only the single authorization decision they need.
create or replace function public.authorize_keyset_read(
  target_business_id uuid,
  required_permission text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select private.has_permission(target_business_id, required_permission);
$$;

revoke all on function public.authorize_keyset_read(uuid, text) from public, anon;
grant execute on function public.authorize_keyset_read(uuid, text) to authenticated;

create or replace function public.list_sales_keyset(
  target_business_id uuid,
  after_created_at timestamptz,
  after_id uuid,
  page_size integer
)
returns setof jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select to_jsonb(sale)
  from public.sales sale
  where sale.business_id = target_business_id
    and (select public.authorize_keyset_read(target_business_id, 'sales.view'))
    and (
      after_created_at is null
      or (after_id is not null and (sale.created_at, sale.id) < (after_created_at, after_id))
    )
  order by sale.created_at desc, sale.id desc
  limit least(greatest(coalesce(page_size, 50), 1), 100);
$$;

create or replace function public.list_products_keyset(
  target_business_id uuid,
  after_created_at timestamptz,
  after_id uuid,
  page_size integer
)
returns setof jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select to_jsonb(product)
  from public.products product
  where product.business_id = target_business_id
    and (select public.authorize_keyset_read(target_business_id, 'products.view'))
    and (
      after_created_at is null
      or (after_id is not null and (product.created_at, product.id) < (after_created_at, after_id))
    )
  order by product.created_at desc, product.id desc
  limit least(greatest(coalesce(page_size, 50), 1), 100);
$$;

commit;
