-- Explicit, auditable corrections for posted manual journal entries.
begin;

create or replace function public.reverse_journal_entry(
  target_journal_entry_id uuid,
  correction_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  source_entry public.accounting_journal_entries%rowtype;
  target_period public.accounting_periods%rowtype;
  reversal_id uuid := gen_random_uuid();
  reversal_number text;
  actor uuid := auth.uid();
  source_line record;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  select * into source_entry
  from public.accounting_journal_entries
  where id = target_journal_entry_id
  for update;
  if source_entry.id is null then raise exception 'Journal entry not found'; end if;
  if not private.has_permission(source_entry.business_id, 'accounting.manage') then
    raise exception 'Accounting management permission required';
  end if;
  if source_entry.status <> 'posted' then
    raise exception 'Only posted journal entries can be reversed';
  end if;
  if length(btrim(coalesce(correction_reason, ''))) < 3 then
    raise exception 'A correction reason is required';
  end if;
  select * into target_period from public.accounting_periods
  where business_id = source_entry.business_id
    and source_entry.entry_date between starts_on and ends_on
  order by starts_on desc limit 1;
  if target_period.status = 'closed' then raise exception 'Accounting period is closed'; end if;
  select id into reversal_id
  from public.accounting_journal_entries
  where business_id = source_entry.business_id
    and source_type = 'journal_reversal'
    and source_id = source_entry.id;
  if reversal_id is not null then
    return jsonb_build_object('id', reversal_id, 'status', 'already_reversed');
  end if;
  reversal_id := gen_random_uuid();
  reversal_number := 'JE-REV-' || to_char(source_entry.entry_date, 'YYYYMMDD') || '-' || upper(substr(replace(reversal_id::text, '-', ''), 1, 8));
  insert into public.accounting_journal_entries (
    id, business_id, entry_number, entry_date, source_type, source_id, memo, created_by
  ) values (
    reversal_id, source_entry.business_id, reversal_number, current_date,
    'journal_reversal', source_entry.id,
    'Reversal of ' || source_entry.entry_number || ': ' || btrim(correction_reason), actor
  );
  for source_line in
    select account_id, branch_id, description, debit, credit
    from public.accounting_journal_lines
    where journal_entry_id = source_entry.id and business_id = source_entry.business_id
  loop
    insert into public.accounting_journal_lines (
      business_id, journal_entry_id, account_id, branch_id, description, debit, credit
    ) values (
      source_entry.business_id, reversal_id, source_line.account_id, source_line.branch_id,
      'Correction: ' || coalesce(source_line.description, source_entry.memo),
      source_line.credit, source_line.debit
    );
  end loop;
  update public.accounting_journal_entries
  set status = 'void'
  where id = source_entry.id;
  perform private.write_tenant_audit(
    source_entry.business_id, 'accounting.journal_reversed', 'journal_entry',
    source_entry.id::text, jsonb_build_object('reversal_id', reversal_id, 'reason', btrim(correction_reason))
  );
  return jsonb_build_object('id', reversal_id, 'entry_number', reversal_number, 'status', 'reversed');
end;
$$;

revoke all on function public.reverse_journal_entry(uuid, text) from public, anon;
grant execute on function public.reverse_journal_entry(uuid, text) to authenticated;

commit;
