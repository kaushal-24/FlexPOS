-- Allow safe editing of sale metadata without changing financial totals,
-- line items, payment history, invoice numbers, or audit-critical status.

insert into public.permissions (code, category, description)
values ('sales.update', 'Sales', 'Edit sale customer and notes')
on conflict (code) do update set
  category = excluded.category,
  description = excluded.description;

-- Existing roles that can create a sale may also correct its customer or note
-- metadata. Owners and administrators receive every permission through the
-- default-role seeding rule; this covers the operational sales roles too.
insert into public.role_permissions (role_id, permission_code)
select distinct role_id, 'sales.update'
from public.role_permissions
where permission_code = 'sales.create'
on conflict do nothing;

create or replace function public.update_sale_metadata(
  target_sale_id uuid,
  target_customer_id uuid default null,
  sale_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  sale_record public.sales%rowtype;
  normalized_notes text := nullif(btrim(coalesce(sale_notes, '')), '');
begin
  if caller_id is null then
    raise exception 'Authentication required';
  end if;

  select *
  into sale_record
  from public.sales
  where id = target_sale_id
  for update;

  if not found then
    raise exception 'Sale not found';
  end if;
  if not private.has_permission(sale_record.business_id, 'sales.update') then
    raise exception 'You do not have permission to edit sales';
  end if;
  if not private.has_branch_access(sale_record.branch_id) then
    raise exception 'Sale branch is not accessible';
  end if;
  if target_customer_id is not null
     and target_customer_id is distinct from sale_record.customer_id
     and not exists (
       select 1
       from public.customers customer
       where customer.id = target_customer_id
         and customer.business_id = sale_record.business_id
         and customer.is_active
         and customer.archived_at is null
     ) then
    raise exception 'Invalid customer';
  end if;
  if normalized_notes is not null and length(normalized_notes) > 1000 then
    raise exception 'Sale notes cannot exceed 1000 characters';
  end if;

  update public.sales
  set customer_id = target_customer_id,
      notes = normalized_notes
  where id = target_sale_id;

  perform private.write_tenant_audit(
    sale_record.business_id,
    'sale.metadata_updated',
    'sale',
    target_sale_id::text,
    jsonb_build_object(
      'customer_changed', sale_record.customer_id is distinct from target_customer_id,
      'notes_changed', sale_record.notes is distinct from normalized_notes
    )
  );

  return jsonb_build_object(
    'sale_id', target_sale_id,
    'customer_id', target_customer_id,
    'notes', normalized_notes
  );
end;
$$;

revoke all on function public.update_sale_metadata(uuid, uuid, text)
from public, anon;
grant execute on function public.update_sale_metadata(uuid, uuid, text)
to authenticated;
