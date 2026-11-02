-- Persistent editable POS drafts. Drafts do not reserve stock, create sales,
-- or move inventory; checkout revalidates current products, prices, and stock.

create table public.pos_drafts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  warehouse_id uuid not null,
  customer_id uuid,
  title text not null check (length(btrim(title)) between 1 and 120),
  payment_method text not null default 'cash' check (payment_method in (
    'cash', 'upi', 'card', 'bank_transfer', 'wallet', 'customer_credit',
    'credit_note', 'split', 'partial'
  )),
  order_discount numeric(18,2) not null default 0 check (order_discount >= 0),
  operation_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, operation_id),
  constraint pos_drafts_branch_fkey foreign key (branch_id, business_id)
    references public.branches(id, business_id) on delete restrict,
  constraint pos_drafts_warehouse_fkey foreign key (warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete restrict,
  constraint pos_drafts_customer_fkey foreign key (customer_id, business_id)
    references public.customers(id, business_id) on delete restrict
);

create table public.pos_draft_items (
  draft_id uuid not null,
  business_id uuid not null,
  variant_id uuid not null,
  quantity numeric(20,6) not null check (quantity > 0),
  created_at timestamptz not null default now(),
  primary key (draft_id, variant_id),
  constraint pos_draft_items_draft_fkey
    foreign key (draft_id, business_id)
    references public.pos_drafts(id, business_id) on delete cascade,
  constraint pos_draft_items_variant_fkey
    foreign key (variant_id, business_id)
    references public.product_variants(id, business_id) on delete restrict
);

create index pos_drafts_business_updated_idx
  on public.pos_drafts(business_id, updated_at desc);
create index pos_drafts_branch_business_fk_idx
  on public.pos_drafts(branch_id, business_id);
create index pos_drafts_warehouse_business_fk_idx
  on public.pos_drafts(warehouse_id, business_id);
create index pos_drafts_customer_business_fk_idx
  on public.pos_drafts(customer_id, business_id)
  where customer_id is not null;
create index pos_drafts_created_by_idx on public.pos_drafts(created_by);
create index pos_drafts_updated_by_idx on public.pos_drafts(updated_by);
create index pos_draft_items_draft_business_fk_idx
  on public.pos_draft_items(draft_id, business_id);
create index pos_draft_items_variant_business_fk_idx
  on public.pos_draft_items(variant_id, business_id);

alter table public.pos_drafts enable row level security;
alter table public.pos_draft_items enable row level security;

create policy pos_drafts_select on public.pos_drafts
for select to authenticated
using (
  (select private.has_permission(business_id, 'sales.create'))
  and (select private.has_branch_access(branch_id))
);

create policy pos_draft_items_select on public.pos_draft_items
for select to authenticated
using (
  exists (
    select 1
    from public.pos_drafts draft
    where draft.id = draft_id
      and draft.business_id = pos_draft_items.business_id
      and (select private.has_permission(draft.business_id, 'sales.create'))
      and (select private.has_branch_access(draft.branch_id))
  )
);

revoke all on public.pos_drafts, public.pos_draft_items
from public, anon, authenticated;
grant select on public.pos_drafts, public.pos_draft_items to authenticated;

create or replace function public.save_pos_draft(
  target_business_id uuid,
  target_branch_id uuid,
  target_warehouse_id uuid,
  target_customer_id uuid,
  operation_id uuid,
  draft_title text,
  selected_payment_method text,
  order_discount numeric,
  line_items jsonb,
  target_draft_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  saved_draft_id uuid;
  existing_title text;
  line_record record;
  variant_record record;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if jsonb_typeof(line_items) <> 'array' or jsonb_array_length(line_items) = 0 then
    raise exception 'At least one draft item is required';
  end if;
  if length(btrim(coalesce(draft_title, ''))) not between 1 and 120 then
    raise exception 'Draft title must be between 1 and 120 characters';
  end if;
  if selected_payment_method not in (
    'cash', 'upi', 'card', 'bank_transfer', 'wallet', 'customer_credit',
    'credit_note', 'split', 'partial'
  ) then raise exception 'Invalid draft payment method'; end if;
  if coalesce(order_discount, 0) < 0 then
    raise exception 'Order discount cannot be negative';
  end if;
  if not private.has_permission(target_business_id, 'sales.create') then
    raise exception 'You do not have permission to save sales drafts';
  end if;
  if order_discount > 0
     and not private.has_permission(target_business_id, 'sales.discount') then
    raise exception 'You do not have permission to save a discounted draft';
  end if;
  if not private.has_branch_access(target_branch_id) then
    raise exception 'Branch is not accessible';
  end if;
  if not exists (
    select 1 from public.warehouses warehouse
    where warehouse.id = target_warehouse_id
      and warehouse.business_id = target_business_id
      and warehouse.branch_id = target_branch_id
      and warehouse.is_active
  ) then raise exception 'Invalid warehouse for sales draft'; end if;
  if target_customer_id is not null and not exists (
    select 1 from public.customers customer
    where customer.id = target_customer_id
      and customer.business_id = target_business_id
      and customer.is_active
      and customer.archived_at is null
  ) then raise exception 'Invalid customer for sales draft'; end if;

  if target_draft_id is not null then
    select draft.id into saved_draft_id
    from public.pos_drafts draft
    where draft.id = target_draft_id
      and draft.business_id = target_business_id
    for update;
    if not found then raise exception 'Sales draft not found'; end if;

    update public.pos_drafts
    set branch_id = target_branch_id,
        warehouse_id = target_warehouse_id,
        customer_id = target_customer_id,
        title = btrim(draft_title),
        payment_method = selected_payment_method,
        order_discount = round(coalesce(save_pos_draft.order_discount, 0), 2),
        operation_id = save_pos_draft.operation_id,
        updated_by = caller_id,
        updated_at = now()
    where id = saved_draft_id;
    delete from public.pos_draft_items draft_item
    where draft_item.draft_id = saved_draft_id;
  else
    select draft.id, draft.title into saved_draft_id, existing_title
    from public.pos_drafts draft
    where draft.business_id = target_business_id
      and draft.operation_id = save_pos_draft.operation_id;
    if found then
      return jsonb_build_object(
        'draft_id', saved_draft_id,
        'title', existing_title,
        'replayed', true
      );
    end if;

    saved_draft_id := gen_random_uuid();
    insert into public.pos_drafts (
      id, business_id, branch_id, warehouse_id, customer_id, title,
      payment_method, order_discount, operation_id, created_by, updated_by
    ) values (
      saved_draft_id, target_business_id, target_branch_id, target_warehouse_id,
      target_customer_id, btrim(draft_title), selected_payment_method,
      round(coalesce(order_discount, 0), 2), operation_id, caller_id, caller_id
    );
  end if;

  for line_record in
    select *
    from jsonb_to_recordset(line_items) as x(variant_id uuid, quantity numeric)
    order by variant_id
  loop
    if line_record.variant_id is null
       or line_record.quantity is null
       or line_record.quantity <= 0 then
      raise exception 'Invalid sales draft item';
    end if;
    select variant.id, product.allow_fractional_quantity
    into variant_record
    from public.product_variants variant
    join public.products product
      on product.id = variant.product_id
     and product.business_id = variant.business_id
    where variant.id = line_record.variant_id
      and variant.business_id = target_business_id
      and variant.is_active
      and variant.archived_at is null
      and product.is_active
      and product.archived_at is null;
    if not found then raise exception 'Sales draft variant is unavailable'; end if;
    if not variant_record.allow_fractional_quantity
       and line_record.quantity <> trunc(line_record.quantity) then
      raise exception 'Fractional quantity is not allowed for sales draft item';
    end if;
    insert into public.pos_draft_items (
      draft_id, business_id, variant_id, quantity
    ) values (
      saved_draft_id, target_business_id, line_record.variant_id,
      round(line_record.quantity, 6)
    );
  end loop;

  perform private.write_tenant_audit(
    target_business_id,
    case when target_draft_id is null then 'pos.draft_saved' else 'pos.draft_updated' end,
    'pos_draft',
    saved_draft_id::text,
    jsonb_build_object('title', btrim(draft_title), 'item_count', jsonb_array_length(line_items))
  );

  return jsonb_build_object(
    'draft_id', saved_draft_id,
    'title', btrim(draft_title),
    'replayed', false
  );
end;
$$;

create or replace function public.delete_pos_draft(target_draft_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  draft_record record;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;

  select draft.id, draft.business_id, draft.branch_id, draft.title
  into draft_record
  from public.pos_drafts draft
  where draft.id = target_draft_id
  for update;
  if not found then return jsonb_build_object('deleted', false); end if;
  if not private.has_permission(draft_record.business_id, 'sales.create')
     or not private.has_branch_access(draft_record.branch_id) then
    raise exception 'You do not have permission to delete this sales draft';
  end if;

  delete from public.pos_drafts where id = draft_record.id;
  perform private.write_tenant_audit(
    draft_record.business_id,
    'pos.draft_deleted',
    'pos_draft',
    draft_record.id::text,
    jsonb_build_object('title', draft_record.title)
  );
  return jsonb_build_object('deleted', true);
end;
$$;

revoke all on function public.save_pos_draft(
  uuid, uuid, uuid, uuid, uuid, text, text, numeric, jsonb, uuid
) from public, anon, authenticated;
grant execute on function public.save_pos_draft(
  uuid, uuid, uuid, uuid, uuid, text, text, numeric, jsonb, uuid
) to authenticated;

revoke all on function public.delete_pos_draft(uuid)
from public, anon, authenticated;
grant execute on function public.delete_pos_draft(uuid) to authenticated;
