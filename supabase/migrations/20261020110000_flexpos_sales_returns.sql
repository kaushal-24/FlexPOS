-- FlexPOS sale returns: append-only return/refund documents, atomic stock
-- restoration, cash refund controls, register reconciliation, and net reports.

alter table public.sale_items
  add constraint sale_items_id_business_unique unique (id, business_id);

create table public.sale_returns (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  sale_id uuid not null,
  return_number text not null,
  status text not null default 'completed' check (status = 'completed'),
  subtotal numeric(18,2) not null check (subtotal >= 0),
  discount_total numeric(18,2) not null default 0 check (discount_total >= 0),
  tax_total numeric(18,2) not null default 0 check (tax_total >= 0),
  refund_total numeric(18,2) not null check (refund_total > 0),
  cost_total numeric(18,2) not null default 0 check (cost_total >= 0),
  reason text not null check (length(btrim(reason)) between 3 and 500),
  operation_id uuid not null,
  returned_by uuid not null references auth.users(id) on delete restrict,
  returned_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, return_number),
  unique (business_id, operation_id),
  constraint sale_returns_sale_fkey foreign key (sale_id, business_id)
    references public.sales(id, business_id) on delete restrict,
  constraint sale_returns_branch_fkey foreign key (branch_id, business_id)
    references public.branches(id, business_id) on delete restrict,
  check (refund_total = round(subtotal - discount_total + tax_total, 2))
);

create table public.sale_return_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  return_id uuid not null,
  sale_item_id uuid not null,
  warehouse_id uuid,
  variant_id uuid not null,
  product_name text not null,
  variant_name text not null,
  sku text not null,
  quantity numeric(20,6) not null check (quantity > 0),
  restocked boolean not null default true,
  subtotal numeric(18,2) not null check (subtotal >= 0),
  discount_amount numeric(18,2) not null default 0 check (discount_amount >= 0),
  tax_amount numeric(18,2) not null default 0 check (tax_amount >= 0),
  line_total numeric(18,2) not null check (line_total >= 0),
  unit_cost numeric(18,4) not null default 0 check (unit_cost >= 0),
  cost_total numeric(18,2) not null default 0 check (cost_total >= 0),
  created_at timestamptz not null default now(),
  unique (return_id, sale_item_id),
  constraint sale_return_items_return_fkey foreign key (return_id, business_id)
    references public.sale_returns(id, business_id) on delete restrict
    deferrable initially deferred,
  constraint sale_return_items_sale_item_fkey foreign key (sale_item_id, business_id)
    references public.sale_items(id, business_id) on delete restrict,
  constraint sale_return_items_variant_fkey foreign key (variant_id, business_id)
    references public.product_variants(id, business_id) on delete restrict,
  constraint sale_return_items_warehouse_fkey foreign key (warehouse_id, business_id)
    references public.warehouses(id, business_id) on delete restrict,
  check (line_total = round(subtotal - discount_amount + tax_amount, 2)),
  check (cost_total = round(quantity * unit_cost, 2))
);

create table public.sale_refunds (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  sale_id uuid not null,
  return_id uuid not null,
  payment_method text not null check (payment_method in (
    'cash', 'upi', 'card', 'bank_transfer', 'wallet', 'gift_card'
  )),
  status text not null check (status in ('pending', 'settled', 'failed')),
  amount numeric(18,2) not null check (amount > 0),
  reference text,
  processed_by uuid not null references auth.users(id) on delete restrict,
  processed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (return_id),
  constraint sale_refunds_sale_fkey foreign key (sale_id, business_id)
    references public.sales(id, business_id) on delete restrict,
  constraint sale_refunds_return_fkey foreign key (return_id, business_id)
    references public.sale_returns(id, business_id) on delete restrict,
  check ((status = 'settled' and payment_method = 'cash') or status <> 'settled')
);

create index sale_returns_sale_business_fk_idx
  on public.sale_returns(sale_id, business_id);
create index sale_returns_branch_business_fk_idx
  on public.sale_returns(branch_id, business_id);
create index sale_returns_returned_by_idx on public.sale_returns(returned_by);
create index sale_returns_business_time_idx
  on public.sale_returns(business_id, returned_at desc);

create index sale_return_items_business_id_idx
  on public.sale_return_items(business_id);
create index sale_return_items_return_business_fk_idx
  on public.sale_return_items(return_id, business_id);
create index sale_return_items_sale_item_business_fk_idx
  on public.sale_return_items(sale_item_id, business_id);
create index sale_return_items_variant_business_fk_idx
  on public.sale_return_items(variant_id, business_id);
create index sale_return_items_warehouse_business_fk_idx
  on public.sale_return_items(warehouse_id, business_id)
  where warehouse_id is not null;

create index sale_refunds_business_id_idx on public.sale_refunds(business_id);
create index sale_refunds_sale_business_fk_idx
  on public.sale_refunds(sale_id, business_id);
create index sale_refunds_return_business_fk_idx
  on public.sale_refunds(return_id, business_id);
create index sale_refunds_processed_by_idx on public.sale_refunds(processed_by);
create index sale_refunds_business_time_idx
  on public.sale_refunds(business_id, processed_at desc);

create trigger sale_returns_immutable
before update or delete on public.sale_returns
for each row execute function private.prevent_immutable_change();

create trigger sale_return_items_immutable
before update or delete on public.sale_return_items
for each row execute function private.prevent_immutable_change();

create trigger sale_refunds_immutable
before update or delete on public.sale_refunds
for each row execute function private.prevent_immutable_change();

create or replace function public.process_sale_return(
  target_sale_id uuid,
  operation_id uuid,
  return_lines jsonb,
  refund_method text default 'cash',
  return_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  sale_record public.sales%rowtype;
  item record;
  sale_item_record public.sale_items%rowtype;
  balance_record public.inventory_balances%rowtype;
  existing_result jsonb;
  inserted_count integer;
  return_id uuid := gen_random_uuid();
  return_item_id uuid;
  return_no text;
  previously_returned numeric(20,6);
  previously_returned_subtotal numeric(18,2);
  previously_returned_discount numeric(18,2);
  previously_returned_tax numeric(18,2);
  previously_returned_cost numeric(18,2);
  quantity_to_return numeric(20,6);
  next_quantity numeric(20,6);
  line_ratio numeric;
  line_subtotal numeric(18,2);
  line_discount numeric(18,2);
  line_tax numeric(18,2);
  line_total_amount numeric(18,2);
  line_cost numeric(18,2);
  subtotal_amount numeric(18,2) := 0;
  line_discount_total numeric(18,2) := 0;
  tax_amount_total numeric(18,2) := 0;
  pre_order_total numeric(18,2) := 0;
  cost_amount_total numeric(18,2) := 0;
  original_line_discounts numeric(18,2);
  original_order_discount numeric(18,2);
  previously_allocated_order_discount numeric(18,2);
  order_discount_allocation numeric(18,2);
  remaining_order_discount numeric(18,2);
  original_pre_order_total numeric(18,2);
  refund_amount numeric(18,2);
  refundable_cash numeric(18,2);
  all_items_returned boolean := true;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null then raise exception 'Operation ID is required'; end if;
  if jsonb_typeof(return_lines) <> 'array' or jsonb_array_length(return_lines) = 0 then
    raise exception 'At least one return line is required';
  end if;
  if length(btrim(coalesce(return_reason, ''))) < 3 then
    raise exception 'A meaningful return reason is required';
  end if;
  if refund_method <> 'cash' then
    raise exception 'Only verified cash refunds are currently supported';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(return_lines) as x(sale_item_id uuid, quantity numeric, restock boolean)
    group by x.sale_item_id
    having x.sale_item_id is null or count(*) > 1
  ) then
    raise exception 'Return lines must contain distinct sale items';
  end if;

  select * into sale_record
  from public.sales
  where id = target_sale_id
  for update;
  if not found then raise exception 'Sale not found'; end if;
  if sale_record.status not in ('completed', 'partially_refunded') then
    raise exception 'Sale is not eligible for return';
  end if;
  if not private.has_permission(sale_record.business_id, 'sales.refund') then
    raise exception 'Refund permission required';
  end if;
  if not private.has_branch_access(sale_record.branch_id) then
    raise exception 'Branch access required';
  end if;

  insert into public.idempotency_records (
    business_id, operation_id, operation_type, actor_user_id
  ) values (sale_record.business_id, operation_id, 'sale.return', caller_id)
  on conflict do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select result into existing_result
    from public.idempotency_records
    where business_id = sale_record.business_id
      and idempotency_records.operation_id = process_sale_return.operation_id
      and operation_type = 'sale.return';
    if existing_result <> '{}'::jsonb then return existing_result; end if;
    raise exception 'Return operation is already in progress';
  end if;

  select coalesce(sum(si.discount_amount), 0),
         coalesce(sum((si.quantity * si.unit_price) - si.discount_amount), 0)
  into original_line_discounts, original_pre_order_total
  from public.sale_items si
  where si.sale_id = sale_record.id;
  original_order_discount := greatest(
    sale_record.discount_total - original_line_discounts, 0
  );
  select coalesce(sum(sr.discount_total - line_discounts.total), 0)
  into previously_allocated_order_discount
  from public.sale_returns sr
  cross join lateral (
    select coalesce(sum(sri.discount_amount), 0) as total
    from public.sale_return_items sri
    where sri.return_id = sr.id
  ) line_discounts
  where sr.sale_id = sale_record.id;
  remaining_order_discount := greatest(
    original_order_discount - previously_allocated_order_discount, 0
  );

  return_no := 'RT-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS') || '-' ||
    upper(substr(replace(return_id::text, '-', ''), 1, 8));

  for item in
    select *
    from jsonb_to_recordset(return_lines) as x(
      sale_item_id uuid, quantity numeric, restock boolean
    )
    order by sale_item_id
  loop
    quantity_to_return := round(item.quantity, 6);
    if item.sale_item_id is null or quantity_to_return is null or quantity_to_return <= 0 then
      raise exception 'Invalid return line';
    end if;

    select * into sale_item_record
    from public.sale_items
    where id = item.sale_item_id and sale_id = sale_record.id
    for share;
    if not found then raise exception 'Sale item is not part of this sale'; end if;

    select coalesce(sum(sri.quantity), 0),
           coalesce(sum(sri.subtotal), 0),
           coalesce(sum(sri.discount_amount), 0),
           coalesce(sum(sri.tax_amount), 0),
           coalesce(sum(sri.cost_total), 0)
    into previously_returned, previously_returned_subtotal,
         previously_returned_discount, previously_returned_tax,
         previously_returned_cost
    from public.sale_return_items sri
    join public.sale_returns sr on sr.id = sri.return_id
    where sri.sale_item_id = sale_item_record.id
      and sr.status = 'completed';
    if quantity_to_return > sale_item_record.quantity - previously_returned then
      raise exception 'Return quantity exceeds the remaining quantity for SKU %',
        sale_item_record.sku;
    end if;
    if previously_returned + quantity_to_return < sale_item_record.quantity then
      all_items_returned := false;
    end if;

    if quantity_to_return = sale_item_record.quantity - previously_returned then
      line_subtotal := round(
        sale_item_record.quantity * sale_item_record.unit_price, 2
      ) - previously_returned_subtotal;
      line_discount := sale_item_record.discount_amount - previously_returned_discount;
      line_tax := sale_item_record.tax_amount - previously_returned_tax;
      line_cost := round(
        sale_item_record.quantity * sale_item_record.unit_cost, 2
      ) - previously_returned_cost;
    else
      line_ratio := quantity_to_return / sale_item_record.quantity;
      line_subtotal := round(
        sale_item_record.quantity * sale_item_record.unit_price * line_ratio, 2
      );
      line_discount := round(sale_item_record.discount_amount * line_ratio, 2);
      line_tax := round(sale_item_record.tax_amount * line_ratio, 2);
      line_cost := round(quantity_to_return * sale_item_record.unit_cost, 2);
    end if;
    line_total_amount := round(line_subtotal - line_discount + line_tax, 2);
    return_item_id := gen_random_uuid();

    insert into public.sale_return_items (
      id, business_id, return_id, sale_item_id, warehouse_id, variant_id,
      product_name, variant_name, sku, quantity, restocked, subtotal,
      discount_amount, tax_amount, line_total, unit_cost, cost_total
    ) values (
      return_item_id, sale_record.business_id, return_id, sale_item_record.id,
      sale_item_record.warehouse_id, sale_item_record.variant_id,
      sale_item_record.product_name, sale_item_record.variant_name,
      sale_item_record.sku, quantity_to_return, coalesce(item.restock, true),
      line_subtotal, line_discount, line_tax, line_total_amount,
      sale_item_record.unit_cost, line_cost
    );

    subtotal_amount := subtotal_amount + line_subtotal;
    line_discount_total := line_discount_total + line_discount;
    tax_amount_total := tax_amount_total + line_tax;
    pre_order_total := pre_order_total + line_subtotal - line_discount;
    cost_amount_total := cost_amount_total + line_cost;

    if coalesce(item.restock, true) and sale_item_record.warehouse_id is not null then
      select * into balance_record
      from public.inventory_balances ib
      where ib.warehouse_id = sale_item_record.warehouse_id
        and ib.variant_id = sale_item_record.variant_id
      for update;
      if not found then raise exception 'Inventory balance not found for returned item'; end if;
      next_quantity := balance_record.quantity_on_hand + quantity_to_return;
      update public.inventory_balances
      set quantity_on_hand = next_quantity, updated_at = now()
      where warehouse_id = sale_item_record.warehouse_id
        and variant_id = sale_item_record.variant_id;
      insert into public.inventory_movements (
        business_id, warehouse_id, variant_id, movement_type, quantity_delta,
        quantity_before, quantity_after, unit_cost, reference_type, reference_id,
        reason, operation_id, created_by
      ) values (
        sale_record.business_id, sale_item_record.warehouse_id,
        sale_item_record.variant_id, 'sale_return', quantity_to_return,
        balance_record.quantity_on_hand, next_quantity, sale_item_record.unit_cost,
        'sale_return', return_id, btrim(return_reason), return_item_id, caller_id
      );
    end if;
  end loop;

  if exists (
    select 1
    from public.sale_items si
    where si.sale_id = sale_record.id
      and si.id not in (
        select x.sale_item_id
        from jsonb_to_recordset(return_lines) as x(
          sale_item_id uuid, quantity numeric, restock boolean
        )
      )
      and coalesce((
        select sum(sri.quantity)
        from public.sale_return_items sri
        join public.sale_returns sr on sr.id = sri.return_id
        where sri.sale_item_id = si.id and sr.status = 'completed'
      ), 0) < si.quantity
  ) then
    all_items_returned := false;
  end if;

  order_discount_allocation := case
    when all_items_returned then remaining_order_discount
    when original_pre_order_total = 0 then 0
    else least(
      remaining_order_discount,
      round(original_order_discount * pre_order_total / original_pre_order_total, 2)
    )
  end;
  refund_amount := round(
    subtotal_amount - line_discount_total - order_discount_allocation + tax_amount_total,
    2
  );
  if refund_amount <= 0 then raise exception 'Return has no refundable value'; end if;

  select coalesce((
    select sum(p.amount) from public.payments p
    where p.sale_id = sale_record.id and p.payment_method = 'cash' and p.status = 'settled'
  ), 0) - coalesce((
    select sum(r.amount) from public.sale_refunds r
    where r.sale_id = sale_record.id and r.payment_method = 'cash' and r.status = 'settled'
  ), 0)
  into refundable_cash;
  if refund_amount > refundable_cash then
    raise exception 'Refund exceeds the remaining settled cash amount';
  end if;

  insert into public.sale_returns (
    id, business_id, branch_id, sale_id, return_number,
    subtotal, discount_total, tax_total, refund_total, cost_total,
    reason, operation_id, returned_by
  ) values (
    return_id, sale_record.business_id, sale_record.branch_id, sale_record.id,
    return_no, subtotal_amount,
    line_discount_total + order_discount_allocation, tax_amount_total,
    refund_amount, cost_amount_total, btrim(return_reason), operation_id, caller_id
  );

  insert into public.sale_refunds (
    business_id, sale_id, return_id, payment_method, status, amount,
    reference, processed_by
  ) values (
    sale_record.business_id, sale_record.id, return_id, 'cash', 'settled',
    refund_amount, return_no, caller_id
  );

  update public.sales
  set status = case when all_items_returned then 'refunded' else 'partially_refunded' end,
      payment_status = case when all_items_returned then 'refunded' else 'partially_refunded' end
  where id = sale_record.id;

  existing_result := jsonb_build_object(
    'return_id', return_id,
    'return_number', return_no,
    'sale_id', sale_record.id,
    'refund_total', refund_amount,
    'sale_status', case when all_items_returned then 'refunded' else 'partially_refunded' end
  );
  update public.idempotency_records set result = existing_result
  where business_id = sale_record.business_id
    and idempotency_records.operation_id = process_sale_return.operation_id
    and operation_type = 'sale.return';
  perform private.write_tenant_audit(
    sale_record.business_id, 'sale.returned', 'sale_return', return_id::text,
    existing_result || jsonb_build_object('reason', btrim(return_reason))
  );
  return existing_result;
end;
$$;

create or replace function public.get_business_dashboard(
  target_business_id uuid,
  period_start timestamptz,
  period_end timestamptz
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  result jsonb;
  can_view_profit boolean;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not private.has_permission(target_business_id, 'reports.view') then
    raise exception 'Report viewing permission required';
  end if;
  if period_start is null or period_end is null or period_end <= period_start then
    raise exception 'Invalid report period';
  end if;
  can_view_profit := private.has_permission(target_business_id, 'reports.profit');

  select jsonb_build_object(
    'period_start', period_start,
    'period_end', period_end,
    'sales_total', coalesce((
      select sum(activity.amount) from (
        select s.grand_total as amount
        from public.sales s
        where s.business_id = target_business_id
          and s.status in ('completed', 'partially_refunded', 'refunded')
          and s.completed_at >= period_start and s.completed_at < period_end
          and private.has_branch_access(s.branch_id)
        union all
        select -sr.refund_total
        from public.sale_returns sr
        where sr.business_id = target_business_id and sr.status = 'completed'
          and sr.returned_at >= period_start and sr.returned_at < period_end
          and private.has_branch_access(sr.branch_id)
      ) activity
    ), 0),
    'tax_total', coalesce((
      select sum(activity.amount) from (
        select s.tax_total as amount
        from public.sales s
        where s.business_id = target_business_id
          and s.status in ('completed', 'partially_refunded', 'refunded')
          and s.completed_at >= period_start and s.completed_at < period_end
          and private.has_branch_access(s.branch_id)
        union all
        select -sr.tax_total
        from public.sale_returns sr
        where sr.business_id = target_business_id and sr.status = 'completed'
          and sr.returned_at >= period_start and sr.returned_at < period_end
          and private.has_branch_access(sr.branch_id)
      ) activity
    ), 0),
    'order_count', coalesce((
      select count(*) from public.sales s
      where s.business_id = target_business_id
        and s.status in ('completed', 'partially_refunded', 'refunded')
        and s.completed_at >= period_start and s.completed_at < period_end
        and private.has_branch_access(s.branch_id)
    ), 0),
    'expenses_total', coalesce((
      select sum(case when e.entry_type = 'expense' then e.amount else -e.amount end)
      from public.expenses e
      where e.business_id = target_business_id
        and e.incurred_on >= period_start::date and e.incurred_on < period_end::date
        and private.has_branch_access(e.branch_id)
    ), 0),
    'outstanding_receivables', coalesce((
      select sum(case when cle.direction = 'debit' then cle.amount else -cle.amount end)
      from public.customer_ledger_entries cle
      where cle.business_id = target_business_id
        and private.has_branch_access(cle.branch_id)
    ), 0),
    'low_stock_count', coalesce((
      select count(*) from public.inventory_balances ib
      join public.warehouses w on w.id = ib.warehouse_id and w.business_id = ib.business_id
      where ib.business_id = target_business_id
        and ib.quantity_on_hand - ib.quantity_reserved <= ib.reorder_point
        and private.has_branch_access(w.branch_id)
    ), 0),
    'gross_profit', case when can_view_profit then coalesce((
      select sum(activity.amount) from (
        select s.grand_total - s.tax_total - coalesce((
          select sum(si.quantity * si.unit_cost)
          from public.sale_items si where si.sale_id = s.id
        ), 0) as amount
        from public.sales s
        where s.business_id = target_business_id
          and s.status in ('completed', 'partially_refunded', 'refunded')
          and s.completed_at >= period_start and s.completed_at < period_end
          and private.has_branch_access(s.branch_id)
        union all
        select -(sr.refund_total - sr.tax_total - sr.cost_total)
        from public.sale_returns sr
        where sr.business_id = target_business_id and sr.status = 'completed'
          and sr.returned_at >= period_start and sr.returned_at < period_end
          and private.has_branch_access(sr.branch_id)
      ) activity
    ), 0) else null end,
    'daily_sales', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'date', daily.day,
          'total', daily.total,
          'orders', daily.orders
        ) order by daily.day
      )
      from (
        select activity.day, sum(activity.amount) as total,
               sum(activity.orders) as orders
        from (
          select s.completed_at::date as day, s.grand_total as amount, 1 as orders
          from public.sales s
          where s.business_id = target_business_id
            and s.status in ('completed', 'partially_refunded', 'refunded')
            and s.completed_at >= period_start and s.completed_at < period_end
            and private.has_branch_access(s.branch_id)
          union all
          select sr.returned_at::date, -sr.refund_total, 0
          from public.sale_returns sr
          where sr.business_id = target_business_id and sr.status = 'completed'
            and sr.returned_at >= period_start and sr.returned_at < period_end
            and private.has_branch_access(sr.branch_id)
        ) activity
        group by activity.day
      ) daily
    ), '[]'::jsonb),
    'payment_breakdown', coalesce((
      select jsonb_agg(
        jsonb_build_object('method', paid.payment_method, 'total', paid.total)
        order by paid.payment_method
      )
      from (
        select activity.payment_method, sum(activity.amount) as total
        from (
          select p.payment_method, p.amount
          from public.payments p
          join public.sales s on s.id = p.sale_id and s.business_id = p.business_id
          where p.business_id = target_business_id and p.status = 'settled'
            and p.settled_at >= period_start and p.settled_at < period_end
            and private.has_branch_access(s.branch_id)
          union all
          select r.payment_method, -r.amount
          from public.sale_refunds r
          join public.sale_returns sr on sr.id = r.return_id and sr.business_id = r.business_id
          where r.business_id = target_business_id and r.status = 'settled'
            and r.processed_at >= period_start and r.processed_at < period_end
            and private.has_branch_access(sr.branch_id)
        ) activity
        group by activity.payment_method
      ) paid
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

alter table public.sale_returns enable row level security;
alter table public.sale_return_items enable row level security;
alter table public.sale_refunds enable row level security;

create policy sale_returns_select on public.sale_returns
for select to authenticated
using (
  (select private.has_permission(business_id, 'sales.view'))
  and (select private.has_branch_access(branch_id))
);

create policy sale_return_items_select on public.sale_return_items
for select to authenticated
using (exists (
  select 1 from public.sale_returns sr
  where sr.id = sale_return_items.return_id
    and sr.business_id = sale_return_items.business_id
    and (select private.has_permission(sr.business_id, 'sales.view'))
    and (select private.has_branch_access(sr.branch_id))
));

create policy sale_refunds_select on public.sale_refunds
for select to authenticated
using (exists (
  select 1 from public.sale_returns sr
  where sr.id = sale_refunds.return_id
    and sr.business_id = sale_refunds.business_id
    and (select private.has_permission(sr.business_id, 'sales.view'))
    and (select private.has_branch_access(sr.branch_id))
));

revoke all on public.sale_returns, public.sale_return_items, public.sale_refunds
from anon, authenticated;
grant select on public.sale_returns, public.sale_return_items, public.sale_refunds
to authenticated;

revoke all on function public.process_sale_return(uuid, uuid, jsonb, text, text)
from public, anon, authenticated;
grant execute on function public.process_sale_return(uuid, uuid, jsonb, text, text)
to authenticated;
