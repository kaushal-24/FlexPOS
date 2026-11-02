-- Permission- and branch-scoped sales discounts, returns, and refund reporting.
-- Promotion attribution is intentionally excluded until sales persist a
-- promotion/campaign identifier.

create or replace function public.get_sales_adjustments_report(
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
    raise exception 'Sales reporting permission required';
  end if;
  if period_start is null or period_end is null or period_end <= period_start then
    raise exception 'Invalid report period';
  end if;

  with sales_scope as (
    select s.id,
           s.branch_id,
           s.subtotal,
           s.discount_total,
           s.grand_total
    from public.sales s
    where s.business_id = target_business_id
      and s.status in ('completed', 'partially_refunded', 'refunded')
      and s.completed_at >= period_start
      and s.completed_at < period_end
      and private.has_branch_access(s.branch_id)
  ),
  line_discounts as (
    select si.sale_id, coalesce(sum(si.discount_amount), 0) as amount
    from public.sale_items si
    join sales_scope s on s.id = si.sale_id
    where si.business_id = target_business_id
    group by si.sale_id
  ),
  sales_summary as (
    select count(*) as sale_count,
           count(*) filter (where s.discount_total > 0) as discounted_sale_count,
           coalesce(sum(s.subtotal), 0) as subtotal,
           coalesce(sum(s.discount_total), 0) as discount_total,
           coalesce(sum(least(s.discount_total, coalesce(ld.amount, 0))), 0)
             as line_discount_total,
           coalesce(sum(greatest(s.discount_total - coalesce(ld.amount, 0), 0)), 0)
             as order_discount_total
    from sales_scope s
    left join line_discounts ld on ld.sale_id = s.id
  ),
  returns_scope as (
    select sr.id,
           sr.return_number,
           sr.branch_id,
           sr.sale_id,
           sr.subtotal,
           sr.discount_total,
           sr.tax_total,
           sr.refund_total,
           sr.reason,
           sr.returned_at
    from public.sale_returns sr
    where sr.business_id = target_business_id
      and sr.status = 'completed'
      and sr.returned_at >= period_start
      and sr.returned_at < period_end
      and private.has_branch_access(sr.branch_id)
  ),
  return_item_totals as (
    select coalesce(sum(sri.quantity), 0) as returned_quantity
    from public.sale_return_items sri
    join returns_scope sr on sr.id = sri.return_id
    where sri.business_id = target_business_id
  ),
  return_summary as (
    select count(*) as return_count,
           coalesce(sum(sr.subtotal), 0) as returned_subtotal,
           coalesce(sum(sr.discount_total), 0) as returned_discount_total,
           coalesce(sum(sr.tax_total), 0) as returned_tax_total,
           coalesce(sum(sr.refund_total), 0) as refund_total
    from returns_scope sr
  ),
  refund_allocations as (
    select sr.id as return_id,
           r.payment_method as method,
           r.status,
           r.amount,
           'payment_refund'::text as allocation_type
    from returns_scope sr
    join public.sale_refunds r
      on r.return_id = sr.id and r.business_id = target_business_id
    union all
    select sr.id,
           'credit_note'::text,
           'issued'::text,
           cn.issued_amount,
           'credit_note'::text
    from returns_scope sr
    join public.credit_notes cn
      on cn.return_id = sr.id and cn.business_id = target_business_id
  ),
  refund_totals as (
    select coalesce(sum(amount) filter (
             where allocation_type = 'payment_refund' and status = 'settled'
           ), 0) as settled_refund_total,
           coalesce(sum(amount) filter (
             where allocation_type = 'payment_refund' and status = 'pending'
           ), 0) as pending_refund_total,
           coalesce(sum(amount) filter (
             where allocation_type = 'payment_refund' and status = 'failed'
           ), 0) as failed_refund_total,
           coalesce(sum(amount) filter (
             where allocation_type = 'credit_note'
           ), 0) as credit_note_total
    from refund_allocations
  )
  select jsonb_build_object(
    'period_start', period_start,
    'period_end', period_end,
    'sale_count', ss.sale_count,
    'discounted_sale_count', ss.discounted_sale_count,
    'sale_subtotal', ss.subtotal,
    'discount_total', ss.discount_total,
    'line_discount_total', ss.line_discount_total,
    'order_discount_total', ss.order_discount_total,
    'discount_rate', case
      when ss.subtotal = 0 then null
      else round((ss.discount_total / ss.subtotal) * 100, 2)
    end,
    'return_count', rs.return_count,
    'returned_quantity', rit.returned_quantity,
    'returned_subtotal', rs.returned_subtotal,
    'returned_discount_total', rs.returned_discount_total,
    'returned_tax_total', rs.returned_tax_total,
    'refund_total', rs.refund_total,
    'settled_refund_total', rt.settled_refund_total,
    'pending_refund_total', rt.pending_refund_total,
    'failed_refund_total', rt.failed_refund_total,
    'credit_note_total', rt.credit_note_total,
    'refund_allocations', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'method', grouped.method,
          'status', grouped.status,
          'amount', grouped.amount,
          'return_count', grouped.return_count
        ) order by grouped.amount desc, grouped.method, grouped.status
      )
      from (
        select method, status, sum(amount) as amount,
               count(distinct return_id) as return_count
        from refund_allocations
        group by method, status
      ) grouped
    ), '[]'::jsonb),
    'return_reasons', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'reason', grouped.reason,
          'return_count', grouped.return_count,
          'refund_total', grouped.refund_total
        ) order by grouped.refund_total desc, grouped.reason
      )
      from (
        select sr.reason, count(*) as return_count,
               sum(sr.refund_total) as refund_total
        from returns_scope sr
        group by sr.reason
        order by refund_total desc, sr.reason
        limit 20
      ) grouped
    ), '[]'::jsonb),
    'returned_products', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'variant_id', grouped.variant_id,
          'product_name', grouped.product_name,
          'variant_name', grouped.variant_name,
          'sku', grouped.sku,
          'quantity', grouped.quantity,
          'return_count', grouped.return_count,
          'refund_total', grouped.refund_total
        ) order by grouped.refund_total desc, grouped.product_name,
                   grouped.variant_name
      )
      from (
        select sri.variant_id,
               sri.product_name,
               sri.variant_name,
               sri.sku,
               sum(sri.quantity) as quantity,
               count(distinct sri.return_id) as return_count,
               sum(sri.line_total) as refund_total
        from public.sale_return_items sri
        join returns_scope sr on sr.id = sri.return_id
        where sri.business_id = target_business_id
        group by sri.variant_id, sri.product_name, sri.variant_name, sri.sku
        order by refund_total desc, sri.product_name, sri.variant_name
        limit 20
      ) grouped
    ), '[]'::jsonb),
    'branch_discounts', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'branch_id', grouped.branch_id,
          'branch_name', grouped.branch_name,
          'sale_count', grouped.sale_count,
          'discounted_sale_count', grouped.discounted_sale_count,
          'sale_subtotal', grouped.sale_subtotal,
          'discount_total', grouped.discount_total,
          'discount_rate', grouped.discount_rate
        ) order by grouped.discount_total desc, grouped.branch_name
      )
      from (
        select b.id as branch_id,
               b.name as branch_name,
               count(*) as sale_count,
               count(*) filter (where s.discount_total > 0)
                 as discounted_sale_count,
               sum(s.subtotal) as sale_subtotal,
               sum(s.discount_total) as discount_total,
               case when sum(s.subtotal) = 0 then null
                 else round((sum(s.discount_total) / sum(s.subtotal)) * 100, 2)
               end as discount_rate
        from sales_scope s
        join public.branches b
          on b.id = s.branch_id and b.business_id = target_business_id
        group by b.id, b.name
      ) grouped
    ), '[]'::jsonb)
  ) into result
  from sales_summary ss
  cross join return_summary rs
  cross join return_item_totals rit
  cross join refund_totals rt;

  return result;
end;
$$;

revoke all on function public.get_sales_adjustments_report(
  uuid,
  timestamptz,
  timestamptz
) from public, anon;

grant execute on function public.get_sales_adjustments_report(
  uuid,
  timestamptz,
  timestamptz
) to authenticated;
