-- Add server-authoritative net profit and net margin to the existing business
-- dashboard without duplicating its permission checks, branch scoping, or
-- return-adjusted gross-profit calculation.

create or replace function public.get_business_dashboard_with_net_profit(
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
  dashboard jsonb;
  gross_profit numeric;
  expenses_total numeric;
  sales_total numeric;
  net_profit numeric;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not private.has_permission(target_business_id, 'reports.view') then
    raise exception 'Report viewing permission required';
  end if;
  if period_start is null or period_end is null or period_end <= period_start then
    raise exception 'Invalid report period';
  end if;

  dashboard := public.get_business_dashboard(
    target_business_id,
    period_start,
    period_end
  );

  if dashboard -> 'gross_profit' = 'null'::jsonb then
    return dashboard || jsonb_build_object(
      'net_profit', null,
      'net_profit_margin', null
    );
  end if;

  gross_profit := coalesce((dashboard ->> 'gross_profit')::numeric, 0);
  expenses_total := coalesce((dashboard ->> 'expenses_total')::numeric, 0);
  sales_total := coalesce((dashboard ->> 'sales_total')::numeric, 0);
  net_profit := gross_profit - expenses_total;

  return dashboard || jsonb_build_object(
    'net_profit', net_profit,
    'net_profit_margin', case
      when sales_total = 0 then null
      else round((net_profit / sales_total) * 100, 2)
    end
  );
end;
$$;

revoke all on function public.get_business_dashboard_with_net_profit(
  uuid,
  timestamptz,
  timestamptz
) from public, anon;

grant execute on function public.get_business_dashboard_with_net_profit(
  uuid,
  timestamptz,
  timestamptz
) to authenticated;
