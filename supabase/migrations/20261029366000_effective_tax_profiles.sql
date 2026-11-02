-- Make tax-invoice and GST-summary origin-state resolution honor effective profiles.
begin;

create or replace function private.tax_origin_state(
  target_business_id uuid,
  target_branch_id uuid,
  target_date date
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select tp.state_code
      from public.accounting_tax_profiles tp
      where tp.business_id = target_business_id
        and (tp.branch_id = target_branch_id or tp.branch_id is null)
        and tp.effective_from <= target_date
        and (tp.effective_to is null or tp.effective_to >= target_date)
        and tp.is_active
      order by (tp.branch_id is not null) desc, tp.effective_from desc
      limit 1
    ),
    (select nullif(substring(b.tax_registration_number from 1 for 2), '')
     from public.businesses b where b.id = target_business_id)
  )
$$;

create or replace function public.get_tax_invoice_breakdown(target_sale_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  s public.sales%rowtype;
  origin_state text;
  destination_state text;
  interstate boolean;
  tax numeric;
  lines jsonb;
begin
  select * into s from public.sales where id = target_sale_id;
  if s.id is null or not private.has_permission(s.business_id,'tax.view') then
    raise exception 'Tax invoice is not accessible';
  end if;
  origin_state := private.tax_origin_state(s.business_id, s.branch_id, s.completed_at::date);
  select coalesce(
    nullif(substring(c.gstin from 1 for 2), ''),
    (select nullif(substring(tp.default_place_of_supply from 1 for 2), '')
     from public.accounting_tax_profiles tp
     where tp.business_id=s.business_id
       and (tp.branch_id=s.branch_id or tp.branch_id is null)
       and tp.effective_from <= s.completed_at::date
       and (tp.effective_to is null or tp.effective_to >= s.completed_at::date)
       and tp.is_active
     order by (tp.branch_id is not null) desc, tp.effective_from desc limit 1),
    origin_state
  ) into destination_state
  from public.customers c
  where c.id=s.customer_id and c.business_id=s.business_id;
  if destination_state is null then destination_state := origin_state; end if;
  interstate := origin_state is not null and destination_state is not null and origin_state<>destination_state;
  select coalesce(sum(tax_amount),0) into tax from public.sale_items where sale_id=s.id and business_id=s.business_id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'product_name',product_name,'sku',sku,'quantity',quantity,'tax_rate',tax_rate,
    'tax_amount',tax_amount,
    'cgst',case when interstate then 0 else round(tax_amount/2,2) end,
    'sgst',case when interstate then 0 else round(tax_amount-round(tax_amount/2,2),2) end,
    'igst',case when interstate then tax_amount else 0 end
  ) order by created_at),'[]'::jsonb) into lines
  from public.sale_items where sale_id=s.id and business_id=s.business_id;
  return jsonb_build_object(
    'invoice_number',s.invoice_number,'origin_state',origin_state,
    'place_of_supply',destination_state,'interstate',interstate,
    'subtotal',s.subtotal,'tax_total',tax,
    'cgst',case when interstate then 0 else round(tax/2,2) end,
    'sgst',case when interstate then 0 else round(tax-round(tax/2,2),2) end,
    'igst',case when interstate then tax else 0 end,'lines',lines
  );
end;
$$;

create or replace function public.get_gst_summary(target_business_id uuid,period_start timestamptz,period_end timestamptz)
returns jsonb language plpgsql security definer set search_path='' as $$
declare total_tax numeric; intra_tax numeric; inter_tax numeric;
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
  )
  select coalesce(sum(tax_total),0),
    coalesce(sum(tax_total) filter(where origin_state=destination_state or destination_state is null),0),
    coalesce(sum(tax_total) filter(where origin_state<>destination_state and destination_state is not null),0)
  into total_tax,intra_tax,inter_tax from scoped;
  return jsonb_build_object(
    'total_tax',total_tax,'cgst',round(intra_tax/2,2),
    'sgst',round(intra_tax-intra_tax/2,2),'igst',inter_tax,
    'period_start',period_start,'period_end',period_end
  );
end;
$$;

revoke all on function private.tax_origin_state(uuid,uuid,date) from public, anon, authenticated, service_role;
revoke all on function public.get_tax_invoice_breakdown(uuid), public.get_gst_summary(uuid,timestamptz,timestamptz) from public, anon;
grant execute on function public.get_tax_invoice_breakdown(uuid), public.get_gst_summary(uuid,timestamptz,timestamptz) to authenticated;

commit;
