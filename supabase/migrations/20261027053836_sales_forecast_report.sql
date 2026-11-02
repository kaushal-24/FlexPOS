-- Branch-scoped sales forecasting using historical net sales, weekday
-- seasonality, and a linear daily trend. The estimate range is derived from
-- historical model residuals and is intentionally presented as indicative.

create or replace function public.get_sales_forecast_report(
  target_business_id uuid,
  history_start timestamptz,
  history_end timestamptz,
  history_starts_on date,
  history_ends_on date,
  forecast_days integer default 30
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $sales_forecast$
declare
  result jsonb;
  history_days integer;
  business_timezone text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not private.has_permission(target_business_id, 'reports.view') then
    raise exception 'Report viewing permission required';
  end if;
  if not private.has_permission(target_business_id, 'sales.view') then
    raise exception 'Sales viewing permission required';
  end if;
  if history_start is null or history_end is null or history_end <= history_start then
    raise exception 'Invalid forecast history period';
  end if;
  if history_starts_on is null or history_ends_on is null
     or history_ends_on < history_starts_on then
    raise exception 'Invalid forecast history dates';
  end if;

  history_days := history_ends_on - history_starts_on + 1;
  if history_days < 7 or history_days > 366 then
    raise exception 'Forecast history must contain between 7 and 366 days';
  end if;
  if forecast_days is null or forecast_days < 1 or forecast_days > 90 then
    raise exception 'Forecast horizon must contain between 1 and 90 days';
  end if;

  select business.timezone
  into business_timezone
  from public.businesses business
  where business.id = target_business_id
    and business.archived_at is null;

  if business_timezone is null then
    raise exception 'Active business not found';
  end if;

  result := (
  with accessible_branches as materialized (
    select branch.id
    from public.branches branch
    where branch.business_id = target_business_id
      and branch.is_active
      and branch.archived_at is null
      and private.has_branch_access(branch.id)
  ),
  history_calendar as materialized (
    select day::date as day
    from pg_catalog.generate_series(
      history_starts_on::timestamp,
      history_ends_on::timestamp,
      interval '1 day'
    ) day
  ),
  sales_activity as materialized (
    select
      (sale.completed_at at time zone business_timezone)::date as day,
      sale.grand_total as amount,
      1::bigint as orders
    from public.sales sale
    join accessible_branches branch on branch.id = sale.branch_id
    where sale.business_id = target_business_id
      and sale.status in ('completed', 'partially_refunded', 'refunded')
      and sale.completed_at >= history_start
      and sale.completed_at < history_end
    union all
    select
      (return_entry.returned_at at time zone business_timezone)::date,
      -return_entry.refund_total,
      0::bigint
    from public.sale_returns return_entry
    join accessible_branches branch on branch.id = return_entry.branch_id
    where return_entry.business_id = target_business_id
      and return_entry.status = 'completed'
      and return_entry.returned_at >= history_start
      and return_entry.returned_at < history_end
  ),
  daily_history as materialized (
    select
      calendar.day,
      coalesce(sum(activity.amount), 0)::numeric as net_sales,
      coalesce(sum(activity.orders), 0)::bigint as orders
    from history_calendar calendar
    left join sales_activity activity on activity.day = calendar.day
    group by calendar.day
  ),
  indexed_history as materialized (
    select
      daily.day,
      daily.net_sales,
      daily.orders,
      (row_number() over (order by daily.day) - 1)::double precision as day_index,
      extract(isodow from daily.day)::integer as weekday
    from daily_history daily
  ),
  regression as materialized (
    select
      count(*)::integer as day_count,
      count(*) filter (where history.net_sales <> 0)::integer as active_days,
      sum(history.net_sales)::numeric as total_sales,
      sum(history.orders)::bigint as total_orders,
      avg(history.net_sales)::numeric as average_daily_sales,
      coalesce(
        regr_slope(
          history.net_sales::double precision,
          history.day_index
        ),
        0
      )::numeric as daily_slope,
      coalesce(
        regr_intercept(
          history.net_sales::double precision,
          history.day_index
        ),
        avg(history.net_sales)::double precision
      )::numeric as intercept
    from indexed_history history
  ),
  weekday_profiles as materialized (
    select
      history.weekday,
      (
        sum(history.net_sales) + regression.average_daily_sales * 2
      ) / (count(*) + 2)::numeric as average_sales
    from indexed_history history
    cross join regression
    group by history.weekday, regression.average_daily_sales
  ),
  residuals as materialized (
    select
      history.net_sales - (
        regression.intercept
        + regression.daily_slope * history.day_index
      ) as residual
    from indexed_history history
    cross join regression
  ),
  model_quality as materialized (
    select
      sqrt(coalesce(avg(residual * residual), 0))::numeric as residual_rmse
    from residuals
  ),
  forecast_calendar as materialized (
    select
      day_offset,
      history_ends_on + day_offset as day,
      (history_days - 1 + day_offset)::numeric as day_index
    from pg_catalog.generate_series(1, forecast_days) day_offset
  ),
  forecast_estimates as materialized (
    select
      calendar.day,
      greatest(
        0,
        case
          when regression.day_count >= 28 and regression.active_days >= 7
            then regression.intercept
              + regression.daily_slope * calendar.day_index
          else regression.average_daily_sales
        end * case
          when regression.average_daily_sales <> 0
            then coalesce(profile.average_sales, regression.average_daily_sales)
              / regression.average_daily_sales
          else 1
        end
      )::numeric as estimate,
      quality.residual_rmse
    from forecast_calendar calendar
    cross join regression
    cross join model_quality quality
    left join weekday_profiles profile
      on profile.weekday = extract(isodow from calendar.day)::integer
  ),
  forecast_values as materialized (
    select
      estimate.day,
      round(estimate.estimate, 2) as estimate,
      round(greatest(0, estimate.estimate - 1.96 * estimate.residual_rmse), 2)
        as lower_estimate,
      round(estimate.estimate + 1.96 * estimate.residual_rmse, 2)
        as upper_estimate
    from forecast_estimates estimate
  ),
  forecast_totals as materialized (
    select
      sum(forecast.estimate)::numeric as projected_sales,
      greatest(
        0,
        sum(forecast.estimate)
          - 1.96 * quality.residual_rmse * sqrt(forecast_days::numeric)
      )::numeric as projected_low,
      (
        sum(forecast.estimate)
          + 1.96 * quality.residual_rmse * sqrt(forecast_days::numeric)
      )::numeric as projected_high,
      avg(forecast.estimate)::numeric as projected_daily_average
    from forecast_values forecast
    cross join model_quality quality
    group by quality.residual_rmse
  )
  select jsonb_build_object(
    'history_start', history_starts_on,
    'history_end', history_ends_on,
    'history_days', history_days,
    'forecast_start', history_ends_on + 1,
    'forecast_end', history_ends_on + forecast_days,
    'forecast_days', forecast_days,
    'method', 'weekday_seasonality_linear_trend',
    'range_method', 'approximate_95_percent_residual_range',
    'data_quality', case
      when regression.day_count < 28 or regression.active_days < 7 then 'limited'
      when regression.active_days < regression.day_count * 0.25 then 'sparse'
      else 'sufficient'
    end,
    'active_history_days', regression.active_days,
    'historical_sales', regression.total_sales,
    'historical_orders', regression.total_orders,
    'historical_daily_average', round(regression.average_daily_sales, 2),
    'daily_trend_amount', case
      when regression.day_count >= 28 and regression.active_days >= 7
        then round(regression.daily_slope, 2)
      else null
    end,
    'trend_direction', case
      when regression.day_count < 28 or regression.active_days < 7
        then 'insufficient_data'
      when regression.daily_slope
        > greatest(abs(regression.average_daily_sales) * 0.005, 0.01)
        then 'rising'
      when regression.daily_slope
        < -greatest(abs(regression.average_daily_sales) * 0.005, 0.01)
        then 'falling'
      else 'stable'
    end,
    'residual_rmse', round(model_quality.residual_rmse, 2),
    'projected_sales', round(forecast_totals.projected_sales, 2),
    'projected_low', round(forecast_totals.projected_low, 2),
    'projected_high', round(forecast_totals.projected_high, 2),
    'projected_daily_average', round(
      forecast_totals.projected_daily_average,
      2
    ),
    'projected_change_rate', case
      when regression.average_daily_sales <> 0 then round(
        (
          forecast_totals.projected_daily_average
          - regression.average_daily_sales
        ) / abs(regression.average_daily_sales) * 100,
        2
      )
      else null
    end,
    'history', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'date', history.day,
          'actual_sales', history.net_sales,
          'orders', history.orders
        ) order by history.day
      )
      from daily_history history
    ), '[]'::jsonb),
    'forecast', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'date', forecast.day,
          'estimate', forecast.estimate,
          'lower_estimate', forecast.lower_estimate,
          'upper_estimate', forecast.upper_estimate
        ) order by forecast.day
      )
      from forecast_values forecast
    ), '[]'::jsonb)
  )
  from regression
  cross join model_quality
  cross join forecast_totals
  );

  return result;
end;
$sales_forecast$;

comment on function public.get_sales_forecast_report(
  uuid, timestamptz, timestamptz, date, date, integer
) is 'Returns a branch-scoped sales forecast with weekday seasonality, linear trend, and an indicative residual range.';

revoke all on function public.get_sales_forecast_report(
  uuid, timestamptz, timestamptz, date, date, integer
) from public, anon, authenticated;

grant execute on function public.get_sales_forecast_report(
  uuid, timestamptz, timestamptz, date, date, integer
) to authenticated;
