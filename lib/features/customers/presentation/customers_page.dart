import 'package:flexpos/core/utils/money.dart';
import 'package:flexpos/core/security/crud_permissions.dart';
import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/core/widgets/data_page_skeleton.dart';
import 'package:flexpos/core/widgets/data_list_controls.dart';
import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/features/accounting/data/accounting_repository.dart';
import 'package:flexpos/features/catalog/data/catalog_repository.dart';
import 'package:flexpos/features/customers/data/customer_repository.dart';
import 'package:flexpos/features/customers/domain/customer_models.dart';
import 'package:flexpos/features/receipts/presentation/receipt_dialog.dart';
import 'package:flexpos/features/tenants/domain/business_workspace.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class CustomersPage extends ConsumerStatefulWidget {
  const CustomersPage({super.key});

  @override
  ConsumerState<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends ConsumerState<CustomersPage> {
  String _query = '';
  String _sort = 'name_asc';
  int _page = 0;
  final Set<String> _selectedCustomerIds = {};

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    if (workspace == null) {
      return const EmptyState(
        icon: Icons.add_business_outlined,
        title: 'Select a business',
        message: 'A workspace is required to view customers.',
      );
    }
    if (!workspace.canRead('customers')) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Customers are restricted',
        message: 'Your role does not include permission to view customers.',
      );
    }
    final customers = ref.watch(customersProvider);
    final groups = ref.watch(customerGroupsProvider);
    final canCreate = workspace.canCreate('customers');
    final canUpdate = workspace.canUpdate('customers');
    final canDelete = workspace.canDelete('customers');
    final canManage = canUpdate || canDelete;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _createCustomer(context, workspace),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('New customer'),
            )
          : null,
      body: customers.when(
        loading: () => const DataPageSkeleton(sectionLabel: 'customers'),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load customers',
          message: error.toString(),
          action: FilledButton.icon(
            onPressed: () => ref.invalidate(customersProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ),
        data: (items) {
          final canViewPurchases = workspace.permissionCodes.contains(
            'sales.view',
          );
          final canViewStatement = workspace.permissionCodes.contains(
            'customer_credit.view',
          );
          final filtered = items
              .where((customer) => customer.searchText.contains(_query))
              .toList();
          filtered.sort(
            (a, b) => switch (_sort) {
              'credit_desc' => b.creditLimitMinor.compareTo(a.creditLimitMinor),
              'points_desc' => b.loyaltyPoints.compareTo(a.loyaltyPoints),
              _ => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            },
          );
          final pageCount = pageCountFor(filtered.length);
          if (_page >= pageCount) _page = pageCount - 1;
          final visible = pageItems(filtered, _page);
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 96),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Customers',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  if (canManage)
                    OutlinedButton.icon(
                      onPressed: () => _createCustomerGroup(context, workspace),
                      icon: const Icon(Icons.group_add_outlined),
                      label: const Text('New group'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${items.length} active customer${items.length == 1 ? '' : 's'}',
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
                searchLabel: 'Search name, code, phone, or email',
                sortValue: _sort,
                sortOptions: const [
                  DataListSortOption('name_asc', 'Name (A–Z)'),
                  DataListSortOption('credit_desc', 'Credit limit (high–low)'),
                  DataListSortOption(
                    'points_desc',
                    'Loyalty points (high–low)',
                  ),
                ],
                onSortChanged: (value) => setState(() {
                  _sort = value;
                  _page = 0;
                }),
                page: _page,
                pageCount: pageCount,
                totalCount: filtered.length,
                onPageChanged: (value) => setState(() => _page = value),
                selectedCount: _selectedCustomerIds.length,
                allSelected:
                    visible.isNotEmpty &&
                    visible.every(
                      (customer) => _selectedCustomerIds.contains(customer.id),
                    ),
                onSelectAll: visible.isEmpty
                    ? null
                    : (selected) => setState(() {
                        if (selected ?? false) {
                          _selectedCustomerIds.addAll(
                            visible.map((customer) => customer.id),
                          );
                        } else {
                          _selectedCustomerIds.removeAll(
                            visible.map((customer) => customer.id),
                          );
                        }
                      }),
                onClearSelection: () =>
                    setState(() => _selectedCustomerIds.clear()),
                bulkActions: [
                  FilledButton.tonalIcon(
                    onPressed: () => _copySelectedContacts(
                      items
                          .where(
                            (customer) =>
                                _selectedCustomerIds.contains(customer.id),
                          )
                          .toList(growable: false),
                    ),
                    icon: const Icon(Icons.copy_all_rounded),
                    label: const Text('Copy contacts'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (visible.isEmpty)
                EmptyState(
                  icon: Icons.people_alt_outlined,
                  title: _query.isEmpty
                      ? 'No customers yet'
                      : 'No matching customers',
                  message: _query.isEmpty
                      ? 'Create a customer to attach them to POS sales.'
                      : 'Try a different search.',
                )
              else
                for (final customer in visible) ...[
                  AppPanel(
                    onTap: canViewPurchases
                        ? () =>
                              _showPurchaseHistory(context, workspace, customer)
                        : canViewStatement
                        ? () => _showStatement(context, workspace, customer)
                        : null,
                    child: Row(
                      children: [
                        Checkbox(
                          value: _selectedCustomerIds.contains(customer.id),
                          onChanged: (selected) => setState(() {
                            if (selected ?? false) {
                              _selectedCustomerIds.add(customer.id);
                            } else {
                              _selectedCustomerIds.remove(customer.id);
                            }
                          }),
                        ),
                        CircleAvatar(
                          child: Text(
                            customer.name.characters.first.toUpperCase(),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                customer.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                [
                                  customer.phone,
                                  customer.email,
                                  customer.groupName == null
                                      ? null
                                      : 'Group: ${customer.groupName}',
                                ].whereType<String>().join(' • '),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        if (customer.creditLimitMinor > 0)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                formatMoney(
                                  workspace.currencyCode,
                                  customer.creditLimitMinor,
                                ),
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              Text(
                                'Credit limit',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        if (customer.loyaltyPoints > 0)
                          Padding(
                            padding: const EdgeInsets.only(left: 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _pointsText(customer.loyaltyPoints),
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                Text(
                                  'Loyalty points',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        if (canUpdate)
                          IconButton(
                            tooltip: 'Edit customer',
                            onPressed: () =>
                                _editCustomer(context, workspace, customer),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        if (canDelete)
                          IconButton(
                            tooltip: 'Archive customer',
                            onPressed: () =>
                                _archiveCustomer(context, workspace, customer),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        if (canViewPurchases ||
                            canViewStatement ||
                            canUpdate) ...[
                          const SizedBox(width: 8),
                          PopupMenuButton<_CustomerAction>(
                            tooltip: 'Customer actions',
                            onSelected: (action) => switch (action) {
                              _CustomerAction.purchaseHistory =>
                                _showPurchaseHistory(
                                  context,
                                  workspace,
                                  customer,
                                ),
                              _CustomerAction.statement => _showStatement(
                                context,
                                workspace,
                                customer,
                              ),
                              _CustomerAction.changeGroup =>
                                _changeCustomerGroup(
                                  context,
                                  workspace,
                                  customer,
                                  groups.asData?.value ?? const [],
                                ),
                              _CustomerAction.loyalty => _showLoyalty(
                                context,
                                workspace,
                                customer,
                              ),
                            },
                            itemBuilder: (_) => [
                              if (canViewPurchases)
                                const PopupMenuItem(
                                  value: _CustomerAction.purchaseHistory,
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(Icons.shopping_bag_outlined),
                                    title: Text('Purchase history'),
                                  ),
                                ),
                              if (canViewStatement)
                                const PopupMenuItem(
                                  value: _CustomerAction.statement,
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                      Icons.account_balance_wallet_outlined,
                                    ),
                                    title: Text('Credit statement'),
                                  ),
                                ),
                              if (canUpdate)
                                const PopupMenuItem(
                                  value: _CustomerAction.changeGroup,
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(Icons.group_outlined),
                                    title: Text('Change group'),
                                  ),
                                ),
                              if (canUpdate)
                                const PopupMenuItem(
                                  value: _CustomerAction.loyalty,
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(Icons.loyalty_outlined),
                                    title: Text('Loyalty points'),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _copySelectedContacts(List<Customer> customers) async {
    if (customers.isEmpty) return;
    final text = customers
        .map(
          (customer) => [
            customer.name,
            customer.phone,
            customer.email,
          ].whereType<String>().where((value) => value.isNotEmpty).join(' • '),
        )
        .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _selectedCustomerIds.clear());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${customers.length} contact${customers.length == 1 ? '' : 's'} copied.',
        ),
      ),
    );
  }

  Future<void> _showStatement(
    BuildContext context,
    BusinessWorkspace workspace,
    Customer customer,
  ) => showDialog<void>(
    context: context,
    builder: (_) =>
        _CustomerStatementDialog(workspace: workspace, customer: customer),
  );

  Future<void> _showPurchaseHistory(
    BuildContext context,
    BusinessWorkspace workspace,
    Customer customer,
  ) => showDialog<void>(
    context: context,
    builder: (_) => _CustomerPurchaseHistoryDialog(
      workspace: workspace,
      customer: customer,
    ),
  );

  Future<void> _createCustomer(
    BuildContext context,
    BusinessWorkspace workspace,
  ) async {
    final groups = await ref.read(customerGroupsProvider.future);
    if (!context.mounted) return;
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CustomerDialog(
        workspace: workspace,
        repository: ref.read(customerRepositoryProvider),
        groups: groups,
      ),
    );
    if (created == true) {
      ref.invalidate(customersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Customer created.')));
      }
    }
  }

  Future<void> _editCustomer(
    BuildContext context,
    BusinessWorkspace workspace,
    Customer customer,
  ) async {
    final groups = await ref.read(customerGroupsProvider.future);
    if (!context.mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CustomerDialog(
        workspace: workspace,
        repository: ref.read(customerRepositoryProvider),
        groups: groups,
        customer: customer,
      ),
    );
    if (saved == true) {
      ref.invalidate(customersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Customer updated.')),
        );
      }
    }
  }

  Future<void> _archiveCustomer(
    BuildContext context,
    BusinessWorkspace workspace,
    Customer customer,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive customer?'),
        content: Text(
          '“${customer.name}” will be hidden from active lists. Historical sales are preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(customerRepositoryProvider).archiveCustomer(
        businessId: workspace.businessId,
        customerId: customer.id,
      );
      ref.invalidate(customersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Customer archived.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not archive customer: $error')),
        );
      }
    }
  }

  Future<void> _createCustomerGroup(
    BuildContext context,
    BusinessWorkspace workspace,
  ) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CustomerGroupDialog(
        workspace: workspace,
        repository: ref.read(customerRepositoryProvider),
      ),
    );
    if (created == true) {
      ref.invalidate(customerGroupsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Customer group created.')),
        );
      }
    }
  }

  Future<void> _changeCustomerGroup(
    BuildContext context,
    BusinessWorkspace workspace,
    Customer customer,
    List<CustomerGroup> groups,
  ) async {
    final choice = await showDialog<({bool save, String? groupId})>(
      context: context,
      builder: (_) =>
          _CustomerGroupChoiceDialog(customer: customer, groups: groups),
    );
    if (choice == null || !choice.save || !context.mounted) return;
    try {
      await ref
          .read(customerRepositoryProvider)
          .updateCustomerGroup(
            businessId: workspace.businessId,
            customerId: customer.id,
            groupId: choice.groupId,
          );
      ref.invalidate(customersProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update customer group: $error')),
        );
      }
    }
  }

  Future<void> _showLoyalty(
    BuildContext context,
    BusinessWorkspace workspace,
    Customer customer,
  ) => showDialog<void>(
    context: context,
    builder: (_) =>
        _CustomerLoyaltyDialog(workspace: workspace, customer: customer),
  );
}

enum _CustomerAction {
  purchaseHistory,
  statement,
  changeGroup,
  loyalty,
}

String _pointsText(double value) {
  final rounded = value.roundToDouble() == value
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '');
  return '$rounded pts';
}

class _CustomerLoyaltyDialog extends ConsumerStatefulWidget {
  const _CustomerLoyaltyDialog({
    required this.workspace,
    required this.customer,
  });

  final BusinessWorkspace workspace;
  final Customer customer;

  @override
  ConsumerState<_CustomerLoyaltyDialog> createState() =>
      _CustomerLoyaltyDialogState();
}

class _CustomerLoyaltyDialogState
    extends ConsumerState<_CustomerLoyaltyDialog> {
  final _points = TextEditingController();
  final _note = TextEditingController();
  String _mode = 'earn';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _points.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(
      customerLoyaltyTransactionsProvider(widget.customer.id),
    );
    final currentBalance =
        history.asData?.value.firstOrNull?.balanceAfter ??
        widget.customer.loyaltyPoints;
    return AlertDialog(
      title: Text('${widget.customer.name} loyalty'),
      content: SizedBox(
        width: 600,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppPanel(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Current balance'),
                  Text(
                    _pointsText(currentBalance),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'earn', label: Text('Earn')),
                ButtonSegment(value: 'redeem', label: Text('Redeem')),
                ButtonSegment(value: 'adjust', label: Text('Adjust')),
              ],
              selected: {_mode},
              onSelectionChanged: _saving
                  ? null
                  : (value) => setState(() => _mode = value.first),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _points,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: InputDecoration(
                labelText: _mode == 'adjust'
                    ? 'Points delta'
                    : _mode == 'earn'
                    ? 'Points to earn'
                    : 'Points to redeem',
                helperText: _mode == 'adjust'
                    ? 'Use a negative value to remove points.'
                    : null,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              enabled: !_saving,
              maxLength: 240,
              decoration: const InputDecoration(
                labelText: 'Reason or note',
                hintText: 'Campaign, correction, or redemption reference',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: history.when(
                loading: () => const DataListSkeleton(
                  sectionLabel: 'loyalty transactions',
                ),
                error: (error, _) => EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load loyalty history',
                  message: error.toString(),
                  action: FilledButton.icon(
                    onPressed: () => ref.invalidate(
                      customerLoyaltyTransactionsProvider(widget.customer.id),
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  ),
                ),
                data: (items) => items.isEmpty
                    ? const EmptyState(
                        icon: Icons.loyalty_outlined,
                        title: 'No loyalty activity',
                        message: 'Earned and redeemed points will appear here.',
                      )
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final positive = item.pointsDelta > 0;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              positive
                                  ? Icons.add_circle_outline
                                  : Icons.remove_circle_outline,
                              color: positive
                                  ? Colors.green
                                  : Theme.of(context).colorScheme.error,
                            ),
                            title: Text(_label(item.transactionType)),
                            subtitle: Text(
                              '${DateFormat.yMMMd().add_jm().format(item.createdAt)}'
                              '${item.note == null ? '' : ' · ${item.note}'}',
                            ),
                            trailing: Text(
                              '${positive ? '+' : ''}${_pointsText(item.pointsDelta)}',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Post transaction'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final parsed = double.tryParse(_points.text.trim());
    if (parsed == null || parsed == 0) {
      setState(() => _error = 'Enter a non-zero points value.');
      return;
    }
    final delta = _mode == 'redeem'
        ? -parsed.abs()
        : _mode == 'earn'
        ? parsed.abs()
        : parsed;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(customerRepositoryProvider)
          .adjustLoyaltyPoints(
            businessId: widget.workspace.businessId,
            customerId: widget.customer.id,
            pointsDelta: delta,
            transactionType: _mode,
            note: _note.text,
          );
      ref.invalidate(customerLoyaltyTransactionsProvider(widget.customer.id));
      ref.invalidate(customersProvider);
      if (mounted) {
        _points.clear();
        _note.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Loyalty transaction posted.')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _CustomerPurchaseHistoryDialog extends ConsumerWidget {
  const _CustomerPurchaseHistoryDialog({
    required this.workspace,
    required this.customer,
  });

  final BusinessWorkspace workspace;
  final Customer customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(customerPurchaseHistoryProvider(customer.id));
    return AlertDialog(
      title: Text('${customer.name} purchases'),
      content: SizedBox(
        width: 680,
        height: 500,
        child: history.when(
          loading: () =>
              const DataListSkeleton(sectionLabel: 'customer purchase history'),
          error: (error, _) => EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load purchase history',
            message: error.toString(),
            action: FilledButton.icon(
              onPressed: () =>
                  ref.invalidate(customerPurchaseHistoryProvider(customer.id)),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ),
          data: (purchases) {
            final netSpend = purchases.fold<int>(
              0,
              (total, purchase) => total + purchase.netTotalMinor,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _PurchaseMetric(
                      label: 'Purchases',
                      value: purchases.length.toString(),
                    ),
                    _PurchaseMetric(
                      label: 'Net spend',
                      value: formatMoney(workspace.currencyCode, netSpend),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: purchases.isEmpty
                      ? const EmptyState(
                          icon: Icons.shopping_bag_outlined,
                          title: 'No purchases yet',
                          message: 'Completed sales assigned to this customer appear here.',
                        )
                      : ListView.separated(
                          itemCount: purchases.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final purchase = purchases[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.receipt_long_outlined),
                              title: Text(purchase.invoiceNumber),
                              subtitle: Text(
                                '${DateFormat.yMMMd().add_jm().format(purchase.completedAt)} · '
                                '${purchase.itemCount} item${purchase.itemCount == 1 ? '' : 's'} · '
                                '${_label(purchase.paymentStatus)}',
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    formatMoney(
                                      workspace.currencyCode,
                                      purchase.netTotalMinor,
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                  ),
                                  if (purchase.refundedMinor > 0)
                                    Text(
                                      '${formatMoney(workspace.currencyCode, purchase.refundedMinor)} refunded',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                ],
                              ),
                              onTap: () => showReceiptDialog(
                                context: context,
                                ref: ref,
                                businessId: workspace.businessId,
                                saleId: purchase.saleId,
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _PurchaseMetric extends StatelessWidget {
  const _PurchaseMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => AppPanel(
    child: SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    ),
  );
}

String _label(String value) => value
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

class _CustomerStatementDialog extends ConsumerWidget {
  const _CustomerStatementDialog({
    required this.workspace,
    required this.customer,
  });

  final BusinessWorkspace workspace;
  final Customer customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statement = ref.watch(customerLedgerProvider(customer.id));
    return AlertDialog(
      title: Text('${customer.name} statement'),
      content: SizedBox(
        width: 620,
        height: 480,
        child: statement.when(
          loading: () =>
              const DataListSkeleton(sectionLabel: 'customer statement'),
          error: (error, _) => EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load statement',
            message: error.toString(),
          ),
          data: (entries) {
            final balance = entries.fold<int>(
              0,
              (total, entry) => total + entry.signedAmountMinor,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppPanel(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Outstanding balance'),
                      Text(
                        formatMoney(workspace.currencyCode, balance),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: entries.isEmpty
                      ? const EmptyState(
                          icon: Icons.account_balance_wallet_outlined,
                          title: 'No credit activity',
                          message: 'Credit sales and repayments appear here.',
                        )
                      : ListView.separated(
                          itemCount: entries.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                entry.direction == 'debit'
                                    ? Icons.arrow_upward_rounded
                                    : Icons.arrow_downward_rounded,
                                color: entry.direction == 'debit'
                                    ? Theme.of(context).colorScheme.error
                                    : Colors.green,
                              ),
                              title: Text(entry.description),
                              subtitle: Text(
                                DateFormat.yMMMd().add_jm().format(
                                  entry.occurredAt,
                                ),
                              ),
                              trailing: Text(
                                formatMoney(
                                  workspace.currencyCode,
                                  entry.signedAmountMinor,
                                ),
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            );
                          },
                        ),
                ),
                if (balance > 0 &&
                    workspace.permissionCodes.contains(
                      'customer_credit.manage',
                    )) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () =>
                              _recordRepayment(context, ref, balance),
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('Record repayment'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _recordAdjustment(context, ref, balance),
                          icon: const Icon(Icons.tune_rounded),
                          label: const Text('Adjust credit'),
                        ),
                      ),
                    ],
                  ),
                ],
                if (balance <= 0 &&
                    workspace.permissionCodes.contains(
                      'customer_credit.manage',
                    )) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => _recordAdjustment(context, ref, balance),
                      icon: const Icon(Icons.tune_rounded),
                      label: const Text('Adjust credit'),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Future<void> _recordRepayment(
    BuildContext context,
    WidgetRef ref,
    int outstandingMinor,
  ) async {
    final recorded = await showDialog<bool>(
      context: context,
      builder: (_) => _RepaymentDialog(
        workspace: workspace,
        customer: customer,
        outstandingMinor: outstandingMinor,
        repository: ref.read(accountingRepositoryProvider),
      ),
    );
    if (recorded == true) {
      ref.invalidate(customerLedgerProvider(customer.id));
      ref.invalidate(accountingDashboardProvider);
      ref.invalidate(salesProvider);
      ref.invalidate(filteredSalesProvider);
    }
  }

  Future<void> _recordAdjustment(
    BuildContext context,
    WidgetRef ref,
    int outstandingMinor,
  ) async {
    final recorded = await showDialog<bool>(
      context: context,
      builder: (_) => _CreditAdjustmentDialog(
        workspace: workspace,
        customer: customer,
        outstandingMinor: outstandingMinor,
        repository: ref.read(accountingRepositoryProvider),
      ),
    );
    if (recorded == true) {
      ref.invalidate(customerLedgerProvider(customer.id));
      ref.invalidate(accountingDashboardProvider);
    }
  }
}

class _CreditAdjustmentDialog extends StatefulWidget {
  const _CreditAdjustmentDialog({
    required this.workspace,
    required this.customer,
    required this.outstandingMinor,
    required this.repository,
  });

  final BusinessWorkspace workspace;
  final Customer customer;
  final int outstandingMinor;
  final AccountingRepository repository;

  @override
  State<_CreditAdjustmentDialog> createState() =>
      _CreditAdjustmentDialogState();
}

class _CreditAdjustmentDialogState extends State<_CreditAdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  late String _branchId;
  String _adjustmentType = 'credit';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _branchId = widget.workspace.branches.first.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Adjust credit · ${widget.customer.name}'),
    content: SizedBox(
      width: 480,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Current outstanding: ${formatMoney(widget.workspace.currencyCode, widget.outstandingMinor)}',
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _adjustmentType,
              decoration: const InputDecoration(labelText: 'Adjustment type'),
              items: const [
                DropdownMenuItem(
                  value: 'credit',
                  child: Text('Credit adjustment (reduce due)'),
                ),
                DropdownMenuItem(
                  value: 'debit',
                  child: Text('Debit adjustment (increase due)'),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(
                      () => _adjustmentType = value ?? _adjustmentType,
                    ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Amount'),
              validator: (value) {
                final amount = parseMoneyToMinor(value ?? '');
                if (amount == null || amount <= 0) {
                  return 'Enter a positive amount';
                }
                if (_adjustmentType == 'credit' &&
                    amount > widget.outstandingMinor) {
                  return 'Amount exceeds outstanding balance';
                }
                return null;
              },
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
            TextFormField(
              controller: _description,
              maxLength: 240,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Reason for this adjustment',
              ),
              validator: (value) => value == null || value.trim().length < 3
                  ? 'Enter a meaningful description'
                  : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
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
            : const Text('Post adjustment'),
      ),
    ],
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.createCustomerCreditAdjustment(
        businessId: widget.workspace.businessId,
        branchId: _branchId,
        customerId: widget.customer.id,
        adjustmentType: _adjustmentType,
        amountMinor: parseMoneyToMinor(_amount.text)!,
        description: _description.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _RepaymentDialog extends StatefulWidget {
  const _RepaymentDialog({
    required this.workspace,
    required this.customer,
    required this.outstandingMinor,
    required this.repository,
  });

  final BusinessWorkspace workspace;
  final Customer customer;
  final int outstandingMinor;
  final AccountingRepository repository;

  @override
  State<_RepaymentDialog> createState() => _RepaymentDialogState();
}

class _RepaymentDialogState extends State<_RepaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  late String _branchId;
  String _paymentMethod = 'cash';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _branchId = widget.workspace.branches.first.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Repayment from ${widget.customer.name}'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Outstanding: ${formatMoney(widget.workspace.currencyCode, widget.outstandingMinor)}',
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Amount received'),
                validator: (value) {
                  final amount = parseMoneyToMinor(value ?? '');
                  if (amount == null || amount <= 0) {
                    return 'Enter a positive amount';
                  }
                  if (amount > widget.outstandingMinor) {
                    return 'Amount exceeds outstanding balance';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _branchId,
                decoration: const InputDecoration(
                  labelText: 'Receiving branch',
                ),
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
              DropdownButtonFormField<String>(
                initialValue: _paymentMethod,
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
                onChanged: (value) => _paymentMethod = value ?? _paymentMethod,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reference,
                decoration: const InputDecoration(labelText: 'Reference'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
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
              : const Text('Record repayment'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.recordCustomerRepayment(
        businessId: widget.workspace.businessId,
        branchId: _branchId,
        customerId: widget.customer.id,
        amountMinor: parseMoneyToMinor(_amount.text)!,
        paymentMethod: _paymentMethod,
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

class _CustomerDialog extends StatefulWidget {
  const _CustomerDialog({
    required this.workspace,
    required this.repository,
    required this.groups,
    this.customer,
  });

  final BusinessWorkspace workspace;
  final CustomerRepository repository;
  final List<CustomerGroup> groups;
  final Customer? customer;

  @override
  State<_CustomerDialog> createState() => _CustomerDialogState();
}

class _CustomerDialogState extends State<_CustomerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _gstin = TextEditingController();
  final _creditLimit = TextEditingController(text: '0.00');
  String? _groupId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final customer = widget.customer;
    if (customer != null) {
      _name.text = customer.name;
      _code.text = customer.code ?? '';
      _phone.text = customer.phone ?? '';
      _email.text = customer.email ?? '';
      _gstin.text = customer.gstin ?? '';
      _creditLimit.text = (customer.creditLimitMinor / 100).toStringAsFixed(2);
      _groupId = customer.groupId;
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _code,
      _phone,
      _email,
      _gstin,
      _creditLimit,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.customer == null ? 'Create customer' : 'Edit customer'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Customer name'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _code,
                        decoration: const InputDecoration(
                          labelText: 'Code (optional)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Phone'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    return text.isNotEmpty && !text.contains('@')
                        ? 'Enter a valid email'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _gstin,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'GSTIN (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _creditLimit,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Credit limit'),
                  validator: (value) => parseMoneyToMinor(value ?? '') == null
                      ? 'Enter a valid amount'
                      : null,
                ),
                if (widget.groups.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _groupId,
                    decoration: const InputDecoration(labelText: 'Group'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('No group'),
                      ),
                      for (final group in widget.groups)
                        DropdownMenuItem<String?>(
                          value: group.id,
                          child: Text(group.name),
                        ),
                    ],
                    onChanged: (value) => setState(() => _groupId = value),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
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
              : Text(widget.customer == null ? 'Create' : 'Save changes'),
        ),
      ],
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final customer = widget.customer;
      if (customer == null) {
        await widget.repository.createCustomer(
          businessId: widget.workspace.businessId,
          name: _name.text,
          code: _code.text,
          phone: _phone.text,
          email: _email.text,
          gstin: _gstin.text,
          creditLimitMinor: parseMoneyToMinor(_creditLimit.text)!,
          groupId: _groupId,
        );
      } else {
        await widget.repository.updateCustomer(
          businessId: widget.workspace.businessId,
          customerId: customer.id,
          name: _name.text,
          code: _code.text,
          phone: _phone.text,
          email: _email.text,
          gstin: _gstin.text,
          creditLimitMinor: parseMoneyToMinor(_creditLimit.text)!,
          groupId: _groupId,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _CustomerGroupDialog extends StatefulWidget {
  const _CustomerGroupDialog({
    required this.workspace,
    required this.repository,
  });

  final BusinessWorkspace workspace;
  final CustomerRepository repository;

  @override
  State<_CustomerGroupDialog> createState() => _CustomerGroupDialogState();
}

class _CustomerGroupDialogState extends State<_CustomerGroupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _description = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New customer group'),
    content: SizedBox(
      width: 460,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Group name'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _code,
              decoration: const InputDecoration(labelText: 'Code (optional)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 2,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
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
            : const Text('Create group'),
      ),
    ],
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.createCustomerGroup(
        businessId: widget.workspace.businessId,
        name: _name.text,
        code: _code.text,
        description: _description.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _CustomerGroupChoiceDialog extends StatefulWidget {
  const _CustomerGroupChoiceDialog({
    required this.customer,
    required this.groups,
  });

  final Customer customer;
  final List<CustomerGroup> groups;

  @override
  State<_CustomerGroupChoiceDialog> createState() =>
      _CustomerGroupChoiceDialogState();
}

class _CustomerGroupChoiceDialogState
    extends State<_CustomerGroupChoiceDialog> {
  late String? _groupId = widget.customer.groupId;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Group for ${widget.customer.name}'),
    content: DropdownButtonFormField<String?>(
      initialValue: _groupId,
      decoration: const InputDecoration(labelText: 'Customer group'),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('No group')),
        for (final group in widget.groups)
          DropdownMenuItem<String?>(value: group.id, child: Text(group.name)),
      ],
      onChanged: (value) => setState(() => _groupId = value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.pop(context, (save: true, groupId: _groupId)),
        child: const Text('Save'),
      ),
    ],
  );
}
