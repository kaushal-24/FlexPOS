import 'dart:async';

import 'package:flexpos/core/utils/money.dart';
import 'package:flexpos/core/utils/csv_export.dart';
import 'package:flexpos/core/utils/pdf_export.dart';
import 'package:flexpos/core/security/crud_permissions.dart';
import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/core/widgets/data_page_skeleton.dart';
import 'package:flexpos/core/widgets/data_list_controls.dart';
import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/core/widgets/product_image.dart';
import 'package:flexpos/core/widgets/status_badge.dart';
import 'package:flexpos/features/accounting/data/accounting_repository.dart';
import 'package:flexpos/features/auth/data/auth_repository.dart';
import 'package:flexpos/features/catalog/data/catalog_repository.dart';
import 'package:flexpos/features/catalog/domain/catalog_models.dart';
import 'package:flexpos/features/customers/data/customer_repository.dart';
import 'package:flexpos/features/customers/domain/customer_models.dart';
import 'package:flexpos/features/pos/domain/pos_calculations.dart';
import 'package:flexpos/features/receipts/presentation/receipt_dialog.dart';
import 'package:flexpos/features/registers/data/register_repository.dart';
import 'package:flexpos/features/registers/domain/register_models.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({super.key});

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  Timer? _searchDebounce;
  String _search = '';
  SaleHistoryStatusFilter _status = SaleHistoryStatusFilter.all;
  DateTimeRange? _dateRange;
  String _sort = 'newest';
  int _page = 0;
  final Set<String> _selectedSaleIds = {};

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _updateSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _search = value.trim());
    });
  }

  Future<void> _chooseDateRange() async {
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _dateRange,
      helpText: 'Filter completed sales by date',
    );
    if (selected != null && mounted) {
      setState(() => _dateRange = selected);
    }
  }

  void _clearFilters() {
    _searchDebounce?.cancel();
    setState(() {
      _search = '';
      _status = SaleHistoryStatusFilter.all;
      _dateRange = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    if (workspace == null) {
      return const EmptyState(
        icon: Icons.add_business_outlined,
        title: 'Select a business',
        message: 'A business workspace is required to view orders.',
      );
    }
    if (!workspace.canRead('sales')) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Orders are restricted',
        message: 'Your role does not include permission to view sales.',
      );
    }
    final canRefund = workspace.permissionCodes.contains('sales.refund');
    final canCreateSale = workspace.canCreate('sales');
    final canUpdateSale = workspace.canUpdate('sales');
    final canExchange = canRefund && workspace.canCreate('sales');
    final canReconcilePayments = workspace.permissionCodes.contains(
      'payments.reconcile',
    );
    final canViewTaxInvoice = workspace.canRead('tax');
    final filter = SaleHistoryFilter(
      businessId: workspace.businessId,
      search: _search,
      status: _status,
      from: _dateRange?.start,
      through: _dateRange?.end,
    );
    final sales = ref.watch(filteredSalesProvider(filter));
    final customers = ref.watch(customersProvider).value ?? const <Customer>[];
    return sales.when(
      loading: () => const DataPageSkeleton(sectionLabel: 'orders'),
      error: (error, _) => EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load orders',
        message: error.toString(),
        action: FilledButton.icon(
          onPressed: () => ref.invalidate(filteredSalesProvider(filter)),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      ),
      data: (items) {
        final sorted = items.toList();
        sorted.sort(
          (a, b) => switch (_sort) {
            'oldest' => a.completedAt.compareTo(b.completedAt),
            'amount_desc' => b.netTotalMinor.compareTo(a.netTotalMinor),
            'amount_asc' => a.netTotalMinor.compareTo(b.netTotalMinor),
            _ => b.completedAt.compareTo(a.completedAt),
          },
        );
        final pageCount = pageCountFor(sorted.length);
        if (_page >= pageCount) _page = pageCount - 1;
        final visible = pageItems(sorted, _page);
        return RefreshIndicator(
          onRefresh: () => ref.refresh(filteredSalesProvider(filter).future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 12,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sales',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      Text(
                        '${items.length} ${filter.isActive ? 'matching' : 'recent'} sale${items.length == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _exportSales(items),
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Export CSV'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _exportSalesPdf(items),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Export PDF'),
                      ),
                      if (canCreateSale)
                        FilledButton.icon(
                          onPressed: () => context.go('/pos'),
                          icon: const Icon(Icons.add_shopping_cart_rounded),
                          label: const Text('New sale'),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _OrderFilters(
                status: _status,
                dateRange: _dateRange,
                filtersActive: filter.isActive,
                onStatusChanged: (value) => setState(() => _status = value),
                onChooseDates: _chooseDateRange,
                onClear: _clearFilters,
              ),
              const SizedBox(height: 12),
              DataListControls(
                query: _search,
                onSearchChanged: _updateSearch,
                searchLabel: 'Search invoice number',
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
                totalCount: sorted.length,
                onPageChanged: (value) => setState(() => _page = value),
                selectedCount: _selectedSaleIds.length,
                allSelected:
                    visible.isNotEmpty &&
                    visible.every((sale) => _selectedSaleIds.contains(sale.id)),
                onSelectAll: visible.isEmpty
                    ? null
                    : (selected) => setState(() {
                        if (selected ?? false) {
                          _selectedSaleIds.addAll(
                            visible.map((sale) => sale.id),
                          );
                        } else {
                          _selectedSaleIds.removeAll(
                            visible.map((sale) => sale.id),
                          );
                        }
                      }),
                onClearSelection: () =>
                    setState(() => _selectedSaleIds.clear()),
                bulkActions: [
                  FilledButton.tonalIcon(
                    onPressed: () => _copySelectedInvoices(
                      items
                          .where((sale) => _selectedSaleIds.contains(sale.id))
                          .toList(growable: false),
                    ),
                    icon: const Icon(Icons.copy_all_rounded),
                    label: const Text('Copy invoices'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (visible.isEmpty)
                EmptyState(
                  icon: filter.isActive
                      ? Icons.search_off_rounded
                      : Icons.receipt_long_outlined,
                  title: filter.isActive
                      ? 'No matching orders'
                      : 'No orders yet',
                  message: filter.isActive
                      ? 'Try a different invoice number, status, or date range.'
                      : 'Completed POS sales will appear here.',
                  action: filter.isActive
                      ? OutlinedButton.icon(
                          onPressed: _clearFilters,
                          icon: const Icon(Icons.filter_alt_off_outlined),
                          label: const Text('Clear filters'),
                        )
                      : null,
                )
              else
                for (final sale in visible) ...[
                  AppPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: _selectedSaleIds.contains(sale.id),
                              onChanged: (selected) => setState(() {
                                if (selected ?? false) {
                                  _selectedSaleIds.add(sale.id);
                                } else {
                                  _selectedSaleIds.remove(sale.id);
                                }
                              }),
                            ),
                            const CircleAvatar(
                              child: Icon(Icons.receipt_long_outlined),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SelectableText(
                                    sale.invoiceNumber,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    DateFormat.yMMMd().add_jm().format(
                                      sale.completedAt,
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
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
                                    sale.netTotalMinor,
                                  ),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 5),
                                StatusBadge(
                                  label: _saleStatusLabel(sale),
                                  tone: _saleStatusTone(sale),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (sale.refundedTotalMinor > 0) ...[
                          const SizedBox(height: 12),
                          Text(
                            '${formatMoney(workspace.currencyCode, sale.refundedTotalMinor)} returned from '
                            '${formatMoney(workspace.currencyCode, sale.grandTotalMinor)}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                        for (final note in sale.creditNotes) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .secondaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.confirmation_number_outlined),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SelectableText(
                                        note.number,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge,
                                      ),
                                      Text(
                                        'Expires ${DateFormat.yMMMd().format(note.expiresAt)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      formatMoney(
                                        workspace.currencyCode,
                                        note.availableAmountMinor,
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge,
                                    ),
                                    Text(
                                      note.isRedeemed
                                          ? 'Redeemed'
                                          : note.isExpired
                                          ? 'Expired'
                                          : 'Available',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                        for (final payment in sale.pendingExternalPayments) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .tertiaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.pending_actions_outlined),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${payment.methodLabel} verification pending',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge,
                                      ),
                                      Text(
                                        [
                                              if (payment.provider != null)
                                                payment.provider!,
                                              if (payment.reference != null)
                                                payment.reference!,
                                            ].isEmpty
                                            ? 'Awaiting settlement evidence'
                                            : [
                                                if (payment.provider != null)
                                                  payment.provider!,
                                                if (payment.reference != null)
                                                  payment.reference!,
                                              ].join(' • '),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      formatMoney(
                                        workspace.currencyCode,
                                        payment.amountMinor,
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge,
                                    ),
                                    if (canReconcilePayments)
                                      TextButton(
                                        onPressed: () =>
                                            _openPaymentReconciliationDialog(
                                              context,
                                              ref,
                                              payment,
                                              workspace.currencyCode,
                                            ),
                                        child: const Text('Reconcile'),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                        const Divider(height: 28),
                        Wrap(
                          alignment: WrapAlignment.start,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _showSaleDetails(
                                context,
                                sale,
                                workspace.currencyCode,
                              ),
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('View details'),
                            ),
                            if (canUpdateSale)
                              OutlinedButton.icon(
                                onPressed: () => _showEditSaleDialog(
                                  context,
                                  sale,
                                  customers,
                                ),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Edit sale'),
                              ),
                            OutlinedButton.icon(
                              onPressed: () => showReceiptDialog(
                                context: context,
                                ref: ref,
                                businessId: workspace.businessId,
                                saleId: sale.id,
                              ),
                              icon: const Icon(Icons.print_outlined),
                              label: const Text('Receipt'),
                            ),
                            if (canViewTaxInvoice)
                              OutlinedButton.icon(
                                onPressed: () => _showTaxInvoice(
                                  context,
                                  sale.id,
                                  workspace.currencyCode,
                                ),
                                icon: const Icon(Icons.receipt_long_outlined),
                                label: const Text('Tax invoice'),
                              ),
                            if (canRefund && sale.canReturn)
                              OutlinedButton.icon(
                                onPressed: () => _openReturnDialog(
                                  context,
                                  ref,
                                  sale,
                                  workspace.currencyCode,
                                ),
                                icon: const Icon(
                                  Icons.assignment_return_outlined,
                                ),
                                label: const Text('Return items'),
                              ),
                            if (canExchange && sale.canReturn)
                              FilledButton.tonalIcon(
                                onPressed: () => _openExchangeDialog(
                                  context,
                                  ref,
                                  sale,
                                  workspace.currencyCode,
                                ),
                                icon: const Icon(Icons.swap_horiz_rounded),
                                label: const Text('Exchange'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _exportSales(List<SaleSummary> items) async {
    try {
      final path = await saveCsvExport(
        fileName: 'flexpos-sales.csv',
        rows: [
          const [
            'Invoice',
            'Completed at',
            'Grand total (minor)',
            'Refunded total (minor)',
            'Net total (minor)',
            'Payment status',
            'Sale status',
          ],
          for (final sale in items)
            [
              sale.invoiceNumber,
              sale.completedAt.toIso8601String(),
              sale.grandTotalMinor,
              sale.refundedTotalMinor,
              sale.netTotalMinor,
              sale.paymentStatus,
              sale.status,
            ],
        ],
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sales CSV exported.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not export sales: $error')));
    }
  }

  Future<void> _exportSalesPdf(List<SaleSummary> items) async {
    try {
      final path = await savePdfExport(
        fileName: 'flexpos-sales.pdf',
        title: 'FlexPOS sales',
        headers: const [
          'Invoice',
          'Completed at',
          'Grand total (minor)',
          'Refunded total (minor)',
          'Net total (minor)',
          'Payment status',
          'Sale status',
        ],
        rows: [
          for (final sale in items)
            [
              sale.invoiceNumber,
              sale.completedAt.toIso8601String(),
              sale.grandTotalMinor,
              sale.refundedTotalMinor,
              sale.netTotalMinor,
              sale.paymentStatus,
              sale.status,
            ],
        ],
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sales PDF exported.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not export sales: $error')));
    }
  }

  Future<void> _showTaxInvoice(
    BuildContext context,
    String saleId,
    String currencyCode,
  ) async {
    try {
      final data = await ref
          .read(accountingRepositoryProvider)
          .getTaxInvoiceBreakdown(saleId);
      if (!context.mounted) return;
      final lines = (data['lines'] as List? ?? const [])
          .map((line) => Map<String, dynamic>.from(line as Map))
          .toList(growable: false);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Tax invoice ${data['invoice_number'] ?? ''}'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Place of supply: ${data['place_of_supply'] ?? 'Not configured'}',
                  ),
                  Text(
                    data['interstate'] == true
                        ? 'IGST supply'
                        : 'CGST + SGST supply',
                  ),
                  const SizedBox(height: 12),
                  for (final line in lines)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${line['product_name']} • ${line['sku']}'),
                      subtitle: Text(
                        'Tax ${line['tax_rate']}% • CGST ${formatMoney(currencyCode, _minorValue(line['cgst']))} • SGST ${formatMoney(currencyCode, _minorValue(line['sgst']))} • IGST ${formatMoney(currencyCode, _minorValue(line['igst']))}',
                      ),
                      trailing: Text(
                        formatMoney(
                          currencyCode,
                          _minorValue(line['tax_amount']),
                        ),
                      ),
                    ),
                  const Divider(),
                  Text(
                    'Total tax: ${formatMoney(currencyCode, _minorValue(data['tax_total']))}',
                  ),
                ],
              ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load tax invoice: $error')),
        );
      }
    }
  }

  Future<void> _showSaleDetails(
    BuildContext context,
    SaleSummary sale,
    String currencyCode,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Sale ${sale.invoiceNumber}'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Completed ${DateFormat.yMMMd().add_jm().format(sale.completedAt)}',
                ),
                const SizedBox(height: 10),
                Text('Status: ${_saleStatusLabel(sale)}'),
                Text('Payment: ${sale.paymentStatus}'),
                Text(
                  'Total: ${formatMoney(currencyCode, sale.grandTotalMinor)}',
                ),
                if (sale.customerId != null) const Text('Customer linked'),
                if (sale.notes?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text('Notes: ${sale.notes}'),
                ],
                if (sale.refundedTotalMinor > 0)
                  Text(
                    'Refunded: ${formatMoney(currencyCode, sale.refundedTotalMinor)}',
                  ),
                const SizedBox(height: 14),
                const Text(
                  'Payments',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                for (final payment in sale.payments)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(payment.methodLabel),
                    subtitle: Text(payment.status),
                    trailing: Text(
                      formatMoney(currencyCode, payment.amountMinor),
                    ),
                  ),
              ],
            ),
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
  }

  Future<void> _showEditSaleDialog(
    BuildContext context,
    SaleSummary sale,
    List<Customer> customers,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditSaleDialog(sale: sale, customers: customers),
    );
    if (saved == true) {
      ref.invalidate(salesProvider);
      ref.invalidate(filteredSalesProvider);
    }
  }

  Future<void> _copySelectedInvoices(List<SaleSummary> sales) async {
    if (sales.isEmpty) return;
    await Clipboard.setData(
      ClipboardData(
        text: sales
            .map((sale) => '${sale.invoiceNumber}\t${sale.netTotalMinor}')
            .join('\n'),
      ),
    );
    if (!mounted) return;
    setState(() => _selectedSaleIds.clear());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${sales.length} invoice${sales.length == 1 ? '' : 's'} copied.',
        ),
      ),
    );
  }
}

class _EditSaleDialog extends ConsumerStatefulWidget {
  const _EditSaleDialog({required this.sale, required this.customers});

  final SaleSummary sale;
  final List<Customer> customers;

  @override
  ConsumerState<_EditSaleDialog> createState() => _EditSaleDialogState();
}

class _EditSaleDialogState extends ConsumerState<_EditSaleDialog> {
  late final TextEditingController _notes;
  String? _customerId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _customerId = widget.sale.customerId;
    _notes = TextEditingController(text: widget.sale.notes ?? '');
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  List<Customer> get _customerOptions {
    final options = [...widget.customers];
    if (_customerId != null &&
        !options.any((customer) => customer.id == _customerId)) {
      options.insert(
        0,
        Customer(
          id: _customerId!,
          name: 'Current customer',
          creditLimitMinor: 0,
        ),
      );
    }
    return options;
  }

  Future<void> _save() async {
    if (_notes.text.length > 1000) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(catalogRepositoryProvider)
          .updateSaleMetadata(
            saleId: widget.sale.id,
            customerId: _customerId,
            notes: _notes.text,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update sale: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = _customerOptions;
    return AlertDialog(
      title: Text('Edit sale ${widget.sale.invoiceNumber}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _customerId ?? '',
                decoration: const InputDecoration(
                  labelText: 'Customer',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Walk-in customer'),
                  ),
                  ...options.map(
                    (customer) => DropdownMenuItem(
                      value: customer.id,
                      child: Text(customer.name),
                    ),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(
                        () => _customerId = value == null || value.isEmpty
                            ? null
                            : value,
                      ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _notes,
                maxLength: 1000,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Sale notes',
                  hintText: 'Add an internal note for this sale',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Invoice totals, line items, payments, and return history remain immutable.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('Save changes'),
        ),
      ],
    );
  }
}

class _OrderFilters extends StatelessWidget {
  const _OrderFilters({
    required this.status,
    required this.dateRange,
    required this.filtersActive,
    required this.onStatusChanged,
    required this.onChooseDates,
    required this.onClear,
  });

  final SaleHistoryStatusFilter status;
  final DateTimeRange? dateRange;
  final bool filtersActive;
  final ValueChanged<SaleHistoryStatusFilter> onStatusChanged;
  final VoidCallback onChooseDates;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final dateLabel = dateRange == null
        ? 'Any date'
        : '${DateFormat.yMMMd().format(dateRange!.start)} – ${DateFormat.yMMMd().format(dateRange!.end)}';
    return LayoutBuilder(
      builder: (context, constraints) {
        // The invoice filters are also rendered in the compact browser view.
        // Size fields from the viewport so the status field can never push
        // its dropdown arrow outside the screen.
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 330.0;
        final statusWidth = availableWidth < 210 ? availableWidth : 210.0;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: statusWidth,
              child: DropdownButtonFormField<SaleHistoryStatusFilter>(
                initialValue: status,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                items: [
                  for (final value in SaleHistoryStatusFilter.values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(
                        value.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) onStatusChanged(value);
                },
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: availableWidth),
              child: OutlinedButton.icon(
                onPressed: onChooseDates,
                icon: const Icon(Icons.date_range_outlined),
                label: Text(
                  dateLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (filtersActive)
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Clear'),
              ),
          ],
        );
      },
    );
  }
}

String _saleStatusLabel(SaleSummary sale) => switch (sale.status) {
  'refunded' => 'Refunded',
  'partially_refunded' => 'Partially refunded',
  _ when sale.paymentStatus == 'paid' => 'Paid',
  _ => 'Pending',
};

StatusTone _saleStatusTone(SaleSummary sale) => switch (sale.status) {
  'refunded' => StatusTone.neutral,
  'partially_refunded' => StatusTone.warning,
  _ when sale.paymentStatus == 'paid' => StatusTone.success,
  _ => StatusTone.warning,
};

Future<void> _openPaymentReconciliationDialog(
  BuildContext context,
  WidgetRef ref,
  PaymentSummary payment,
  String currencyCode,
) async {
  final reconciled = await showDialog<bool>(
    context: context,
    builder: (_) => _PaymentReconciliationDialog(
      payment: payment,
      currencyCode: currencyCode,
      repository: ref.read(catalogRepositoryProvider),
    ),
  );
  if (reconciled != true || !context.mounted) return;
  ref.invalidate(salesProvider);
  ref.invalidate(filteredSalesProvider);
  ref.invalidate(accountingDashboardProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Payment reconciliation recorded.')),
  );
}

class _PaymentReconciliationDialog extends StatefulWidget {
  const _PaymentReconciliationDialog({
    required this.payment,
    required this.currencyCode,
    required this.repository,
  });

  final PaymentSummary payment;
  final String currencyCode;
  final CatalogRepository repository;

  @override
  State<_PaymentReconciliationDialog> createState() =>
      _PaymentReconciliationDialogState();
}

class _PaymentReconciliationDialogState
    extends State<_PaymentReconciliationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _noteController = TextEditingController();
  late final TextEditingController _referenceController;
  final String _operationId = createUuidV4();
  String _status = 'settled';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _referenceController = TextEditingController(
      text: widget.payment.reference ?? '',
    );
  }

  @override
  void dispose() {
    _referenceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.reconcilePayment(
        paymentId: widget.payment.id,
        operationId: _operationId,
        status: _status,
        reference: _referenceController.text,
        note: _noteController.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.verified_user_outlined),
      title: const Text('Reconcile payment'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${widget.payment.methodLabel} • ${formatMoney(widget.currencyCode, widget.payment.amountMinor)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'This action does not contact the provider. Record it only after checking independent provider or bank evidence.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Verification result',
                    prefixIcon: Icon(Icons.rule_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'settled',
                      child: Text('Verified and settled'),
                    ),
                    DropdownMenuItem(
                      value: 'failed',
                      child: Text('Failed / rejected'),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) setState(() => _status = value);
                        },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _referenceController,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Evidence reference',
                    hintText: 'Settlement, bank, or provider reference',
                    prefixIcon: Icon(Icons.tag_outlined),
                  ),
                  maxLength: 200,
                  validator: (value) {
                    final length = value?.trim().length ?? 0;
                    if (length < 4) return 'Enter at least 4 characters.';
                    return null;
                  },
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _noteController,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Reconciliation note',
                    hintText:
                        'Describe where and when the evidence was checked',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 1000,
                  validator: (value) {
                    final length = value?.trim().length ?? 0;
                    if (length < 8) return 'Enter at least 8 characters.';
                    return null;
                  },
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
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _submit,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _status == 'settled'
                      ? Icons.verified_outlined
                      : Icons.cancel_outlined,
                ),
          label: Text(
            _status == 'settled' ? 'Record settlement' : 'Record failure',
          ),
        ),
      ],
    );
  }
}

Future<void> _openReturnDialog(
  BuildContext context,
  WidgetRef ref,
  SaleSummary sale,
  String currencyCode,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final repository = ref.read(catalogRepositoryProvider);
    final results = await Future.wait<Object>([
      repository.fetchReturnableSaleItems(sale.id),
      repository.fetchSerializedSaleReturnUnits(sale.id),
    ]);
    if (!context.mounted) return;
    final items = results[0] as List<ReturnableSaleItem>;
    final serializedUnits =
        results[1] as Map<String, List<SerializedSaleReturnUnit>>;
    if (items.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('This sale has no remaining returnable quantity.'),
        ),
      );
      return;
    }
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReturnSaleDialog(
        sale: sale,
        items: items,
        currencyCode: currencyCode,
        repository: repository,
        serializedUnitsByItem: serializedUnits,
      ),
    );
    if (result == null || !context.mounted) return;
    ref.invalidate(salesProvider);
    ref.invalidate(filteredSalesProvider);
    ref.invalidate(catalogSnapshotProvider);
    ref.invalidate(accountingDashboardProvider);
    final returnValueMinor =
        ((double.tryParse(result['refund_total'].toString()) ?? 0) * 100)
            .round();
    final isCreditNote = result['settlement_method'] == 'credit_note';
    final outcome = isCreditNote
        ? 'Credit note ${result['credit_note_number']} issued for '
              '${formatMoney(currencyCode, returnValueMinor)}.'
        : 'Cash refund: ${formatMoney(currencyCode, returnValueMinor)}.';
    messenger.showSnackBar(
      SnackBar(content: Text('Return completed. $outcome')),
    );
  } catch (error) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(error.toString())));
  }
}

Future<void> _openExchangeDialog(
  BuildContext context,
  WidgetRef ref,
  SaleSummary sale,
  String currencyCode,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final repository = ref.read(catalogRepositoryProvider);
    final results = await Future.wait<Object>([
      repository.fetchReturnableSaleItems(sale.id),
      ref.read(catalogSnapshotProvider.future),
      ref.read(registerOperationsProvider.future),
    ]);
    if (!context.mounted) return;
    final items = results[0] as List<ReturnableSaleItem>;
    final catalog = results[1] as CatalogSnapshot;
    final registerData = results[2] as RegisterOperationsSnapshot;
    final workspace = ref.read(selectedWorkspaceProvider).value;
    final currentUserId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    final canManage = workspace?.canUpdate('registers') ?? false;
    final shifts = registerData.openShifts
        .where(
          (shift) =>
              shift.branchId == sale.branchId &&
              (canManage || shift.openedBy == currentUserId),
        )
        .toList(growable: false);
    final warehouses = catalog.warehouses
        .where((warehouse) => warehouse.branchId == sale.branchId)
        .toList(growable: false);
    if (items.isEmpty || shifts.isEmpty || warehouses.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            items.isEmpty
                ? 'This sale has no remaining exchangeable quantity.'
                : shifts.isEmpty
                ? 'Open a register shift in the original sale branch first.'
                : 'No active warehouse is available in the original sale branch.',
          ),
        ),
      );
      return;
    }
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ExchangeSaleDialog(
        sale: sale,
        returnableItems: items,
        catalog: catalog,
        warehouses: warehouses,
        shifts: shifts,
        currencyCode: currencyCode,
        repository: repository,
      ),
    );
    if (result == null || !context.mounted) return;
    ref.invalidate(salesProvider);
    ref.invalidate(filteredSalesProvider);
    ref.invalidate(catalogSnapshotProvider);
    ref.invalidate(registerOperationsProvider);
    ref.invalidate(accountingDashboardProvider);
    final differenceMinor =
        ((double.tryParse(result['cash_difference'].toString()) ?? 0) * 100)
            .round();
    final differenceText = differenceMinor == 0
        ? 'No cash difference.'
        : differenceMinor > 0
        ? 'Collect ${formatMoney(currencyCode, differenceMinor)}.'
        : 'Refund ${formatMoney(currencyCode, differenceMinor.abs())}.';
    messenger.showSnackBar(
      SnackBar(content: Text('Exchange completed. $differenceText')),
    );
  } catch (error) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(error.toString())));
  }
}

class _ReturnSaleDialog extends StatefulWidget {
  const _ReturnSaleDialog({
    required this.sale,
    required this.items,
    required this.currencyCode,
    required this.repository,
    required this.serializedUnitsByItem,
  });

  final SaleSummary sale;
  final List<ReturnableSaleItem> items;
  final String currencyCode;
  final CatalogRepository repository;
  final Map<String, List<SerializedSaleReturnUnit>> serializedUnitsByItem;

  @override
  State<_ReturnSaleDialog> createState() => _ReturnSaleDialogState();
}

class _ReturnSaleDialogState extends State<_ReturnSaleDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  late final Map<String, TextEditingController> _quantityControllers;
  bool _submitting = false;
  String _settlementMethod = 'cash';
  String? _error;
  late final Map<String, Set<String>> _selectedSerializedUnits;

  @override
  void initState() {
    super.initState();
    _quantityControllers = {
      for (final item in widget.items)
        item.id: TextEditingController(text: '0'),
    };
    _selectedSerializedUnits = {
      for (final item in widget.items) item.id: <String>{},
    };
  }

  @override
  void dispose() {
    _reasonController.dispose();
    for (final controller in _quantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final selected = widget.items
        .map(
          (item) => (
            saleItemId: item.id,
            quantity:
                double.tryParse(_quantityControllers[item.id]!.text.trim()) ??
                0,
          ),
        )
        .where((item) => item.quantity > 0)
        .toList(growable: false);
    if (selected.isEmpty) {
      setState(() => _error = 'Enter a return quantity for at least one item.');
      return;
    }
    final serializedSelections = <String, List<String>>{};
    for (final item in widget.items) {
      final available = widget.serializedUnitsByItem[item.id];
      if (available == null || available.isEmpty) continue;
      final selectedIds = _selectedSerializedUnits[item.id]!.toList(
        growable: false,
      );
      final quantity = selected
          .where((entry) => entry.saleItemId == item.id)
          .firstOrNull
          ?.quantity;
      if (quantity == null || selectedIds.length != quantity) {
        setState(
          () => _error =
              'Select exactly ${_quantityText(quantity ?? 0)} serial unit(s) for ${item.sku}.',
        );
        return;
      }
      serializedSelections[item.id] = selectedIds;
    }
    if (_settlementMethod == 'credit_note' && serializedSelections.isNotEmpty) {
      setState(
        () => _error = 'Serialized returns currently require a cash refund. Choose cash or return a non-serialized item.',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = _settlementMethod == 'credit_note'
          ? await widget.repository.processSaleCreditNoteReturn(
              saleId: widget.sale.id,
              items: selected,
              reason: _reasonController.text,
            )
          : await widget.repository.processSaleReturn(
              saleId: widget.sale.id,
              items: selected,
              reason: _reasonController.text,
              serializedUnitIdsBySaleItem: serializedSelections,
            );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Return ${widget.sale.invoiceNumber}'),
      content: SizedBox(
        width: 600,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Choose quantities to return. Stock restoration and the selected settlement are committed atomically.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                for (final item in widget.items) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.productName,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              '${item.variantName} · ${item.sku} · ${formatMoney(widget.currencyCode, item.lineTotalMinor)} sold',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      if (_serializedUnitsFor(item).isEmpty)
                        SizedBox(
                          width: 150,
                          child: TextFormField(
                            controller: _quantityControllers[item.id],
                            enabled: !_submitting,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d{0,6}'),
                              ),
                            ],
                            decoration: InputDecoration(
                              labelText: 'Quantity',
                              helperText:
                                  'Max ${_quantityText(item.remainingQuantity)}',
                            ),
                            validator: (value) {
                              final quantity = double.tryParse(
                                value?.trim() ?? '',
                              );
                              if (quantity == null || quantity < 0) {
                                return 'Invalid quantity';
                              }
                              if (quantity >
                                  item.remainingQuantity + 0.000001) {
                                return 'Exceeds remaining';
                              }
                              return null;
                            },
                          ),
                        )
                      else
                        SizedBox(
                          width: 260,
                          child: _SerializedReturnUnitPicker(
                            units: _serializedUnitsFor(item),
                            selectedIds: _selectedSerializedUnits[item.id]!,
                            enabled: !_submitting,
                            onChanged: (unitId, selected) {
                              final next = _selectedSerializedUnits[item.id]!;
                              if (selected) {
                                if (next.length >= item.remainingQuantity) {
                                  return;
                                }
                                next.add(unitId);
                              } else {
                                next.remove(unitId);
                              }
                              _quantityControllers[item.id]!.text = next.length
                                  .toString();
                              setState(() {});
                            },
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                DropdownButtonFormField<String>(
                  initialValue: _settlementMethod,
                  decoration: const InputDecoration(
                    labelText: 'Return settlement',
                    prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Cash refund')),
                    DropdownMenuItem(
                      value: 'credit_note',
                      child: Text('Issue credit note'),
                    ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _settlementMethod = value);
                          }
                        },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _reasonController,
                  enabled: !_submitting,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Return reason',
                    hintText:
                        'Damaged item, incorrect product, customer request…',
                  ),
                  validator: (value) => (value?.trim().length ?? 0) < 3
                      ? 'Enter a meaningful reason.'
                      : null,
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
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.assignment_return_outlined),
          label: Text(
            _submitting
                ? 'Processing…'
                : _settlementMethod == 'credit_note'
                ? 'Issue credit note'
                : 'Complete cash refund',
          ),
        ),
      ],
    );
  }

  List<SerializedSaleReturnUnit> _serializedUnitsFor(ReturnableSaleItem item) =>
      widget.serializedUnitsByItem[item.id] ?? const [];
}

class _SerializedReturnUnitPicker extends StatelessWidget {
  const _SerializedReturnUnitPicker({
    required this.units,
    required this.selectedIds,
    required this.enabled,
    required this.onChanged,
  });

  final List<SerializedSaleReturnUnit> units;
  final Set<String> selectedIds;
  final bool enabled;
  final void Function(String unitId, bool selected) onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Serial units (${selectedIds.length}/${units.length})',
        style: Theme.of(context).textTheme.labelMedium,
      ),
      const SizedBox(height: 4),
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final unit in units)
            FilterChip(
              label: Text(unit.identifier),
              selected: selectedIds.contains(unit.id),
              onSelected: enabled
                  ? (selected) => onChanged(unit.id, selected)
                  : null,
            ),
        ],
      ),
    ],
  );
}

class _ExchangeSaleDialog extends StatefulWidget {
  const _ExchangeSaleDialog({
    required this.sale,
    required this.returnableItems,
    required this.catalog,
    required this.warehouses,
    required this.shifts,
    required this.currencyCode,
    required this.repository,
  });

  final SaleSummary sale;
  final List<ReturnableSaleItem> returnableItems;
  final CatalogSnapshot catalog;
  final List<WarehouseOption> warehouses;
  final List<RegisterShift> shifts;
  final String currencyCode;
  final CatalogRepository repository;

  @override
  State<_ExchangeSaleDialog> createState() => _ExchangeSaleDialogState();
}

class _ExchangeSaleDialogState extends State<_ExchangeSaleDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  late final Map<String, TextEditingController> _returnControllers;
  final Map<String, int> _replacementQuantities = {};
  String? _warehouseId;
  String? _shiftId;
  String? _selectedVariantId;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _returnControllers = {
      for (final item in widget.returnableItems)
        item.id: TextEditingController(text: '0'),
    };
    _warehouseId =
        widget.catalog.bestWarehouse(candidates: widget.warehouses)?.id ??
        widget.warehouses.first.id;
    _shiftId = widget.shifts.first.id;
    _selectedVariantId = _availableProducts.firstOrNull?.variantId;
  }

  @override
  void dispose() {
    _reasonController.dispose();
    for (final controller in _returnControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<CatalogProduct> get _availableProducts {
    final warehouseId = _warehouseId;
    if (warehouseId == null) return const [];
    return widget.catalog.products
        .where(
          (product) =>
              !product.trackInventory ||
              widget.catalog.stockForWarehouse(product.variantId, warehouseId) >
                  0,
        )
        .toList(growable: false);
  }

  List<PosCartLine> get _replacementItems => _replacementQuantities.entries
      .where((entry) => entry.value > 0)
      .map(
        (entry) => (
          product: widget.catalog.products.firstWhere(
            (product) => product.variantId == entry.key,
          ),
          quantity: entry.value,
        ),
      )
      .toList(growable: false);

  PosTotals get _totals => calculatePosTotals(_replacementItems);

  void _changeWarehouse(String? value) {
    if (value == null || value == _warehouseId) return;
    setState(() {
      _warehouseId = value;
      _replacementQuantities.clear();
      _selectedVariantId = _availableProducts.firstOrNull?.variantId;
      _error = null;
    });
  }

  void _addProduct() {
    final id = _selectedVariantId;
    if (id == null) return;
    final product = widget.catalog.products.firstWhere(
      (item) => item.variantId == id,
    );
    final next = (_replacementQuantities[id] ?? 0) + 1;
    final stock = widget.catalog.stockForWarehouse(id, _warehouseId!);
    if (product.trackInventory && next > stock) {
      setState(() => _error = 'Not enough stock for ${product.name}.');
      return;
    }
    setState(() {
      _replacementQuantities[id] = next;
      _error = null;
    });
  }

  void _changeReplacement(CatalogProduct product, int delta) {
    final next = (_replacementQuantities[product.variantId] ?? 0) + delta;
    final stock = widget.catalog.stockForWarehouse(
      product.variantId,
      _warehouseId!,
    );
    if (product.trackInventory && next > stock) {
      setState(() => _error = 'Not enough stock for ${product.name}.');
      return;
    }
    setState(() {
      if (next <= 0) {
        _replacementQuantities.remove(product.variantId);
      } else {
        _replacementQuantities[product.variantId] = next;
      }
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final returnedItems = widget.returnableItems
        .map(
          (item) => (
            saleItemId: item.id,
            quantity:
                double.tryParse(_returnControllers[item.id]!.text.trim()) ?? 0,
          ),
        )
        .where((item) => item.quantity > 0)
        .toList(growable: false);
    if (returnedItems.isEmpty) {
      setState(() => _error = 'Choose at least one item to return.');
      return;
    }
    if (_replacementItems.isEmpty) {
      setState(() => _error = 'Add at least one replacement item.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await widget.repository.processSaleExchange(
        saleId: widget.sale.id,
        registerId: widget.shifts
            .firstWhere((shift) => shift.id == _shiftId)
            .registerId,
        shiftId: _shiftId!,
        warehouseId: _warehouseId!,
        returnedItems: returnedItems,
        replacementItems: _replacementItems,
        reason: _reasonController.text,
      );
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = _availableProducts;
    final totals = _totals;
    return AlertDialog(
      title: Text('Exchange ${widget.sale.invoiceNumber}'),
      content: SizedBox(
        width: 760,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'The return, cash refund, replacement sale, stock movements, and cash difference are committed as one transaction.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                Text(
                  'Items being returned',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                for (final item in widget.returnableItems) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${item.productName} · ${item.variantName}\n${item.sku}',
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 145,
                        child: TextFormField(
                          controller: _returnControllers[item.id],
                          enabled: !_submitting,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d{0,6}'),
                            ),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Return qty',
                            helperText:
                                'Max ${_quantityText(item.remainingQuantity)}',
                          ),
                          validator: (value) {
                            final quantity = double.tryParse(
                              value?.trim() ?? '',
                            );
                            if (quantity == null || quantity < 0) {
                              return 'Invalid';
                            }
                            if (quantity > item.remainingQuantity + 0.000001) {
                              return 'Too high';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                const Divider(height: 30),
                Text(
                  'Replacement sale',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _warehouseId,
                        decoration: const InputDecoration(
                          labelText: 'Warehouse',
                        ),
                        items: widget.warehouses
                            .map(
                              (item) => DropdownMenuItem(
                                value: item.id,
                                child: Text(item.name),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: _submitting ? null : _changeWarehouse,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _shiftId,
                        decoration: const InputDecoration(
                          labelText: 'Open register shift',
                        ),
                        items: widget.shifts
                            .map(
                              (shift) => DropdownMenuItem(
                                value: shift.id,
                                child: Text(
                                  '${shift.registerName} · ${shift.registerCode}',
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: _submitting
                            ? null
                            : (value) => setState(() => _shiftId = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(_warehouseId),
                        initialValue:
                            products.any(
                              (item) => item.variantId == _selectedVariantId,
                            )
                            ? _selectedVariantId
                            : products.firstOrNull?.variantId,
                        decoration: const InputDecoration(
                          labelText: 'Replacement product',
                        ),
                        items: products
                            .map(
                              (product) => DropdownMenuItem(
                                value: product.variantId,
                                child: Text('${product.name} · ${product.sku}'),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: _submitting
                            ? null
                            : (value) =>
                                  setState(() => _selectedVariantId = value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _submitting || products.isEmpty
                          ? null
                          : _addProduct,
                      icon: const Icon(Icons.add_shopping_cart_rounded),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                if (_replacementItems.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('No replacement items added yet.'),
                  )
                else ...[
                  const SizedBox(height: 12),
                  for (final line in _replacementItems)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: ProductImage(
                        imagePath: line.product.imagePath,
                        width: 44,
                        height: 44,
                        borderRadius: 8,
                        fit: BoxFit.contain,
                        iconSize: 20,
                      ),
                      title: Text(line.product.name),
                      subtitle: Text(
                        '${line.product.variantName} · ${line.product.sku}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Decrease ${line.product.name} quantity',
                            onPressed: _submitting
                                ? null
                                : () => _changeReplacement(line.product, -1),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text('${line.quantity}'),
                          IconButton(
                            tooltip: 'Increase ${line.product.name} quantity',
                            onPressed: _submitting
                                ? null
                                : () => _changeReplacement(line.product, 1),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            formatMoney(
                              widget.currencyCode,
                              line.product.priceMinor * line.quantity,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Replacement total: ${formatMoney(widget.currencyCode, totals.totalMinor)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                TextFormField(
                  controller: _reasonController,
                  enabled: !_submitting,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Exchange reason',
                    hintText: 'Wrong size, damaged item, customer request…',
                  ),
                  validator: (value) => (value?.trim().length ?? 0) < 3
                      ? 'Enter a meaningful reason.'
                      : null,
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.swap_horiz_rounded),
          label: Text(_submitting ? 'Processing…' : 'Complete exchange'),
        ),
      ],
    );
  }
}

int _minorValue(Object? value) =>
    (((value is num ? value.toDouble() : double.tryParse('$value') ?? 0)) * 100)
        .round();

String _quantityText(double value) => value == value.truncateToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(6).replaceFirst(RegExp(r'0+$'), '');
