-- Complete procurement workflows: requisitions/approval, supplier invoices,
-- landed-cost allocation, and supplier payment tracking.
begin;

create table if not exists public.purchase_requisitions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  status text not null default 'submitted'
    check (status in ('draft','submitted','approved','rejected','cancelled')),
  notes text,
  requested_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  decision_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, business_id),
  constraint purchase_requisitions_branch_fkey foreign key (branch_id, business_id)
    references public.branches(id, business_id) on delete restrict
);

create table if not exists public.purchase_requisition_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  requisition_id uuid not null,
  variant_id uuid not null,
  product_name text not null,
  sku text not null,
  quantity numeric(20,6) not null check (quantity > 0),
  notes text,
  created_at timestamptz not null default now(),
  unique (requisition_id, variant_id),
  constraint purchase_requisition_items_requisition_fkey
    foreign key (requisition_id, business_id)
    references public.purchase_requisitions(id, business_id) on delete cascade,
  constraint purchase_requisition_items_variant_fkey
    foreign key (variant_id, business_id)
    references public.product_variants(id, business_id) on delete restrict
);

create table if not exists public.purchase_invoices (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  purchase_order_id uuid not null,
  supplier_id uuid not null,
  invoice_number text not null check (length(btrim(invoice_number)) between 1 and 80),
  invoice_date date not null default current_date,
  due_date date,
  subtotal numeric(18,2) not null check (subtotal >= 0),
  tax_total numeric(18,2) not null default 0 check (tax_total >= 0),
  total numeric(18,2) not null check (total >= 0 and total = round(subtotal + tax_total, 2)),
  paid_total numeric(18,2) not null default 0 check (paid_total >= 0 and paid_total <= total),
  status text not null default 'posted'
    check (status in ('draft','posted','partially_paid','paid','void')),
  notes text,
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, invoice_number),
  constraint purchase_invoices_order_fkey foreign key (purchase_order_id, business_id)
    references public.purchase_orders(id, business_id) on delete restrict,
  constraint purchase_invoices_supplier_fkey foreign key (supplier_id, business_id)
    references public.suppliers(id, business_id) on delete restrict
);

create table if not exists public.purchase_invoice_payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  invoice_id uuid not null,
  amount numeric(18,2) not null check (amount > 0),
  payment_method text not null check (payment_method in ('cash','bank_transfer','card','upi','wallet','other')),
  reference text,
  notes text,
  operation_id uuid not null,
  paid_at timestamptz not null default now(),
  paid_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  unique (business_id, operation_id),
  constraint purchase_invoice_payments_invoice_fkey foreign key (invoice_id, business_id)
    references public.purchase_invoices(id, business_id) on delete restrict
);

create table if not exists public.purchase_landed_costs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  purchase_order_id uuid not null,
  amount numeric(18,2) not null check (amount > 0),
  allocation_method text not null check (allocation_method in ('by_value','by_quantity')),
  notes text,
  operation_id uuid not null,
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, operation_id),
  constraint purchase_landed_costs_order_fkey foreign key (purchase_order_id, business_id)
    references public.purchase_orders(id, business_id) on delete restrict
);

create table if not exists public.purchase_landed_cost_allocations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  landed_cost_id uuid not null,
  purchase_order_item_id uuid not null,
  amount numeric(18,2) not null check (amount >= 0),
  unique (landed_cost_id, purchase_order_item_id),
  constraint purchase_landed_cost_allocations_cost_fkey
    foreign key (landed_cost_id, business_id)
    references public.purchase_landed_costs(id, business_id) on delete restrict,
  constraint purchase_landed_cost_allocations_item_fkey
    foreign key (purchase_order_item_id, business_id)
    references public.purchase_order_items(id, business_id) on delete restrict
);

create index if not exists purchase_requisitions_business_created_idx on public.purchase_requisitions(business_id, created_at desc);
create index if not exists purchase_requisitions_branch_status_idx on public.purchase_requisitions(branch_id, status);
create index if not exists purchase_requisition_items_requisition_idx on public.purchase_requisition_items(requisition_id);
create index if not exists purchase_invoices_business_due_idx on public.purchase_invoices(business_id, due_date, status);
create index if not exists purchase_invoices_supplier_idx on public.purchase_invoices(supplier_id, business_id);
create index if not exists purchase_invoice_payments_invoice_idx on public.purchase_invoice_payments(invoice_id, business_id);
create index if not exists purchase_landed_costs_order_idx on public.purchase_landed_costs(purchase_order_id, business_id);
create index if not exists purchase_landed_cost_allocations_item_idx on public.purchase_landed_cost_allocations(purchase_order_item_id, business_id);

create trigger purchase_requisitions_set_updated_at before update on public.purchase_requisitions
for each row execute function private.set_updated_at();
create trigger purchase_invoices_set_updated_at before update on public.purchase_invoices
for each row execute function private.set_updated_at();

alter table public.purchase_requisitions enable row level security;
alter table public.purchase_requisition_items enable row level security;
alter table public.purchase_invoices enable row level security;
alter table public.purchase_invoice_payments enable row level security;
alter table public.purchase_landed_costs enable row level security;
alter table public.purchase_landed_cost_allocations enable row level security;

create policy purchase_requisitions_select on public.purchase_requisitions for select to authenticated
using ((select private.has_permission(business_id, 'purchases.view')) and (select private.has_branch_access(branch_id)));
create policy purchase_requisitions_manage on public.purchase_requisitions for all to authenticated
using ((select private.has_permission(business_id, 'purchases.manage')))
with check ((select private.has_permission(business_id, 'purchases.manage')));
create policy purchase_requisition_items_select on public.purchase_requisition_items for select to authenticated
using (exists (select 1 from public.purchase_requisitions r where r.id = requisition_id and (select private.has_permission(r.business_id, 'purchases.view')) and (select private.has_branch_access(r.branch_id))));
create policy purchase_requisition_items_manage on public.purchase_requisition_items for all to authenticated
using ((select private.has_permission(business_id, 'purchases.manage')))
with check ((select private.has_permission(business_id, 'purchases.manage')));

create policy purchase_invoices_select on public.purchase_invoices for select to authenticated
using ((select private.has_permission(business_id, 'purchases.view')));
create policy purchase_invoices_manage on public.purchase_invoices for all to authenticated
using ((select private.has_permission(business_id, 'purchases.manage')))
with check ((select private.has_permission(business_id, 'purchases.manage')));
create policy purchase_invoice_payments_select on public.purchase_invoice_payments for select to authenticated
using ((select private.has_permission(business_id, 'purchases.view')));
create policy purchase_invoice_payments_manage on public.purchase_invoice_payments for all to authenticated
using ((select private.has_permission(business_id, 'purchases.manage')))
with check ((select private.has_permission(business_id, 'purchases.manage')));
create policy purchase_landed_costs_select on public.purchase_landed_costs for select to authenticated
using ((select private.has_permission(business_id, 'purchases.view')));
create policy purchase_landed_costs_manage on public.purchase_landed_costs for all to authenticated
using ((select private.has_permission(business_id, 'purchases.manage')))
with check ((select private.has_permission(business_id, 'purchases.manage')));
create policy purchase_landed_cost_allocations_select on public.purchase_landed_cost_allocations for select to authenticated
using ((select private.has_permission(business_id, 'purchases.view')));
create policy purchase_landed_cost_allocations_manage on public.purchase_landed_cost_allocations for all to authenticated
using ((select private.has_permission(business_id, 'purchases.manage')))
with check ((select private.has_permission(business_id, 'purchases.manage')));

grant select, insert, update on public.purchase_requisitions, public.purchase_requisition_items,
  public.purchase_invoices, public.purchase_invoice_payments, public.purchase_landed_costs,
  public.purchase_landed_cost_allocations to authenticated;
revoke all on public.purchase_requisitions, public.purchase_requisition_items,
  public.purchase_invoices, public.purchase_invoice_payments, public.purchase_landed_costs,
  public.purchase_landed_cost_allocations from anon;

create or replace function public.create_purchase_requisition(
  target_business_id uuid,
  target_branch_id uuid,
  operation_id uuid,
  requested_items jsonb,
  requisition_notes text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  caller_id uuid := auth.uid();
  requisition_id uuid;
  item record;
begin
  if caller_id is null or not private.has_permission(target_business_id, 'purchases.manage') then
    raise exception 'Purchase management permission required';
  end if;
  if not private.has_branch_access(target_branch_id) then raise exception 'Branch is not accessible'; end if;
  if jsonb_typeof(requested_items) <> 'array' or jsonb_array_length(requested_items) = 0 then raise exception 'At least one requested item is required'; end if;
  insert into public.purchase_requisitions (business_id, branch_id, status, notes, requested_by)
  values (target_business_id, target_branch_id, 'submitted', nullif(btrim(requisition_notes), ''), caller_id)
  returning id into requisition_id;
  for item in select * from jsonb_to_recordset(requested_items) as x(variant_id uuid, quantity numeric, notes text) loop
    if item.quantity is null or item.quantity <= 0 then raise exception 'Requested quantities must be greater than zero'; end if;
    insert into public.purchase_requisition_items (business_id, requisition_id, variant_id, product_name, sku, quantity, notes)
    select target_business_id, requisition_id, v.id, p.name, v.sku, item.quantity, nullif(btrim(item.notes), '')
    from public.product_variants v join public.products p on p.id = v.product_id and p.business_id = target_business_id
    where v.id = item.variant_id and v.business_id = target_business_id and p.archived_at is null;
    if not found then raise exception 'Requested product variant is unavailable'; end if;
  end loop;
  return jsonb_build_object('id', requisition_id, 'status', 'submitted');
end;
$$;

create or replace function public.decide_purchase_requisition(
  target_requisition_id uuid,
  approve_request boolean,
  decision_notes text default null
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  request public.purchase_requisitions;
begin
  select * into request from public.purchase_requisitions where id = target_requisition_id for update;
  if not found or not private.has_permission(request.business_id, 'purchases.manage') then raise exception 'Requisition is not accessible'; end if;
  if request.status <> 'submitted' then raise exception 'Only submitted requisitions can be decided'; end if;
  update public.purchase_requisitions set status = case when approve_request then 'approved' else 'rejected' end,
    approved_by = auth.uid(), approved_at = now(), decision_note = nullif(btrim(decision_notes), '') where id = target_requisition_id;
end;
$$;

create or replace function public.create_purchase_invoice(
  target_business_id uuid,
  target_purchase_order_id uuid,
  invoice_number text,
  invoice_date date,
  due_date date,
  subtotal_amount numeric,
  tax_amount numeric,
  invoice_notes text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  order_record public.purchase_orders;
  invoice_id uuid;
  total_amount numeric(18,2) := round(subtotal_amount + tax_amount, 2);
begin
  if not private.has_permission(target_business_id, 'purchases.manage') then raise exception 'Purchase management permission required'; end if;
  if subtotal_amount is null or subtotal_amount < 0 or tax_amount is null or tax_amount < 0 then raise exception 'Invoice amounts are invalid'; end if;
  select * into order_record from public.purchase_orders where id = target_purchase_order_id and business_id = target_business_id;
  if not found then raise exception 'Purchase order is not accessible'; end if;
  insert into public.purchase_invoices (business_id, purchase_order_id, supplier_id, invoice_number, invoice_date, due_date, subtotal, tax_total, total, notes)
  values (target_business_id, target_purchase_order_id, order_record.supplier_id, btrim(invoice_number), coalesce(invoice_date, current_date), due_date, subtotal_amount, tax_amount, total_amount, nullif(btrim(invoice_notes), ''))
  returning id into invoice_id;
  return jsonb_build_object('id', invoice_id, 'total', total_amount);
end;
$$;

create or replace function public.record_purchase_invoice_payment(
  target_invoice_id uuid,
  operation_id uuid,
  payment_amount numeric,
  payment_method text,
  payment_reference text default null,
  payment_notes text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  invoice_record public.purchase_invoices;
  payment_id uuid;
  new_paid numeric(18,2);
begin
  select * into invoice_record from public.purchase_invoices where id = target_invoice_id for update;
  if not found or not private.has_permission(invoice_record.business_id, 'purchases.manage') then raise exception 'Supplier invoice is not accessible'; end if;
  if payment_amount is null or payment_amount <= 0 or payment_method not in ('cash','bank_transfer','card','upi','wallet','other') then raise exception 'Payment is invalid'; end if;
  if payment_amount > invoice_record.total - invoice_record.paid_total then raise exception 'Payment exceeds outstanding invoice balance'; end if;
  insert into public.purchase_invoice_payments (business_id, invoice_id, amount, payment_method, reference, notes, operation_id, paid_by)
  values (invoice_record.business_id, invoice_record.id, payment_amount, payment_method, nullif(btrim(payment_reference), ''), nullif(btrim(payment_notes), ''), operation_id, auth.uid())
  on conflict (business_id, operation_id) do nothing
  returning id into payment_id;
  if payment_id is null then
    select id into payment_id from public.purchase_invoice_payments where business_id = invoice_record.business_id and operation_id = record_purchase_invoice_payment.operation_id;
    return jsonb_build_object('id', payment_id, 'idempotent', true);
  end if;
  new_paid := round(invoice_record.paid_total + payment_amount, 2);
  update public.purchase_invoices set paid_total = new_paid, status = case when new_paid >= total then 'paid' else 'partially_paid' end where id = invoice_record.id;
  return jsonb_build_object('id', payment_id, 'paid_total', new_paid);
end;
$$;

create or replace function public.add_purchase_landed_cost(
  target_purchase_order_id uuid,
  operation_id uuid,
  cost_amount numeric,
  allocation_method text,
  cost_notes text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  order_record public.purchase_orders;
  cost_id uuid;
  item record;
  basis_total numeric := 0;
  allocated numeric := 0;
  share numeric;
begin
  select * into order_record from public.purchase_orders where id = target_purchase_order_id for update;
  if not found or not private.has_permission(order_record.business_id, 'purchases.manage') then raise exception 'Purchase order is not accessible'; end if;
  if cost_amount is null or cost_amount <= 0 or allocation_method not in ('by_value','by_quantity') then raise exception 'Landed cost is invalid'; end if;
  insert into public.purchase_landed_costs (business_id, purchase_order_id, amount, allocation_method, notes, operation_id)
  values (order_record.business_id, order_record.id, cost_amount, allocation_method, nullif(btrim(cost_notes), ''), operation_id)
  on conflict (business_id, operation_id) do nothing
  returning id into cost_id;
  if cost_id is null then select id into cost_id from public.purchase_landed_costs where business_id = order_record.business_id and operation_id = add_purchase_landed_cost.operation_id; return jsonb_build_object('id', cost_id, 'idempotent', true); end if;
  select coalesce(sum(case when allocation_method = 'by_value' then line_total else ordered_quantity end), 0) into basis_total from public.purchase_order_items where purchase_order_id = order_record.id;
  if basis_total <= 0 then raise exception 'Purchase order has no allocation basis'; end if;
  for item in select id, (case when allocation_method = 'by_value' then line_total else ordered_quantity end) as basis from public.purchase_order_items where purchase_order_id = order_record.id order by id loop
    share := case when item.id = (select id from public.purchase_order_items where purchase_order_id = order_record.id order by id desc limit 1)
      then round(cost_amount - allocated, 2) else round(cost_amount * item.basis / basis_total, 2) end;
    allocated := allocated + share;
    insert into public.purchase_landed_cost_allocations (business_id, landed_cost_id, purchase_order_item_id, amount) values (order_record.business_id, cost_id, item.id, share);
  end loop;
  return jsonb_build_object('id', cost_id, 'amount', cost_amount);
end;
$$;

revoke all on function public.create_purchase_requisition(uuid, uuid, uuid, jsonb, text) from public, anon;
revoke all on function public.decide_purchase_requisition(uuid, boolean, text) from public, anon;
revoke all on function public.create_purchase_invoice(uuid, uuid, text, date, date, numeric, numeric, text) from public, anon;
revoke all on function public.record_purchase_invoice_payment(uuid, uuid, numeric, text, text, text) from public, anon;
revoke all on function public.add_purchase_landed_cost(uuid, uuid, numeric, text, text) from public, anon;
grant execute on function public.create_purchase_requisition(uuid, uuid, uuid, jsonb, text) to authenticated;
grant execute on function public.decide_purchase_requisition(uuid, boolean, text) to authenticated;
grant execute on function public.create_purchase_invoice(uuid, uuid, text, date, date, numeric, numeric, text) to authenticated;
grant execute on function public.record_purchase_invoice_payment(uuid, uuid, numeric, text, text, text) to authenticated;
grant execute on function public.add_purchase_landed_cost(uuid, uuid, numeric, text, text) to authenticated;

commit;
