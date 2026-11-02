import 'package:flexpos/core/utils/money.dart';
import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/core/widgets/data_page_skeleton.dart';
import 'package:flexpos/core/widgets/data_list_controls.dart';
import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/core/widgets/product_image.dart';
import 'package:flexpos/core/widgets/status_badge.dart';
import 'package:flexpos/core/security/crud_permissions.dart';
import 'package:flexpos/features/catalog/data/catalog_repository.dart';
import 'package:flexpos/features/catalog/domain/catalog_models.dart';
import 'package:flexpos/features/inventory/data/inventory_repository.dart';
import 'package:flexpos/features/purchasing/data/purchasing_repository.dart';
import 'package:flexpos/features/purchasing/domain/purchasing_models.dart';
import 'package:flexpos/features/tenants/domain/business_workspace.dart';
import 'package:flexpos/features/tenants/domain/feature_entitlement.dart';
import 'package:flexpos/features/tenants/presentation/feature_entitlements/feature_disabled_state.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class PurchasingPage extends ConsumerStatefulWidget {
  const PurchasingPage({super.key});

  @override
  ConsumerState<PurchasingPage> createState() => _PurchasingPageState();
}

class _PurchasingPageState extends ConsumerState<PurchasingPage> {
  String _query = '';
  String _sort = 'newest';
  int _page = 0;
  final Set<String> _selectedOrderIds = {};
  String _supplierQuery = '';
  String _supplierSort = 'name';
  int _supplierPage = 0;
  final Set<String> _selectedSupplierIds = {};

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    if (workspace == null) {
      return const EmptyState(
        icon: Icons.add_business_outlined,
        title: 'Select a business',
        message: 'A workspace is required to manage purchasing.',
      );
    }
    if (!workspace.isFeatureEnabled(FeatureCodes.purchasing)) {
      return FeatureDisabledState(
        featureName: 'Suppliers and purchasing',
        canManage: workspace.canManage('business'),
      );
    }
    if (!workspace.canRead('purchases')) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Purchasing is restricted',
        message: 'Your role does not include permission to view purchases.',
      );
    }
    final suppliers = ref.watch(suppliersProvider);
    final orders = ref.watch(purchaseOrdersProvider);
    final requisitions = ref.watch(purchaseRequisitionsProvider);
    final invoices = ref.watch(purchaseInvoicesProvider);
    final catalog = ref.watch(catalogSnapshotProvider);
    final canCreate = workspace.canCreate('purchases');
    final canUpdate = workspace.canUpdate('purchases');
    final canDelete = workspace.canDelete('purchases');
    final canManage = canUpdate || canDelete;

    if (suppliers.isLoading ||
        orders.isLoading ||
        requisitions.isLoading ||
        invoices.isLoading ||
        catalog.isLoading) {
      return const DataPageSkeleton(sectionLabel: 'purchasing');
    }
    final error =
        suppliers.error ??
        orders.error ??
        requisitions.error ??
        invoices.error ??
        catalog.error;
    if (error != null) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load purchasing',
        message: error.toString(),
        action: FilledButton.icon(
          onPressed: () {
            ref.invalidate(suppliersProvider);
            ref.invalidate(purchaseOrdersProvider);
            ref.invalidate(purchaseRequisitionsProvider);
            ref.invalidate(purchaseInvoicesProvider);
            ref.invalidate(catalogSnapshotProvider);
          },
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      );
    }
    final supplierItems = suppliers.value ?? const <Supplier>[];
    final orderItems = orders.value ?? const <PurchaseOrder>[];
    final requisitionItems =
        requisitions.value ?? const <Map<String, dynamic>>[];
    final invoiceItems = invoices.value ?? const <Map<String, dynamic>>[];
    final payableTotals = <String, int>{};
    for (final invoice in invoiceItems) {
      final supplier = invoice['suppliers'] is Map
          ? Map<String, dynamic>.from(invoice['suppliers'] as Map)
          : const <String, dynamic>{};
      final supplierName = supplier['name'] as String? ?? 'Supplier';
      final outstanding =
          _minorFromValue(invoice['total']) -
          _minorFromValue(invoice['paid_total']);
      payableTotals[supplierName] =
          (payableTotals[supplierName] ?? 0) + outstanding;
    }
    final catalogData = catalog.value ?? CatalogSnapshot.empty;
    final filteredOrders = orderItems
        .where(
          (order) =>
              '${order.orderNumber} ${order.supplierName} ${order.warehouseName} ${order.status}'
                  .toLowerCase()
                  .contains(_query),
        )
        .toList();
    filteredOrders.sort(
      (a, b) => switch (_sort) {
        'amount_desc' => b.grandTotalMinor.compareTo(a.grandTotalMinor),
        'amount_asc' => a.grandTotalMinor.compareTo(b.grandTotalMinor),
        'oldest' => a.orderedAt.compareTo(b.orderedAt),
        _ => b.orderedAt.compareTo(a.orderedAt),
      },
    );
    final pageCount = pageCountFor(filteredOrders.length);
    if (_page >= pageCount) _page = pageCount - 1;
    final visibleOrders = pageItems(filteredOrders, _page);
    final filteredSuppliers = supplierItems
        .where(
          (supplier) =>
              '${supplier.name} ${supplier.code ?? ''} ${supplier.contactName ?? ''} ${supplier.phone ?? ''} ${supplier.email ?? ''}'
                  .toLowerCase()
                  .contains(_supplierQuery),
        )
        .toList();
    filteredSuppliers.sort((a, b) {
      final comparison = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return _supplierSort == 'name_desc' ? -comparison : comparison;
    });
    final supplierPageCount = pageCountFor(filteredSuppliers.length);
    if (_supplierPage >= supplierPageCount)
      _supplierPage = supplierPageCount - 1;
    final visibleSuppliers = pageItems(filteredSuppliers, _supplierPage);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(suppliersProvider);
        ref.invalidate(purchaseOrdersProvider);
        ref.invalidate(purchaseRequisitionsProvider);
        ref.invalidate(purchaseInvoicesProvider);
        ref.invalidate(catalogSnapshotProvider);
        await ref.read(purchaseOrdersProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
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
                    'Purchasing',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Suppliers, purchase orders, and goods receipts',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (canCreate || canManage)
                Wrap(
                  spacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: canCreate
                          ? () => _createSupplier(context, ref, workspace)
                          : null,
                      icon: const Icon(Icons.add_business_outlined),
                      label: const Text('New supplier'),
                    ),
                    FilledButton.icon(
                      onPressed:
                          !canCreate
                          ? null
                          :
                          supplierItems.isEmpty ||
                              catalogData.warehouses.isEmpty ||
                              catalogData.products
                                  .where((product) => product.trackInventory)
                                  .isEmpty
                          ? null
                          : () => _createOrder(
                              context,
                              ref,
                              workspace,
                              supplierItems,
                              catalogData,
                            ),
                      icon: const Icon(Icons.add_shopping_cart_rounded),
                      label: const Text('New purchase order'),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 26),
          Text(
            'Purchase orders',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          DataListControls(
            query: _query,
            onSearchChanged: (value) => setState(() {
              _query = value.trim().toLowerCase();
              _page = 0;
            }),
            searchLabel: 'Search order, supplier, warehouse, or status',
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
            totalCount: filteredOrders.length,
            onPageChanged: (value) => setState(() => _page = value),
            selectedCount: _selectedOrderIds.length,
            allSelected:
                visibleOrders.isNotEmpty &&
                visibleOrders.every(
                  (order) => _selectedOrderIds.contains(order.id),
                ),
            onSelectAll: visibleOrders.isEmpty
                ? null
                : (selected) => setState(() {
                    if (selected ?? false) {
                      _selectedOrderIds.addAll(
                        visibleOrders.map((order) => order.id),
                      );
                    } else {
                      _selectedOrderIds.removeAll(
                        visibleOrders.map((order) => order.id),
                      );
                    }
                  }),
            onClearSelection: () => setState(() => _selectedOrderIds.clear()),
            bulkActions: [
              FilledButton.tonalIcon(
                onPressed: () => _copySelectedOrders(
                  orderItems
                      .where((order) => _selectedOrderIds.contains(order.id))
                      .toList(growable: false),
                ),
                icon: const Icon(Icons.copy_all_rounded),
                label: const Text('Copy orders'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (visibleOrders.isEmpty)
            const EmptyState(
              icon: Icons.shopping_cart_checkout_outlined,
              title: 'No purchase orders yet',
              message: 'Create a supplier, then place the first stock order.',
            )
          else
            for (final order in visibleOrders) ...[
              AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: _selectedOrderIds.contains(order.id),
                          onChanged: (selected) => setState(() {
                            if (selected ?? false) {
                              _selectedOrderIds.add(order.id);
                            } else {
                              _selectedOrderIds.remove(order.id);
                            }
                          }),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                order.orderNumber,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                '${order.supplierName} • ${order.warehouseName} • ${DateFormat.yMMMd().format(order.orderedAt)}',
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
                                order.grandTotalMinor,
                              ),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 5),
                            StatusBadge(
                              label: _statusLabel(order.status),
                              tone: order.status == 'received'
                                  ? StatusTone.success
                                  : StatusTone.warning,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      order.lines
                          .map(
                            (line) =>
                                '${line.productName} ${_quantity(line.receivedQuantity)}/${_quantity(line.orderedQuantity)}'
                                '${line.returnedQuantity > 0 ? ' • returned ${_quantity(line.returnedQuantity)}' : ''}',
                          )
                          .join('  •  '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (canUpdate && (order.canReceive || order.canReturn)) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            if (order.canReturn)
                              OutlinedButton.icon(
                                onPressed: () =>
                                    _returnOrder(context, ref, order),
                                icon: const Icon(Icons.undo_rounded),
                                label: const Text('Return to supplier'),
                              ),
                            if (order.canReceive)
                              FilledButton.tonalIcon(
                                onPressed: () =>
                                    _receiveOrder(context, ref, order),
                                icon: const Icon(Icons.inventory_rounded),
                                label: const Text('Receive stock'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          const SizedBox(height: 22),
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Procurement workflow',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Requisitions, approvals, supplier invoices, payments, and landed costs',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    if (canUpdate)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed:
                                catalogData.products.isEmpty ||
                                    workspace.branches.isEmpty
                                ? null
                                : () => _createRequisition(
                                    context,
                                    ref,
                                    workspace,
                                    catalogData,
                                  ),
                            icon: const Icon(Icons.playlist_add_rounded),
                            label: const Text('New requisition'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: orderItems.isEmpty
                                ? null
                                : () => _createInvoice(
                                    context,
                                    ref,
                                    workspace,
                                    orderItems,
                                  ),
                            icon: const Icon(Icons.receipt_long_rounded),
                            label: const Text('Supplier invoice'),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (payableTotals.isNotEmpty) ...[
                  Text(
                    'Supplier payable statement',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final entry in payableTotals.entries)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.account_balance_wallet_outlined,
                      ),
                      title: Text(entry.key),
                      trailing: Text(
                        formatMoney(workspace.currencyCode, entry.value),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  const Divider(height: 20),
                ],
                if (requisitionItems.isEmpty && invoiceItems.isEmpty)
                  Text(
                    'No procurement workflow records yet.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                for (final requisition in requisitionItems.take(8)) ...[
                  _RequisitionCard(
                    requisition: requisition,
                    canManage: canUpdate,
                    onDecide: () =>
                        _decideRequisition(context, ref, requisition),
                  ),
                  const SizedBox(height: 8),
                ],
                for (final invoice in invoiceItems.take(8)) ...[
                  _InvoiceCard(
                    invoice: invoice,
                    currencyCode: workspace.currencyCode,
                    canManage: canUpdate,
                    onPay: () => _payInvoice(context, ref, invoice),
                    onLandedCost: () =>
                        _addLandedCost(context, ref, orderItems, invoice),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text('Suppliers', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          DataListControls(
            query: _supplierQuery,
            onSearchChanged: (value) => setState(() {
              _supplierQuery = value.trim().toLowerCase();
              _supplierPage = 0;
            }),
            searchLabel: 'Search suppliers, contacts, or email',
            sortValue: _supplierSort,
            sortOptions: const [
              DataListSortOption('name', 'Name A–Z'),
              DataListSortOption('name_desc', 'Name Z–A'),
            ],
            onSortChanged: (value) => setState(() {
              _supplierSort = value;
              _supplierPage = 0;
            }),
            page: _supplierPage,
            pageCount: supplierPageCount,
            totalCount: filteredSuppliers.length,
            onPageChanged: (value) => setState(() => _supplierPage = value),
            selectedCount: _selectedSupplierIds.length,
            allSelected:
                visibleSuppliers.isNotEmpty &&
                visibleSuppliers.every(
                  (supplier) => _selectedSupplierIds.contains(supplier.id),
                ),
            onSelectAll: visibleSuppliers.isEmpty
                ? null
                : (selected) => setState(() {
                    if (selected ?? false) {
                      _selectedSupplierIds.addAll(
                        visibleSuppliers.map((supplier) => supplier.id),
                      );
                    } else {
                      _selectedSupplierIds.removeAll(
                        visibleSuppliers.map((supplier) => supplier.id),
                      );
                    }
                  }),
            onClearSelection: () =>
                setState(() => _selectedSupplierIds.clear()),
            bulkActions: [
              FilledButton.tonalIcon(
                onPressed: () => _copySelectedSuppliers(
                  supplierItems
                      .where(
                        (supplier) =>
                            _selectedSupplierIds.contains(supplier.id),
                      )
                      .toList(growable: false),
                ),
                icon: const Icon(Icons.copy_all_rounded),
                label: const Text('Copy suppliers'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (visibleSuppliers.isEmpty)
            const EmptyState(
              icon: Icons.local_shipping_outlined,
              title: 'No suppliers yet',
              message: 'Create a supplier before placing a purchase order.',
            )
          else
            for (final supplier in visibleSuppliers) ...[
              AppPanel(
                child: Row(
                  children: [
                    Checkbox(
                      value: _selectedSupplierIds.contains(supplier.id),
                      onChanged: (selected) => setState(() {
                        if (selected ?? false) {
                          _selectedSupplierIds.add(supplier.id);
                        } else {
                          _selectedSupplierIds.remove(supplier.id);
                        }
                      }),
                    ),
                    const CircleAvatar(
                      child: Icon(Icons.local_shipping_outlined),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            supplier.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            [
                              supplier.contactName,
                              supplier.phone,
                              supplier.email,
                            ].whereType<String>().join(' • '),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (canUpdate)
                      IconButton(
                        tooltip: 'Edit supplier',
                        onPressed: () =>
                            _editSupplier(context, ref, workspace, supplier),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    if (canDelete)
                      IconButton(
                        tooltip: 'Archive supplier',
                        onPressed: () => _archiveSupplier(
                          context,
                          ref,
                          workspace,
                          supplier,
                        ),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  Future<void> _copySelectedOrders(List<PurchaseOrder> orders) async {
    if (orders.isEmpty) return;
    await Clipboard.setData(
      ClipboardData(
        text: orders
            .map((order) => '${order.orderNumber}\t${order.grandTotalMinor}')
            .join('\n'),
      ),
    );
    if (!mounted) return;
    setState(() => _selectedOrderIds.clear());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${orders.length} purchase order${orders.length == 1 ? '' : 's'} copied.',
        ),
      ),
    );
  }

  Future<void> _copySelectedSuppliers(List<Supplier> suppliers) async {
    if (suppliers.isEmpty) return;
    await Clipboard.setData(
      ClipboardData(
        text: suppliers
            .map(
              (supplier) =>
                  '${supplier.name}\t${supplier.email ?? supplier.phone ?? ''}',
            )
            .join('\n'),
      ),
    );
    if (!mounted) return;
    setState(() => _selectedSupplierIds.clear());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${suppliers.length} supplier${suppliers.length == 1 ? '' : 's'} copied.',
        ),
      ),
    );
  }

  Future<void> _createSupplier(
    BuildContext context,
    WidgetRef ref,
    BusinessWorkspace workspace,
  ) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _SupplierDialog(
        workspace: workspace,
        repository: ref.read(purchasingRepositoryProvider),
      ),
    );
    if (created == true) {
      ref.invalidate(suppliersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Supplier created.')));
      }
    }
  }

  Future<void> _editSupplier(
    BuildContext context,
    WidgetRef ref,
    BusinessWorkspace workspace,
    Supplier supplier,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _SupplierDialog(
        workspace: workspace,
        repository: ref.read(purchasingRepositoryProvider),
        supplier: supplier,
      ),
    );
    if (saved == true) {
      ref.invalidate(suppliersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Supplier updated.')),
        );
      }
    }
  }

  Future<void> _archiveSupplier(
    BuildContext context,
    WidgetRef ref,
    BusinessWorkspace workspace,
    Supplier supplier,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive supplier?'),
        content: Text(
          '“${supplier.name}” will be hidden from active lists. Purchase history is preserved.',
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
      await ref.read(purchasingRepositoryProvider).archiveSupplier(
        businessId: workspace.businessId,
        supplierId: supplier.id,
      );
      ref.invalidate(suppliersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Supplier archived.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not archive supplier: $error')),
        );
      }
    }
  }

  Future<void> _createOrder(
    BuildContext context,
    WidgetRef ref,
    BusinessWorkspace workspace,
    List<Supplier> suppliers,
    CatalogSnapshot catalog,
  ) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _PurchaseOrderDialog(
        workspace: workspace,
        suppliers: suppliers,
        catalog: catalog,
        repository: ref.read(purchasingRepositoryProvider),
      ),
    );
    if (created == true) {
      ref.invalidate(purchaseOrdersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase order created.')),
        );
      }
    }
  }

  Future<void> _receiveOrder(
    BuildContext context,
    WidgetRef ref,
    PurchaseOrder order,
  ) async {
    final received = await showDialog<bool>(
      context: context,
      builder: (_) => _ReceiveOrderDialog(
        order: order,
        repository: ref.read(purchasingRepositoryProvider),
      ),
    );
    if (received == true) {
      ref.invalidate(purchaseOrdersProvider);
      ref.invalidate(catalogSnapshotProvider);
      ref.invalidate(serializedInventoryUnitsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stock received and inventory updated.'),
          ),
        );
      }
    }
  }

  Future<void> _returnOrder(
    BuildContext context,
    WidgetRef ref,
    PurchaseOrder order,
  ) async {
    final returned = await showDialog<bool>(
      context: context,
      builder: (_) => _ReturnOrderDialog(
        order: order,
        repository: ref.read(purchasingRepositoryProvider),
      ),
    );
    if (returned == true) {
      ref.invalidate(purchaseOrdersProvider);
      ref.invalidate(catalogSnapshotProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Supplier return completed and inventory updated.'),
          ),
        );
      }
    }
  }

  Future<void> _createRequisition(
    BuildContext context,
    WidgetRef ref,
    BusinessWorkspace workspace,
    CatalogSnapshot catalog,
  ) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _RequisitionDialog(
        workspace: workspace,
        catalog: catalog,
        repository: ref.read(purchasingRepositoryProvider),
      ),
    );
    if (created == true) {
      ref.invalidate(purchaseRequisitionsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase requisition submitted.')),
        );
      }
    }
  }

  Future<void> _decideRequisition(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> requisition,
  ) async {
    final decision = await showDialog<bool>(
      context: context,
      builder: (_) => _RequisitionDecisionDialog(
        requisition: requisition,
        repository: ref.read(purchasingRepositoryProvider),
      ),
    );
    if (decision == true) {
      ref.invalidate(purchaseRequisitionsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Requisition decision saved.')),
        );
      }
    }
  }

  Future<void> _createInvoice(
    BuildContext context,
    WidgetRef ref,
    BusinessWorkspace workspace,
    List<PurchaseOrder> orders,
  ) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _InvoiceDialog(
        workspace: workspace,
        orders: orders,
        repository: ref.read(purchasingRepositoryProvider),
      ),
    );
    if (created == true) {
      ref.invalidate(purchaseInvoicesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Supplier invoice recorded.')),
        );
      }
    }
  }

  Future<void> _payInvoice(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> invoice,
  ) async {
    final paid = await showDialog<bool>(
      context: context,
      builder: (_) => _InvoicePaymentDialog(
        invoice: invoice,
        repository: ref.read(purchasingRepositoryProvider),
      ),
    );
    if (paid == true) {
      ref.invalidate(purchaseInvoicesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Supplier payment recorded.')),
        );
      }
    }
  }

  Future<void> _addLandedCost(
    BuildContext context,
    WidgetRef ref,
    List<PurchaseOrder> orders,
    Map<String, dynamic> invoice,
  ) async {
    final orderId = invoice['purchase_order_id'] as String?;
    if (orderId == null) return;
    final matches = orders.where((item) => item.id == orderId).toList();
    final order = matches.isEmpty ? null : matches.first;
    if (order == null) return;
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => _LandedCostDialog(
        order: order,
        repository: ref.read(purchasingRepositoryProvider),
      ),
    );
    if (added == true) {
      ref.invalidate(purchaseInvoicesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Landed cost allocated to order lines.'),
          ),
        );
      }
    }
  }
}

class _RequisitionCard extends StatelessWidget {
  const _RequisitionCard({
    required this.requisition,
    required this.canManage,
    required this.onDecide,
  });

  final Map<String, dynamic> requisition;
  final bool canManage;
  final VoidCallback onDecide;

  @override
  Widget build(BuildContext context) {
    final branch = requisition['branches'] is Map
        ? Map<String, dynamic>.from(requisition['branches'] as Map)
        : const <String, dynamic>{};
    final items =
        (requisition['purchase_requisition_items'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
    final status = requisition['status'] as String? ?? 'submitted';
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.playlist_add_rounded)),
      title: Text('Requisition • ${branch['name'] ?? 'Branch'}'),
      subtitle: Text(
        '${items.map((item) => '${item['product_name']} × ${item['quantity']}').join(' • ')}${requisition['notes'] == null ? '' : ' • ${requisition['notes']}'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          StatusBadge(
            label: status[0].toUpperCase() + status.substring(1),
            tone: status == 'approved'
                ? StatusTone.success
                : status == 'rejected'
                ? StatusTone.danger
                : StatusTone.warning,
          ),
          if (canManage && status == 'submitted')
            IconButton(
              tooltip: 'Approve or reject',
              onPressed: onDecide,
              icon: const Icon(Icons.fact_check_outlined),
            ),
        ],
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({
    required this.invoice,
    required this.currencyCode,
    required this.canManage,
    required this.onPay,
    required this.onLandedCost,
  });

  final Map<String, dynamic> invoice;
  final String currencyCode;
  final bool canManage;
  final VoidCallback onPay;
  final VoidCallback onLandedCost;

  @override
  Widget build(BuildContext context) {
    final supplier = invoice['suppliers'] is Map
        ? Map<String, dynamic>.from(invoice['suppliers'] as Map)
        : const <String, dynamic>{};
    final order = invoice['purchase_orders'] is Map
        ? Map<String, dynamic>.from(invoice['purchase_orders'] as Map)
        : const <String, dynamic>{};
    final total = _minorFromValue(invoice['total']);
    final paid = _minorFromValue(invoice['paid_total']);
    final outstanding = total - paid;
    final status = invoice['status'] as String? ?? 'posted';
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.receipt_long_rounded)),
      title: Text(
        '${invoice['invoice_number'] ?? 'Invoice'} • ${supplier['name'] ?? 'Supplier'}',
      ),
      subtitle: Text(
        '${order['order_number'] ?? 'Purchase order'} • Paid ${formatMoney(currencyCode, paid)} of ${formatMoney(currencyCode, total)} • Outstanding ${formatMoney(currencyCode, outstanding)}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          StatusBadge(
            label: status.replaceAll('_', ' '),
            tone: status == 'paid' ? StatusTone.success : StatusTone.warning,
          ),
          if (canManage && outstanding > 0)
            IconButton(
              tooltip: 'Record payment',
              onPressed: onPay,
              icon: const Icon(Icons.payments_outlined),
            ),
          if (canManage)
            IconButton(
              tooltip: 'Add landed cost',
              onPressed: onLandedCost,
              icon: const Icon(Icons.local_shipping_outlined),
            ),
        ],
      ),
    );
  }
}

class _RequisitionDialog extends StatefulWidget {
  const _RequisitionDialog({
    required this.workspace,
    required this.catalog,
    required this.repository,
  });

  final BusinessWorkspace workspace;
  final CatalogSnapshot catalog;
  final PurchasingRepository repository;

  @override
  State<_RequisitionDialog> createState() => _RequisitionDialogState();
}

class _RequisitionDialogState extends State<_RequisitionDialog> {
  late String _branchId;
  late String _variantId;
  final _quantity = TextEditingController(text: '1');
  final _notes = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _branchId = widget.workspace.branches.first.id;
    _variantId = widget.catalog.products.first.variantId;
  }

  @override
  void dispose() {
    _quantity.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New purchase requisition'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _branchId,
              decoration: const InputDecoration(labelText: 'Branch'),
              items: [
                for (final branch in widget.workspace.branches)
                  DropdownMenuItem(value: branch.id, child: Text(branch.name)),
              ],
              onChanged: (value) => setState(() => _branchId = value!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _variantId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Product'),
              items: [
                for (final product in widget.catalog.products)
                  DropdownMenuItem(
                    value: product.variantId,
                    child: Text('${product.name} • ${product.sku}'),
                  ),
              ],
              onChanged: (value) => setState(() => _variantId = value!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Quantity'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
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
            : const Text('Submit'),
      ),
    ],
  );

  Future<void> _save() async {
    final quantity = double.tryParse(_quantity.text.trim());
    if (quantity == null || quantity <= 0) {
      setState(() => _error = 'Enter a quantity greater than zero.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.createPurchaseRequisition(
        businessId: widget.workspace.businessId,
        branchId: _branchId,
        items: [(variantId: _variantId, quantity: quantity, notes: null)],
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

class _RequisitionDecisionDialog extends StatefulWidget {
  const _RequisitionDecisionDialog({
    required this.requisition,
    required this.repository,
  });
  final Map<String, dynamic> requisition;
  final PurchasingRepository repository;
  @override
  State<_RequisitionDecisionDialog> createState() =>
      _RequisitionDecisionDialogState();
}

class _RequisitionDecisionDialogState
    extends State<_RequisitionDecisionDialog> {
  final _notes = TextEditingController();
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Decide requisition'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Approve this requisition so purchasing can proceed, or reject it with a reason.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Decision note'),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      OutlinedButton(
        onPressed: _saving ? null : () => _save(false),
        child: const Text('Reject'),
      ),
      FilledButton(
        onPressed: _saving ? null : () => _save(true),
        child: const Text('Approve'),
      ),
    ],
  );
  Future<void> _save(bool approve) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.decidePurchaseRequisition(
        requisitionId: widget.requisition['id'] as String,
        approve: approve,
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

class _InvoiceDialog extends StatefulWidget {
  const _InvoiceDialog({
    required this.workspace,
    required this.orders,
    required this.repository,
  });
  final BusinessWorkspace workspace;
  final List<PurchaseOrder> orders;
  final PurchasingRepository repository;
  @override
  State<_InvoiceDialog> createState() => _InvoiceDialogState();
}

class _InvoiceDialogState extends State<_InvoiceDialog> {
  late String _orderId;
  final _number = TextEditingController();
  final _subtotal = TextEditingController();
  final _tax = TextEditingController(text: '0');
  final _dueDate = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _orderId = widget.orders.first.id;
  }

  @override
  void dispose() {
    for (final c in [_number, _subtotal, _tax, _dueDate, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Record supplier invoice'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _orderId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Purchase order'),
              items: [
                for (final order in widget.orders)
                  DropdownMenuItem(
                    value: order.id,
                    child: Text('${order.orderNumber} • ${order.supplierName}'),
                  ),
              ],
              onChanged: (value) => setState(() => _orderId = value!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _number,
              decoration: const InputDecoration(labelText: 'Invoice number'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _subtotal,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Subtotal'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _tax,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Tax'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dueDate,
              decoration: const InputDecoration(
                labelText: 'Due date (YYYY-MM-DD, optional)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
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
      FilledButton(
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Save invoice'),
      ),
    ],
  );
  Future<void> _save() async {
    final subtotal = _parseMinor(_subtotal.text);
    final tax = _parseMinor(_tax.text) ?? 0;
    if (_number.text.trim().isEmpty ||
        subtotal == null ||
        subtotal < 0 ||
        tax < 0) {
      setState(() => _error = 'Enter an invoice number and valid amounts.');
      return;
    }
    DateTime? due;
    if (_dueDate.text.trim().isNotEmpty)
      due = DateTime.tryParse(_dueDate.text.trim());
    if (_dueDate.text.trim().isNotEmpty && due == null) {
      setState(() => _error = 'Due date must be YYYY-MM-DD.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.createPurchaseInvoice(
        businessId: widget.workspace.businessId,
        purchaseOrderId: _orderId,
        invoiceNumber: _number.text,
        invoiceDate: DateTime.now(),
        dueDate: due,
        subtotalMinor: subtotal,
        taxMinor: tax,
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

class _InvoicePaymentDialog extends StatefulWidget {
  const _InvoicePaymentDialog({
    required this.invoice,
    required this.repository,
  });
  final Map<String, dynamic> invoice;
  final PurchasingRepository repository;
  @override
  State<_InvoicePaymentDialog> createState() => _InvoicePaymentDialogState();
}

class _InvoicePaymentDialogState extends State<_InvoicePaymentDialog> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  String _method = 'bank_transfer';
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    for (final c in [_amount, _reference, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Pay invoice ${widget.invoice['invoice_number'] ?? ''}'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Payment amount'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _method,
            decoration: const InputDecoration(labelText: 'Payment method'),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Cash')),
              DropdownMenuItem(
                value: 'bank_transfer',
                child: Text('Bank transfer'),
              ),
              DropdownMenuItem(value: 'card', child: Text('Card')),
              DropdownMenuItem(value: 'upi', child: Text('UPI')),
              DropdownMenuItem(value: 'wallet', child: Text('Wallet')),
              DropdownMenuItem(value: 'other', child: Text('Other')),
            ],
            onChanged: (value) => setState(() => _method = value!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reference,
            decoration: const InputDecoration(
              labelText: 'Reference (optional)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
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
            : const Text('Record payment'),
      ),
    ],
  );
  Future<void> _save() async {
    final amount = _parseMinor(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a payment amount greater than zero.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.recordPurchaseInvoicePayment(
        invoiceId: widget.invoice['id'] as String,
        amountMinor: amount,
        paymentMethod: _method,
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

class _LandedCostDialog extends StatefulWidget {
  const _LandedCostDialog({required this.order, required this.repository});
  final PurchaseOrder order;
  final PurchasingRepository repository;
  @override
  State<_LandedCostDialog> createState() => _LandedCostDialogState();
}

class _LandedCostDialogState extends State<_LandedCostDialog> {
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  String _method = 'by_value';
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Landed cost • ${widget.order.orderNumber}'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Cost amount'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _method,
            decoration: const InputDecoration(labelText: 'Allocate by'),
            items: const [
              DropdownMenuItem(value: 'by_value', child: Text('Line value')),
              DropdownMenuItem(value: 'by_quantity', child: Text('Quantity')),
            ],
            onChanged: (value) => setState(() => _method = value!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
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
            : const Text('Allocate cost'),
      ),
    ],
  );
  Future<void> _save() async {
    final amount = _parseMinor(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a cost amount greater than zero.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.addPurchaseLandedCost(
        purchaseOrderId: widget.order.id,
        amountMinor: amount,
        allocationMethod: _method,
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

int? _parseMinor(String value) {
  final parsed = double.tryParse(value.trim());
  if (parsed == null) return null;
  return (parsed * 100).round();
}

int _minorFromValue(Object? value) {
  if (value is num) return (value.toDouble() * 100).round();
  return ((double.tryParse(value?.toString() ?? '') ?? 0) * 100).round();
}

class _SupplierDialog extends StatefulWidget {
  const _SupplierDialog({
    required this.workspace,
    required this.repository,
    this.supplier,
  });

  final BusinessWorkspace workspace;
  final PurchasingRepository repository;
  final Supplier? supplier;

  @override
  State<_SupplierDialog> createState() => _SupplierDialogState();
}

class _SupplierDialogState extends State<_SupplierDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _contact = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _gstin = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final supplier = widget.supplier;
    if (supplier != null) {
      _name.text = supplier.name;
      _code.text = supplier.code ?? '';
      _contact.text = supplier.contactName ?? '';
      _phone.text = supplier.phone ?? '';
      _email.text = supplier.email ?? '';
      _gstin.text = supplier.gstin ?? '';
    }
  }

  @override
  void dispose() {
    for (final controller in [_name, _code, _contact, _phone, _email, _gstin]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.supplier == null ? 'Create supplier' : 'Edit supplier'),
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
                decoration: const InputDecoration(labelText: 'Supplier name'),
                validator: _required,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _code,
                      decoration: const InputDecoration(labelText: 'Code'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _contact,
                      decoration: const InputDecoration(
                        labelText: 'Contact person',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone'),
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
                decoration: const InputDecoration(labelText: 'GSTIN'),
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
            : Text(widget.supplier == null ? 'Create' : 'Save changes'),
      ),
    ],
  );

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final supplier = widget.supplier;
      if (supplier == null) {
        await widget.repository.createSupplier(
          businessId: widget.workspace.businessId,
          name: _name.text,
          code: _code.text,
          contactName: _contact.text,
          phone: _phone.text,
          email: _email.text,
          gstin: _gstin.text,
        );
      } else {
        await widget.repository.updateSupplier(
          businessId: widget.workspace.businessId,
          supplierId: supplier.id,
          name: _name.text,
          code: _code.text,
          contactName: _contact.text,
          phone: _phone.text,
          email: _email.text,
          gstin: _gstin.text,
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

class _PurchaseOrderDialog extends StatefulWidget {
  const _PurchaseOrderDialog({
    required this.workspace,
    required this.suppliers,
    required this.catalog,
    required this.repository,
  });

  final BusinessWorkspace workspace;
  final List<Supplier> suppliers;
  final CatalogSnapshot catalog;
  final PurchasingRepository repository;

  @override
  State<_PurchaseOrderDialog> createState() => _PurchaseOrderDialogState();
}

class _PurchaseOrderDialogState extends State<_PurchaseOrderDialog> {
  late String _supplierId = widget.suppliers.first.id;
  late String _warehouseId = widget.catalog.warehouses.first.id;
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  final List<_PurchaseDraftLine> _lines = [];
  bool _saving = false;
  String? _error;

  List<CatalogProduct> get _products => widget.catalog.products
      .where((product) => product.trackInventory)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _lines.add(_PurchaseDraftLine(_products.first));
  }

  @override
  void dispose() {
    _reference.dispose();
    _notes.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create purchase order'),
    content: SizedBox(
      width: 720,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _supplierId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Supplier'),
                    items: widget.suppliers
                        .map(
                          (supplier) => DropdownMenuItem(
                            value: supplier.id,
                            child: Text(supplier.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _supplierId = value ?? _supplierId),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _warehouseId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Receiving warehouse',
                    ),
                    items: widget.catalog.warehouses
                        .map(
                          (warehouse) => DropdownMenuItem(
                            value: warehouse.id,
                            child: Text(warehouse.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _warehouseId = value ?? _warehouseId),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reference,
              decoration: const InputDecoration(
                labelText: 'Supplier reference (optional)',
              ),
            ),
            const SizedBox(height: 16),
            for (var index = 0; index < _lines.length; index++) ...[
              _PurchaseLineEditor(
                line: _lines[index],
                products: _products,
                remove: _lines.length == 1
                    ? null
                    : () => setState(() {
                        final removed = _lines.removeAt(index);
                        removed.dispose();
                      }),
              ),
              const SizedBox(height: 10),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _lines.length >= _products.length
                    ? null
                    : () => setState(() {
                        final used = _lines
                            .map((line) => line.variantId)
                            .toSet();
                        final product = _products.firstWhere(
                          (item) => !used.contains(item.variantId),
                        );
                        _lines.add(_PurchaseDraftLine(product));
                      }),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add line'),
              ),
            ),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
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
            : const Text('Create order'),
      ),
    ],
  );

  Future<void> _save() async {
    final variantIds = _lines.map((line) => line.variantId).toSet();
    if (variantIds.length != _lines.length) {
      setState(() => _error = 'Each product may appear only once.');
      return;
    }
    final parsed =
        <
          ({
            String variantId,
            double quantity,
            int unitCostMinor,
            int taxBasisPoints,
          })
        >[];
    for (final line in _lines) {
      final quantity = double.tryParse(line.quantity.text.trim());
      final cost = parseMoneyToMinor(line.cost.text);
      final tax = double.tryParse(line.taxRate.text.trim());
      if (quantity == null ||
          quantity <= 0 ||
          cost == null ||
          tax == null ||
          tax < 0 ||
          tax > 100) {
        setState(
          () => _error = 'Every line needs a positive quantity, valid cost, and tax from 0–100%.',
        );
        return;
      }
      parsed.add((
        variantId: line.variantId,
        quantity: quantity,
        unitCostMinor: cost,
        taxBasisPoints: (tax * 100).round(),
      ));
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.createPurchaseOrder(
        businessId: widget.workspace.businessId,
        supplierId: _supplierId,
        warehouseId: _warehouseId,
        lines: parsed,
        supplierReference: _reference.text,
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

class _PurchaseDraftLine {
  _PurchaseDraftLine(CatalogProduct product)
    : variantId = product.variantId,
      quantity = TextEditingController(text: '1'),
      cost = TextEditingController(
        text: (product.costMinor / 100).toStringAsFixed(2),
      ),
      taxRate = TextEditingController(
        text: (product.taxRateBasisPoints / 100).toStringAsFixed(2),
      );

  String variantId;
  final TextEditingController quantity;
  final TextEditingController cost;
  final TextEditingController taxRate;

  void dispose() {
    quantity.dispose();
    cost.dispose();
    taxRate.dispose();
  }
}

class _PurchaseLineEditor extends StatefulWidget {
  const _PurchaseLineEditor({
    required this.line,
    required this.products,
    this.remove,
  });

  final _PurchaseDraftLine line;
  final List<CatalogProduct> products;
  final VoidCallback? remove;

  @override
  State<_PurchaseLineEditor> createState() => _PurchaseLineEditorState();
}

class _PurchaseLineEditorState extends State<_PurchaseLineEditor> {
  @override
  Widget build(BuildContext context) {
    final selectedProduct = widget.products
        .where((product) => product.variantId == widget.line.variantId)
        .firstOrNull;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ProductImage(
                imagePath: selectedProduct?.imagePath,
                width: 44,
                height: 44,
                borderRadius: 8,
                fit: BoxFit.contain,
                iconSize: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: widget.line.variantId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Product'),
                  items: widget.products
                      .map(
                        (product) => DropdownMenuItem(
                          value: product.variantId,
                          child: Text('${product.name} • ${product.sku}'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    final product = widget.products.firstWhere(
                      (item) => item.variantId == value,
                    );
                    setState(() {
                      widget.line.variantId = value;
                      widget.line.cost.text = (product.costMinor / 100)
                          .toStringAsFixed(2);
                      widget.line.taxRate.text =
                          (product.taxRateBasisPoints / 100).toStringAsFixed(2);
                    });
                  },
                ),
              ),
              if (widget.remove != null)
                IconButton(
                  tooltip: 'Remove line',
                  onPressed: widget.remove,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.line.quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: widget.line.cost,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Unit cost'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: widget.line.taxRate,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Tax %'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReceiveOrderDialog extends StatefulWidget {
  const _ReceiveOrderDialog({required this.order, required this.repository});

  final PurchaseOrder order;
  final PurchasingRepository repository;

  @override
  State<_ReceiveOrderDialog> createState() => _ReceiveOrderDialogState();
}

class _ReceiveOrderDialogState extends State<_ReceiveOrderDialog> {
  late final Map<String, TextEditingController> _quantities = {
    for (final line in widget.order.lines.where(
      (item) => item.remainingQuantity > 0,
    ))
      line.id: TextEditingController(text: _quantity(line.remainingQuantity)),
  };
  late final Map<String, TextEditingController> _identifiers = {
    for (final line in widget.order.lines.where(
      (item) => item.remainingQuantity > 0 && item.isSerialized,
    ))
      line.id: TextEditingController(),
  };
  late final Map<String, TextEditingController> _batchNumbers = {
    for (final line in widget.order.lines.where(
      (item) => item.remainingQuantity > 0 && !item.isSerialized,
    ))
      line.id: TextEditingController(),
  };
  late final Map<String, TextEditingController> _lotNumbers = {
    for (final line in widget.order.lines.where(
      (item) => item.remainingQuantity > 0 && !item.isSerialized,
    ))
      line.id: TextEditingController(),
  };
  late final Map<String, TextEditingController> _manufacturedDates = {
    for (final line in widget.order.lines.where(
      (item) => item.remainingQuantity > 0 && !item.isSerialized,
    ))
      line.id: TextEditingController(),
  };
  late final Map<String, TextEditingController> _expiryDates = {
    for (final line in widget.order.lines.where(
      (item) => item.remainingQuantity > 0 && !item.isSerialized,
    ))
      line.id: TextEditingController(),
  };
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in _quantities.values) {
      controller.dispose();
    }
    for (final controller in _identifiers.values) {
      controller.dispose();
    }
    for (final controller in _batchNumbers.values) {
      controller.dispose();
    }
    for (final controller in _lotNumbers.values) {
      controller.dispose();
    }
    for (final controller in _manufacturedDates.values) {
      controller.dispose();
    }
    for (final controller in _expiryDates.values) {
      controller.dispose();
    }
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Receive ${widget.order.orderNumber}'),
    content: SizedBox(
      width: 620,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final line in widget.order.lines.where(
              (item) => item.remainingQuantity > 0,
            )) ...[
              Row(
                children: [
                  Expanded(child: Text('${line.productName} • ${line.sku}')),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: _quantities[line.id],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Receive',
                        helperText: 'Max ${_quantity(line.remainingQuantity)}',
                      ),
                    ),
                  ),
                ],
              ),
              if (line.isSerialized) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _identifiers[line.id],
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText: line.trackingMode == 'imei'
                        ? 'IMEIs, one per line'
                        : 'Serial numbers, one per line',
                    helperText:
                        'Enter exactly one ${line.identifierLabel} for each unit received.',
                    alignLabelWithHint: true,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 10),
                Text(
                  'Batch and expiry (optional)',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _batchNumbers[line.id],
                        decoration: const InputDecoration(
                          labelText: 'Batch number',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _lotNumbers[line.id],
                        decoration: const InputDecoration(
                          labelText: 'Lot number',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manufacturedDates[line.id],
                        decoration: const InputDecoration(
                          labelText: 'Manufactured',
                          hintText: 'YYYY-MM-DD',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _expiryDates[line.id],
                        decoration: const InputDecoration(
                          labelText: 'Expiry',
                          hintText: 'YYYY-MM-DD',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _reference,
              decoration: const InputDecoration(
                labelText: 'Supplier document number',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Receipt notes'),
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
            : const Text('Receive stock'),
      ),
    ],
  );

  Future<void> _save() async {
    final values = <String, double>{};
    final identifiersByLine = <String, List<String>>{};
    final batchDetailsByLine = <String, Map<String, String?>>{};
    final seenIdentifiers = <String>{};
    for (final line in widget.order.lines.where(
      (item) => item.remainingQuantity > 0,
    )) {
      final value = double.tryParse(_quantities[line.id]!.text.trim());
      if (value == null || value < 0 || value > line.remainingQuantity) {
        setState(
          () => _error =
              'Enter quantities between zero and each remaining amount.',
        );
        return;
      }
      if (line.isSerialized) {
        final identifiers = _parseIdentifiers(_identifiers[line.id]!.text);
        if (value == 0 && identifiers.isNotEmpty) {
          setState(
            () =>
                _error = 'Clear identifiers for ${line.sku} or receive stock.',
          );
          return;
        }
        if (value > 0) {
          if (value != value.roundToDouble()) {
            setState(
              () => _error =
                  'Serialized SKU ${line.sku} requires a whole quantity.',
            );
            return;
          }
          if (identifiers.length != value.toInt()) {
            setState(
              () => _error =
                  'Enter exactly ${value.toInt()} ${line.identifierLabel}${value == 1 ? '' : 's'} for ${line.sku}.',
            );
            return;
          }
          for (final identifier in identifiers) {
            final normalized = line.trackingMode == 'imei'
                ? identifier.replaceAll(RegExp('[^0-9]'), '')
                : identifier.toUpperCase();
            if (line.trackingMode == 'imei' &&
                !RegExp(r'^[0-9]{15}$').hasMatch(normalized)) {
              setState(
                () => _error =
                    'Every IMEI for ${line.sku} must contain 15 digits.',
              );
              return;
            }
            if (line.trackingMode == 'serial' &&
                (normalized.length < 3 || normalized.length > 120)) {
              setState(
                () => _error =
                    'Serial numbers for ${line.sku} must contain 3 to 120 characters.',
              );
              return;
            }
            if (!seenIdentifiers.add(normalized)) {
              setState(
                () => _error = 'Remove duplicate identifier $identifier.',
              );
              return;
            }
          }
          identifiersByLine[line.id] = identifiers;
        }
      } else {
        final batchNumber = _batchNumbers[line.id]!.text.trim();
        final lotNumber = _lotNumbers[line.id]!.text.trim();
        final manufactured = _manufacturedDates[line.id]!.text.trim();
        final expiry = _expiryDates[line.id]!.text.trim();
        final hasBatchMetadata =
            batchNumber.isNotEmpty ||
            lotNumber.isNotEmpty ||
            manufactured.isNotEmpty ||
            expiry.isNotEmpty;
        if (hasBatchMetadata && batchNumber.isEmpty) {
          setState(() => _error = 'Enter a batch number for ${line.sku}.');
          return;
        }
        DateTime? manufacturedDate;
        DateTime? expiryDate;
        if (manufactured.isNotEmpty) {
          manufacturedDate = DateTime.tryParse(manufactured);
          if (manufacturedDate == null) {
            setState(() => _error = 'Use YYYY-MM-DD for manufacture date.');
            return;
          }
        }
        if (expiry.isNotEmpty) {
          expiryDate = DateTime.tryParse(expiry);
          if (expiryDate == null) {
            setState(() => _error = 'Use YYYY-MM-DD for expiry date.');
            return;
          }
          final today = DateTime.now();
          final todayOnly = DateTime(today.year, today.month, today.day);
          if (expiryDate.isBefore(todayOnly)) {
            setState(() => _error = 'Expiry date cannot be in the past.');
            return;
          }
        }
        if (manufacturedDate != null &&
            expiryDate != null &&
            expiryDate.isBefore(manufacturedDate)) {
          setState(
            () => _error = 'Expiry date cannot be before manufacture date.',
          );
          return;
        }
        if (hasBatchMetadata) {
          batchDetailsByLine[line.id] = {
            'batch_number': batchNumber,
            'lot_number': lotNumber,
            'manufactured_on': manufactured.isEmpty ? null : manufactured,
            'expires_on': expiry.isEmpty ? null : expiry,
          };
        }
      }
      if (value > 0) values[line.id] = value;
    }
    if (values.isEmpty) {
      setState(() => _error = 'Receive at least one item.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.receivePurchaseOrder(
        purchaseOrderId: widget.order.id,
        quantities: values,
        identifiersByLine: identifiersByLine,
        batchDetailsByLine: batchDetailsByLine,
        supplierReference: _reference.text,
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

List<String> _parseIdentifiers(String value) => value
    .split(RegExp(r'[\r\n]+'))
    .map((identifier) => identifier.trim())
    .where((identifier) => identifier.isNotEmpty)
    .toList(growable: false);

class _ReturnOrderDialog extends StatefulWidget {
  const _ReturnOrderDialog({required this.order, required this.repository});

  final PurchaseOrder order;
  final PurchasingRepository repository;

  @override
  State<_ReturnOrderDialog> createState() => _ReturnOrderDialogState();
}

class _ReturnOrderDialogState extends State<_ReturnOrderDialog> {
  late final Map<String, TextEditingController> _quantities = {
    for (final line in widget.order.lines.where(
      (item) => item.returnableQuantity > 0,
    ))
      line.id: TextEditingController(text: '0'),
  };
  final _reason = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in _quantities.values) {
      controller.dispose();
    }
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Return ${widget.order.orderNumber}'),
    content: SizedBox(
      width: 620,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Only received stock that is still available and unreserved can be returned.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            for (final line in widget.order.lines.where(
              (item) => item.returnableQuantity > 0,
            )) ...[
              Row(
                children: [
                  Expanded(child: Text('${line.productName} • ${line.sku}')),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: _quantities[line.id],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Return',
                        helperText: 'Max ${_quantity(line.returnableQuantity)}',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _reason,
              autofocus: true,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Return reason',
                hintText: 'Damaged delivery, incorrect item, supplier recall…',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Return notes'),
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
            : const Text('Complete return'),
      ),
    ],
  );

  Future<void> _save() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Enter a return reason.');
      return;
    }
    final values = <String, double>{};
    for (final line in widget.order.lines.where(
      (item) => item.returnableQuantity > 0,
    )) {
      final value = double.tryParse(_quantities[line.id]!.text.trim());
      if (value == null || value < 0 || value > line.returnableQuantity) {
        setState(
          () => _error =
              'Enter quantities between zero and each returnable amount.',
        );
        return;
      }
      if (value > 0) values[line.id] = value;
    }
    if (values.isEmpty) {
      setState(() => _error = 'Return at least one item.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.returnPurchaseOrder(
        purchaseOrderId: widget.order.id,
        quantities: values,
        reason: reason,
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

String _statusLabel(String status) => switch (status) {
  'partially_received' => 'Partially received',
  'received' => 'Received',
  'ordered' => 'Ordered',
  _ => status,
};

String _quantity(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(3);
