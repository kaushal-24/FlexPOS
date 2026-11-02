-- Include posted sales tax credit/debit notes in tax summaries.
begin;

create or replace function public.get_gst_summary(target_business_id uuid,period_start timestamptz,period_end timestamptz)
returns jsonb language plpgsql security definer set search_path='' as $$
declare total_tax numeric; intra_tax numeric; inter_tax numeric; input_adjustment numeric;
begin
  if not private.has_permission(target_business_id,'tax.view') then
    raise exception 'Tax view permission required';
  end if;
  with scoped as (
    select s.id,s.tax_total,
      private.tax_origin_state(s.business_id,s.branch_id,s.completed_at::date) origin_state,
      coalesce(
        nullif(substring(c.gstin from 1 for 2), ''),
        (select nullif(substring(tp.default_place_of_supply from 1 for 2), '')
         from public.accounting_tax_profiles tp
         where tp.business_id=s.business_id
           and (tp.branch_id=s.branch_id or tp.branch_id is null)
           and tp.effective_from <= s.completed_at::date
           and (tp.effective_to is null or tp.effective_to >= s.completed_at::date)
           and tp.is_active
         order by (tp.branch_id is not null) desc, tp.effective_from desc limit 1),
        private.tax_origin_state(s.business_id,s.branch_id,s.completed_at::date)
      ) destination_state
    from public.sales s
    left join public.customers c on c.id=s.customer_id and c.business_id=s.business_id
    where s.business_id=target_business_id and s.status='completed'
      and s.completed_at>=period_start and s.completed_at<period_end
  ), sales_totals as (
    select coalesce(sum(tax_total),0) total_tax,
      coalesce(sum(tax_total) filter(where origin_state=destination_state or destination_state is null),0) intra_tax,
      coalesce(sum(tax_total) filter(where origin_state<>destination_state and destination_state is not null),0) inter_tax
    from scoped
  ), note_totals as (
    select
      coalesce(sum(case when scope='sales' then (cgst_amount+sgst_amount+igst_amount) * case when note_type='credit' then -1 else 1 end else 0 end),0) output_adjustment,
      coalesce(sum(case when scope='sales' then (cgst_amount+sgst_amount) * case when note_type='credit' then -1 else 1 end else 0 end),0) output_intra_adjustment,
      coalesce(sum(case when scope='sales' then igst_amount * case when note_type='credit' then -1 else 1 end else 0 end),0) output_inter_adjustment,
      coalesce(sum(case when scope='purchase' then (cgst_amount+sgst_amount+igst_amount) * case when note_type='credit' then -1 else 1 end else 0 end),0) input_adjustment
    from public.accounting_tax_adjustment_notes
    where business_id=target_business_id and status='posted' and note_date>=period_start::date and note_date<period_end::date
  )
  select round(s.total_tax+n.output_adjustment,2), round(s.intra_tax+n.output_intra_adjustment,2), round(s.inter_tax+n.output_inter_adjustment,2), round(n.input_adjustment,2)
  into total_tax,intra_tax,inter_tax,input_adjustment
  from sales_totals s cross join note_totals n;
  return jsonb_build_object(
    'total_tax',total_tax,'cgst',round(intra_tax/2,2),
    'sgst',round(intra_tax-intra_tax/2,2),'igst',inter_tax,
    'input_tax_adjustment',input_adjustment,
    'period_start',period_start,'period_end',period_end
  );
end;
$$;

revoke all on function public.get_gst_summary(uuid,timestamptz,timestamptz) from public, anon;
grant execute on function public.get_gst_summary(uuid,timestamptz,timestamptz) to authenticated;

commit;
