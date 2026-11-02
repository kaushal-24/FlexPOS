-- Promotion campaign performance reporting for the reports.view audience.
-- The report is aggregated in Postgres so the client never loads sales history.

create or replace function public.get_promotion_performance_report(
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
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not private.has_permission(target_business_id, 'reports.view')
     or not private.has_permission(target_business_id, 'sales.view') then
    raise exception 'Promotion reporting permission required';
  end if;
  if period_start is null or period_end is null or period_end <= period_start then
    raise exception 'Invalid report period';
  end if;
  if period_end - period_start > interval '366 days' then
    raise exception 'Promotion performance period cannot exceed 366 days';
  end if;

  with redemption_scope as materialized (
    select
      pr.id,
      pr.promotion_id,
      pr.customer_id,
      pr.discount_amount,
      pr.redeemed_at,
      p.branch_id as promotion_branch_id,
      p.code,
      p.name,
      p.discount_type,
      p.discount_value,
      p.usage_limit,
      p.is_active,
      s.id as sale_id,
      s.branch_id,
      s.subtotal,
      s.grand_total,
      s.status as sale_status,
      b.name as branch_name
    from public.promotion_redemptions pr
    join public.promotions p
      on p.id = pr.promotion_id
     and p.business_id = target_business_id
    join public.sales s
      on s.id = pr.sale_id
     and s.business_id = target_business_id
    join public.branches b
      on b.id = s.branch_id
     and b.business_id = target_business_id
    where pr.business_id = target_business_id
      and pr.redeemed_at >= period_start
      and pr.redeemed_at < period_end
      and s.status in ('completed', 'partially_refunded', 'refunded')
      and private.has_branch_access(s.branch_id)
  ),
  campaign_rows as materialized (
    select
      p.id,
      p.code,
      p.name,
      p.branch_id,
      case when p.branch_id is null then 'All branches'
           else coalesce(max(rs.branch_name), max(pb.name), 'Assigned branch') end as branch_name,
      p.discount_type,
      p.discount_value,
      p.usage_limit,
      p.redeemed_count,
      p.is_active,
      count(rs.id) as redemption_count,
      count(distinct rs.customer_id) filter (where rs.customer_id is not null)
        as unique_customer_count,
      coalesce(sum(rs.discount_amount), 0) as discount_total,
      coalesce(sum(rs.subtotal), 0) as attributed_subtotal,
      coalesce(sum(rs.grand_total), 0) as attributed_sales,
      min(rs.redeemed_at) as first_redeemed_at,
      max(rs.redeemed_at) as last_redeemed_at
    from public.promotions p
    left join public.branches pb
      on pb.id = p.branch_id
     and pb.business_id = target_business_id
    left join redemption_scope rs on rs.promotion_id = p.id
    where p.business_id = target_business_id
      and (p.branch_id is null or private.has_branch_access(p.branch_id))
    group by
      p.id, p.code, p.name, p.branch_id, pb.name, p.discount_type,
      p.discount_value, p.usage_limit, p.redeemed_count, p.is_active
  ),
  daily_rows as (
    select
      date_trunc('day', rs.redeemed_at)::date as day,
      count(*) as redemption_count,
      coalesce(sum(rs.discount_amount), 0) as discount_total,
      coalesce(sum(rs.grand_total), 0) as attributed_sales
    from redemption_scope rs
    group by date_trunc('day', rs.redeemed_at)::date
  ),
  totals as (
    select
      count(*) filter (where cr.redemption_count > 0) as campaigns_used,
      count(*) filter (where cr.is_active) as active_campaign_count,
      coalesce(sum(cr.redemption_count), 0) as redemption_count,
      (select count(distinct rs.customer_id)
       from redemption_scope rs
       where rs.customer_id is not null) as unique_customer_count,
      coalesce(sum(cr.discount_total), 0) as discount_total,
      coalesce(sum(cr.attributed_subtotal), 0) as attributed_subtotal,
      coalesce(sum(cr.attributed_sales), 0) as attributed_sales
    from campaign_rows cr
  )
  select jsonb_build_object(
    'period_start', period_start,
    'period_end', period_end,
    'promotion_count', (select count(*) from campaign_rows),
    'active_promotion_count', totals.active_campaign_count,
    'campaigns_used', totals.campaigns_used,
    'redemption_count', totals.redemption_count,
    'unique_customer_count', totals.unique_customer_count,
    'discount_total', totals.discount_total,
    'attributed_subtotal', totals.attributed_subtotal,
    'attributed_sales', totals.attributed_sales,
    'average_order_value', case
      when totals.redemption_count = 0 then null
      else round(totals.attributed_sales / totals.redemption_count, 2)
    end,
    'discount_rate', case
      when totals.attributed_subtotal = 0 then null
      else round(totals.discount_total / totals.attributed_subtotal * 100, 2)
    end,
    'campaigns', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'promotion_id', cr.id,
          'code', cr.code,
          'name', cr.name,
          'branch_id', cr.branch_id,
          'branch_name', cr.branch_name,
          'discount_type', cr.discount_type,
          'discount_value', cr.discount_value,
          'usage_limit', cr.usage_limit,
          'redeemed_count', cr.redeemed_count,
          'is_active', cr.is_active,
          'redemption_count', cr.redemption_count,
          'unique_customer_count', cr.unique_customer_count,
          'discount_total', cr.discount_total,
          'attributed_subtotal', cr.attributed_subtotal,
          'attributed_sales', cr.attributed_sales,
          'average_order_value', case when cr.redemption_count = 0 then null
            else round(cr.attributed_sales / cr.redemption_count, 2) end,
          'discount_rate', case when cr.attributed_subtotal = 0 then null
            else round(cr.discount_total / cr.attributed_subtotal * 100, 2) end,
          'first_redeemed_at', cr.first_redeemed_at,
          'last_redeemed_at', cr.last_redeemed_at
        ) order by cr.attributed_sales desc, cr.redemption_count desc, cr.name
      )
      from campaign_rows cr
    ), '[]'::jsonb),
    'daily', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'day', dr.day,
          'redemption_count', dr.redemption_count,
          'discount_total', dr.discount_total,
          'attributed_sales', dr.attributed_sales
        ) order by dr.day
      )
      from daily_rows dr
    ), '[]'::jsonb)
  ) into result
  from totals;

  return result;
end;
$$;

revoke all on function public.get_promotion_performance_report(
  uuid, timestamptz, timestamptz
) from public, anon, authenticated;
grant execute on function public.get_promotion_performance_report(
  uuid, timestamptz, timestamptz
) to authenticated;

comment on function public.get_promotion_performance_report(uuid, timestamptz, timestamptz)
is 'Branch-scoped campaign performance metrics for completed coupon-attributed sales.';
