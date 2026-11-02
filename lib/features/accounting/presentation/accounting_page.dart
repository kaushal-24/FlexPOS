import 'dart:convert';

import 'package:flexpos/core/utils/money.dart';
import 'package:flexpos/core/security/crud_permissions.dart';
import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/core/widgets/data_page_skeleton.dart';
import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/core/widgets/status_badge.dart';
import 'package:flexpos/features/accounting/data/accounting_repository.dart';
import 'package:flexpos/features/tenants/domain/business_workspace.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

class AccountingPage extends ConsumerStatefulWidget {
  const AccountingPage({super.key});

  @override
  ConsumerState<AccountingPage> createState() => _AccountingPageState();
}

class _AccountingPageState extends ConsumerState<AccountingPage> {
  late DateTime _asOf;
  Future<List<Map<String, dynamic>>>? _trialBalance;
  Future<Map<String, dynamic>>? _gstSummary;
  Future<Map<String, dynamic>>? _financialStatements;

  @override
  void initState() {
    super.initState();
    _asOf = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    if (workspace == null) {
      return const EmptyState(
        icon: Icons.account_balance_outlined,
        title: 'Select a business',
        message: 'A workspace is required to manage accounting.',
      );
    }
    if (!workspace.canRead('accounting')) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Accounting is restricted',
        message: 'Your role does not include accounting permission.',
      );
    }
    final accounts = ref.watch(accountingAccountsProvider);
    final journalEntries = ref.watch(accountingJournalEntriesProvider);
    final fiscalYears = ref.watch(accountingFiscalYearsProvider);
    final cashBank = ref.watch(cashBankAccountsProvider);
    final recurring = ref.watch(recurringExpensesProvider);
    final taxProfiles = ref.watch(taxProfilesProvider);
    final subledgerPostings = ref.watch(accountingSubledgerPostingsProvider);
    final bankReconciliations = ref.watch(bankReconciliationsProvider);
    final taxAdjustmentNotes = ref.watch(taxAdjustmentNotesProvider);
    if (accounts.isLoading ||
        journalEntries.isLoading ||
        fiscalYears.isLoading ||
        cashBank.isLoading ||
        recurring.isLoading ||
        taxProfiles.isLoading ||
        subledgerPostings.isLoading ||
        bankReconciliations.isLoading ||
        taxAdjustmentNotes.isLoading) {
      return const DataPageSkeleton(sectionLabel: 'accounting');
    }
    final error =
        accounts.error ??
        journalEntries.error ??
        fiscalYears.error ??
        cashBank.error ??
        recurring.error ??
        taxProfiles.error ??
        subledgerPostings.error ??
        bankReconciliations.error ??
        taxAdjustmentNotes.error;
    if (error != null) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load accounting',
        message: error.toString(),
        action: FilledButton.icon(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      );
    }
    final accountRows = accounts.value ?? const <Map<String, dynamic>>[];
    final journalRows = journalEntries.value ?? const <Map<String, dynamic>>[];
    final fiscalYearRows = fiscalYears.value ?? const <Map<String, dynamic>>[];
    final cashRows = cashBank.value ?? const <Map<String, dynamic>>[];
    final recurringRows = recurring.value ?? const <Map<String, dynamic>>[];
    final taxRows = taxProfiles.value ?? const <Map<String, dynamic>>[];
    final postingRows =
        subledgerPostings.value ?? const <Map<String, dynamic>>[];
    final reconciliationRows =
        bankReconciliations.value ?? const <Map<String, dynamic>>[];
    final taxNoteRows =
        taxAdjustmentNotes.value ?? const <Map<String, dynamic>>[];
    final canCreate = workspace.canCreate('accounting');
    final canUpdate = workspace.canUpdate('accounting');
    final canManage = canUpdate;
    final canExpenseManage = workspace.canManage('expenses');
    final canTaxManage = workspace.canManage('tax');

    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Accounting and tax',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Chart of accounts, journals, periods, cash/bank, recurring expenses, and GST summaries',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (canManage || canExpenseManage || canTaxManage)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (canCreate)
                      OutlinedButton.icon(
                        onPressed: () => _createAccount(context, workspace),
                        icon: const Icon(Icons.account_tree_outlined),
                        label: const Text('New account'),
                      ),
                    if (canCreate)
                      OutlinedButton.icon(
                        onPressed: () => _createFiscalYear(context, workspace),
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: const Text('Fiscal year'),
                      ),
                    if (canCreate)
                      OutlinedButton.icon(
                        onPressed: () =>
                            _createCashBank(context, workspace, accountRows),
                        icon: const Icon(Icons.account_balance_wallet_outlined),
                        label: const Text('Cash / bank'),
                      ),
                    if (canUpdate)
                      FilledButton.tonalIcon(
                        onPressed: () => _syncOperationalLedger(
                          context,
                          workspace.businessId,
                        ),
                        icon: const Icon(Icons.sync_rounded),
                        label: const Text('Post operational entries'),
                      ),
                    if (workspace.canCreate('expenses'))
                      FilledButton.tonalIcon(
                        onPressed: () => _createRecurring(context, workspace),
                        icon: const Icon(Icons.repeat_rounded),
                        label: const Text('Recurring expense'),
                      ),
                    if (workspace.canCreate('tax'))
                      OutlinedButton.icon(
                        onPressed: () => _createTaxProfile(context, workspace),
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('Tax profile'),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 24),
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Trial balance',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _loadTrialBalance(workspace.businessId),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
                Text(
                  'As of ${DateFormat.yMMMd().format(_asOf)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (_trialBalance == null)
                  const Text('Refresh to load posted journal balances.')
                else
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _trialBalance,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const LinearProgressIndicator();
                      }
                      if (snapshot.hasError)
                        return Text(snapshot.error.toString());
                      final rows =
                          snapshot.data ?? const <Map<String, dynamic>>[];
                      if (rows.isEmpty)
                        return const Text('No posted journal entries yet.');
                      return Column(
                        children: [
                          for (final row in rows)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text('${row['code']} • ${row['name']}'),
                              subtitle: Text(
                                '${row['account_type']} • Debit ${formatMoney(workspace.currencyCode, _minor(row['debit']))} • Credit ${formatMoney(workspace.currencyCode, _minor(row['credit']))}',
                              ),
                              trailing: Text(
                                formatMoney(
                                  workspace.currencyCode,
                                  _minor(row['balance']),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                if (canManage) ...[
                  const Divider(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      onPressed: () =>
                          _createJournalEntry(context, workspace, accountRows),
                      icon: const Icon(Icons.post_add_rounded),
                      label: const Text('Post journal entry'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GST summary',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Tax is split into CGST/SGST for intra-state supplies and IGST for inter-state supplies.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Current calendar year',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _loadGstSummary(workspace.businessId),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
                if (_gstSummary == null)
                  const Text('Refresh to load GST totals.')
                else
                  FutureBuilder<Map<String, dynamic>>(
                    future: _gstSummary,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting)
                        return const LinearProgressIndicator();
                      if (snapshot.hasError)
                        return Text(snapshot.error.toString());
                      final row = snapshot.data ?? const <String, dynamic>{};
                      return Wrap(
                        spacing: 24,
                        runSpacing: 12,
                        children: [
                          _Metric(
                            label: 'Total tax',
                            value: formatMoney(
                              workspace.currencyCode,
                              _minor(row['total_tax']),
                            ),
                          ),
                          _Metric(
                            label: 'CGST',
                            value: formatMoney(
                              workspace.currencyCode,
                              _minor(row['cgst']),
                            ),
                          ),
                          _Metric(
                            label: 'SGST',
                            value: formatMoney(
                              workspace.currencyCode,
                              _minor(row['sgst']),
                            ),
                          ),
                          _Metric(
                            label: 'IGST',
                            value: formatMoney(
                              workspace.currencyCode,
                              _minor(row['igst']),
                            ),
                          ),
                          _Metric(
                            label: 'Input tax adjustments',
                            value: formatMoney(
                              workspace.currencyCode,
                              _minor(row['input_tax_adjustment']),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _exportGstSummary(row),
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('Export GST CSV'),
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Financial statements',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          _loadFinancialStatements(workspace.businessId),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
                Text(
                  'Net profit and statements are backed by posted journal entries. Use Post operational entries after reviewing source records.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (_financialStatements == null)
                  const Text(
                    'Refresh to load profit and loss, balance sheet, and cash-flow totals.',
                  )
                else
                  FutureBuilder<Map<String, dynamic>>(
                    future: _financialStatements,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const LinearProgressIndicator();
                      }
                      if (snapshot.hasError)
                        return Text(snapshot.error.toString());
                      final data = snapshot.data ?? const <String, dynamic>{};
                      final cashFlow = Map<String, dynamic>.from(
                        data['cash_flow'] as Map? ?? const {},
                      );
                      final profitRows =
                          (data['profit_loss'] as List? ?? const [])
                              .map(
                                (row) => Map<String, dynamic>.from(row as Map),
                              )
                              .toList(growable: false);
                      final balanceRows =
                          (data['balance_sheet'] as List? ?? const [])
                              .map(
                                (row) => Map<String, dynamic>.from(row as Map),
                              )
                              .toList(growable: false);
                      return Wrap(
                        spacing: 24,
                        runSpacing: 12,
                        children: [
                          _Metric(
                            label: 'Revenue',
                            value: formatMoney(
                              workspace.currencyCode,
                              _statementTotal(profitRows, 'revenue'),
                            ),
                          ),
                          _Metric(
                            label: 'Expenses',
                            value: formatMoney(
                              workspace.currencyCode,
                              _statementTotal(profitRows, 'expense'),
                            ),
                          ),
                          _Metric(
                            label: 'Net profit',
                            value: formatMoney(
                              workspace.currencyCode,
                              _statementTotal(profitRows, 'revenue') -
                                  _statementTotal(profitRows, 'expense'),
                            ),
                          ),
                          _Metric(
                            label: 'Cash flow',
                            value: formatMoney(
                              workspace.currencyCode,
                              _minor(cashFlow['net_change']),
                            ),
                          ),
                          _Metric(
                            label: 'Balance-sheet lines',
                            value: '${balanceRows.length}',
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _ListPanel(
            title: 'Fiscal years',
            emptyText: 'No fiscal years configured.',
            children: [
              for (final year in fiscalYearRows)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: Text(year['label'] as String? ?? ''),
                  subtitle: Text('${year['starts_on']} → ${year['ends_on']}'),
                  trailing: Wrap(
                    spacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusBadge(
                        label: year['status'] as String? ?? 'open',
                        tone: year['status'] == 'closed'
                            ? StatusTone.warning
                            : StatusTone.success,
                      ),
                      if (canManage && year['status'] == 'open') ...[
                        IconButton(
                          tooltip: 'Edit fiscal year',
                          onPressed: () =>
                              _editFiscalYear(context, workspace, year),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Delete fiscal year',
                          onPressed: () =>
                              _deleteFiscalYear(context, workspace, year),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _ListPanel(
            title: 'Journal entries',
            emptyText: 'No journal entries posted yet.',
            children: [
              for (final entry in journalRows)
                ListTile(
                  dense: true,
                  leading: Icon(
                    entry['status'] == 'void'
                        ? Icons.block_outlined
                        : Icons.menu_book_outlined,
                  ),
                  title: Text(
                    '${entry['entry_number']} • ${entry['memo'] ?? ''}',
                  ),
                  subtitle: Text(
                    '${entry['entry_date']} • ${entry['source_type'] ?? 'manual'}',
                  ),
                  trailing: canManage && entry['status'] == 'posted'
                      ? IconButton(
                          tooltip: 'Reverse journal entry',
                          onPressed: () => _reverseJournal(context, entry),
                          icon: const Icon(Icons.undo_rounded),
                        )
                      : StatusBadge(
                          label: entry['status'] as String? ?? 'posted',
                          tone: entry['status'] == 'void'
                              ? StatusTone.warning
                              : StatusTone.success,
                        ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _ListPanel(
            title: 'Subledger posting status',
            emptyText: 'No operational records have been posted to the GL yet.',
            children: [
              for (final posting in postingRows.take(12))
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.link_rounded),
                  title: Text(
                    '${posting['subledger_type']} • ${posting['memo'] ?? ''}',
                  ),
                  subtitle: Text('Posted ${posting['posted_at'] ?? ''}'),
                  trailing: const StatusBadge(
                    label: 'Posted',
                    tone: StatusTone.success,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _ListPanel(
            title: 'Chart of accounts',
            emptyText: 'No accounts found.',
            children: [
              for (final account in accountRows)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.account_tree_outlined),
                  title: Text('${account['code']} • ${account['name']}'),
                  subtitle: Text(account['account_type'] as String? ?? ''),
                  trailing: account['is_system'] == true
                      ? const StatusBadge(label: 'System')
                      : canManage
                      ? Wrap(
                          spacing: 2,
                          children: [
                            IconButton(
                              tooltip: 'Edit account',
                              onPressed: () =>
                                  _editAccount(context, workspace, account),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Delete account',
                              onPressed: () =>
                                  _deleteAccount(context, workspace, account),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        )
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 16),
          _ListPanel(
            title: 'Cash and bank accounts',
            emptyText: 'No cash or bank accounts configured.',
            children: [
              for (final account in cashRows)
                ListTile(
                  dense: true,
                  leading: Icon(
                    account['account_type'] == 'bank'
                        ? Icons.account_balance
                        : Icons.payments_outlined,
                  ),
                  title: Text(account['name'] as String? ?? ''),
                  subtitle: Text(
                    '${account['account_type']} • ${account['account_number_masked'] ?? 'No account number'}',
                  ),
                  trailing: canManage
                      ? Wrap(
                          spacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              formatMoney(
                                workspace.currencyCode,
                                _minor(account['opening_balance']),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Edit cash / bank account',
                              onPressed: () => _editCashBank(
                                context,
                                workspace,
                                account,
                                accountRows,
                              ),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Delete cash / bank account',
                              onPressed: () =>
                                  _deleteCashBank(context, workspace, account),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        )
                      : Text(
                          formatMoney(
                            workspace.currencyCode,
                            _minor(account['opening_balance']),
                          ),
                        ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _ListPanel(
            title: 'Bank reconciliation',
            emptyText: 'No bank reconciliations configured.',
            children: [
              for (final reconciliation in reconciliationRows)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.fact_check_outlined),
                  title: Text(
                    '${_nestedName(reconciliation['accounting_cash_bank_accounts'])} • ${reconciliation['statement_start']} → ${reconciliation['statement_end']}',
                  ),
                  subtitle: Text(
                    'Difference ${formatMoney(workspace.currencyCode, _minor(reconciliation['difference_amount']))}',
                  ),
                  trailing: canManage && reconciliation['status'] != 'completed'
                      ? TextButton(
                          onPressed: () => _autoReconcile(
                            context,
                            reconciliation['id'] as String,
                          ),
                          child: const Text('Auto-match'),
                        )
                      : StatusBadge(
                          label: reconciliation['status'] as String? ?? 'draft',
                          tone: reconciliation['status'] == 'completed'
                              ? StatusTone.success
                              : StatusTone.warning,
                        ),
                ),
              if (canManage)
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _createBankReconciliation(context, workspace, cashRows),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New reconciliation'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _ListPanel(
            title: 'Recurring expenses',
            emptyText: 'No recurring expenses configured.',
            children: [
              for (final item in recurringRows)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.repeat_rounded),
                  title: Text(item['description'] as String? ?? ''),
                  subtitle: Text(
                    '${item['frequency']} • next ${item['next_run_on']} • ${item['vendor_name'] ?? 'No vendor'}',
                  ),
                  trailing: canExpenseManage
                      ? Wrap(
                          spacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              formatMoney(
                                workspace.currencyCode,
                                _minor(item['amount']),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Edit recurring expense',
                              onPressed: () =>
                                  _editRecurring(context, workspace, item),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Delete recurring expense',
                              onPressed: () =>
                                  _deleteRecurring(context, workspace, item),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        )
                      : Text(
                          formatMoney(
                            workspace.currencyCode,
                            _minor(item['amount']),
                          ),
                        ),
                ),
              if (canExpenseManage)
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: () => _runRecurring(workspace.businessId),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Run due expenses'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _ListPanel(
            title: 'Tax profiles',
            emptyText: 'No tax profiles configured. GST summaries use the business GSTIN fallback.',
            children: [
              for (final profile in taxRows)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(profile['legal_name'] as String? ?? ''),
                  subtitle: Text(
                    '${(profile['tax_regime'] ?? 'gst').toString().toUpperCase()} • ${profile['country_code'] ?? 'IN'} • ${profile['registration_number'] ?? profile['gstin'] ?? 'No registration'} • ${profile['default_tax_rate'] ?? 0}%${profile['tax_inclusive'] == true ? ' inclusive' : ''} • effective ${profile['effective_from']}',
                  ),
                  trailing: canTaxManage
                      ? Wrap(
                          spacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            profile['is_active'] == true
                                ? const StatusBadge(
                                    label: 'Active',
                                    tone: StatusTone.success,
                                  )
                                : const StatusBadge(label: 'Inactive'),
                            IconButton(
                              tooltip: 'Edit tax profile',
                              onPressed: () =>
                                  _editTaxProfile(context, workspace, profile),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Delete tax profile',
                              onPressed: () => _deleteTaxProfile(
                                context,
                                workspace,
                                profile,
                              ),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        )
                      : profile['is_active'] == true
                      ? const StatusBadge(
                          label: 'Active',
                          tone: StatusTone.success,
                        )
                      : const StatusBadge(label: 'Inactive'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _ListPanel(
            title: 'Tax credit and debit notes',
            emptyText: 'No tax adjustment notes recorded.',
            children: [
              for (final note in taxNoteRows)
                ListTile(
                  dense: true,
                  leading: Icon(
                    note['note_type'] == 'credit'
                        ? Icons.remove_circle_outline
                        : Icons.add_circle_outline,
                  ),
                  title: Text(
                    '${note['note_number']} • ${(note['note_type'] as String? ?? '').toUpperCase()} ${note['scope']}',
                  ),
                  subtitle: Text('${note['reason']} • ${note['note_date']}'),
                  trailing: canManage && note['status'] == 'draft'
                      ? TextButton(
                          onPressed: () =>
                              _postTaxNote(context, note['id'] as String),
                          child: const Text('Post to GL'),
                        )
                      : StatusBadge(
                          label: note['status'] as String? ?? 'draft',
                          tone: note['status'] == 'posted'
                              ? StatusTone.success
                              : StatusTone.warning,
                        ),
                ),
              if (canTaxManage)
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _createTaxAdjustmentNote(context, workspace),
                    icon: const Icon(Icons.note_add_outlined),
                    label: const Text('New tax note'),
                  ),
                ),
            ],
          ),
          if (canManage) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => _closePeriod(context, workspace),
                icon: const Icon(Icons.lock_clock_outlined),
                label: const Text('Close accounting period'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(accountingAccountsProvider);
    ref.invalidate(accountingJournalEntriesProvider);
    ref.invalidate(accountingFiscalYearsProvider);
    ref.invalidate(cashBankAccountsProvider);
    ref.invalidate(recurringExpensesProvider);
    ref.invalidate(taxProfilesProvider);
    ref.invalidate(accountingSubledgerPostingsProvider);
    ref.invalidate(bankReconciliationsProvider);
    ref.invalidate(taxAdjustmentNotesProvider);
    await ref.read(accountingAccountsProvider.future);
  }

  void _loadTrialBalance(String businessId) {
    setState(() {
      _trialBalance = ref
          .read(accountingRepositoryProvider)
          .fetchTrialBalance(businessId, _asOf);
    });
  }

  void _loadGstSummary(String businessId) {
    final start = DateTime(DateTime.now().year);
    final end = DateTime(DateTime.now().year + 1);
    setState(() {
      _gstSummary = ref
          .read(accountingRepositoryProvider)
          .getGstSummary(businessId: businessId, start: start, end: end);
    });
  }

  Future<void> _exportGstSummary(Map<String, dynamic> row) async {
    final csv = [
      'period_start,period_end,total_tax,cgst,sgst,igst,input_tax_adjustment',
      '${row['period_start'] ?? ''},${row['period_end'] ?? ''},${row['total_tax'] ?? 0},${row['cgst'] ?? 0},${row['sgst'] ?? 0},${row['igst'] ?? 0},${row['input_tax_adjustment'] ?? 0}',
    ].join('\n');
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: 'Save GST summary',
        fileName: 'gst-summary.csv',
        bytes: utf8.encode(csv),
        mimeType: 'text/csv',
        type: FileType.custom,
        allowedExtensions: const ['csv'],
      );
      if (mounted && path != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('GST summary exported.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  void _loadFinancialStatements(String businessId) {
    final now = DateTime.now();
    setState(() {
      _financialStatements = ref
          .read(accountingRepositoryProvider)
          .fetchFinancialStatements(
            businessId: businessId,
            start: DateTime(now.year, now.month, 1),
            end: DateTime(now.year, now.month + 1, 0),
          );
    });
  }

  Future<void> _createAccount(
    BuildContext context,
    BusinessWorkspace workspace,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _AccountDialog(
        repository: ref.read(accountingRepositoryProvider),
        businessId: workspace.businessId,
      ),
    );
    if (result == true) ref.invalidate(accountingAccountsProvider);
  }

  Future<void> _createFiscalYear(
    BuildContext context,
    BusinessWorkspace workspace,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _FiscalYearDialog(
        repository: ref.read(accountingRepositoryProvider),
        businessId: workspace.businessId,
      ),
    );
    if (result == true) ref.invalidate(accountingFiscalYearsProvider);
  }

  Future<void> _createCashBank(
    BuildContext context,
    BusinessWorkspace workspace,
    List<Map<String, dynamic>> accounts,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _CashBankDialog(
        repository: ref.read(accountingRepositoryProvider),
        businessId: workspace.businessId,
        accounts: accounts,
      ),
    );
    if (result == true) ref.invalidate(cashBankAccountsProvider);
  }

  Future<void> _createRecurring(
    BuildContext context,
    BusinessWorkspace workspace,
  ) async {
    final categories = await ref.read(expenseCategoriesProvider.future);
    if (!context.mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _RecurringDialog(
        repository: ref.read(accountingRepositoryProvider),
        workspace: workspace,
        categories: categories,
      ),
    );
    if (result == true) ref.invalidate(recurringExpensesProvider);
  }

  Future<void> _createTaxProfile(
    BuildContext context,
    BusinessWorkspace workspace,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _TaxProfileDialog(
        repository: ref.read(accountingRepositoryProvider),
        workspace: workspace,
      ),
    );
    if (result == true) ref.invalidate(taxProfilesProvider);
  }

  Future<void> _editAccount(
    BuildContext context,
    BusinessWorkspace workspace,
    Map<String, dynamic> account,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AccountDialog(
        repository: ref.read(accountingRepositoryProvider),
        businessId: workspace.businessId,
        existing: account,
      ),
    );
    if (saved == true) ref.invalidate(accountingAccountsProvider);
  }

  Future<void> _deleteAccount(
    BuildContext context,
    BusinessWorkspace workspace,
    Map<String, dynamic> account,
  ) async {
    if (!await _confirmDelete(
      context,
      'Delete ledger account?',
      'Delete ${account['code']} • ${account['name']}?',
    ))
      return;
    await ref
        .read(accountingRepositoryProvider)
        .deleteAccountingAccount(
          id: account['id'] as String,
          businessId: workspace.businessId,
        );
    ref.invalidate(accountingAccountsProvider);
  }

  Future<void> _editFiscalYear(
    BuildContext context,
    BusinessWorkspace workspace,
    Map<String, dynamic> year,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _FiscalYearDialog(
        repository: ref.read(accountingRepositoryProvider),
        businessId: workspace.businessId,
        existing: year,
      ),
    );
    if (saved == true) ref.invalidate(accountingFiscalYearsProvider);
  }

  Future<void> _deleteFiscalYear(
    BuildContext context,
    BusinessWorkspace workspace,
    Map<String, dynamic> year,
  ) async {
    if (!await _confirmDelete(
      context,
      'Delete fiscal year?',
      'Delete ${year['label']}? Only open, unused fiscal years can be removed.',
    ))
      return;
    await ref
        .read(accountingRepositoryProvider)
        .deleteFiscalYear(
          id: year['id'] as String,
          businessId: workspace.businessId,
        );
    ref.invalidate(accountingFiscalYearsProvider);
  }

  Future<void> _editCashBank(
    BuildContext context,
    BusinessWorkspace workspace,
    Map<String, dynamic> account,
    List<Map<String, dynamic>> accounts,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CashBankDialog(
        repository: ref.read(accountingRepositoryProvider),
        businessId: workspace.businessId,
        accounts: accounts,
        existing: account,
      ),
    );
    if (saved == true) ref.invalidate(cashBankAccountsProvider);
  }

  Future<void> _deleteCashBank(
    BuildContext context,
    BusinessWorkspace workspace,
    Map<String, dynamic> account,
  ) async {
    if (!await _confirmDelete(
      context,
      'Delete cash / bank account?',
      'Delete ${account['name']}? Accounts referenced by transactions cannot be removed.',
    ))
      return;
    await ref
        .read(accountingRepositoryProvider)
        .deleteCashBankAccount(
          id: account['id'] as String,
          businessId: workspace.businessId,
        );
    ref.invalidate(cashBankAccountsProvider);
  }

  Future<void> _editRecurring(
    BuildContext context,
    BusinessWorkspace workspace,
    Map<String, dynamic> item,
  ) async {
    final categories = await ref.read(expenseCategoriesProvider.future);
    if (!context.mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RecurringDialog(
        repository: ref.read(accountingRepositoryProvider),
        workspace: workspace,
        categories: categories,
        existing: item,
      ),
    );
    if (saved == true) ref.invalidate(recurringExpensesProvider);
  }

  Future<void> _deleteRecurring(
    BuildContext context,
    BusinessWorkspace workspace,
    Map<String, dynamic> item,
  ) async {
    if (!await _confirmDelete(
      context,
      'Delete recurring expense?',
      'Delete ${item['description']}? Future runs will stop.',
    ))
      return;
    await ref
        .read(accountingRepositoryProvider)
        .deleteRecurringExpense(
          id: item['id'] as String,
          businessId: workspace.businessId,
        );
    ref.invalidate(recurringExpensesProvider);
  }

  Future<void> _editTaxProfile(
    BuildContext context,
    BusinessWorkspace workspace,
    Map<String, dynamic> profile,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _TaxProfileDialog(
        repository: ref.read(accountingRepositoryProvider),
        workspace: workspace,
        existing: profile,
      ),
    );
    if (saved == true) ref.invalidate(taxProfilesProvider);
  }

  Future<void> _deleteTaxProfile(
    BuildContext context,
    BusinessWorkspace workspace,
    Map<String, dynamic> profile,
  ) async {
    if (!await _confirmDelete(
      context,
      'Delete tax profile?',
      'Delete ${profile['legal_name']}? Historical documents keep their tax snapshot.',
    ))
      return;
    await ref
        .read(accountingRepositoryProvider)
        .deleteTaxProfile(
          id: profile['id'] as String,
          businessId: workspace.businessId,
        );
    ref.invalidate(taxProfilesProvider);
  }

  Future<bool> _confirmDelete(
    BuildContext context,
    String title,
    String message,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _createJournalEntry(
    BuildContext context,
    BusinessWorkspace workspace,
    List<Map<String, dynamic>> accounts,
  ) async {
    if (accounts.length < 2) return;
    await showDialog<bool>(
      context: context,
      builder: (_) => _JournalDialog(
        repository: ref.read(accountingRepositoryProvider),
        businessId: workspace.businessId,
        accounts: accounts,
      ),
    );
    _loadTrialBalance(workspace.businessId);
    ref.invalidate(accountingJournalEntriesProvider);
  }

  Future<void> _reverseJournal(
    BuildContext context,
    Map<String, dynamic> entry,
  ) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Reverse ${entry['entry_number']}'),
        content: TextField(
          controller: reason,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Correction reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, reason.text.trim().length >= 3),
            child: const Text('Reverse'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      reason.dispose();
      return;
    }
    try {
      await ref
          .read(accountingRepositoryProvider)
          .reverseJournalEntry(
            journalEntryId: entry['id'] as String,
            reason: reason.text,
          );
      ref.invalidate(accountingJournalEntriesProvider);
      ref.invalidate(accountingAccountsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Journal entry reversed with an audit trail.'),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      reason.dispose();
    }
  }

  Future<void> _runRecurring(String businessId) async {
    try {
      final result = await ref
          .read(accountingRepositoryProvider)
          .runRecurringExpenses(businessId);
      ref.invalidate(recurringExpensesProvider);
      ref.invalidate(expensesProvider);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Generated ${result['generated'] ?? 0} recurring expense(s).',
            ),
          ),
        );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _syncOperationalLedger(
    BuildContext context,
    String businessId,
  ) async {
    try {
      final result = await ref
          .read(accountingRepositoryProvider)
          .syncOperationalLedger(businessId);
      ref.invalidate(accountingSubledgerPostingsProvider);
      ref.invalidate(accountingJournalEntriesProvider);
      ref.invalidate(accountingAccountsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Posted ${result['sales'] ?? 0} sales, ${result['purchase_invoices'] ?? 0} purchase invoices, ${result['expenses'] ?? 0} expenses, ${result['customer_receipts'] ?? 0} customer receipts, ${result['tax_notes'] ?? 0} tax notes, ${result['sale_returns'] ?? 0} returns, and ${result['sale_refunds'] ?? 0} refunds.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _createBankReconciliation(
    BuildContext context,
    BusinessWorkspace workspace,
    List<Map<String, dynamic>> accounts,
  ) async {
    if (accounts.isEmpty) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _BankReconciliationDialog(
        repository: ref.read(accountingRepositoryProvider),
        businessId: workspace.businessId,
        accounts: accounts,
      ),
    );
    if (result == true) ref.invalidate(bankReconciliationsProvider);
  }

  Future<void> _autoReconcile(BuildContext context, String id) async {
    try {
      final result = await ref
          .read(accountingRepositoryProvider)
          .autoReconcileBankReconciliation(id);
      ref.invalidate(bankReconciliationsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Matched ${result['matched_amount'] ?? 0}; difference ${result['difference'] ?? 0}.',
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _createTaxAdjustmentNote(
    BuildContext context,
    BusinessWorkspace workspace,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _TaxAdjustmentNoteDialog(
        repository: ref.read(accountingRepositoryProvider),
        workspace: workspace,
      ),
    );
    if (result == true) ref.invalidate(taxAdjustmentNotesProvider);
  }

  Future<void> _postTaxNote(BuildContext context, String id) async {
    try {
      await ref.read(accountingRepositoryProvider).postTaxAdjustmentNote(id);
      ref.invalidate(taxAdjustmentNotesProvider);
      ref.invalidate(accountingSubledgerPostingsProvider);
      ref.invalidate(accountingJournalEntriesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tax note posted to the general ledger.'),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _closePeriod(
    BuildContext context,
    BusinessWorkspace workspace,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _ClosePeriodDialog(
        repository: ref.read(accountingRepositoryProvider),
        businessId: workspace.businessId,
      ),
    );
    if (result == true && mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Accounting period closed.')),
      );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 3),
      Text(value, style: Theme.of(context).textTheme.titleMedium),
    ],
  );
}

class _ListPanel extends StatelessWidget {
  const _ListPanel({
    required this.title,
    required this.emptyText,
    required this.children,
  });
  final String title;
  final String emptyText;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => AppPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (children.isEmpty) Text(emptyText) else ...children,
      ],
    ),
  );
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({
    required this.repository,
    required this.businessId,
    this.existing,
  });
  final AccountingRepository repository;
  final String businessId;
  final Map<String, dynamic>? existing;
  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  String _type = 'expense';
  bool _saving = false;
  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _code.text = existing['code']?.toString() ?? '';
      _name.text = existing['name']?.toString() ?? '';
      _type = existing['account_type']?.toString() ?? _type;
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_editing ? 'Edit ledger account' : 'New ledger account'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _code,
          decoration: const InputDecoration(labelText: 'Account code'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Account name'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _type,
          decoration: const InputDecoration(labelText: 'Type'),
          items: const [
            DropdownMenuItem(value: 'asset', child: Text('Asset')),
            DropdownMenuItem(value: 'liability', child: Text('Liability')),
            DropdownMenuItem(value: 'equity', child: Text('Equity')),
            DropdownMenuItem(value: 'revenue', child: Text('Revenue')),
            DropdownMenuItem(value: 'expense', child: Text('Expense')),
          ],
          onChanged: (value) => setState(() => _type = value!),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_editing ? 'Save changes' : 'Create'),
      ),
    ],
  );
  Future<void> _save() async {
    if (_code.text.trim().isEmpty || _name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final existing = widget.existing;
      if (existing == null) {
        await widget.repository.createAccountingAccount(
          businessId: widget.businessId,
          code: _code.text,
          name: _name.text,
          accountType: _type,
        );
      } else {
        await widget.repository.updateAccountingAccount(
          id: existing['id'] as String,
          businessId: widget.businessId,
          code: _code.text,
          name: _name.text,
          accountType: _type,
          isActive: existing['is_active'] as bool? ?? true,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _CashBankDialog extends StatefulWidget {
  const _CashBankDialog({
    required this.repository,
    required this.businessId,
    required this.accounts,
    this.existing,
  });
  final AccountingRepository repository;
  final String businessId;
  final List<Map<String, dynamic>> accounts;
  final Map<String, dynamic>? existing;
  @override
  State<_CashBankDialog> createState() => _CashBankDialogState();
}

class _CashBankDialogState extends State<_CashBankDialog> {
  final _name = TextEditingController();
  final _number = TextEditingController();
  final _opening = TextEditingController(text: '0');
  String _type = 'cash';
  String? _ledgerId;
  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _name.text = existing['name']?.toString() ?? '';
      _number.text = existing['account_number_masked']?.toString() ?? '';
      _opening.text = ((existing['opening_balance'] as num?)?.toDouble() ?? 0)
          .toStringAsFixed(2);
      _type = existing['account_type']?.toString() ?? _type;
      _ledgerId = existing['ledger_account_id'] as String?;
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _number, _opening]) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _editing ? 'Edit cash or bank account' : 'Cash or bank account',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(value: 'bank', child: Text('Bank')),
              ],
              onChanged: (value) => setState(() => _type = value!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _number,
              decoration: const InputDecoration(
                labelText: 'Masked account number',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _opening,
              decoration: const InputDecoration(labelText: 'Opening balance'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _ledgerId,
              decoration: const InputDecoration(
                labelText: 'Ledger account (optional)',
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('None'),
                ),
                ...widget.accounts.map(
                  (account) => DropdownMenuItem<String?>(
                    value: account['id'] as String,
                    child: Text('${account['code']} • ${account['name']}'),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _ledgerId = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(_editing ? 'Save changes' : 'Create'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final amount = double.tryParse(_opening.text.trim()) ?? 0;
    if (_name.text.trim().isEmpty) return;
    try {
      final existing = widget.existing;
      if (existing == null) {
        await widget.repository.createCashBankAccount(
          businessId: widget.businessId,
          name: _name.text,
          accountType: _type,
          maskedNumber: _number.text,
          openingBalanceMinor: (amount * 100).round(),
          ledgerAccountId: _ledgerId,
        );
      } else {
        await widget.repository.updateCashBankAccount(
          id: existing['id'] as String,
          businessId: widget.businessId,
          name: _name.text,
          accountType: _type,
          maskedNumber: _number.text,
          openingBalanceMinor: (amount * 100).round(),
          ledgerAccountId: _ledgerId,
          isActive: existing['is_active'] as bool? ?? true,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _RecurringDialog extends StatefulWidget {
  const _RecurringDialog({
    required this.repository,
    required this.workspace,
    required this.categories,
    this.existing,
  });
  final AccountingRepository repository;
  final BusinessWorkspace workspace;
  final List<dynamic> categories;
  final Map<String, dynamic>? existing;
  @override
  State<_RecurringDialog> createState() => _RecurringDialogState();
}

class _RecurringDialogState extends State<_RecurringDialog> {
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _tax = TextEditingController(text: '0');
  final _vendor = TextEditingController();
  late String _branchId;
  late String _categoryId;
  String _frequency = 'monthly';
  String _method = 'bank_transfer';
  late DateTime _nextRunOn;
  bool get _editing => widget.existing != null;
  @override
  void initState() {
    super.initState();
    _branchId = widget.workspace.branches.first.id;
    _categoryId = (widget.categories.first as dynamic).id;
    _nextRunOn = DateTime.now();
    final existing = widget.existing;
    if (existing != null) {
      _description.text = existing['description']?.toString() ?? '';
      _amount.text = ((existing['amount'] as num?)?.toDouble() ?? 0)
          .toStringAsFixed(2);
      _tax.text = ((existing['tax_amount'] as num?)?.toDouble() ?? 0)
          .toStringAsFixed(2);
      _vendor.text = existing['vendor_name']?.toString() ?? '';
      _branchId = existing['branch_id'] as String? ?? _branchId;
      _categoryId = existing['category_id'] as String? ?? _categoryId;
      _frequency = existing['frequency']?.toString() ?? _frequency;
      _method = existing['payment_method']?.toString() ?? _method;
      _nextRunOn =
          DateTime.tryParse(existing['next_run_on']?.toString() ?? '') ??
          _nextRunOn;
    }
  }

  @override
  void dispose() {
    for (final c in [_description, _amount, _tax, _vendor]) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_editing ? 'Edit recurring expense' : 'Recurring expense'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _branchId,
            decoration: const InputDecoration(labelText: 'Branch'),
            items: [
              for (final branch in widget.workspace.branches)
                DropdownMenuItem(value: branch.id, child: Text(branch.name)),
            ],
            onChanged: (value) => setState(() => _branchId = value!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _categoryId,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final category in widget.categories)
                DropdownMenuItem(
                  value: (category as dynamic).id as String,
                  child: Text((category as dynamic).name as String),
                ),
            ],
            onChanged: (value) => setState(() => _categoryId = value!),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amount,
                  decoration: const InputDecoration(labelText: 'Amount'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _tax,
                  decoration: const InputDecoration(labelText: 'Tax'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _vendor,
            decoration: const InputDecoration(labelText: 'Vendor'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _frequency,
            decoration: const InputDecoration(labelText: 'Frequency'),
            items: const [
              DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
              DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
              DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
            ],
            onChanged: (value) => setState(() => _frequency = value!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration: const InputDecoration(labelText: 'Payment method'),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Cash')),
              DropdownMenuItem(value: 'upi', child: Text('UPI')),
              DropdownMenuItem(value: 'card', child: Text('Card')),
              DropdownMenuItem(
                value: 'bank_transfer',
                child: Text('Bank transfer'),
              ),
              DropdownMenuItem(value: 'wallet', child: Text('Wallet')),
            ],
            onChanged: (value) => setState(() => _method = value!),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _save,
        child: Text(_editing ? 'Save changes' : 'Create'),
      ),
    ],
  );
  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    final tax = double.tryParse(_tax.text.trim()) ?? 0;
    if (_description.text.trim().isEmpty || amount == null || amount <= 0)
      return;
    try {
      final existing = widget.existing;
      if (existing == null) {
        await widget.repository.createRecurringExpense(
          businessId: widget.workspace.businessId,
          branchId: _branchId,
          categoryId: _categoryId,
          description: _description.text,
          amountMinor: (amount * 100).round(),
          taxMinor: (tax * 100).round(),
          paymentMethod: _method,
          vendorName: _vendor.text,
          frequency: _frequency,
          nextRunOn: _nextRunOn,
        );
      } else {
        await widget.repository.updateRecurringExpense(
          id: existing['id'] as String,
          businessId: widget.workspace.businessId,
          branchId: _branchId,
          categoryId: _categoryId,
          description: _description.text,
          amountMinor: (amount * 100).round(),
          taxMinor: (tax * 100).round(),
          paymentMethod: _method,
          vendorName: _vendor.text,
          frequency: _frequency,
          nextRunOn: _nextRunOn,
          endOn: DateTime.tryParse(existing['end_on']?.toString() ?? ''),
          isActive: existing['is_active'] as bool? ?? true,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _TaxProfileDialog extends StatefulWidget {
  const _TaxProfileDialog({
    required this.repository,
    required this.workspace,
    this.existing,
  });
  final AccountingRepository repository;
  final BusinessWorkspace workspace;
  final Map<String, dynamic>? existing;
  @override
  State<_TaxProfileDialog> createState() => _TaxProfileDialogState();
}

class _TaxProfileDialogState extends State<_TaxProfileDialog> {
  final _legal = TextEditingController();
  final _gstin = TextEditingController();
  final _state = TextEditingController();
  final _pos = TextEditingController();
  final _country = TextEditingController(text: 'IN');
  final _registration = TextEditingController();
  final _rate = TextEditingController(text: '0');
  String? _branchId;
  String _regime = 'gst';
  bool _taxInclusive = false;
  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _legal.text = existing['legal_name']?.toString() ?? '';
      _gstin.text = existing['gstin']?.toString() ?? '';
      _state.text = existing['state_code']?.toString() ?? '';
      _pos.text = existing['default_place_of_supply']?.toString() ?? '';
      _country.text = existing['country_code']?.toString() ?? 'IN';
      _registration.text = existing['registration_number']?.toString() ?? '';
      _rate.text = ((existing['default_tax_rate'] as num?)?.toDouble() ?? 0)
          .toString();
      _branchId = existing['branch_id'] as String?;
      _regime = existing['tax_regime']?.toString() ?? _regime;
      _taxInclusive = existing['tax_inclusive'] as bool? ?? false;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _legal,
      _gstin,
      _state,
      _pos,
      _country,
      _registration,
      _rate,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editing ? 'Edit tax profile' : 'Tax profile'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _legal,
              decoration: const InputDecoration(labelText: 'Legal name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _gstin,
              decoration: const InputDecoration(
                labelText: 'GSTIN (GST profiles only)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _state,
              decoration: const InputDecoration(
                labelText: 'State code (2 digits; use 00 internationally)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pos,
              decoration: const InputDecoration(
                labelText: 'Default place of supply',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _branchId,
              decoration: const InputDecoration(labelText: 'Branch (optional)'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Business-wide'),
                ),
                ...widget.workspace.branches.map(
                  (branch) => DropdownMenuItem<String?>(
                    value: branch.id,
                    child: Text(branch.name),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _branchId = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _regime,
              decoration: const InputDecoration(labelText: 'Tax regime'),
              items: const [
                DropdownMenuItem(value: 'gst', child: Text('GST')),
                DropdownMenuItem(value: 'vat', child: Text('VAT')),
                DropdownMenuItem(value: 'sales_tax', child: Text('Sales tax')),
                DropdownMenuItem(value: 'none', child: Text('No tax')),
              ],
              onChanged: (value) => setState(() => _regime = value ?? 'gst'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _country,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Country code (ISO-2)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _registration,
              decoration: const InputDecoration(
                labelText: 'Registration number (VAT / sales tax)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rate,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Default tax rate (%)',
              ),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tax-inclusive prices'),
              value: _taxInclusive,
              onChanged: (value) => setState(() => _taxInclusive = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(_editing ? 'Save changes' : 'Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final country = _country.text.trim().toUpperCase();
    final rate = double.tryParse(_rate.text.trim());
    if (_legal.text.trim().isEmpty ||
        !RegExp(r'^[A-Z]{2}$').hasMatch(country) ||
        !RegExp(r'^\d{2}$')
            .hasMatch(_state.text.trim().isEmpty ? '00' : _state.text.trim()) ||
        rate == null ||
        rate < 0 ||
        rate > 100)
      return;
    try {
      final existing = widget.existing;
      if (existing == null) {
        await widget.repository.createTaxProfile(
          businessId: widget.workspace.businessId,
          branchId: _branchId,
          legalName: _legal.text,
          gstin: _gstin.text,
          stateCode: _state.text.trim().isEmpty ? '00' : _state.text,
          placeOfSupply: _pos.text,
          effectiveFrom: DateTime.now(),
          taxRegime: _regime,
          countryCode: country,
          registrationNumber: _registration.text,
          defaultTaxRate: rate,
          taxInclusive: _taxInclusive,
        );
      } else {
        await widget.repository.updateTaxProfile(
          id: existing['id'] as String,
          businessId: widget.workspace.businessId,
          branchId: _branchId,
          legalName: _legal.text,
          gstin: _gstin.text,
          stateCode: _state.text.trim().isEmpty ? '00' : _state.text,
          placeOfSupply: _pos.text,
          effectiveFrom:
              DateTime.tryParse(existing['effective_from']?.toString() ?? '') ??
              DateTime.now(),
          taxRegime: _regime,
          countryCode: country,
          registrationNumber: _registration.text,
          defaultTaxRate: rate,
          taxInclusive: _taxInclusive,
          isActive: existing['is_active'] as bool? ?? true,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _BankReconciliationDialog extends StatefulWidget {
  const _BankReconciliationDialog({
    required this.repository,
    required this.businessId,
    required this.accounts,
  });
  final AccountingRepository repository;
  final String businessId;
  final List<Map<String, dynamic>> accounts;

  @override
  State<_BankReconciliationDialog> createState() =>
      _BankReconciliationDialogState();
}

class _BankReconciliationDialogState extends State<_BankReconciliationDialog> {
  late String _accountId;
  final _start = TextEditingController();
  final _end = TextEditingController();
  final _opening = TextEditingController(text: '0');
  final _closing = TextEditingController();
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _accountId = widget.accounts.first['id'] as String;
    final now = DateTime.now();
    _start.text = _dateInput(DateTime(now.year, now.month, 1));
    _end.text = _dateInput(DateTime(now.year, now.month + 1, 0));
  }

  @override
  void dispose() {
    for (final controller in [_start, _end, _opening, _closing, _notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New bank reconciliation'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _accountId,
            decoration: const InputDecoration(labelText: 'Cash / bank account'),
            items: [
              for (final account in widget.accounts)
                DropdownMenuItem(
                  value: account['id'] as String,
                  child: Text(
                    '${account['name']} • ${account['account_type']}',
                  ),
                ),
            ],
            onChanged: (value) => setState(() => _accountId = value!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _start,
            decoration: const InputDecoration(
              labelText: 'Statement start (YYYY-MM-DD)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _end,
            decoration: const InputDecoration(
              labelText: 'Statement end (YYYY-MM-DD)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _opening,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Opening balance'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _closing,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Statement closing balance',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Create')),
    ],
  );

  Future<void> _save() async {
    final start = DateTime.tryParse(_start.text.trim());
    final end = DateTime.tryParse(_end.text.trim());
    final opening = _minorFromText(_opening.text);
    final closing = _minorFromText(_closing.text);
    if (start == null || end == null || closing == null || opening == null) {
      return;
    }
    try {
      await widget.repository.createBankReconciliation(
        businessId: widget.businessId,
        cashBankAccountId: _accountId,
        statementStart: start,
        statementEnd: end,
        openingBalanceMinor: opening,
        closingBalanceMinor: closing,
        notes: _notes.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class _TaxAdjustmentNoteDialog extends StatefulWidget {
  const _TaxAdjustmentNoteDialog({
    required this.repository,
    required this.workspace,
  });
  final AccountingRepository repository;
  final BusinessWorkspace workspace;

  @override
  State<_TaxAdjustmentNoteDialog> createState() =>
      _TaxAdjustmentNoteDialogState();
}

class _TaxAdjustmentNoteDialogState extends State<_TaxAdjustmentNoteDialog> {
  final _number = TextEditingController();
  final _taxable = TextEditingController(text: '0');
  final _cgst = TextEditingController(text: '0');
  final _sgst = TextEditingController(text: '0');
  final _igst = TextEditingController(text: '0');
  final _reason = TextEditingController();
  String _type = 'credit';
  String _scope = 'sales';
  String? _branchId;

  @override
  void dispose() {
    for (final controller in [
      _number,
      _taxable,
      _cgst,
      _sgst,
      _igst,
      _reason,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Tax credit / debit note'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _number,
            decoration: const InputDecoration(labelText: 'Note number'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: 'credit', child: Text('Credit')),
                    DropdownMenuItem(value: 'debit', child: Text('Debit')),
                  ],
                  onChanged: (value) => setState(() => _type = value!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _scope,
                  decoration: const InputDecoration(labelText: 'Scope'),
                  items: const [
                    DropdownMenuItem(value: 'sales', child: Text('Sales')),
                    DropdownMenuItem(
                      value: 'purchase',
                      child: Text('Purchase'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _scope = value!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _branchId,
            decoration: const InputDecoration(labelText: 'Branch (optional)'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Business-wide'),
              ),
              ...widget.workspace.branches.map(
                (branch) => DropdownMenuItem<String?>(
                  value: branch.id,
                  child: Text(branch.name),
                ),
              ),
            ],
            onChanged: (value) => setState(() => _branchId = value),
          ),
          for (final field in [
            (_taxable, 'Taxable amount'),
            (_cgst, 'CGST'),
            (_sgst, 'SGST'),
            (_igst, 'IGST'),
          ]) ...[
            const SizedBox(height: 12),
            TextField(
              controller: field.$1,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(labelText: field.$2),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Reason'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save draft')),
    ],
  );

  Future<void> _save() async {
    final taxable = _minorFromText(_taxable.text);
    final cgst = _minorFromText(_cgst.text);
    final sgst = _minorFromText(_sgst.text);
    final igst = _minorFromText(_igst.text);
    if (_number.text.trim().isEmpty ||
        _reason.text.trim().length < 3 ||
        taxable == null ||
        cgst == null ||
        sgst == null ||
        igst == null) {
      return;
    }
    try {
      await widget.repository.createTaxAdjustmentNote(
        businessId: widget.workspace.businessId,
        branchId: _branchId,
        noteNumber: _number.text,
        noteType: _type,
        scope: _scope,
        taxableAmountMinor: taxable,
        cgstMinor: cgst,
        sgstMinor: sgst,
        igstMinor: igst,
        reason: _reason.text,
        noteDate: DateTime.now(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class _JournalDialog extends StatefulWidget {
  const _JournalDialog({
    required this.repository,
    required this.businessId,
    required this.accounts,
  });
  final AccountingRepository repository;
  final String businessId;
  final List<Map<String, dynamic>> accounts;
  @override
  State<_JournalDialog> createState() => _JournalDialogState();
}

class _JournalDialogState extends State<_JournalDialog> {
  final _memo = TextEditingController();
  final _debit = TextEditingController();
  final _credit = TextEditingController();
  late String _debitId;
  late String _creditId;
  @override
  void initState() {
    super.initState();
    _debitId = widget.accounts.first['id'] as String;
    _creditId = widget.accounts[1]['id'] as String;
  }

  @override
  void dispose() {
    for (final c in [_memo, _debit, _credit]) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Post journal entry'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _memo,
            decoration: const InputDecoration(labelText: 'Memo'),
          ),
          const SizedBox(height: 12),
          _accountDropdown(
            'Debit account',
            _debitId,
            (value) => setState(() => _debitId = value!),
          ),
          const SizedBox(height: 12),
          _accountDropdown(
            'Credit account',
            _creditId,
            (value) => setState(() => _creditId = value!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _debit,
            decoration: const InputDecoration(labelText: 'Amount'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Post')),
    ],
  );
  Widget _accountDropdown(
    String label,
    String value,
    ValueChanged<String?> onChanged,
  ) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final account in widget.accounts)
        DropdownMenuItem(
          value: account['id'] as String,
          child: Text('${account['code']} • ${account['name']}'),
        ),
    ],
    onChanged: onChanged,
  );
  Future<void> _save() async {
    final amount = double.tryParse(_debit.text.trim());
    if (amount == null || amount <= 0 || _debitId == _creditId) return;
    try {
      await widget.repository.createJournalEntry(
        businessId: widget.businessId,
        entryDate: DateTime.now(),
        memo: _memo.text,
        lines: [
          {'account_id': _debitId, 'debit': amount, 'credit': 0},
          {'account_id': _creditId, 'debit': 0, 'credit': amount},
        ],
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _FiscalYearDialog extends StatefulWidget {
  const _FiscalYearDialog({
    required this.repository,
    required this.businessId,
    this.existing,
  });
  final AccountingRepository repository;
  final String businessId;
  final Map<String, dynamic>? existing;

  @override
  State<_FiscalYearDialog> createState() => _FiscalYearDialogState();
}

class _FiscalYearDialogState extends State<_FiscalYearDialog> {
  final _label = TextEditingController();
  DateTime _startsOn = DateTime(DateTime.now().year, 4, 1);
  DateTime _endsOn = DateTime(DateTime.now().year + 1, 3, 31);
  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _label.text = existing['label']?.toString() ?? '';
      _startsOn =
          DateTime.tryParse(existing['starts_on']?.toString() ?? '') ??
          _startsOn;
      _endsOn =
          DateTime.tryParse(existing['ends_on']?.toString() ?? '') ?? _endsOn;
    }
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_editing ? 'Edit fiscal year' : 'Create fiscal year'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _label,
          decoration: const InputDecoration(labelText: 'Label'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Starts on'),
          subtitle: Text(DateFormat.yMMMd().format(_startsOn)),
          trailing: const Icon(Icons.calendar_today_outlined),
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
              initialDate: _startsOn,
            );
            if (date != null && mounted) setState(() => _startsOn = date);
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Ends on'),
          subtitle: Text(DateFormat.yMMMd().format(_endsOn)),
          trailing: const Icon(Icons.calendar_today_outlined),
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
              initialDate: _endsOn,
            );
            if (date != null && mounted) setState(() => _endsOn = date);
          },
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _save,
        child: Text(_editing ? 'Save changes' : 'Create'),
      ),
    ],
  );

  Future<void> _save() async {
    if (_label.text.trim().isEmpty || _endsOn.isBefore(_startsOn)) return;
    try {
      final existing = widget.existing;
      if (existing == null) {
        await widget.repository.createFiscalYear(
          businessId: widget.businessId,
          label: _label.text,
          startsOn: _startsOn,
          endsOn: _endsOn,
        );
      } else {
        await widget.repository.updateFiscalYear(
          id: existing['id'] as String,
          businessId: widget.businessId,
          label: _label.text,
          startsOn: _startsOn,
          endsOn: _endsOn,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class _ClosePeriodDialog extends StatefulWidget {
  const _ClosePeriodDialog({
    required this.repository,
    required this.businessId,
  });
  final AccountingRepository repository;
  final String businessId;
  @override
  State<_ClosePeriodDialog> createState() => _ClosePeriodDialogState();
}

class _ClosePeriodDialogState extends State<_ClosePeriodDialog> {
  final _notes = TextEditingController();
  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Close accounting period'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Close the current calendar month. Posted journal entries in this period will be locked.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          decoration: const InputDecoration(labelText: 'Notes'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Close period')),
    ],
  );
  Future<void> _save() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month);
    final end = DateTime(
      now.year,
      now.month + 1,
    ).subtract(const Duration(days: 1));
    try {
      await widget.repository.closeAccountingPeriod(
        businessId: widget.businessId,
        startsOn: start,
        endsOn: end,
        notes: _notes.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

int _minor(Object? value) =>
    (((value is num
                ? value.toDouble()
                : double.tryParse(value?.toString() ?? '') ?? 0)) *
            100)
        .round();

int? _minorFromText(String value) {
  final parsed = double.tryParse(value.trim());
  if (parsed == null || parsed < 0) return null;
  return (parsed * 100).round();
}

String _dateInput(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _nestedName(Object? value) {
  if (value is Map) return value['name']?.toString() ?? 'Account';
  if (value is List && value.isNotEmpty && value.first is Map) {
    return (value.first as Map)['name']?.toString() ?? 'Account';
  }
  return 'Account';
}

int _statementTotal(List<Map<String, dynamic>> rows, String type) {
  final amount = rows
      .where((row) => row['account_type'] == type)
      .fold<double>(
        0,
        (sum, row) =>
            sum +
            (row['amount'] is num
                ? (row['amount'] as num).toDouble()
                : double.tryParse('${row['amount']}') ?? 0),
      );
  return (amount * 100).round();
}
