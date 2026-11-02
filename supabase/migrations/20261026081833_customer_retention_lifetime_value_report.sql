-- Identified-customer retention and lifetime-value analytics. Walk-in orders
-- remain in the capture-rate denominator but are deliberately excluded from
-- customer retention and LTV because they cannot be linked reliably.

create index if not exists sales_customer_lifetime_idx
  on public.sales (business_id, customer_id, completed_at desc)
  include (branch_id, grand_total)
  where customer_id is not null
    and status in ('completed', 'partially_refunded', 'refunded');

create or replace function public.get_customer_analytics_report(
  target_business_id uuid,
  period_start timestamptz,
  period_end timestamptz
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $customer_analytics$
declare
  result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not private.has_permission(target_business_id, 'reports.view') then
    raise exception 'Report viewing permission required';
  end if;
  if not private.has_permission(target_business_id, 'customers.view') then
    raise exception 'Customer viewing permission required';
  end if;
  if not private.has_permission(target_business_id, 'sales.view') then
    raise exception 'Sales viewing permission required';
  end if;
  if period_start is null or period_end is null or period_end <= period_start then
    raise exception 'Invalid report period';
  end if;
  if period_end - period_start > interval '366 days' then
    raise exception 'Customer analytics period cannot exceed 366 days';
  end if;

  with scoped_sales as materialized (
    select
      s.id,
      s.customer_id,
      s.completed_at,
      s.grand_total
    from public.sales s
    where s.business_id = target_business_id
      and s.customer_id is not null
      and s.status in ('completed', 'partially_refunded', 'refunded')
      and private.has_branch_access(s.branch_id)
  ),
  scoped_returns as materialized (
    select
      sr.id,
      ss.customer_id,
      sr.returned_at,
      sr.refund_total
    from public.sale_returns sr
    join scoped_sales ss on ss.id = sr.sale_id
    where sr.business_id = target_business_id
      and sr.status = 'completed'
      and private.has_branch_access(sr.branch_id)
  ),
  period_order_summary as materialized (
    select
      count(*) as total_orders,
      count(*) filter (where s.customer_id is not null) as identified_orders
    from public.sales s
    where s.business_id = target_business_id
      and s.status in ('completed', 'partially_refunded', 'refunded')
      and s.completed_at >= period_start
      and s.completed_at < period_end
      and private.has_branch_access(s.branch_id)
  ),
  customer_sales as materialized (
    select
      ss.customer_id,
      count(*) as lifetime_order_count,
      sum(ss.grand_total) as lifetime_gross_sales,
      min(ss.completed_at) as first_purchase_at,
      max(ss.completed_at) as last_purchase_at
    from scoped_sales ss
    group by ss.customer_id
  ),
  customer_refunds as materialized (
    select
      sr.customer_id,
      sum(sr.refund_total) as lifetime_refunds
    from scoped_returns sr
    group by sr.customer_id
  ),
  period_sales as materialized (
    select
      ss.customer_id,
      count(*) as period_order_count,
      sum(ss.grand_total) as period_gross_sales
    from scoped_sales ss
    where ss.completed_at >= period_start
      and ss.completed_at < period_end
    group by ss.customer_id
  ),
  period_refunds as materialized (
    select
      sr.customer_id,
      sum(sr.refund_total) as period_refunds
    from scoped_returns sr
    where sr.returned_at >= period_start
      and sr.returned_at < period_end
    group by sr.customer_id
  ),
  customer_metrics as materialized (
    select
      c.id,
      c.name,
      c.phone,
      c.email,
      cs.first_purchase_at,
      cs.last_purchase_at,
      cs.lifetime_order_count,
      cs.lifetime_gross_sales,
      coalesce(cr.lifetime_refunds, 0) as lifetime_refunds,
      cs.lifetime_gross_sales - coalesce(cr.lifetime_refunds, 0)
        as net_lifetime_value,
      (cs.lifetime_gross_sales - coalesce(cr.lifetime_refunds, 0))
        / nullif(cs.lifetime_order_count, 0) as average_order_value,
      coalesce(ps.period_order_count, 0) as period_order_count,
      coalesce(ps.period_gross_sales, 0) - coalesce(pr.period_refunds, 0)
        as period_net_revenue,
      case
        when coalesce(ps.period_order_count, 0) = 0 then 'inactive'
        when cs.first_purchase_at >= period_start
          and cs.first_purchase_at < period_end then 'new'
        else 'returning'
      end as period_status
    from customer_sales cs
    join public.customers c
      on c.id = cs.customer_id and c.business_id = target_business_id
    left join customer_refunds cr on cr.customer_id = cs.customer_id
    left join period_sales ps on ps.customer_id = cs.customer_id
    left join period_refunds pr on pr.customer_id = cs.customer_id
  ),
  customer_activity as materialized (
    select
      ss.customer_id,
      ss.completed_at as occurred_at,
      ss.grand_total as amount
    from scoped_sales ss
    union all
    select
      sr.customer_id,
      sr.returned_at,
      -sr.refund_total
    from scoped_returns sr
  ),
  months as materialized (
    select generate_series(
      date_trunc('month', period_start),
      date_trunc('month', period_end - interval '1 microsecond'),
      interval '1 month'
    )::date as month
  ),
  monthly_metrics as materialized (
    select
      month.month,
      count(distinct sale.customer_id) as active_customers,
      count(distinct sale.customer_id) filter (
        where date_trunc('month', metric.first_purchase_at)::date = month.month
      ) as new_customers,
      count(distinct sale.customer_id) filter (
        where metric.first_purchase_at < month.month::timestamptz
      ) as returning_customers,
      coalesce((
        select sum(activity.amount)
        from customer_activity activity
        where activity.occurred_at >= month.month::timestamptz
          and activity.occurred_at < (month.month + interval '1 month')::timestamptz
      ), 0) as net_revenue
    from months month
    left join scoped_sales sale
      on sale.completed_at >= month.month::timestamptz
     and sale.completed_at < (month.month + interval '1 month')::timestamptz
    left join customer_metrics metric on metric.id = sale.customer_id
    group by month.month
  )
  select jsonb_build_object(
    'period_start', period_start,
    'period_end', period_end,
    'period_days', greatest(
      1,
      ceil(extract(epoch from (period_end - period_start)) / 86400)
    )::integer,
    'total_period_orders', (
      select total_orders from period_order_summary
    ),
    'identified_period_orders', (
      select identified_orders from period_order_summary
    ),
    'walk_in_period_orders', (
      select total_orders - identified_orders from period_order_summary
    ),
    'customer_capture_rate', (
      select case when total_orders > 0
        then round(identified_orders::numeric / total_orders * 100, 2)
        else null
      end
      from period_order_summary
    ),
    'active_customers', (
      select count(*) from customer_metrics where period_order_count > 0
    ),
    'new_customers', (
      select count(*) from customer_metrics where period_status = 'new'
    ),
    'returning_customers', (
      select count(*) from customer_metrics where period_status = 'returning'
    ),
    'repeat_customers', (
      select count(*) from customer_metrics
      where period_order_count > 0 and lifetime_order_count > 1
    ),
    'retention_rate', (
      select case when count(*) filter (where period_order_count > 0) > 0
        then round(
          count(*) filter (where period_status = 'returning')::numeric
          / count(*) filter (where period_order_count > 0) * 100,
          2
        )
        else null
      end
      from customer_metrics
    ),
    'repeat_customer_rate', (
      select case when count(*) filter (where period_order_count > 0) > 0
        then round(
          count(*) filter (
            where period_order_count > 0 and lifetime_order_count > 1
          )::numeric
          / count(*) filter (where period_order_count > 0) * 100,
          2
        )
        else null
      end
      from customer_metrics
    ),
    'lifetime_customer_count', (select count(*) from customer_metrics),
    'total_lifetime_value', coalesce((
      select sum(net_lifetime_value) from customer_metrics
    ), 0),
    'average_lifetime_value', (
      select avg(net_lifetime_value) from customer_metrics
    ),
    'identified_period_net_revenue', coalesce((
      select sum(period_net_revenue) from customer_metrics
    ), 0),
    'monthly_retention', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'month', monthly.month,
          'active_customers', monthly.active_customers,
          'new_customers', monthly.new_customers,
          'returning_customers', monthly.returning_customers,
          'retention_rate', case when monthly.active_customers > 0
            then round(
              monthly.returning_customers::numeric
              / monthly.active_customers * 100,
              2
            )
            else null
          end,
          'net_revenue', monthly.net_revenue
        ) order by monthly.month
      )
      from monthly_metrics monthly
    ), '[]'::jsonb),
    'top_customers', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', ranked.id,
          'name', ranked.name,
          'phone', ranked.phone,
          'email', ranked.email,
          'first_purchase_at', ranked.first_purchase_at,
          'last_purchase_at', ranked.last_purchase_at,
          'lifetime_order_count', ranked.lifetime_order_count,
          'lifetime_gross_sales', ranked.lifetime_gross_sales,
          'lifetime_refunds', ranked.lifetime_refunds,
          'net_lifetime_value', ranked.net_lifetime_value,
          'average_order_value', ranked.average_order_value,
          'period_order_count', ranked.period_order_count,
          'period_net_revenue', ranked.period_net_revenue,
          'period_status', ranked.period_status,
          'lifetime_days', greatest(
            ranked.last_purchase_at::date - ranked.first_purchase_at::date,
            0
          ),
          'days_since_last_purchase', greatest(
            current_date - ranked.last_purchase_at::date,
            0
          )
        ) order by
          ranked.net_lifetime_value desc,
          ranked.last_purchase_at desc,
          ranked.name
      )
      from (
        select *
        from customer_metrics
        order by net_lifetime_value desc, last_purchase_at desc, name
        limit 100
      ) ranked
    ), '[]'::jsonb)
  ) into result;

  return result;
end;
$customer_analytics$;

comment on function public.get_customer_analytics_report(
  uuid, timestamptz, timestamptz
) is 'Returns branch-scoped identified-customer retention and net LTV analytics.';

revoke all on function public.get_customer_analytics_report(
  uuid, timestamptz, timestamptz
) from public, anon;
grant execute on function public.get_customer_analytics_report(
  uuid, timestamptz, timestamptz
) to authenticated;
