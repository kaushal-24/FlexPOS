-- Keep accounting RLS explicit: one read policy and separate write policies.
begin;

drop policy if exists accounting_periods_manage on public.accounting_periods;
drop policy if exists accounting_journal_entries_manage on public.accounting_journal_entries;
drop policy if exists accounting_journal_lines_manage on public.accounting_journal_lines;
drop policy if exists accounting_cash_bank_manage on public.accounting_cash_bank_accounts;
drop policy if exists accounting_recurring_manage on public.accounting_recurring_expenses;
drop policy if exists expense_approval_events_manage on public.expense_approval_events;
drop policy if exists expense_attachments_manage on public.expense_attachments;
drop policy if exists accounting_tax_profiles_manage on public.accounting_tax_profiles;

create policy accounting_periods_insert on public.accounting_periods for insert to authenticated
with check ((select private.has_permission(business_id, 'accounting.manage')));
create policy accounting_periods_update on public.accounting_periods for update to authenticated
using ((select private.has_permission(business_id, 'accounting.manage')))
with check ((select private.has_permission(business_id, 'accounting.manage')));
create policy accounting_periods_delete on public.accounting_periods for delete to authenticated
using ((select private.has_permission(business_id, 'accounting.manage')));

create policy accounting_journal_entries_insert on public.accounting_journal_entries for insert to authenticated
with check ((select private.has_permission(business_id, 'accounting.manage')));
create policy accounting_journal_entries_update on public.accounting_journal_entries for update to authenticated
using ((select private.has_permission(business_id, 'accounting.manage')))
with check ((select private.has_permission(business_id, 'accounting.manage')));
create policy accounting_journal_entries_delete on public.accounting_journal_entries for delete to authenticated
using ((select private.has_permission(business_id, 'accounting.manage')));

create policy accounting_journal_lines_insert on public.accounting_journal_lines for insert to authenticated
with check ((select private.has_permission(business_id, 'accounting.manage')));
create policy accounting_journal_lines_update on public.accounting_journal_lines for update to authenticated
using ((select private.has_permission(business_id, 'accounting.manage')))
with check ((select private.has_permission(business_id, 'accounting.manage')));
create policy accounting_journal_lines_delete on public.accounting_journal_lines for delete to authenticated
using ((select private.has_permission(business_id, 'accounting.manage')));

create policy accounting_cash_bank_insert on public.accounting_cash_bank_accounts for insert to authenticated
with check ((select private.has_permission(business_id, 'accounting.manage')));
create policy accounting_cash_bank_update on public.accounting_cash_bank_accounts for update to authenticated
using ((select private.has_permission(business_id, 'accounting.manage')))
with check ((select private.has_permission(business_id, 'accounting.manage')));
create policy accounting_cash_bank_delete on public.accounting_cash_bank_accounts for delete to authenticated
using ((select private.has_permission(business_id, 'accounting.manage')));

create policy accounting_recurring_insert on public.accounting_recurring_expenses for insert to authenticated
with check ((select private.has_permission(business_id, 'expenses.manage')));
create policy accounting_recurring_update on public.accounting_recurring_expenses for update to authenticated
using ((select private.has_permission(business_id, 'expenses.manage')))
with check ((select private.has_permission(business_id, 'expenses.manage')));
create policy accounting_recurring_delete on public.accounting_recurring_expenses for delete to authenticated
using ((select private.has_permission(business_id, 'expenses.manage')));

create policy expense_approval_events_insert on public.expense_approval_events for insert to authenticated
with check ((select private.has_permission(business_id, 'expenses.approve')));

create policy expense_attachments_insert on public.expense_attachments for insert to authenticated
with check ((select private.has_permission(business_id, 'expenses.attachments')));
create policy expense_attachments_delete on public.expense_attachments for delete to authenticated
using ((select private.has_permission(business_id, 'expenses.attachments')));

create policy accounting_tax_profiles_insert on public.accounting_tax_profiles for insert to authenticated
with check ((select private.has_permission(business_id, 'tax.manage')));
create policy accounting_tax_profiles_update on public.accounting_tax_profiles for update to authenticated
using ((select private.has_permission(business_id, 'tax.manage')))
with check ((select private.has_permission(business_id, 'tax.manage')));
create policy accounting_tax_profiles_delete on public.accounting_tax_profiles for delete to authenticated
using ((select private.has_permission(business_id, 'tax.manage')));

commit;
