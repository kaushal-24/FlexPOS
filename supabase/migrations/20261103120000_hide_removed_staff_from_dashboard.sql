-- Add server-authoritative sales breakdowns to the business dashboard while
-- preserving tenant permission checks, branch scoping, and net return totals.

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
      join public.warehouses w
        on w.id = ib.warehouse_id and w.business_id = ib.business_id
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
        order by paid.total desc, paid.payment_method
      )
      from (
        select activity.payment_method, sum(activity.amount) as total
        from (
          select p.payment_method, p.amount
          from public.payments p
          join public.sales s
            on s.id = p.sale_id and s.business_id = p.business_id
          where p.business_id = target_business_id and p.status = 'settled'
            and p.settled_at >= period_start and p.settled_at < period_end
            and private.has_branch_access(s.branch_id)
          union all
          select r.payment_method, -r.amount
          from public.sale_refunds r
          join public.sale_returns sr
            on sr.id = r.return_id and sr.business_id = r.business_id
          where r.business_id = target_business_id and r.status = 'settled'
            and r.processed_at >= period_start and r.processed_at < period_end
            and private.has_branch_access(sr.branch_id)
        ) activity
        group by activity.payment_method
      ) paid
    ), '[]'::jsonb),
    'branch_breakdown', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', grouped.id,
          'name', grouped.name,
          'total', grouped.total,
          'orders', grouped.orders
        ) order by grouped.total desc, grouped.name
      )
      from (
        select b.id, b.name, sum(activity.amount) as total,
               sum(activity.orders) as orders
        from (
          select s.branch_id, s.grand_total as amount, 1 as orders
          from public.sales s
          where s.business_id = target_business_id
            and s.status in ('completed', 'partially_refunded', 'refunded')
            and s.completed_at >= period_start and s.completed_at < period_end
            and private.has_branch_access(s.branch_id)
          union all
          select sr.branch_id, -sr.refund_total, 0
          from public.sale_returns sr
          where sr.business_id = target_business_id and sr.status = 'completed'
            and sr.returned_at >= period_start and sr.returned_at < period_end
            and private.has_branch_access(sr.branch_id)
        ) activity
        join public.branches b
          on b.id = activity.branch_id and b.business_id = target_business_id
        group by b.id, b.name
      ) grouped
    ), '[]'::jsonb),
    'employee_breakdown', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', grouped.id,
          'name', grouped.name,
          'total', grouped.total,
          'orders', grouped.orders
        ) order by grouped.total desc, grouped.name
      )
      from (
        select activity.user_id as id,
               coalesce(nullif(btrim(p.full_name), ''), p.email) as name,
               sum(activity.amount) as total,
               sum(activity.orders) as orders
        from (
          select s.completed_by as user_id, s.grand_total as amount, 1 as orders
          from public.sales s
          where s.business_id = target_business_id
            and s.status in ('completed', 'partially_refunded', 'refunded')
            and s.completed_at >= period_start and s.completed_at < period_end
            and private.has_branch_access(s.branch_id)
          union all
          select s.completed_by, -sr.refund_total, 0
          from public.sale_returns sr
          join public.sales s
            on s.id = sr.sale_id and s.business_id = sr.business_id
          where sr.business_id = target_business_id and sr.status = 'completed'
            and sr.returned_at >= period_start and sr.returned_at < period_end
            and private.has_branch_access(sr.branch_id)
        ) activity
        join public.profiles p on p.id = activity.user_id
        where exists (
          select 1
          from public.memberships m
          where m.user_id = activity.user_id
            and m.business_id = target_business_id
            and m.status = 'active'
            and m.archived_at is null
        )
        group by activity.user_id, p.full_name, p.email
      ) grouped
    ), '[]'::jsonb),
    'product_breakdown', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', grouped.id,
          'name', grouped.name,
          'total', grouped.total,
          'quantity', grouped.quantity
        ) order by grouped.total desc, grouped.name
      )
      from (
        select p.id, p.name, sum(activity.amount) as total,
               sum(activity.quantity) as quantity
        from (
          select si.variant_id, si.line_total as amount, si.quantity
          from public.sale_items si
          join public.sales s
            on s.id = si.sale_id and s.business_id = si.business_id
          where si.business_id = target_business_id
            and s.status in ('completed', 'partially_refunded', 'refunded')
            and s.completed_at >= period_start and s.completed_at < period_end
            and private.has_branch_access(s.branch_id)
          union all
          select sri.variant_id, -sri.line_total, -sri.quantity
          from public.sale_return_items sri
          join public.sale_returns sr
            on sr.id = sri.return_id and sr.business_id = sri.business_id
          where sri.business_id = target_business_id and sr.status = 'completed'
            and sr.returned_at >= period_start and sr.returned_at < period_end
            and private.has_branch_access(sr.branch_id)
        ) activity
        join public.product_variants pv
          on pv.id = activity.variant_id and pv.business_id = target_business_id
        join public.products p
          on p.id = pv.product_id and p.business_id = pv.business_id
        group by p.id, p.name
        order by total desc, p.name
        limit 20
      ) grouped
    ), '[]'::jsonb),
    'category_breakdown', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', grouped.id,
          'name', grouped.name,
          'total', grouped.total,
          'quantity', grouped.quantity
        ) order by grouped.total desc, grouped.name
      )
      from (
        select p.category_id as id, coalesce(c.name, 'Uncategorized') as name,
               sum(activity.amount) as total,
               sum(activity.quantity) as quantity
        from (
          select si.variant_id, si.line_total as amount, si.quantity
          from public.sale_items si
          join public.sales s
            on s.id = si.sale_id and s.business_id = si.business_id
          where si.business_id = target_business_id
            and s.status in ('completed', 'partially_refunded', 'refunded')
            and s.completed_at >= period_start and s.completed_at < period_end
            and private.has_branch_access(s.branch_id)
          union all
          select sri.variant_id, -sri.line_total, -sri.quantity
          from public.sale_return_items sri
          join public.sale_returns sr
            on sr.id = sri.return_id and sr.business_id = sri.business_id
          where sri.business_id = target_business_id and sr.status = 'completed'
            and sr.returned_at >= period_start and sr.returned_at < period_end
            and private.has_branch_access(sr.branch_id)
        ) activity
        join public.product_variants pv
          on pv.id = activity.variant_id and pv.business_id = target_business_id
        join public.products p
          on p.id = pv.product_id and p.business_id = pv.business_id
        left join public.categories c
          on c.id = p.category_id and c.business_id = p.business_id
        group by p.category_id, c.name
      ) grouped
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

revoke all on function public.get_business_dashboard(uuid, timestamptz, timestamptz)
  from public, anon;
grant execute on function public.get_business_dashboard(uuid, timestamptz, timestamptz)
  to authenticated;


