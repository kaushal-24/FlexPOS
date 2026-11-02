import 'package:flexpos/core/utils/money.dart';
import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/core/widgets/data_page_skeleton.dart';
import 'package:flexpos/core/widgets/data_list_controls.dart';
import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/core/widgets/status_badge.dart';
import 'package:flexpos/features/accounting/data/accounting_repository.dart';
import 'package:flexpos/features/accounting/domain/accounting_models.dart';
import 'package:flexpos/core/security/crud_permissions.dart';
import 'package:flexpos/features/tenants/domain/business_workspace.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

class ExpensesPage extends ConsumerStatefulWidget {
  const ExpensesPage({super.key});

  @override
  ConsumerState<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends ConsumerState<ExpensesPage> {
  String _query = '';
  String _sort = 'newest';
  int _page = 0;
  final Set<String> _selectedExpenseIds = {};

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    if (workspace == null) {
      return const EmptyState(
        icon: Icons.add_business_outlined,
        title: 'Select a business',
        message: 'A workspace is required to view expenses.',
      );
    }
    if (!workspace.canRead('expenses')) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Expenses are restricted',
        message: 'Your role does not include expense viewing permission.',
      );
    }
    final expenses = ref.watch(expensesProvider);
    final canCreate = workspace.canCreate('expenses');
    final canUpdate = workspace.canUpdate('expenses');
    final canManage = canUpdate;
    final canApprove = workspace.permissionCodes.contains('expenses.approve');
    final canAttach = workspace.permissionCodes.contains(
      'expenses.attachments',
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _createExpense(context, ref, workspace),
              icon: const Icon(Icons.add_card_rounded),
              label: const Text('Record expense'),
            )
          : null,
      body: expenses.when(
        loading: () => const DataPageSkeleton(sectionLabel: 'expenses'),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load expenses',
          message: error.toString(),
          action: FilledButton.icon(
            onPressed: () => ref.invalidate(expensesProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ),
        data: (items) {
          final filtered = items
              .where(
                (expense) =>
                    '${expense.categoryName} ${expense.vendorName} ${expense.branchName} ${expense.expenseNumber} ${expense.paymentMethod}'
                        .toLowerCase()
                        .contains(_query),
              )
              .toList();
          filtered.sort(
            (a, b) => switch (_sort) {
              'amount_desc' => b.signedAmountMinor.compareTo(
                a.signedAmountMinor,
              ),
              'amount_asc' => a.signedAmountMinor.compareTo(
                b.signedAmountMinor,
              ),
              'oldest' => a.incurredOn.compareTo(b.incurredOn),
              _ => b.incurredOn.compareTo(a.incurredOn),
            },
          );
          final pageCount = pageCountFor(filtered.length);
          if (_page >= pageCount) _page = pageCount - 1;
          final visible = pageItems(filtered, _page);
          return RefreshIndicator(
            onRefresh: () => ref.refresh(expensesProvider.future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 96),
              children: [
                Text(
                  'Expenses',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Append-only records with auditable reversals',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                DataListControls(
                  query: _query,
                  onSearchChanged: (value) => setState(() {
                    _query = value.trim().toLowerCase();
                    _page = 0;
                  }),
                  searchLabel: 'Search category, vendor, or expense number',
                  sortValue: _sort,
                  sortOptions: const [
                    DataListSortOption('newest', 'Newest first'),
                    DataListSortOption('oldest', 'Oldest first'),
                    DataListSortOption('amount_desc', 'Amount (high–low)'),
                    DataListSortOption('amount_asc', 'Amount (low–high)'),
                  ],
                  onSortChanged: (value) => setState(() {
                    _sort = value;
                    _page = 0;
                  }),
                  page: _page,
                  pageCount: pageCount,
                  totalCount: filtered.length,
                  onPageChanged: (value) => setState(() => _page = value),
                  selectedCount: _selectedExpenseIds.length,
                  allSelected:
                      visible.isNotEmpty &&
                      visible.every(
                        (expense) => _selectedExpenseIds.contains(expense.id),
                      ),
                  onSelectAll: visible.isEmpty
                      ? null
                      : (selected) => setState(() {
                          if (selected ?? false) {
                            _selectedExpenseIds.addAll(
                              visible.map((expense) => expense.id),
                            );
                          } else {
                            _selectedExpenseIds.removeAll(
                              visible.map((expense) => expense.id),
                            );
                          }
                        }),
                  onClearSelection: () =>
                      setState(() => _selectedExpenseIds.clear()),
                  bulkActions: [
                    FilledButton.tonalIcon(
                      onPressed: _selectedExpenseIds.isEmpty
                          ? null
                          : () => _copySelectedExpenses(
                              items
                                  .where(
                                    (expense) =>
                                        _selectedExpenseIds.contains(expense.id),
                                  )
                                  .toList(growable: false),
                            ),
                      icon: const Icon(Icons.copy_all_rounded),
                      label: const Text('Copy selected'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (visible.isEmpty)
                  const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No expenses yet',
                    message: 'Record the first operating expense.',
                  )
                else
                  for (final expense in visible) ...[
                    AppPanel(
                      child: Row(
                        children: [
                          Checkbox(
                            value: _selectedExpenseIds.contains(expense.id),
                            onChanged: (selected) => setState(() {
                              if (selected ?? false) {
                                _selectedExpenseIds.add(expense.id);
                              } else {
                                _selectedExpenseIds.remove(expense.id);
                              }
                            }),
                          ),
                          CircleAvatar(
                            child: Icon(
                              expense.entryType == 'reversal'
                                  ? Icons.undo_rounded
                                  : Icons.receipt_long_outlined,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        expense.categoryName,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                    ),
                                    if (expense.entryType == 'reversal') ...[
                                      const SizedBox(width: 8),
                                      const StatusBadge(
                                        label: 'Reversal',
                                        tone: StatusTone.warning,
                                      ),
                                    ],
                                    if (expense.entryType == 'expense') ...[
                                      const SizedBox(width: 8),
                                      StatusBadge(
                                        label: expense.approvalStatus,
                                        tone: switch (expense.approvalStatus) {
                                          'approved' => StatusTone.success,
                                          'pending' => StatusTone.warning,
                                          'rejected' => StatusTone.danger,
                                          _ => StatusTone.neutral,
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  [
                                    expense.vendorName,
                                    expense.branchName,
                                    DateFormat.yMMMd().format(
                                      expense.incurredOn,
                                    ),
                                    expense.expenseNumber,
                                  ].whereType<String>().join(' • '),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                formatMoney(
                                  workspace.currencyCode,
                                  expense.signedAmountMinor,
                                ),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                expense.paymentMethod.replaceAll('_', ' '),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          if (canAttach && expense.entryType == 'expense')
                            IconButton(
                              tooltip: 'Attach receipt or document',
                              onPressed: () => _attachExpense(
                                context,
                                ref,
                                workspace,
                                expense,
                              ),
                              icon: const Icon(Icons.attach_file_rounded),
                            ),
                          if (canAttach && expense.entryType == 'expense')
                            IconButton(
                              tooltip: 'View attachments',
                              onPressed: () => _showAttachments(
                                context,
                                ref,
                                workspace,
                                expense,
                              ),
                              icon: const Icon(Icons.folder_open_outlined),
                            ),
                          if (canApprove &&
                              expense.entryType == 'expense' &&
                              expense.approvalStatus == 'pending') ...[
                            IconButton(
                              tooltip: 'Approve expense',
                              onPressed: () => _decideApproval(
                                context,
                                ref,
                                expense,
                                approve: true,
                              ),
                              icon: const Icon(
                                Icons.check_circle_outline_rounded,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Reject expense',
                              onPressed: () => _decideApproval(
                                context,
                                ref,
                                expense,
                                approve: false,
                              ),
                              icon: const Icon(Icons.cancel_outlined),
                            ),
                          ],
                          if (canManage &&
                              expense.entryType == 'expense' &&
                              expense.approvalStatus == 'approved')
                            IconButton(
                              tooltip: 'Request approval',
                              onPressed: () =>
                                  _requestApproval(context, ref, expense),
                              icon: const Icon(Icons.send_outlined),
                            ),
                          if (canManage && expense.entryType == 'expense') ...[
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Reverse expense',
                              onPressed: () =>
                                  _reverseExpense(context, ref, expense),
                              icon: const Icon(Icons.undo_rounded),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _copySelectedExpenses(List<ExpenseEntry> expenses) async {
    if (expenses.isEmpty) return;
    await Clipboard.setData(
      ClipboardData(
        text: expenses
            .map(
              (expense) =>
                  '${expense.expenseNumber}\t${expense.signedAmountMinor}',
            )
            .join('\n'),
      ),
    );
    if (!mounted) return;
    setState(() => _selectedExpenseIds.clear());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${expenses.length} expense${expenses.length == 1 ? '' : 's'} copied.',
        ),
      ),
    );
  }

  Future<void> _createExpense(
    BuildContext context,
    WidgetRef ref,
    BusinessWorkspace workspace,
  ) async {
    final categories = await ref.read(expenseCategoriesProvider.future);
    if (!context.mounted) return;
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _ExpenseDialog(
        workspace: workspace,
        categories: categories,
        repository: ref.read(accountingRepositoryProvider),
      ),
    );
    if (created == true) {
      ref.invalidate(expensesProvider);
      ref.invalidate(accountingDashboardProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Expense recorded.')));
      }
    }
  }

  Future<void> _reverseExpense(
    BuildContext context,
    WidgetRef ref,
    ExpenseEntry expense,
  ) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reverse expense'),
        content: TextField(
          controller: reason,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'Explain why this record is being reversed',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, reason.text.trim().isNotEmpty),
            child: const Text('Create reversal'),
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
          .reverseExpense(expenseId: expense.id, reason: reason.text);
      ref.invalidate(expensesProvider);
      ref.invalidate(accountingDashboardProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Expense reversed.')));
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

  Future<void> _requestApproval(
    BuildContext context,
    WidgetRef ref,
    ExpenseEntry expense,
  ) async {
    try {
      await ref
          .read(accountingRepositoryProvider)
          .requestExpenseApproval(expenseId: expense.id);
      ref.invalidate(expensesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense sent for approval.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _decideApproval(
    BuildContext context,
    WidgetRef ref,
    ExpenseEntry expense, {
    required bool approve,
  }) async {
    final note = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(approve ? 'Approve expense' : 'Reject expense'),
        content: TextField(
          controller: note,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      note.dispose();
      return;
    }
    try {
      await ref
          .read(accountingRepositoryProvider)
          .decideExpenseApproval(
            expenseId: expense.id,
            approve: approve,
            note: note.text,
          );
      ref.invalidate(expensesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approve ? 'Expense approved.' : 'Expense rejected.'),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      note.dispose();
    }
  }

  Future<void> _attachExpense(
    BuildContext context,
    WidgetRef ref,
    BusinessWorkspace workspace,
    ExpenseEntry expense,
  ) async {
    final file = await FilePicker.pickFile(type: FileType.any);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The selected file could not be read.')),
        );
      }
      return;
    }
    try {
      await ref
          .read(accountingRepositoryProvider)
          .uploadExpenseAttachment(
            businessId: workspace.businessId,
            expenseId: expense.id,
            fileName: file.name,
            bytes: bytes,
            mimeType: file.extension == null
                ? null
                : 'application/octet-stream',
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${file.name} attached to ${expense.expenseNumber}.'),
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

  Future<void> _showAttachments(
    BuildContext context,
    WidgetRef ref,
    BusinessWorkspace workspace,
    ExpenseEntry expense,
  ) async {
    try {
      final files = await ref
          .read(accountingRepositoryProvider)
          .fetchExpenseAttachments(workspace.businessId, expense.id);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Attachments • ${expense.expenseNumber}'),
          content: SizedBox(
            width: 480,
            child: files.isEmpty
                ? const Text('No attachments uploaded yet.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: files.length,
                    itemBuilder: (context, index) {
                      final file = files[index];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.insert_drive_file_outlined),
                        title: Text(
                          file['file_name'] as String? ?? 'Attachment',
                        ),
                        subtitle: Text('${file['file_size'] ?? 0} bytes'),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class _ExpenseDialog extends StatefulWidget {
  const _ExpenseDialog({
    required this.workspace,
    required this.categories,
    required this.repository,
  });

  final BusinessWorkspace workspace;
  final List<ExpenseCategory> categories;
  final AccountingRepository repository;

  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _tax = TextEditingController(text: '0.00');
  final _vendor = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  late String _categoryId;
  late String _branchId;
  String _paymentMethod = 'cash';
  DateTime _incurredOn = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.categories.firstOrNull?.id ?? '';
    _branchId = widget.workspace.branches.first.id;
  }

  @override
  void dispose() {
    for (final controller in [_amount, _tax, _vendor, _reference, _notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record expense'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _categoryId.isEmpty ? null : _categoryId,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: widget.categories
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) => _categoryId = value ?? '',
                  validator: (value) => value == null ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _branchId,
                  decoration: const InputDecoration(labelText: 'Branch'),
                  items: widget.workspace.branches
                      .map(
                        (branch) => DropdownMenuItem(
                          value: branch.id,
                          child: Text(branch.name),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) => _branchId = value ?? _branchId,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _amount,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: 'Amount'),
                        validator: (value) {
                          final parsed = parseMoneyToMinor(value ?? '');
                          return parsed == null || parsed <= 0
                              ? 'Enter a positive amount'
                              : null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _tax,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Tax included',
                        ),
                        validator: (value) =>
                            parseMoneyToMinor(value ?? '') == null
                            ? 'Enter a valid amount'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _paymentMethod,
                  decoration: const InputDecoration(labelText: 'Paid using'),
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
                  onChanged: (value) =>
                      _paymentMethod = value ?? _paymentMethod,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _vendor,
                  decoration: const InputDecoration(labelText: 'Vendor'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reference,
                  decoration: const InputDecoration(
                    labelText: 'Reference (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Expense date'),
                  subtitle: Text(DateFormat.yMMMd().format(_incurredOn)),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: _selectDate,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Record'),
        ),
      ],
    );
  }

  Future<void> _selectDate() async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now(),
      initialDate: _incurredOn,
    );
    if (selected != null) setState(() => _incurredOn = selected);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = parseMoneyToMinor(_amount.text)!;
    final tax = parseMoneyToMinor(_tax.text)!;
    if (tax > amount) {
      setState(() => _error = 'Tax cannot exceed the expense amount.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.createExpense(
        businessId: widget.workspace.businessId,
        branchId: _branchId,
        categoryId: _categoryId,
        amountMinor: amount,
        taxAmountMinor: tax,
        paymentMethod: _paymentMethod,
        incurredOn: _incurredOn,
        vendorName: _vendor.text,
        reference: _reference.text,
        notes: _notes.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
