begin;

-- Immutable, persisted invoice snapshots keep document history independent of
-- later product, customer, tax, or receipt-template edits.
create table public.invoice_documents (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  sale_id uuid not null references public.sales(id) on delete restrict,
  branch_id uuid references public.branches(id) on delete set null,
  customer_id uuid references public.customers(id) on delete set null,
  invoice_number text not null,
  document_type text not null default 'sale_invoice'
    check (document_type in ('sale_invoice', 'credit_note')),
  template text not null default 'classic'
    check (template in ('classic', 'minimal', 'detailed')),
  currency_code text not null check (char_length(currency_code) = 3),
  subtotal numeric(20,4) not null check (subtotal >= 0),
  discount_total numeric(20,4) not null check (discount_total >= 0),
  tax_total numeric(20,4) not null check (tax_total >= 0),
  service_charge_total numeric(20,4) not null check (service_charge_total >= 0),
  rounding_amount numeric(20,4) not null,
  grand_total numeric(20,4) not null check (grand_total >= 0),
  paid_total numeric(20,4) not null check (paid_total >= 0),
  due_total numeric(20,4) not null check (due_total >= 0),
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  issued_at timestamptz not null,
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (business_id, sale_id),
  unique (business_id, invoice_number)
);

create index invoice_documents_business_issued_idx
  on public.invoice_documents (business_id, issued_at desc, id desc);
create index invoice_documents_customer_idx
  on public.invoice_documents (business_id, customer_id, issued_at desc);
create index invoice_documents_branch_idx
  on public.invoice_documents (business_id, branch_id, issued_at desc);

alter table public.invoice_documents enable row level security;
create policy invoice_documents_select
on public.invoice_documents for select
to authenticated
using ((select private.has_permission(business_id, 'sales.view')));

revoke all on public.invoice_documents from anon, authenticated;
grant select on public.invoice_documents to authenticated;

create or replace function public.record_invoice_document(
  target_business_id uuid,
  target_sale_id uuid,
  target_template text,
  target_snapshot jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  sale_row public.sales%rowtype;
  document_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not private.has_permission(target_business_id, 'sales.view') then
    raise exception 'Sales view permission required';
  end if;
  if target_template not in ('classic', 'minimal', 'detailed') then
    raise exception 'Invalid invoice template';
  end if;
  if target_snapshot is null or jsonb_typeof(target_snapshot) <> 'object' then
    raise exception 'Invoice presentation snapshot must be a JSON object';
  end if;

  select * into sale_row
  from public.sales
  where id = target_sale_id
    and business_id = target_business_id
    and status = 'completed'
  for share;
  if not found then
    raise exception 'Completed sale not found';
  end if;

  insert into public.invoice_documents (
    business_id, sale_id, branch_id, customer_id, invoice_number,
    document_type, template, currency_code, subtotal, discount_total,
    tax_total, service_charge_total, rounding_amount, grand_total,
    paid_total, due_total, snapshot, issued_at, created_by
  ) values (
    sale_row.business_id, sale_row.id, sale_row.branch_id, sale_row.customer_id,
    sale_row.invoice_number, 'sale_invoice', target_template,
    sale_row.currency_code, sale_row.subtotal, sale_row.discount_total,
    sale_row.tax_total, sale_row.service_charge_total, sale_row.rounding_amount,
    sale_row.grand_total, sale_row.paid_total, sale_row.due_total,
    jsonb_build_object(
      'sale', to_jsonb(sale_row),
      'items', coalesce((
        select jsonb_agg(to_jsonb(item) order by item.id)
        from public.sale_items item where item.sale_id = sale_row.id
      ), '[]'::jsonb),
      'payments', coalesce((
        select jsonb_agg(to_jsonb(payment) order by payment.id)
        from public.payments payment where payment.sale_id = sale_row.id
      ), '[]'::jsonb),
      'presentation', target_snapshot
    ),
    coalesce(sale_row.completed_at, sale_row.created_at), auth.uid()
  )
  on conflict (business_id, sale_id) do nothing
  returning id into document_id;

  if document_id is null then
    select id into document_id
    from public.invoice_documents
    where business_id = target_business_id and sale_id = target_sale_id;
  else
    perform private.write_tenant_audit(
      target_business_id,
      'invoice_document.created',
      'invoice_document',
      document_id::text,
      jsonb_build_object('sale_id', target_sale_id, 'invoice_number', sale_row.invoice_number)
    );
  end if;
  return document_id;
end;
$$;

revoke all on function public.record_invoice_document(uuid, uuid, text, jsonb)
  from public, anon;
grant execute on function public.record_invoice_document(uuid, uuid, text, jsonb)
  to authenticated;

-- Gift-card tables are intentionally read-only through the Data API. The
-- secure issuance/redemption RPCs remain the only write path.
create policy gift_cards_select
on public.gift_cards for select to authenticated
using ((select private.has_permission(business_id, 'sales.view')));
create policy gift_card_transactions_select
on public.gift_card_transactions for select to authenticated
using ((select private.has_permission(business_id, 'sales.view')));
grant select on public.gift_cards, public.gift_card_transactions to authenticated;

-- Split read and write policies for advisor-safe, least-privilege evaluation.
drop policy if exists customer_groups_manage on public.customer_groups;
create policy customer_groups_insert on public.customer_groups for insert to authenticated
with check ((select private.has_permission(business_id, 'customers.manage')));
create policy customer_groups_update on public.customer_groups for update to authenticated
using ((select private.has_permission(business_id, 'customers.manage')))
with check ((select private.has_permission(business_id, 'customers.manage')));
create policy customer_groups_delete on public.customer_groups for delete to authenticated
using ((select private.has_permission(business_id, 'customers.manage')));

drop policy if exists promotions_manage on public.promotions;
create policy promotions_insert on public.promotions for insert to authenticated
with check ((select private.has_permission(business_id, 'promotions.manage')));
create policy promotions_update on public.promotions for update to authenticated
using ((select private.has_permission(business_id, 'promotions.manage')))
with check ((select private.has_permission(business_id, 'promotions.manage')));
create policy promotions_delete on public.promotions for delete to authenticated
using ((select private.has_permission(business_id, 'promotions.manage')));

drop policy if exists industry_workflow_lines_manage on public.industry_workflow_lines;
create policy industry_workflow_lines_insert on public.industry_workflow_lines for insert to authenticated
with check (exists (
  select 1 from public.industry_workflows workflow
  where workflow.id = industry_workflow_lines.workflow_id
    and workflow.business_id = industry_workflow_lines.business_id
    and private.industry_workflow_authorized(workflow.business_id, workflow.module_code, 'industry.manage')
));
create policy industry_workflow_lines_update on public.industry_workflow_lines for update to authenticated
using (exists (
  select 1 from public.industry_workflows workflow
  where workflow.id = industry_workflow_lines.workflow_id
    and workflow.business_id = industry_workflow_lines.business_id
    and private.industry_workflow_authorized(workflow.business_id, workflow.module_code, 'industry.manage')
))
with check (exists (
  select 1 from public.industry_workflows workflow
  where workflow.id = industry_workflow_lines.workflow_id
    and workflow.business_id = industry_workflow_lines.business_id
    and private.industry_workflow_authorized(workflow.business_id, workflow.module_code, 'industry.manage')
));
create policy industry_workflow_lines_delete on public.industry_workflow_lines for delete to authenticated
using (exists (
  select 1 from public.industry_workflows workflow
  where workflow.id = industry_workflow_lines.workflow_id
    and workflow.business_id = industry_workflow_lines.business_id
    and private.industry_workflow_authorized(workflow.business_id, workflow.module_code, 'industry.manage')
));

drop policy if exists enterprise_records_manage on public.enterprise_records;
create policy enterprise_records_insert on public.enterprise_records for insert to authenticated
with check ((select private.enterprise_record_authorized(business_id, branch_id, 'enterprise.manage')));
create policy enterprise_records_update on public.enterprise_records for update to authenticated
using ((select private.enterprise_record_authorized(business_id, branch_id, 'enterprise.manage')))
with check ((select private.enterprise_record_authorized(business_id, branch_id, 'enterprise.manage')));
create policy enterprise_records_delete on public.enterprise_records for delete to authenticated
using ((select private.enterprise_record_authorized(business_id, branch_id, 'enterprise.manage')));

-- Realtime is opt-in per table. These tables contain only RLS-protected rows.
do $$
declare
  table_name text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach table_name in array array[
      'sales', 'payments', 'inventory_stock_alert_notifications',
      'invoice_documents', 'hardware_devices', 'enterprise_records',
      'integration_connections'
    ] loop
      begin
        execute format('alter publication supabase_realtime add table public.%I', table_name);
      exception when duplicate_object then
        null;
      end;
    end loop;
  end if;
end;
$$;

-- Bounded keyset RPCs provide stable pagination without offset drift for the
-- two largest interactive datasets. RLS remains enforced by the invoker.
create index if not exists sales_business_created_id_idx
  on public.sales (business_id, created_at desc, id desc);
create index if not exists products_business_created_id_idx
  on public.products (business_id, created_at desc, id desc);

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
    and (select private.has_permission(target_business_id, 'sales.view'))
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
    and (select private.has_permission(target_business_id, 'products.view'))
    and (
      after_created_at is null
      or (after_id is not null and (product.created_at, product.id) < (after_created_at, after_id))
    )
  order by product.created_at desc, product.id desc
  limit least(greatest(coalesce(page_size, 50), 1), 100);
$$;

revoke all on function public.list_sales_keyset(uuid, timestamptz, uuid, integer)
  from public, anon;
revoke all on function public.list_products_keyset(uuid, timestamptz, uuid, integer)
  from public, anon;
grant execute on function public.list_sales_keyset(uuid, timestamptz, uuid, integer)
  to authenticated;
grant execute on function public.list_products_keyset(uuid, timestamptz, uuid, integer)
  to authenticated;

commit;
