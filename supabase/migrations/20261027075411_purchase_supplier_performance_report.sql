-- Purchase-order and supplier-performance reporting with tenant permission
-- checks, branch scoping, receipt progress, delivery timeliness, and product
-- demand summaries.

create index if not exists purchase_orders_business_ordered_report_idx
  on public.purchase_orders(business_id, ordered_at desc)
  where status <> 'draft';

create or replace function public.get_purchase_supplier_performance_report(
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
     or not private.has_permission(target_business_id, 'purchases.view') then
    raise exception 'Purchase reporting permission required';
  end if;
  if period_start is null or period_end is null or period_end <= period_start then
    raise exception 'Invalid report period';
  end if;

  with orders_scope as (
    select po.id,
           po.branch_id,
           po.supplier_id,
           po.status,
           po.subtotal,
           po.tax_total,
           po.grand_total,
           po.expected_at,
           po.ordered_at,
           po.completed_at
    from public.purchase_orders po
    where po.business_id = target_business_id
      and po.status <> 'draft'
      and po.ordered_at >= period_start
      and po.ordered_at < period_end
      and private.has_branch_access(po.branch_id)
  ),
  item_totals as (
    select poi.purchase_order_id,
           sum(poi.ordered_quantity) as ordered_quantity,
           sum(poi.received_quantity) as received_quantity,
           sum(
             greatest(poi.ordered_quantity - poi.received_quantity, 0)
             * poi.unit_cost
           ) as outstanding_item_cost
    from public.purchase_order_items poi
    join orders_scope po on po.id = poi.purchase_order_id
    where poi.business_id = target_business_id
      and po.status <> 'cancelled'
    group by poi.purchase_order_id
  ),
  receipt_totals as (
    select gr.purchase_order_id,
           count(*) as receipt_count,
           sum(gr.total_cost) as received_cost,
           min(gr.received_at) as first_received_at,
           max(gr.received_at) as last_received_at
    from public.goods_receipts gr
    join orders_scope po on po.id = gr.purchase_order_id
    where gr.business_id = target_business_id
      and gr.status = 'completed'
    group by gr.purchase_order_id
  ),
  order_facts as (
    select po.*,
           coalesce(it.ordered_quantity, 0) as ordered_quantity,
           coalesce(it.received_quantity, 0) as received_quantity,
           coalesce(it.outstanding_item_cost, 0) as outstanding_item_cost,
           coalesce(rt.receipt_count, 0) as receipt_count,
           coalesce(rt.received_cost, 0) as received_cost,
           rt.first_received_at,
           rt.last_received_at
    from orders_scope po
    left join item_totals it on it.purchase_order_id = po.id
    left join receipt_totals rt on rt.purchase_order_id = po.id
  ),
  summary as (
    select count(*) as order_count,
           count(*) filter (where status = 'received') as received_order_count,
           count(*) filter (where status = 'partially_received')
             as partially_received_order_count,
           count(*) filter (where status = 'ordered') as open_order_count,
           count(*) filter (where status = 'cancelled') as cancelled_order_count,
           count(*) filter (
             where status in ('ordered', 'partially_received')
               and expected_at is not null
               and expected_at < now()
           ) as overdue_order_count,
           count(*) filter (
             where status = 'received'
               and expected_at is not null
               and completed_at <= expected_at
           ) as on_time_order_count,
           count(*) filter (
             where status = 'received'
               and expected_at is not null
               and completed_at > expected_at
           ) as late_order_count,
           count(*) filter (
             where status = 'received' and expected_at is not null
           ) as measured_delivery_count,
           coalesce(sum(grand_total) filter (where status <> 'cancelled'), 0)
             as ordered_total,
           coalesce(sum(received_cost), 0) as received_cost,
           coalesce(sum(ordered_quantity), 0) as ordered_quantity,
           coalesce(sum(received_quantity), 0) as received_quantity,
           coalesce(sum(outstanding_item_cost), 0) as outstanding_item_cost,
           coalesce(sum(receipt_count), 0) as receipt_count,
           avg(
             extract(epoch from (completed_at - ordered_at)) / 86400.0
           ) filter (where status = 'received') as average_lead_days
    from order_facts
  )
  select jsonb_build_object(
    'period_start', period_start,
    'period_end', period_end,
    'order_count', s.order_count,
    'received_order_count', s.received_order_count,
    'partially_received_order_count', s.partially_received_order_count,
    'open_order_count', s.open_order_count,
    'cancelled_order_count', s.cancelled_order_count,
    'overdue_order_count', s.overdue_order_count,
    'on_time_order_count', s.on_time_order_count,
    'late_order_count', s.late_order_count,
    'measured_delivery_count', s.measured_delivery_count,
    'on_time_rate', case
      when s.measured_delivery_count = 0 then null
      else round(
        (s.on_time_order_count::numeric / s.measured_delivery_count) * 100,
        2
      )
    end,
    'ordered_total', s.ordered_total,
    'received_cost', s.received_cost,
    'ordered_quantity', s.ordered_quantity,
    'received_quantity', s.received_quantity,
    'outstanding_quantity', greatest(
      s.ordered_quantity - s.received_quantity,
      0
    ),
    'outstanding_item_cost', s.outstanding_item_cost,
    'receipt_count', s.receipt_count,
    'average_lead_days', case
      when s.average_lead_days is null then null
      else round(s.average_lead_days, 2)
    end,
    'suppliers', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'supplier_id', grouped.supplier_id,
          'supplier_name', grouped.supplier_name,
          'order_count', grouped.order_count,
          'received_order_count', grouped.received_order_count,
          'open_order_count', grouped.open_order_count,
          'cancelled_order_count', grouped.cancelled_order_count,
          'overdue_order_count', grouped.overdue_order_count,
          'on_time_order_count', grouped.on_time_order_count,
          'late_order_count', grouped.late_order_count,
          'on_time_rate', grouped.on_time_rate,
          'ordered_total', grouped.ordered_total,
          'received_cost', grouped.received_cost,
          'ordered_quantity', grouped.ordered_quantity,
          'received_quantity', grouped.received_quantity,
          'outstanding_quantity', grouped.outstanding_quantity,
          'average_lead_days', grouped.average_lead_days
        ) order by grouped.ordered_total desc, grouped.supplier_name
      )
      from (
        select supplier.id as supplier_id,
               supplier.name as supplier_name,
               count(*) as order_count,
               count(*) filter (where facts.status = 'received')
                 as received_order_count,
               count(*) filter (
                 where facts.status in ('ordered', 'partially_received')
               ) as open_order_count,
               count(*) filter (where facts.status = 'cancelled')
                 as cancelled_order_count,
               count(*) filter (
                 where facts.status in ('ordered', 'partially_received')
                   and facts.expected_at is not null
                   and facts.expected_at < now()
               ) as overdue_order_count,
               count(*) filter (
                 where facts.status = 'received'
                   and facts.expected_at is not null
                   and facts.completed_at <= facts.expected_at
               ) as on_time_order_count,
               count(*) filter (
                 where facts.status = 'received'
                   and facts.expected_at is not null
                   and facts.completed_at > facts.expected_at
               ) as late_order_count,
               case when count(*) filter (
                 where facts.status = 'received'
                   and facts.expected_at is not null
               ) = 0 then null else round(
                 count(*) filter (
                   where facts.status = 'received'
                     and facts.expected_at is not null
                     and facts.completed_at <= facts.expected_at
                 )::numeric
                 / count(*) filter (
                   where facts.status = 'received'
                     and facts.expected_at is not null
                 ) * 100,
                 2
               ) end as on_time_rate,
               coalesce(sum(facts.grand_total) filter (
                 where facts.status <> 'cancelled'
               ), 0) as ordered_total,
               coalesce(sum(facts.received_cost), 0) as received_cost,
               coalesce(sum(facts.ordered_quantity), 0) as ordered_quantity,
               coalesce(sum(facts.received_quantity), 0) as received_quantity,
               greatest(
                 coalesce(sum(facts.ordered_quantity), 0)
                   - coalesce(sum(facts.received_quantity), 0),
                 0
               ) as outstanding_quantity,
               round(avg(
                 extract(epoch from (facts.completed_at - facts.ordered_at))
                   / 86400.0
               ) filter (where facts.status = 'received'), 2)
                 as average_lead_days
        from order_facts facts
        join public.suppliers supplier
          on supplier.id = facts.supplier_id
         and supplier.business_id = target_business_id
        group by supplier.id, supplier.name
      ) grouped
    ), '[]'::jsonb),
    'products', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'variant_id', grouped.variant_id,
          'product_name', grouped.product_name,
          'variant_name', grouped.variant_name,
          'sku', grouped.sku,
          'supplier_count', grouped.supplier_count,
          'order_count', grouped.order_count,
          'ordered_quantity', grouped.ordered_quantity,
          'received_quantity', grouped.received_quantity,
          'outstanding_quantity', grouped.outstanding_quantity,
          'ordered_item_cost', grouped.ordered_item_cost
        ) order by grouped.ordered_item_cost desc, grouped.product_name,
                   grouped.variant_name
      )
      from (
        select poi.variant_id,
               poi.product_name,
               poi.variant_name,
               poi.sku,
               count(distinct facts.supplier_id) as supplier_count,
               count(distinct facts.id) as order_count,
               sum(poi.ordered_quantity) as ordered_quantity,
               sum(poi.received_quantity) as received_quantity,
               sum(
                 greatest(poi.ordered_quantity - poi.received_quantity, 0)
               ) as outstanding_quantity,
               sum(poi.ordered_quantity * poi.unit_cost) as ordered_item_cost
        from order_facts facts
        join public.purchase_order_items poi
          on poi.purchase_order_id = facts.id
         and poi.business_id = target_business_id
        where facts.status <> 'cancelled'
        group by poi.variant_id, poi.product_name, poi.variant_name, poi.sku
        order by ordered_item_cost desc, poi.product_name, poi.variant_name
        limit 20
      ) grouped
    ), '[]'::jsonb)
  ) into result
  from summary s;

  return result;
end;
$$;

revoke all on function public.get_purchase_supplier_performance_report(
  uuid,
  timestamptz,
  timestamptz
) from public, anon;

grant execute on function public.get_purchase_supplier_performance_report(
  uuid,
  timestamptz,
  timestamptz
) to authenticated;
