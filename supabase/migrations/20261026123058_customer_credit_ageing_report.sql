-- Age open customer-credit invoices from their sale date. Repayment
-- allocations reduce their exact invoices, while credit adjustments are
-- applied FIFO to the oldest remaining accessible debt items.

create index if not exists customer_ledger_credit_ageing_idx
  on public.customer_ledger_entries (
    business_id,
    occurred_at,
    branch_id,
    customer_id,
    sale_id
  )
  include (amount)
  where entry_type = 'credit_sale'
    and direction = 'debit'
    and sale_id is not null;

create or replace function public.get_customer_credit_ageing_report(
  target_business_id uuid,
  target_as_of_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $customer_credit_ageing$
declare
  result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not private.has_permission(target_business_id, 'reports.view') then
    raise exception 'Report viewing permission required';
  end if;
  if not private.has_permission(target_business_id, 'customer_credit.view') then
    raise exception 'Customer credit viewing permission required';
  end if;
  if target_as_of_date is null then
    raise exception 'Customer credit ageing date required';
  end if;

  with credit_sales as materialized (
    select
      s.id as sale_id,
      s.invoice_number,
      cle.customer_id,
      s.branch_id,
      b.name as branch_name,
      s.completed_at,
      sum(cle.amount) as credit_amount
    from public.customer_ledger_entries cle
    join public.sales s
      on s.id = cle.sale_id
     and s.business_id = cle.business_id
    join public.branches b
      on b.id = s.branch_id
     and b.business_id = s.business_id
    where cle.business_id = target_business_id
      and cle.entry_type = 'credit_sale'
      and cle.direction = 'debit'
      and cle.sale_id is not null
      and cle.occurred_at < (target_as_of_date + 1)::timestamptz
      and private.has_branch_access(s.branch_id)
    group by
      s.id,
      s.invoice_number,
      cle.customer_id,
      s.branch_id,
      b.name,
      s.completed_at
  ),
  allocated_repayments as materialized (
    select
      allocation.sale_id,
      sum(allocation.amount) as allocated_amount
    from public.customer_receipt_allocations allocation
    join credit_sales sale on sale.sale_id = allocation.sale_id
    where allocation.business_id = target_business_id
      and allocation.created_at < (target_as_of_date + 1)::timestamptz
    group by allocation.sale_id
  ),
  invoice_debts as materialized (
    select
      sale.sale_id as item_id,
      sale.customer_id,
      sale.branch_id,
      sale.branch_name,
      'credit_sale'::text as source_type,
      sale.invoice_number as reference,
      sale.completed_at as originated_at,
      greatest(
        sale.credit_amount - coalesce(repayment.allocated_amount, 0),
        0
      ) as amount
    from credit_sales sale
    left join allocated_repayments repayment
      on repayment.sale_id = sale.sale_id
  ),
  adjustment_debts as materialized (
    select
      entry.id as item_id,
      entry.customer_id,
      entry.branch_id,
      branch.name as branch_name,
      'debit_adjustment'::text as source_type,
      entry.description as reference,
      entry.occurred_at as originated_at,
      entry.amount
    from public.customer_ledger_entries entry
    join public.branches branch
      on branch.id = entry.branch_id
     and branch.business_id = entry.business_id
    where entry.business_id = target_business_id
      and entry.entry_type = 'debit_adjustment'
      and entry.direction = 'debit'
      and entry.occurred_at < (target_as_of_date + 1)::timestamptz
      and private.has_branch_access(entry.branch_id)
  ),
  debt_items as materialized (
    select * from invoice_debts where amount > 0
    union all
    select * from adjustment_debts where amount > 0
  ),
  customer_credit_adjustments as materialized (
    select
      entry.customer_id,
      sum(entry.amount) as amount
    from public.customer_ledger_entries entry
    where entry.business_id = target_business_id
      and entry.entry_type = 'credit_adjustment'
      and entry.direction = 'credit'
      and entry.occurred_at < (target_as_of_date + 1)::timestamptz
      and private.has_branch_access(entry.branch_id)
    group by entry.customer_id
  ),
  debt_sequence as materialized (
    select
      debt.*,
      coalesce(sum(debt.amount) over (
        partition by debt.customer_id
        order by debt.originated_at, debt.item_id
        rows between unbounded preceding and 1 preceding
      ), 0) as older_debt_amount
    from debt_items debt
  ),
  open_items as materialized (
    select
      debt.item_id,
      debt.customer_id,
      debt.branch_id,
      debt.branch_name,
      debt.source_type,
      debt.reference,
      debt.originated_at,
      greatest(
        debt.amount - greatest(
          coalesce(adjustment.amount, 0) - debt.older_debt_amount,
          0
        ),
        0
      ) as outstanding_amount,
      greatest(target_as_of_date - debt.originated_at::date, 0) as age_days
    from debt_sequence debt
    left join customer_credit_adjustments adjustment
      on adjustment.customer_id = debt.customer_id
  ),
  positive_open_items as materialized (
    select * from open_items where outstanding_amount > 0
  ),
  customer_exposure as materialized (
    select
      customer.id,
      customer.code,
      customer.name,
      customer.phone,
      customer.email,
      customer.credit_limit,
      count(*) filter (where item.source_type = 'credit_sale') as open_invoice_count,
      count(*) filter (where item.source_type = 'debit_adjustment') as open_adjustment_count,
      sum(item.outstanding_amount) as outstanding_amount,
      coalesce(sum(item.outstanding_amount) filter (where item.age_days <= 30), 0)
        as age_0_30,
      coalesce(sum(item.outstanding_amount) filter (
        where item.age_days between 31 and 60
      ), 0) as age_31_60,
      coalesce(sum(item.outstanding_amount) filter (
        where item.age_days between 61 and 90
      ), 0) as age_61_90,
      coalesce(sum(item.outstanding_amount) filter (where item.age_days > 90), 0)
        as age_91_plus,
      max(item.age_days) as oldest_age_days,
      sum(item.outstanding_amount * item.age_days)
        / nullif(sum(item.outstanding_amount), 0) as weighted_average_age_days
    from positive_open_items item
    join public.customers customer
      on customer.id = item.customer_id
     and customer.business_id = target_business_id
    group by
      customer.id,
      customer.code,
      customer.name,
      customer.phone,
      customer.email,
      customer.credit_limit
  ),
  unapplied_credit as materialized (
    select coalesce(sum(greatest(
      adjustment.amount - coalesce(debt.total_debt, 0),
      0
    )), 0) as amount
    from customer_credit_adjustments adjustment
    left join (
      select customer_id, sum(amount) as total_debt
      from debt_items
      group by customer_id
    ) debt on debt.customer_id = adjustment.customer_id
  ),
  bucket_definitions(bucket_key, bucket_label, bucket_order) as (
    values
      ('0_30', '0-30 days', 1),
      ('31_60', '31-60 days', 2),
      ('61_90', '61-90 days', 3),
      ('91_plus', '91+ days', 4)
  ),
  bucket_totals as materialized (
    select
      definition.bucket_key,
      definition.bucket_label,
      definition.bucket_order,
      coalesce(sum(item.outstanding_amount) filter (
        where (definition.bucket_key = '0_30' and item.age_days <= 30)
           or (definition.bucket_key = '31_60' and item.age_days between 31 and 60)
           or (definition.bucket_key = '61_90' and item.age_days between 61 and 90)
           or (definition.bucket_key = '91_plus' and item.age_days > 90)
      ), 0) as amount,
      count(distinct item.customer_id) filter (
        where (definition.bucket_key = '0_30' and item.age_days <= 30)
           or (definition.bucket_key = '31_60' and item.age_days between 31 and 60)
           or (definition.bucket_key = '61_90' and item.age_days between 61 and 90)
           or (definition.bucket_key = '91_plus' and item.age_days > 90)
      ) as customer_count,
      count(*) filter (
        where (definition.bucket_key = '0_30' and item.age_days <= 30)
           or (definition.bucket_key = '31_60' and item.age_days between 31 and 60)
           or (definition.bucket_key = '61_90' and item.age_days between 61 and 90)
           or (definition.bucket_key = '91_plus' and item.age_days > 90)
      ) as item_count
    from bucket_definitions definition
    left join positive_open_items item on true
    group by
      definition.bucket_key,
      definition.bucket_label,
      definition.bucket_order
  )
  select jsonb_build_object(
    'as_of_date', target_as_of_date,
    'age_basis', 'credit_sale_or_adjustment_date',
    'total_receivables', coalesce((
      select sum(outstanding_amount) from positive_open_items
    ), 0),
    'customer_count', (select count(*) from customer_exposure),
    'open_invoice_count', coalesce((
      select sum(open_invoice_count) from customer_exposure
    ), 0),
    'open_adjustment_count', coalesce((
      select sum(open_adjustment_count) from customer_exposure
    ), 0),
    'oldest_age_days', (
      select max(oldest_age_days) from customer_exposure
    ),
    'weighted_average_age_days', (
      select sum(outstanding_amount * weighted_average_age_days)
        / nullif(sum(outstanding_amount), 0)
      from customer_exposure
    ),
    'older_than_60_amount', coalesce((
      select sum(outstanding_amount)
      from positive_open_items
      where age_days > 60
    ), 0),
    'older_than_60_rate', (
      select case when sum(outstanding_amount) > 0
        then round(
          sum(outstanding_amount) filter (where age_days > 60)
          / sum(outstanding_amount) * 100,
          2
        )
        else null
      end
      from positive_open_items
    ),
    'total_credit_limit', coalesce((
      select sum(credit_limit) from customer_exposure
    ), 0),
    'credit_limit_utilization', (
      select case when sum(credit_limit) > 0
        then round(sum(outstanding_amount) / sum(credit_limit) * 100, 2)
        else null
      end
      from customer_exposure
    ),
    'over_limit_customer_count', (
      select count(*) from customer_exposure
      where credit_limit > 0 and outstanding_amount > credit_limit
    ),
    'unlimited_customer_count', (
      select count(*) from customer_exposure where credit_limit <= 0
    ),
    'unapplied_credit_adjustments', (
      select amount from unapplied_credit
    ),
    'buckets', (
      select jsonb_agg(
        jsonb_build_object(
          'key', bucket.bucket_key,
          'label', bucket.bucket_label,
          'amount', bucket.amount,
          'customer_count', bucket.customer_count,
          'item_count', bucket.item_count
        ) order by bucket.bucket_order
      )
      from bucket_totals bucket
    ),
    'customers', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', exposure.id,
          'code', exposure.code,
          'name', exposure.name,
          'phone', exposure.phone,
          'email', exposure.email,
          'credit_limit', exposure.credit_limit,
          'outstanding_amount', exposure.outstanding_amount,
          'available_credit', greatest(
            exposure.credit_limit - exposure.outstanding_amount,
            0
          ),
          'over_limit_amount', greatest(
            exposure.outstanding_amount - exposure.credit_limit,
            0
          ),
          'credit_limit_utilization', case when exposure.credit_limit > 0
            then round(
              exposure.outstanding_amount / exposure.credit_limit * 100,
              2
            )
            else null
          end,
          'open_invoice_count', exposure.open_invoice_count,
          'open_adjustment_count', exposure.open_adjustment_count,
          'age_0_30', exposure.age_0_30,
          'age_31_60', exposure.age_31_60,
          'age_61_90', exposure.age_61_90,
          'age_91_plus', exposure.age_91_plus,
          'oldest_age_days', exposure.oldest_age_days,
          'weighted_average_age_days', exposure.weighted_average_age_days
        ) order by
          exposure.outstanding_amount desc,
          exposure.oldest_age_days desc,
          exposure.name
      )
      from (
        select *
        from customer_exposure
        order by outstanding_amount desc, oldest_age_days desc, name
        limit 100
      ) exposure
    ), '[]'::jsonb)
  ) into result;

  return result;
end;
$customer_credit_ageing$;

comment on function public.get_customer_credit_ageing_report(uuid, date) is
  'Returns branch-scoped open customer-credit exposure aged from each sale or adjustment date.';

revoke all on function public.get_customer_credit_ageing_report(uuid, date)
  from public, anon;
grant execute on function public.get_customer_credit_ageing_report(uuid, date)
  to authenticated;
