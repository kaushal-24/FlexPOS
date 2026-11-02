-- Read-only financial statement summaries for the accounting workspace.
-- Operational-to-GL posting remains an explicit, staged workflow so existing
-- sales/purchasing data cannot be duplicated by an automatic trigger.
begin;

insert into public.accounting_accounts (business_id, code, name, account_type, is_system)
select b.id, '1300', 'GST input credit', 'asset', true
from public.businesses b
on conflict (business_id, code) do nothing;

create or replace function public.get_financial_statements(
  target_business_id uuid,
  period_start date,
  period_end date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  profit_loss jsonb;
  balance_sheet jsonb;
  cash_flow jsonb;
begin
  if not private.has_permission(target_business_id, 'accounting.view') then
    raise exception 'Accounting view permission required';
  end if;
  if period_end < period_start then
    raise exception 'Statement dates are invalid';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'code', q.code, 'name', q.name, 'account_type', q.account_type, 'amount', q.amount
  ) order by q.code), '[]'::jsonb)
  into profit_loss
  from (
    select a.code, a.name, a.account_type,
      round(case when a.account_type = 'revenue'
        then sum(l.credit - l.debit) else sum(l.debit - l.credit) end, 2) as amount
    from public.accounting_accounts a
    join public.accounting_journal_lines l
      on l.account_id = a.id and l.business_id = a.business_id
    join public.accounting_journal_entries e
      on e.id = l.journal_entry_id and e.business_id = l.business_id
    where a.business_id = target_business_id
      and a.account_type in ('revenue', 'expense')
      and e.status = 'posted'
      and e.entry_date between period_start and period_end
    group by a.id, a.code, a.name, a.account_type
  ) q;

  select coalesce(jsonb_agg(jsonb_build_object(
    'code', q.code, 'name', q.name, 'account_type', q.account_type, 'amount', q.amount
  ) order by q.code), '[]'::jsonb)
  into balance_sheet
  from (
    select a.code, a.name, a.account_type,
      round(case when a.account_type in ('liability', 'equity')
        then sum(l.credit - l.debit) else sum(l.debit - l.credit) end, 2) as amount
    from public.accounting_accounts a
    join public.accounting_journal_lines l
      on l.account_id = a.id and l.business_id = a.business_id
    join public.accounting_journal_entries e
      on e.id = l.journal_entry_id and e.business_id = l.business_id
    where a.business_id = target_business_id
      and a.account_type in ('asset', 'liability', 'equity')
      and e.status = 'posted'
      and e.entry_date <= period_end
    group by a.id, a.code, a.name, a.account_type
  ) q;

  select jsonb_build_object(
    'cash_and_bank', coalesce(sum(l.debit - l.credit), 0),
    'net_change', coalesce(sum(l.debit - l.credit), 0)
  )
  into cash_flow
  from public.accounting_journal_lines l
  join public.accounting_journal_entries e
    on e.id = l.journal_entry_id and e.business_id = l.business_id
  join public.accounting_accounts a
    on a.id = l.account_id and a.business_id = l.business_id
  where l.business_id = target_business_id
    and a.code in ('1000', '1010')
    and e.status = 'posted'
    and e.entry_date between period_start and period_end;

  return jsonb_build_object(
    'period_start', period_start,
    'period_end', period_end,
    'profit_loss', profit_loss,
    'balance_sheet', balance_sheet,
    'cash_flow', cash_flow,
    'source', 'posted journal entries'
  );
end;
$$;

revoke all on function public.get_financial_statements(uuid, date, date) from public, anon;
grant execute on function public.get_financial_statements(uuid, date, date) to authenticated;

commit;
