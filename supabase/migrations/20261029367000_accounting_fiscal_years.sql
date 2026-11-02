-- Explicit fiscal-year boundaries for period reporting and close planning.
begin;

create table if not exists public.accounting_fiscal_years (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  label text not null check (length(btrim(label)) between 2 and 80),
  starts_on date not null,
  ends_on date not null,
  status text not null default 'open' check (status in ('open','closed')),
  closed_at timestamptz,
  closed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (business_id, starts_on, ends_on),
  check (ends_on >= starts_on)
);

create index if not exists accounting_fiscal_years_business_start_idx
  on public.accounting_fiscal_years(business_id, starts_on desc);
create index if not exists accounting_fiscal_years_closed_by_idx
  on public.accounting_fiscal_years(closed_by);

alter table public.accounting_fiscal_years enable row level security;
create policy accounting_fiscal_years_select on public.accounting_fiscal_years
  for select to authenticated using ((select private.has_permission(business_id, 'accounting.view')));
create policy accounting_fiscal_years_insert on public.accounting_fiscal_years
  for insert to authenticated with check ((select private.has_permission(business_id, 'accounting.manage')));
create policy accounting_fiscal_years_update on public.accounting_fiscal_years
  for update to authenticated using ((select private.has_permission(business_id, 'accounting.manage')))
  with check ((select private.has_permission(business_id, 'accounting.manage')));
create policy accounting_fiscal_years_delete on public.accounting_fiscal_years
  for delete to authenticated using ((select private.has_permission(business_id, 'accounting.manage')));
grant select, insert, update, delete on public.accounting_fiscal_years to authenticated;
revoke all on public.accounting_fiscal_years from anon;

create or replace function public.create_accounting_fiscal_year(
  target_business_id uuid,
  target_label text,
  target_starts_on date,
  target_ends_on date
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare fiscal_year_id uuid;
begin
  if not private.has_permission(target_business_id, 'accounting.manage') then
    raise exception 'Accounting management permission required';
  end if;
  if target_ends_on < target_starts_on then raise exception 'Fiscal-year dates are invalid'; end if;
  insert into public.accounting_fiscal_years(business_id,label,starts_on,ends_on)
  values(target_business_id,btrim(target_label),target_starts_on,target_ends_on)
  returning id into fiscal_year_id;
  return fiscal_year_id;
end;
$$;

revoke all on function public.create_accounting_fiscal_year(uuid,text,date,date) from public, anon;
grant execute on function public.create_accounting_fiscal_year(uuid,text,date,date) to authenticated;

commit;
