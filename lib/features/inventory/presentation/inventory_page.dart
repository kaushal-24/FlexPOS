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
import 'package:flexpos/features/catalog/data/catalog_repository.dart';
import 'package:flexpos/features/catalog/domain/catalog_models.dart';
import 'package:flexpos/features/inventory/data/inventory_repository.dart';
import 'package:flexpos/features/inventory/domain/inventory_models.dart';
import 'package:flexpos/features/tenants/domain/business_workspace.dart';
import 'package:flexpos/features/tenants/domain/feature_entitlement.dart';
import 'package:flexpos/features/tenants/presentation/feature_entitlements/feature_disabled_state.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  String _query = '';
  String _serializedQuery = '';
  String _transferQuery = '';
  String _lossQuery = '';
  String _sort = 'name_asc';
  int _page = 0;
  final Set<String> _selectedProductIds = {};

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    if (workspace == null) {
      return const EmptyState(
        icon: Icons.add_business_outlined,
        title: 'Select a business',
        message: 'A business workspace is required to view inventory.',
      );
    }
    final isCashier = workspace.roleName.trim().toLowerCase() == 'cashier';
    if (isCashier || !workspace.canRead('inventory')) {
      return EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Inventory is restricted',
        message: isCashier
            ? 'Cashiers can see product availability in POS. Inventory details are limited to stock-management roles.'
            : 'Your role does not include permission to view inventory.',
      );
    }
    if (!workspace.isFeatureEnabled(FeatureCodes.inventory)) {
      return FeatureDisabledState(
        featureName: 'Inventory',
        canManage: workspace.canManage('business'),
      );
    }
    final snapshot = ref.watch(catalogSnapshotProvider);
    final stockLosses = ref.watch(stockLossEventsProvider);
    final serializedUnits = ref.watch(serializedInventoryUnitsProvider);
    final transferRequests = ref.watch(inventoryTransferRequestsProvider);
    final canCreate = workspace.canCreate('inventory');
    final canUpdate = workspace.canUpdate('inventory');
    final canManage = canCreate || canUpdate;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _adjust(context, ref, workspace),
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Adjust stock'),
            )
          : null,
      body: snapshot.when(
        loading: () => const DataPageSkeleton(sectionLabel: 'inventory'),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load inventory',
          message: error.toString(),
          action: FilledButton.icon(
            onPressed: () => ref.invalidate(catalogSnapshotProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ),
        data: (data) {
          final serializedItems = (serializedUnits.value ?? const [])
              .where((unit) {
                final haystack =
                    '${unit.identifier} ${unit.productName} ${unit.variantName} '
                            '${unit.sku} ${unit.warehouseName} ${unit.statusLabel}'
                        .toLowerCase();
                return haystack.contains(_serializedQuery);
              })
              .toList(growable: false);
          final warehouseNames = {
            for (final warehouse in data.warehouses)
              warehouse.id: warehouse.name,
          };
          final productNames = {
            for (final product in data.products)
              product.variantId: '${product.name} ${product.sku}',
          };
          final transferItems = (transferRequests.value ?? const [])
              .where((request) {
                final haystack =
                    '${request.requestNumber} ${request.statusLabel} ${request.reason} '
                            '${warehouseNames[request.sourceWarehouseId] ?? ''} '
                            '${warehouseNames[request.destinationWarehouseId] ?? ''} '
                            '${productNames[request.variantId] ?? ''}'
                        .toLowerCase();
                return haystack.contains(_transferQuery);
              })
              .toList(growable: false);
          final lossItems = (stockLosses.value ?? const [])
              .where((event) {
                final haystack =
                    '${event.eventNumber} ${event.lossType} ${event.productName} '
                            '${event.variantName} ${event.sku} ${event.warehouseName} '
                            '${event.reason} ${event.notes ?? ''}'
                        .toLowerCase();
                return haystack.contains(_lossQuery);
              })
              .toList(growable: false);
          final filteredTracked = data.products
              .where(
                (product) =>
                    product.trackInventory &&
                    product.searchText.contains(_query),
              )
              .toList();
          filteredTracked.sort(
            (a, b) => switch (_sort) {
              'stock_desc' =>
                data
                    .stockFor(b.variantId)
                    .compareTo(data.stockFor(a.variantId)),
              'stock_asc' =>
                data
                    .stockFor(a.variantId)
                    .compareTo(data.stockFor(b.variantId)),
              _ => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            },
          );
          final pageCount = pageCountFor(filteredTracked.length);
          if (_page >= pageCount) _page = pageCount - 1;
          final tracked = pageItems(filteredTracked, _page);
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 96),
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 8,
                children: [
                  Text(
                    'Inventory',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _exportInventory(data),
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Export CSV'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _exportInventoryPdf(data),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Export PDF'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${data.warehouses.length} warehouse${data.warehouses.length == 1 ? '' : 's'} • ${tracked.length} tracked SKU${tracked.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (canManage) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => _registerSerializedInventory(
                        context,
                        ref,
                        workspace,
                        data,
                        tracked,
                      ),
                      icon: const Icon(Icons.qr_code_2_rounded),
                      label: const Text('Register serials or IMEIs'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _recordLoss(
                        context,
                        ref,
                        workspace,
                        data,
                        tracked,
                        serializedUnits.value ?? const [],
                      ),
                      icon: const Icon(Icons.report_problem_outlined),
                      label: const Text('Record damage or wastage'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _transfer(
                        context,
                        ref,
                        workspace,
                        data,
                        tracked,
                        serializedUnits.value ?? const [],
                      ),
                      icon: const Icon(Icons.swap_horiz_rounded),
                      label: const Text('Transfer stock'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _requestTransfer(
                        context,
                        ref,
                        workspace,
                        data,
                        tracked,
                        serializedUnits.value ?? const [],
                      ),
                      icon: const Icon(Icons.assignment_outlined),
                      label: const Text('Request transfer'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _startStocktake(
                        context,
                        ref,
                        workspace,
                        data,
                        tracked,
                      ),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Stocktake'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              DataListControls(
                query: _query,
                onSearchChanged: (value) => setState(() {
                  _query = value.trim().toLowerCase();
                  _page = 0;
                }),
                searchLabel: 'Search tracked SKU',
                sortValue: _sort,
                sortOptions: const [
                  DataListSortOption('name_asc', 'Name (A–Z)'),
                  DataListSortOption('stock_desc', 'Stock (high–low)'),
                  DataListSortOption('stock_asc', 'Stock (low–high)'),
                ],
                onSortChanged: (value) => setState(() {
                  _sort = value;
                  _page = 0;
                }),
                page: _page,
                pageCount: pageCount,
                totalCount: filteredTracked.length,
                onPageChanged: (value) => setState(() => _page = value),
                selectedCount: _selectedProductIds.length,
                allSelected:
                    tracked.isNotEmpty &&
                    tracked.every(
                      (product) =>
                          _selectedProductIds.contains(product.productId),
                    ),
                onSelectAll: tracked.isEmpty
                    ? null
                    : (selected) => setState(() {
                        if (selected ?? false) {
                          _selectedProductIds.addAll(
                            tracked.map((product) => product.productId),
                          );
                        } else {
                          _selectedProductIds.removeAll(
                            tracked.map((product) => product.productId),
                          );
                        }
                      }),
                onClearSelection: () =>
                    setState(() => _selectedProductIds.clear()),
                bulkActions: [
                  FilledButton.tonalIcon(
                    onPressed: canManage
                        ? () => _startStocktake(
                            context,
                            ref,
                            workspace,
                            data,
                            data.products
                                .where(
                                  (product) => _selectedProductIds.contains(
                                    product.productId,
                                  ),
                                )
                                .toList(growable: false),
                          )
                        : null,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Stocktake selected'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (tracked.isEmpty)
                const EmptyState(
                  icon: Icons.warehouse_outlined,
                  title: 'No stock-tracked products',
                  message:
                      'Create a product first, then record its opening stock.',
                )
              else
                for (final product in tracked) ...[
                  AppPanel(
                    child: Row(
                      children: [
                        Checkbox(
                          value: _selectedProductIds.contains(
                            product.productId,
                          ),
                          onChanged: (selected) => setState(() {
                            if (selected ?? false) {
                              _selectedProductIds.add(product.productId);
                            } else {
                              _selectedProductIds.remove(product.productId);
                            }
                          }),
                        ),
                        ProductImage(
                          imagePath: product.imagePath,
                          width: 52,
                          height: 52,
                          borderRadius: 12,
                          fit: BoxFit.contain,
                          iconSize: 24,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                'SKU ${product.sku}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (product.trackingMode != 'none') ...[
                                const SizedBox(height: 5),
                                StatusBadge(
                                  label: product.trackingMode == 'imei'
                                      ? 'IMEI tracked'
                                      : 'Serial tracked',
                                  tone: StatusTone.info,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        _StockValue(
                          value: data.stockFor(product.variantId),
                          threshold: data.reorderPointFor(product.variantId),
                        ),
                        if (canUpdate) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: 'Set low-stock threshold',
                            onPressed: () => _setThreshold(
                              context,
                              ref,
                              workspace,
                              data,
                              product,
                            ),
                            icon: const Icon(
                              Icons.notifications_active_outlined,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              const SizedBox(height: 18),
              Text(
                'Serialized inventory',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Search serials, IMEIs, products, or warehouses',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (value) => setState(
                  () => _serializedQuery = value.trim().toLowerCase(),
                ),
              ),
              const SizedBox(height: 12),
              serializedUnits.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load serialized inventory',
                  message: error.toString(),
                  action: OutlinedButton.icon(
                    onPressed: () =>
                        ref.invalidate(serializedInventoryUnitsProvider),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ),
                data: (units) => serializedItems.isEmpty
                    ? const EmptyState(
                        icon: Icons.qr_code_2_rounded,
                        title: 'No matching serials or IMEIs',
                        message: 'Registered serialized units and their current status will appear here.',
                      )
                    : Column(
                        children: [
                          for (final unit in serializedItems) ...[
                            _SerializedInventoryTile(unit: unit),
                            const SizedBox(height: 12),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 18),
              Text(
                'Transfer requests',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  labelText:
                      'Search transfer number, product, warehouse, or status',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (value) =>
                    setState(() => _transferQuery = value.trim().toLowerCase()),
              ),
              const SizedBox(height: 12),
              transferRequests.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load transfer requests',
                  message: error.toString(),
                  action: OutlinedButton.icon(
                    onPressed: () =>
                        ref.invalidate(inventoryTransferRequestsProvider),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ),
                data: (requests) => transferItems.isEmpty
                    ? const EmptyState(
                        icon: Icons.assignment_outlined,
                        title: 'No matching transfer requests',
                        message: 'Staged warehouse transfer requests will appear here.',
                      )
                    : Column(
                        children: [
                          for (final request in transferItems) ...[
                            _InventoryTransferRequestTile(
                              request: request,
                              snapshot: data,
                              canManage: canManage,
                              onAction: (action) => _advanceTransferRequest(
                                context,
                                ref,
                                workspace,
                                request,
                                action,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 18),
              Text(
                'Recent damage and wastage',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  labelText:
                      'Search loss number, product, warehouse, or reason',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (value) =>
                    setState(() => _lossQuery = value.trim().toLowerCase()),
              ),
              const SizedBox(height: 12),
              stockLosses.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load stock losses',
                  message: error.toString(),
                  action: OutlinedButton.icon(
                    onPressed: () => ref.invalidate(stockLossEventsProvider),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ),
                data: (events) => lossItems.isEmpty
                    ? const EmptyState(
                        icon: Icons.verified_outlined,
                        title: 'No matching damage or wastage',
                        message: 'Stock loss events will appear here after they are recorded.',
                      )
                    : Column(
                        children: [
                          for (final event in lossItems) ...[
                            _StockLossEventTile(
                              event: event,
                              currencyCode: workspace.currencyCode,
                            ),
                            const SizedBox(height: 12),
                          ],
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _exportInventory(CatalogSnapshot data) async {
    try {
      final products = data.products
          .where((item) => item.trackInventory)
          .toList(growable: false);
      final path = await saveCsvExport(
        fileName: 'flexpos-inventory.csv',
        rows: [
          const [
            'Product',
            'SKU',
            'Tracked',
            'On hand',
            'Reserved',
            'Available',
            'Reorder point',
          ],
          for (final product in products) _inventoryExportRow(data, product),
        ],
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Inventory CSV exported.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not export inventory: $error')),
      );
    }
  }

  List<Object?> _inventoryExportRow(
    CatalogSnapshot data,
    CatalogProduct product,
  ) {
    final balances = data.balances.where(
      (balance) => balance.variantId == product.variantId,
    );
    final onHand = balances.fold<double>(
      0,
      (total, balance) => total + balance.quantity,
    );
    final reserved = balances.fold<double>(
      0,
      (total, balance) => total + balance.reserved,
    );
    return [
      product.name,
      product.sku,
      product.trackInventory,
      onHand,
      reserved,
      onHand - reserved,
      data.reorderPointFor(product.variantId),
    ];
  }

  Future<void> _exportInventoryPdf(CatalogSnapshot data) async {
    try {
      final products = data.products
          .where((item) => item.trackInventory)
          .toList(growable: false);
      final path = await savePdfExport(
        fileName: 'flexpos-inventory.pdf',
        title: 'FlexPOS inventory',
        headers: const [
          'Product',
          'SKU',
          'Tracked',
          'On hand',
          'Reserved',
          'Available',
          'Reorder point',
        ],
        rows: [
          for (final product in products) _inventoryExportRow(data, product),
        ],
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Inventory PDF exported.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not export inventory: $error')),
      );
    }
  }

  Future<void> _adjust(
    BuildContext context,
    WidgetRef ref,
    BusinessWorkspace workspace,
  ) async {
    final snapshot = ref.read(catalogSnapshotProvider).value;
    final products = snapshot?.products
        .where((product) => product.trackInventory)
        .toList(growable: false);
    if (snapshot == null ||
        products == null ||
        products.isEmpty ||
        snapshot.warehouses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A product and warehouse are required.')),
      );
      return;
    }
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _InventoryAdjustmentDialog(
        workspace: workspace,
        snapshot: snapshot,
        products: products,
        repository: ref.read(catalogRepositoryProvider),
      ),
    );
    if (changed == true) {
      ref.invalidate(catalogSnapshotProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Inventory adjusted.')));
      }
    }
  }

  Future<void> _setThreshold(
    BuildContext context,
    WidgetRef ref,
    BusinessWorkspace workspace,
    CatalogSnapshot snapshot,
    CatalogProduct product,
  ) async {
    if (snapshot.warehouses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a warehouse before setting a threshold.'),
        ),
      );
      return;
    }
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _InventoryThresholdDialog(
        businessId: workspace.businessId,
        snapshot: snapshot,
        product: product,
        repository: ref.read(inventoryRepositoryProvider),
      ),
    );
    if (updated == true) {
      ref.invalidate(catalogSnapshotProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Low-stock threshold updated.')),
        );
      }
    }
  }

  Future<void> _recordLoss(
    BuildContext context,
    WidgetRef ref,
    BusinessWorkspace workspace,
    CatalogSnapshot snapshot,
    List<CatalogProduct> products,
    List<SerializedInventoryUnit> serializedUnits,
  ) async {
    if (products.isEmpty || snapshot.warehouses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A product and warehouse are required.')),
      );
      return;
    }
    final recorded = await showDialog<bool>(
      context: context,
      builder: (_) => _StockLossDialog(
        workspace: workspace,
        snapshot: snapshot,
        products: products,
        serializedUnits: serializedUnits,
        repository: ref.read(inventoryRepositoryProvider),
      ),
    );
    if (recorded == true) {
      ref.invalidate(catalogSnapshotProvider);
      ref.invalidate(stockLossEventsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stock loss recorded and inventory updated.'),
          ),
        );
      }
    }
  }

  Future<void> _registerSerializedInventory(
    BuildContext context,
    WidgetRef ref,
    BusinessWorkspace workspace,
    CatalogSnapshot snapshot,
    List<CatalogProduct> products,
  ) async {
    final eligible = products
        .where((product) => !product.allowFractionalQuantity)
        .toList(growable: false);
    if (eligible.isEmpty || snapshot.warehouses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A whole-unit product and warehouse are required.'),
        ),
      );
      return;
    }
    final registered = await showDialog<bool>(
      context: context,
      builder: (_) => _SerializedInventoryDialog(
        workspace: workspace,
        snapshot: snapshot,
        products: eligible,
        repository: ref.read(inventoryRepositoryProvider),
      ),
    );
    if (registered == true) {
      ref.invalidate(catalogSnapshotProvider);
      ref.invalidate(serializedInventoryUnitsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Serialized inventory registered.')),
        );
      }
    }
  }

  Future<void> _transfer(
    BuildContext context,
    WidgetRef ref,
    BusinessWorkspace workspace,
    CatalogSnapshot snapshot,
    List<CatalogProduct> products,
    List<SerializedInventoryUnit> serializedUnits,
  ) async {
    if (snapshot.warehouses.length < 2 || products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Two warehouses and a product are required.'),
        ),
      );
      return;
    }
    final transferred = await showDialog<bool>(
      context: context,
      builder: (_) => _InventoryTransferDialog(
        workspace: workspace,
        snapshot: snapshot,
        products: products,
        serializedUnits: serializedUnits,
        repository: ref.read(inventoryRepositoryProvider),
      ),
    );
    if (transferred == true) {
      ref.invalidate(catalogSnapshotProvider);
      ref.invalidate(serializedInventoryUnitsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stock transferred successfully.')),
        );
      }
    }
  }

  Future<void> _requestTransfer(
    BuildContext context,
    WidgetRef ref,
    BusinessWorkspace workspace,
    CatalogSnapshot snapshot,
    List<CatalogProduct> products,
    List<SerializedInventoryUnit> serializedUnits,
  ) async {
    if (snapshot.warehouses.length < 2 || products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Two warehouses and a product are required.'),
        ),
      );
      return;
    }
    final requested = await showDialog<bool>(
      context: context,
      builder: (_) => _InventoryTransferDialog(
        workspace: workspace,
        snapshot: snapshot,
        products: products,
        serializedUnits: serializedUnits,
        repository: ref.read(inventoryRepositoryProvider),
        stagedRequest: true,
      ),
    );
    if (requested == true) {
      ref.invalidate(catalogSnapshotProvider);
      ref.invalidate(serializedInventoryUnitsProvider);
      ref.invalidate(inventoryTransferRequestsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transfer request created.')),
        );
      }
    }
  }

  Future<void> _advanceTransferRequest(
    BuildContext context,
    WidgetRef ref,
    BusinessWorkspace workspace,
    InventoryTransferRequest request,
    String action,
  ) async {
    final repository = ref.read(inventoryRepositoryProvider);
    try {
      switch (action) {
        case 'approve':
          await repository.approveInventoryTransfer(
            businessId: workspace.businessId,
            requestId: request.id,
          );
        case 'dispatch':
          await repository.dispatchInventoryTransfer(
            businessId: workspace.businessId,
            requestId: request.id,
          );
        case 'receive':
          await repository.receiveInventoryTransfer(
            businessId: workspace.businessId,
            requestId: request.id,
          );
        case 'cancel':
          await repository.cancelInventoryTransfer(
            businessId: workspace.businessId,
            requestId: request.id,
          );
      }
      ref.invalidate(catalogSnapshotProvider);
      ref.invalidate(serializedInventoryUnitsProvider);
      ref.invalidate(inventoryTransferRequestsProvider);
      if (context.mounted) {
        final actionLabel = switch (action) {
          'approve' => 'approved',
          'dispatch' => 'dispatched',
          'receive' => 'received',
          'cancel' => 'cancelled',
          _ => action,
        };
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Transfer $actionLabel.')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not $action transfer: $error')),
        );
      }
    }
  }

  Future<void> _startStocktake(
    BuildContext context,
    WidgetRef ref,
    BusinessWorkspace workspace,
    CatalogSnapshot snapshot,
    List<CatalogProduct> products,
  ) async {
    if (products.isEmpty || snapshot.warehouses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A product and warehouse are required.')),
      );
      return;
    }
    final repository = ref.read(inventoryRepositoryProvider);
    final stocktakeId = await showDialog<String>(
      context: context,
      builder: (_) => _InventoryStocktakeStartDialog(
        workspace: workspace,
        snapshot: snapshot,
        warehouses: snapshot.warehouses,
        repository: repository,
      ),
    );
    if (stocktakeId == null || !context.mounted) return;
    try {
      final items = await repository.fetchInventoryStocktakeItems(stocktakeId);
      if (!context.mounted) return;
      final finalized = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _InventoryStocktakeCountDialog(
          stocktakeId: stocktakeId,
          items: items,
          products: products,
          repository: repository,
        ),
      );
      if (finalized == true) {
        ref.invalidate(catalogSnapshotProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Stocktake finalized successfully.')),
          );
        }
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load stocktake items: $error')),
        );
      }
    }
  }
}

class _InventoryThresholdDialog extends StatefulWidget {
  const _InventoryThresholdDialog({
    required this.businessId,
    required this.snapshot,
    required this.product,
    required this.repository,
  });

  final String businessId;
  final CatalogSnapshot snapshot;
  final CatalogProduct product;
  final InventoryRepository repository;

  @override
  State<_InventoryThresholdDialog> createState() =>
      _InventoryThresholdDialogState();
}

class _InventoryThresholdDialogState extends State<_InventoryThresholdDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _thresholdController;
  late String _warehouseId;
  bool _saving = false;
  String? _error;

  double get _currentThreshold =>
      widget.snapshot.balances
          .where(
            (balance) =>
                balance.variantId == widget.product.variantId &&
                balance.warehouseId == _warehouseId,
          )
          .map((balance) => balance.reorderPoint)
          .firstOrNull ??
      0;

  @override
  void initState() {
    super.initState();
    _warehouseId =
        widget.snapshot.bestWarehouse(variantId: widget.product.variantId)?.id ??
        widget.snapshot.warehouses.first.id;
    _thresholdController = TextEditingController(
      text: _formatThreshold(_currentThreshold),
    );
  }

  @override
  void dispose() {
    _thresholdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Low-stock threshold'),
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
                '${widget.product.name} • ${widget.product.sku}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              DropdownMenu<String>(
                initialSelection: _warehouseId,
                enableFilter: true,
                enableSearch: true,
                requestFocusOnTap: true,
                expandedInsets: EdgeInsets.zero,
                label: const Text('Warehouse'),
                hintText: 'Search warehouse',
                leadingIcon: const Icon(Icons.search_rounded),
                dropdownMenuEntries: widget.snapshot.warehouses
                    .map(
                      (warehouse) => DropdownMenuEntry<String>(
                        value: warehouse.id,
                        label: warehouse.name,
                      ),
                    )
                    .toList(),
                onSelected: _saving
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _warehouseId = value;
                          _thresholdController.text = _formatThreshold(
                            _currentThreshold,
                          );
                        });
                      },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _thresholdController,
                enabled: !_saving,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Alert when available stock is at or below',
                  suffixText: 'units',
                  helperText: 'Use 0 to disable the low-stock alert for this warehouse.',
                ),
                validator: (value) {
                  final parsed = double.tryParse(value?.trim() ?? '');
                  if (parsed == null || parsed.isNaN || parsed.isInfinite) {
                    return 'Enter a valid number';
                  }
                  if (parsed < 0) return 'Threshold cannot be negative';
                  return null;
                },
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
            : const Text('Save threshold'),
      ),
    ],
  );

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final threshold = double.parse(_thresholdController.text.trim());
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.setInventoryThreshold(
        businessId: widget.businessId,
        warehouseId: _warehouseId,
        variantId: widget.product.variantId,
        reorderPoint: threshold,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _formatThreshold(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();
}

class _InventoryTransferRequestTile extends StatelessWidget {
  const _InventoryTransferRequestTile({
    required this.request,
    required this.snapshot,
    required this.canManage,
    required this.onAction,
  });

  final InventoryTransferRequest request;
  final CatalogSnapshot snapshot;
  final bool canManage;
  final Future<void> Function(String action) onAction;

  @override
  Widget build(BuildContext context) {
    final source =
        snapshot.warehouses
            .where((warehouse) => warehouse.id == request.sourceWarehouseId)
            .map((warehouse) => warehouse.name)
            .firstOrNull ??
        request.sourceWarehouseId;
    final destination =
        snapshot.warehouses
            .where(
              (warehouse) => warehouse.id == request.destinationWarehouseId,
            )
            .map((warehouse) => warehouse.name)
            .firstOrNull ??
        request.destinationWarehouseId;
    final product =
        snapshot.products
            .where((product) => product.variantId == request.variantId)
            .map((product) => '${product.name} • ${product.sku}')
            .firstOrNull ??
        request.variantId;

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  request.requestNumber,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              StatusBadge(
                label: request.statusLabel,
                tone: switch (request.status) {
                  'received' => StatusTone.success,
                  'cancelled' => StatusTone.danger,
                  'dispatched' => StatusTone.warning,
                  _ => StatusTone.info,
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(product),
          Text('$source → $destination • ${_quantityLabel(request.quantity)}'),
          Text(
            request.reason,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (canManage &&
              request.status != 'received' &&
              request.status != 'cancelled') ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (request.status == 'requested')
                  OutlinedButton.icon(
                    onPressed: () => onAction('approve'),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Approve'),
                  ),
                if (request.status == 'approved')
                  OutlinedButton.icon(
                    onPressed: () => onAction('dispatch'),
                    icon: const Icon(Icons.local_shipping_outlined),
                    label: const Text('Dispatch'),
                  ),
                if (request.status == 'dispatched')
                  FilledButton.tonalIcon(
                    onPressed: () => onAction('receive'),
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('Receive'),
                  ),
                if (request.status == 'requested' ||
                    request.status == 'approved')
                  TextButton.icon(
                    onPressed: () => onAction('cancel'),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancel'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SerializedInventoryTile extends StatelessWidget {
  const _SerializedInventoryTile({required this.unit});

  final SerializedInventoryUnit unit;

  @override
  Widget build(BuildContext context) => AppPanel(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CircleAvatar(child: Icon(Icons.qr_code_2_rounded)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                unit.identifier,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '${unit.productName} • ${unit.sku} • ${unit.warehouseName}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  StatusBadge(label: unit.trackingLabel, tone: StatusTone.info),
                  StatusBadge(
                    label: unit.statusLabel,
                    tone: unit.status == 'in_stock'
                        ? StatusTone.success
                        : StatusTone.neutral,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          DateFormat.yMMMd().add_jm().format(unit.registeredAt),
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.end,
        ),
      ],
    ),
  );
}

class _StockLossEventTile extends StatelessWidget {
  const _StockLossEventTile({required this.event, required this.currencyCode});

  final StockLossEvent event;
  final String currencyCode;

  @override
  Widget build(BuildContext context) => AppPanel(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          child: Icon(
            event.lossType == 'damage'
                ? Icons.broken_image_outlined
                : Icons.delete_sweep_outlined,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    event.productName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  StatusBadge(
                    label: event.typeLabel,
                    tone: event.lossType == 'damage'
                        ? StatusTone.danger
                        : StatusTone.warning,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${event.eventNumber} • ${event.sku} • ${event.warehouseName}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(event.reason),
              if (event.notes != null) ...[
                const SizedBox(height: 2),
                Text(
                  event.notes!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '-${_quantityLabel(event.quantity)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              formatMoney(currencyCode, event.lossValueMinor),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              DateFormat.yMMMd().add_jm().format(event.recordedAt),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    ),
  );
}

class _StockValue extends StatelessWidget {
  const _StockValue({required this.value, required this.threshold});
  final double value;
  final double threshold;

  @override
  Widget build(BuildContext context) {
    final outOfStock = value <= 0;
    final low = !outOfStock && threshold > 0 && value <= threshold;
    final color = outOfStock || low
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value.toStringAsFixed(value == value.roundToDouble() ? 0 : 3),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color),
        ),
        Text(
          outOfStock
              ? 'Out of stock'
              : low
              ? 'Low stock'
              : threshold > 0
              ? 'Alert at ${_quantityLabel(threshold)}'
              : 'Available',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _SerializedInventoryDialog extends StatefulWidget {
  const _SerializedInventoryDialog({
    required this.workspace,
    required this.snapshot,
    required this.products,
    required this.repository,
  });

  final BusinessWorkspace workspace;
  final CatalogSnapshot snapshot;
  final List<CatalogProduct> products;
  final InventoryRepository repository;

  @override
  State<_SerializedInventoryDialog> createState() =>
      _SerializedInventoryDialogState();
}

class _SerializedInventoryDialogState
    extends State<_SerializedInventoryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _identifiers = TextEditingController();
  late String _variantId = widget.products.first.variantId;
  late String _warehouseId =
      widget.snapshot.bestWarehouse(variantId: widget.products.first.variantId)?.id ??
      widget.snapshot.warehouses.first.id;
  late String _trackingMode = widget.products.first.trackingMode == 'none'
      ? 'serial'
      : widget.products.first.trackingMode;
  bool _saving = false;
  String? _error;

  CatalogProduct get _product =>
      widget.products.firstWhere((product) => product.variantId == _variantId);

  double get _available =>
      widget.snapshot.stockForWarehouse(_variantId, _warehouseId);

  List<String> get _parsedIdentifiers => _identifiers.text
      .split(RegExp(r'[\r\n]+'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);

  @override
  void dispose() {
    _identifiers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Register serials or IMEIs'),
    content: SizedBox(
      width: 620,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownMenu<String>(
                initialSelection: _variantId,
                enableFilter: true,
                enableSearch: true,
                requestFocusOnTap: true,
                expandedInsets: EdgeInsets.zero,
                label: const Text('Product'),
                hintText: 'Search product or SKU',
                leadingIcon: const Icon(Icons.search_rounded),
                dropdownMenuEntries: widget.products
                    .map(
                      (product) => DropdownMenuEntry<String>(
                        value: product.variantId,
                        label: '${product.name} • ${product.sku}',
                      ),
                    )
                    .toList(),
                onSelected: (value) {
                  if (value == null) return;
                  final product = widget.products.firstWhere(
                    (candidate) => candidate.variantId == value,
                  );
                  setState(() {
                    _variantId = value;
                    _warehouseId =
                        widget.snapshot.bestWarehouse(variantId: value)?.id ??
                        _warehouseId;
                    _trackingMode = product.trackingMode == 'none'
                        ? 'serial'
                        : product.trackingMode;
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('tracking-$_variantId-$_trackingMode'),
                initialValue: _trackingMode,
                decoration: InputDecoration(
                  labelText: 'Tracking mode',
                  helperText: _product.trackingMode == 'none'
                      ? 'The first registration locks this SKU to the selected mode.'
                      : 'This SKU already uses ${_product.trackingMode.toUpperCase()} tracking.',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'serial',
                    child: Text('Serial number'),
                  ),
                  DropdownMenuItem(value: 'imei', child: Text('IMEI')),
                ],
                onChanged: _product.trackingMode == 'none'
                    ? (value) =>
                          setState(() => _trackingMode = value ?? _trackingMode)
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownMenu<String>(
                initialSelection: _warehouseId,
                enableFilter: true,
                enableSearch: true,
                requestFocusOnTap: true,
                expandedInsets: EdgeInsets.zero,
                label: const Text('Warehouse'),
                hintText: 'Search warehouse',
                leadingIcon: const Icon(Icons.search_rounded),
                dropdownMenuEntries: widget.snapshot.warehouses
                    .map(
                      (warehouse) => DropdownMenuEntry<String>(
                        value: warehouse.id,
                        label: warehouse.name,
                      ),
                    )
                    .toList(),
                onSelected: (value) =>
                    setState(() => _warehouseId = value ?? _warehouseId),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _identifiers,
                autofocus: true,
                minLines: 6,
                maxLines: 10,
                decoration: InputDecoration(
                  labelText: _trackingMode == 'imei'
                      ? 'IMEIs, one per line'
                      : 'Serial numbers, one per line',
                  helperText:
                      '${_quantityLabel(_available)} unreserved units in this warehouse • maximum 500 per registration',
                  alignLabelWithHint: true,
                ),
                validator: (_) => _validateIdentifiers(),
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
            : const Text('Register'),
      ),
    ],
  );

  String? _validateIdentifiers() {
    final values = _parsedIdentifiers;
    if (values.isEmpty) return 'Enter at least one identifier';
    if (values.length > 500) return 'Enter no more than 500 identifiers';
    final normalized = <String>{};
    for (final value in values) {
      final candidate = _trackingMode == 'imei'
          ? value.replaceAll(RegExp('[^0-9]'), '')
          : value.toUpperCase();
      if (_trackingMode == 'imei' &&
          !RegExp(r'^[0-9]{15}$').hasMatch(candidate)) {
        return 'Every IMEI must contain exactly 15 digits';
      }
      if (_trackingMode == 'serial' &&
          (candidate.length < 3 || candidate.length > 120)) {
        return 'Every serial number must contain 3 to 120 characters';
      }
      if (!normalized.add(candidate)) {
        return 'Remove duplicate identifier $value';
      }
    }
    if (values.length > _available.floor()) {
      return 'Identifiers exceed unreserved stock in this warehouse';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.registerSerializedInventory(
        businessId: widget.workspace.businessId,
        warehouseId: _warehouseId,
        variantId: _variantId,
        trackingMode: _trackingMode,
        identifiers: _parsedIdentifiers,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _StockLossDialog extends StatefulWidget {
  const _StockLossDialog({
    required this.workspace,
    required this.snapshot,
    required this.products,
    required this.serializedUnits,
    required this.repository,
  });

  final BusinessWorkspace workspace;
  final CatalogSnapshot snapshot;
  final List<CatalogProduct> products;
  final List<SerializedInventoryUnit> serializedUnits;
  final InventoryRepository repository;

  @override
  State<_StockLossDialog> createState() => _StockLossDialogState();
}

class _StockLossDialogState extends State<_StockLossDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _reason = TextEditingController();
  final _notes = TextEditingController();
  late String _variantId = widget.products.first.variantId;
  late String _warehouseId =
      widget.snapshot.bestWarehouse(variantId: widget.products.first.variantId)?.id ??
      widget.snapshot.warehouses.first.id;
  String _lossType = 'damage';
  bool _saving = false;
  String? _error;
  final Set<String> _selectedSerializedUnits = {};

  double get _available =>
      widget.snapshot.stockForWarehouse(_variantId, _warehouseId);

  List<SerializedInventoryUnit> get _availableSerializedUnits => widget
      .serializedUnits
      .where(
        (unit) =>
            unit.variantId == _variantId &&
            unit.warehouseId == _warehouseId &&
            unit.status == 'in_stock',
      )
      .toList(growable: false);

  bool get _isSerialized =>
      widget.products
          .firstWhere((product) => product.variantId == _variantId)
          .trackingMode !=
      'none';

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Record stock loss'),
    content: SizedBox(
      width: 560,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _lossType,
                decoration: const InputDecoration(labelText: 'Loss type'),
                items: const [
                  DropdownMenuItem(value: 'damage', child: Text('Damage')),
                  DropdownMenuItem(value: 'wastage', child: Text('Wastage')),
                ],
                onChanged: (value) =>
                    setState(() => _lossType = value ?? _lossType),
              ),
              const SizedBox(height: 12),
              DropdownMenu<String>(
                initialSelection: _variantId,
                enableFilter: true,
                enableSearch: true,
                requestFocusOnTap: true,
                expandedInsets: EdgeInsets.zero,
                label: const Text('Product'),
                hintText: 'Search product or SKU',
                leadingIcon: const Icon(Icons.search_rounded),
                dropdownMenuEntries: widget.products
                    .map(
                      (product) => DropdownMenuEntry<String>(
                        value: product.variantId,
                        label: '${product.name} • ${product.sku}',
                      ),
                    )
                    .toList(),
                onSelected: (value) => setState(() {
                  _variantId = value ?? _variantId;
                  _warehouseId =
                      widget.snapshot.bestWarehouse(variantId: _variantId)?.id ??
                      _warehouseId;
                  _selectedSerializedUnits.clear();
                  _quantity.clear();
                }),
              ),
              const SizedBox(height: 12),
              DropdownMenu<String>(
                initialSelection: _warehouseId,
                enableFilter: true,
                enableSearch: true,
                requestFocusOnTap: true,
                expandedInsets: EdgeInsets.zero,
                label: const Text('Warehouse'),
                hintText: 'Search warehouse',
                leadingIcon: const Icon(Icons.search_rounded),
                dropdownMenuEntries: widget.snapshot.warehouses
                    .map(
                      (warehouse) => DropdownMenuEntry<String>(
                        value: warehouse.id,
                        label: warehouse.name,
                      ),
                    )
                    .toList(),
                onSelected: (value) => setState(() {
                  _warehouseId = value ?? _warehouseId;
                  _selectedSerializedUnits.clear();
                  _quantity.clear();
                }),
              ),
              const SizedBox(height: 12),
              if (_isSerialized)
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Serial units lost',
                    helperText:
                        '${_selectedSerializedUnits.length}/${_availableSerializedUnits.length} selected',
                  ),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final unit in _availableSerializedUnits)
                        FilterChip(
                          label: Text(unit.identifier),
                          selected: _selectedSerializedUnits.contains(unit.id),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedSerializedUnits.add(unit.id);
                              } else {
                                _selectedSerializedUnits.remove(unit.id);
                              }
                              _quantity.text = _selectedSerializedUnits.length
                                  .toString();
                            });
                          },
                        ),
                    ],
                  ),
                )
              else
                TextFormField(
                  controller: _quantity,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Quantity lost',
                    helperText:
                        '${_quantityLabel(_available)} unreserved in this warehouse',
                  ),
                  validator: (value) {
                    final parsed = double.tryParse(value?.trim() ?? '');
                    if (parsed == null || parsed <= 0) {
                      return 'Enter a positive quantity';
                    }
                    if (parsed > _available) {
                      return 'Quantity exceeds unreserved stock';
                    }
                    return null;
                  },
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reason,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Reason'),
                validator: (value) => value == null || value.trim().length < 3
                    ? 'Enter a meaningful reason'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes'),
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
            : const Text('Record loss'),
      ),
    ],
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSerialized && _selectedSerializedUnits.isEmpty) {
      setState(() => _error = 'Select at least one serial unit or IMEI.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.recordStockLoss(
        businessId: widget.workspace.businessId,
        warehouseId: _warehouseId,
        variantId: _variantId,
        lossType: _lossType,
        quantity: double.parse(_quantity.text.trim()),
        reason: _reason.text,
        notes: _notes.text,
        serializedUnitIds: _selectedSerializedUnits.toList(growable: false),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _InventoryTransferDialog extends StatefulWidget {
  const _InventoryTransferDialog({
    required this.workspace,
    required this.snapshot,
    required this.products,
    required this.serializedUnits,
    required this.repository,
    this.stagedRequest = false,
  });

  final BusinessWorkspace workspace;
  final CatalogSnapshot snapshot;
  final List<CatalogProduct> products;
  final List<SerializedInventoryUnit> serializedUnits;
  final InventoryRepository repository;
  final bool stagedRequest;

  @override
  State<_InventoryTransferDialog> createState() =>
      _InventoryTransferDialogState();
}

class _InventoryTransferDialogState extends State<_InventoryTransferDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _reason = TextEditingController();
  final _notes = TextEditingController();
  late String _variantId = widget.products.first.variantId;
  late String _sourceWarehouseId =
      widget.snapshot.bestWarehouse(variantId: widget.products.first.variantId)?.id ??
      widget.snapshot.warehouses.first.id;
  late String _destinationWarehouseId = widget.snapshot.warehouses
      .firstWhere(
        (warehouse) =>
            warehouse.id !=
            (widget.snapshot
                    .bestWarehouse(variantId: widget.products.first.variantId)
                    ?.id ??
                widget.snapshot.warehouses.first.id),
        orElse: () => widget.snapshot.warehouses[1],
      )
      .id;
  final Set<String> _selectedSerializedUnits = {};
  bool _saving = false;
  String? _error;

  CatalogProduct get _product =>
      widget.products.firstWhere((product) => product.variantId == _variantId);

  double get _available =>
      widget.snapshot.stockForWarehouse(_variantId, _sourceWarehouseId);

  bool get _isSerialized => _product.trackingMode != 'none';

  List<SerializedInventoryUnit> get _availableSerializedUnits => widget
      .serializedUnits
      .where(
        (unit) =>
            unit.variantId == _variantId &&
            unit.warehouseId == _sourceWarehouseId &&
            unit.status == 'in_stock',
      )
      .toList(growable: false);

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.stagedRequest ? 'Request stock transfer' : 'Transfer stock',
    ),
    content: SizedBox(
      width: 560,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownMenu<String>(
                initialSelection: _variantId,
                enableFilter: true,
                enableSearch: true,
                requestFocusOnTap: true,
                expandedInsets: EdgeInsets.zero,
                label: const Text('Product'),
                hintText: 'Search product or SKU',
                leadingIcon: const Icon(Icons.search_rounded),
                dropdownMenuEntries: widget.products
                    .map(
                      (product) => DropdownMenuEntry<String>(
                        value: product.variantId,
                        label: '${product.name} • ${product.sku}',
                      ),
                    )
                    .toList(),
                onSelected: (value) => setState(() {
                  _variantId = value ?? _variantId;
                  _sourceWarehouseId =
                      widget.snapshot.bestWarehouse(variantId: _variantId)?.id ??
                      _sourceWarehouseId;
                  _selectedSerializedUnits.clear();
                  _quantity.clear();
                }),
              ),
              const SizedBox(height: 12),
              DropdownMenu<String>(
                initialSelection: _sourceWarehouseId,
                enableFilter: true,
                enableSearch: true,
                requestFocusOnTap: true,
                expandedInsets: EdgeInsets.zero,
                label: const Text('From warehouse'),
                hintText: 'Search source warehouse',
                leadingIcon: const Icon(Icons.search_rounded),
                dropdownMenuEntries: widget.snapshot.warehouses
                    .map(
                      (warehouse) => DropdownMenuEntry<String>(
                        value: warehouse.id,
                        label: warehouse.name,
                      ),
                    )
                    .toList(),
                onSelected: (value) => setState(() {
                  _sourceWarehouseId = value ?? _sourceWarehouseId;
                  if (_sourceWarehouseId == _destinationWarehouseId) {
                    final other = widget.snapshot.warehouses.firstWhere(
                      (warehouse) => warehouse.id != _sourceWarehouseId,
                    );
                    _destinationWarehouseId = other.id;
                  }
                  _selectedSerializedUnits.clear();
                  _quantity.clear();
                }),
              ),
              const SizedBox(height: 12),
              DropdownMenu<String>(
                initialSelection: _destinationWarehouseId,
                enableFilter: true,
                enableSearch: true,
                requestFocusOnTap: true,
                expandedInsets: EdgeInsets.zero,
                label: const Text('To warehouse'),
                hintText: 'Search destination warehouse',
                leadingIcon: const Icon(Icons.search_rounded),
                dropdownMenuEntries: widget.snapshot.warehouses
                    .where((warehouse) => warehouse.id != _sourceWarehouseId)
                    .map(
                      (warehouse) => DropdownMenuEntry<String>(
                        value: warehouse.id,
                        label: warehouse.name,
                      ),
                    )
                    .toList(),
                onSelected: (value) => setState(
                  () => _destinationWarehouseId =
                      value ?? _destinationWarehouseId,
                ),
              ),
              const SizedBox(height: 12),
              if (_isSerialized)
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: _product.trackingMode == 'imei'
                        ? 'IMEIs to transfer'
                        : 'Serial units to transfer',
                    helperText:
                        '${_selectedSerializedUnits.length}/${_availableSerializedUnits.length} selected',
                  ),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final unit in _availableSerializedUnits)
                        FilterChip(
                          label: Text(unit.identifier),
                          selected: _selectedSerializedUnits.contains(unit.id),
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _selectedSerializedUnits.add(unit.id);
                            } else {
                              _selectedSerializedUnits.remove(unit.id);
                            }
                            _quantity.text = _selectedSerializedUnits.length
                                .toString();
                          }),
                        ),
                    ],
                  ),
                )
              else
                TextFormField(
                  controller: _quantity,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Quantity to transfer',
                    helperText:
                        '${_quantityLabel(_available)} unreserved in source',
                  ),
                  validator: (value) {
                    final parsed = double.tryParse(value?.trim() ?? '');
                    if (parsed == null || parsed <= 0) {
                      return 'Enter a positive quantity';
                    }
                    if (parsed > _available) {
                      return 'Quantity exceeds unreserved stock';
                    }
                    if (!_product.allowFractionalQuantity &&
                        parsed != parsed.roundToDouble()) {
                      return 'Fractional quantity is not allowed';
                    }
                    return null;
                  },
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reason,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Reason'),
                validator: (value) => value == null || value.trim().length < 3
                    ? 'Enter a meaningful reason'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes'),
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
            : Text(
                widget.stagedRequest ? 'Request transfer' : 'Transfer stock',
              ),
      ),
    ],
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSerialized && _selectedSerializedUnits.isEmpty) {
      setState(() => _error = 'Select at least one serial unit or IMEI.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final quantity = double.parse(_quantity.text.trim());
      if (widget.stagedRequest) {
        await widget.repository.requestInventoryTransfer(
          businessId: widget.workspace.businessId,
          sourceWarehouseId: _sourceWarehouseId,
          destinationWarehouseId: _destinationWarehouseId,
          variantId: _variantId,
          quantity: quantity,
          reason: _reason.text,
          notes: _notes.text,
          serializedUnitIds: _selectedSerializedUnits.toList(growable: false),
        );
      } else {
        await widget.repository.executeInventoryTransfer(
          businessId: widget.workspace.businessId,
          sourceWarehouseId: _sourceWarehouseId,
          destinationWarehouseId: _destinationWarehouseId,
          variantId: _variantId,
          quantity: quantity,
          reason: _reason.text,
          notes: _notes.text,
          serializedUnitIds: _selectedSerializedUnits.toList(growable: false),
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

class _InventoryAdjustmentDialog extends StatefulWidget {
  const _InventoryAdjustmentDialog({
    required this.workspace,
    required this.snapshot,
    required this.products,
    required this.repository,
  });

  final BusinessWorkspace workspace;
  final CatalogSnapshot snapshot;
  final List<CatalogProduct> products;
  final CatalogRepository repository;

  @override
  State<_InventoryAdjustmentDialog> createState() =>
      _InventoryAdjustmentDialogState();
}

class _InventoryAdjustmentDialogState
    extends State<_InventoryAdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _reason = TextEditingController();
  late String _variantId = widget.products.first.variantId;
  late String _warehouseId =
      widget.snapshot.bestWarehouse(variantId: widget.products.first.variantId)?.id ??
      widget.snapshot.warehouses.first.id;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Adjust inventory'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownMenu<String>(
                initialSelection: _variantId,
                enableFilter: true,
                enableSearch: true,
                requestFocusOnTap: true,
                expandedInsets: EdgeInsets.zero,
                label: const Text('Product'),
                hintText: 'Search product or SKU',
                leadingIcon: const Icon(Icons.search_rounded),
                dropdownMenuEntries: widget.products
                    .map(
                      (product) => DropdownMenuEntry<String>(
                        value: product.variantId,
                        label: '${product.name} • ${product.sku}',
                      ),
                    )
                    .toList(),
                onSelected: (value) {
                  if (value == null) return;
                  setState(() {
                    _variantId = value;
                    _warehouseId =
                        widget.snapshot.bestWarehouse(variantId: value)?.id ??
                        _warehouseId;
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownMenu<String>(
                initialSelection: _warehouseId,
                enableFilter: true,
                enableSearch: true,
                requestFocusOnTap: true,
                expandedInsets: EdgeInsets.zero,
                label: const Text('Warehouse'),
                hintText: 'Search warehouse',
                leadingIcon: const Icon(Icons.search_rounded),
                dropdownMenuEntries: widget.snapshot.warehouses
                    .map(
                      (warehouse) => DropdownMenuEntry<String>(
                        value: warehouse.id,
                        label: warehouse.name,
                      ),
                    )
                    .toList(),
                onSelected: (value) =>
                    setState(() => _warehouseId = value ?? _warehouseId),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _quantity,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Quantity change',
                  helperText: 'Use a positive number to add or a negative number to remove.',
                ),
                validator: (value) {
                  final parsed = double.tryParse(value?.trim() ?? '');
                  return parsed == null || parsed == 0
                      ? 'Enter a non-zero quantity'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reason,
                decoration: const InputDecoration(labelText: 'Reason'),
                validator: (value) => value == null || value.trim().length < 3
                    ? 'Enter a short reason'
                    : null,
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
              : const Text('Apply'),
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
      await widget.repository.adjustInventory(
        businessId: widget.workspace.businessId,
        warehouseId: _warehouseId,
        variantId: _variantId,
        quantityDelta: double.parse(_quantity.text.trim()),
        reason: _reason.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _InventoryStocktakeStartDialog extends StatefulWidget {
  const _InventoryStocktakeStartDialog({
    required this.workspace,
    required this.snapshot,
    required this.warehouses,
    required this.repository,
  });

  final BusinessWorkspace workspace;
  final CatalogSnapshot snapshot;
  final List<WarehouseOption> warehouses;
  final InventoryRepository repository;

  @override
  State<_InventoryStocktakeStartDialog> createState() =>
      _InventoryStocktakeStartDialogState();
}

class _InventoryStocktakeStartDialogState
    extends State<_InventoryStocktakeStartDialog> {
  late String _warehouseId =
      widget.snapshot.bestWarehouse()?.id ?? widget.warehouses.first.id;
  final _reason = TextEditingController(text: 'Routine physical count');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Start stocktake'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownMenu<String>(
            initialSelection: _warehouseId,
            enableFilter: true,
            enableSearch: true,
            requestFocusOnTap: true,
            expandedInsets: EdgeInsets.zero,
            label: const Text('Warehouse'),
            hintText: 'Search warehouse',
            leadingIcon: const Icon(Icons.search_rounded),
            dropdownMenuEntries: widget.warehouses
                .map(
                  (warehouse) => DropdownMenuEntry<String>(
                    value: warehouse.id,
                    label: warehouse.name,
                  ),
                )
                .toList(),
            onSelected: _saving
                ? null
                : (value) =>
                      setState(() => _warehouseId = value ?? _warehouseId),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            enabled: !_saving,
            decoration: const InputDecoration(labelText: 'Reason'),
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
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _start,
        child: _saving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Start count'),
      ),
    ],
  );

  Future<void> _start() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.repository.startInventoryStocktake(
        businessId: widget.workspace.businessId,
        warehouseId: _warehouseId,
        reason: _reason.text,
      );
      if (mounted) Navigator.pop(context, result['stocktake_id'] as String);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _InventoryStocktakeCountDialog extends StatefulWidget {
  const _InventoryStocktakeCountDialog({
    required this.stocktakeId,
    required this.items,
    required this.products,
    required this.repository,
  });

  final String stocktakeId;
  final List<InventoryStocktakeItem> items;
  final List<CatalogProduct> products;
  final InventoryRepository repository;

  @override
  State<_InventoryStocktakeCountDialog> createState() =>
      _InventoryStocktakeCountDialogState();
}

class _InventoryStocktakeCountDialogState
    extends State<_InventoryStocktakeCountDialog> {
  late final Map<String, TextEditingController> _counts = {
    for (final item in widget.items)
      item.id: TextEditingController(text: _quantityLabel(item.systemQuantity)),
  };
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in _counts.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Enter physical counts'),
    content: SizedBox(
      width: 620,
      height: 520,
      child: widget.items.isEmpty
          ? const Center(child: Text('No stock-tracked items were found.'))
          : ListView.separated(
              itemCount: widget.items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = widget.items[index];
                final product = widget.products
                    .cast<CatalogProduct?>()
                    .firstWhere(
                      (value) => value?.variantId == item.variantId,
                      orElse: () => null,
                    );
                final title = product == null
                    ? item.variantId
                    : '${product.name} • ${product.sku}';
                final batchLabel = item.batchNumber == null
                    ? 'Untracked stock'
                    : 'Batch ${item.batchNumber}${item.expiresOn == null ? '' : ' • Exp ${item.expiresOn}'}';
                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            '$batchLabel • System ${_quantityLabel(item.systemQuantity)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: _counts[item.id],
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: 'Counted'),
                      ),
                    ),
                  ],
                );
              },
            ),
    ),
    actions: [
      if (_error != null)
        Expanded(
          child: Text(
            _error!,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      TextButton(
        onPressed: _saving ? null : _cancel,
        child: const Text('Cancel stocktake'),
      ),
      FilledButton(
        onPressed: _saving ? null : _finalize,
        child: _saving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Finalize stocktake'),
      ),
    ],
  );

  Future<void> _finalize() async {
    final counts = <InventoryStocktakeItem, double>{};
    for (final item in widget.items) {
      final value = double.tryParse(_counts[item.id]!.text.trim());
      if (value == null || value < 0) {
        setState(() => _error = 'Enter a valid count for every item.');
        return;
      }
      final product = widget.products.cast<CatalogProduct?>().firstWhere(
        (candidate) => candidate?.variantId == item.variantId,
        orElse: () => null,
      );
      if (product != null &&
          !product.allowFractionalQuantity &&
          value != value.truncateToDouble()) {
        setState(
          () => _error = 'Whole-unit SKUs cannot use fractional counts.',
        );
        return;
      }
      counts[item] = value;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      for (final entry in counts.entries) {
        await widget.repository.recordInventoryStocktakeCount(
          stocktakeId: widget.stocktakeId,
          variantId: entry.key.variantId,
          countedQuantity: entry.value,
          batchId: entry.key.batchId,
        );
      }
      await widget.repository.finalizeInventoryStocktake(
        stocktakeId: widget.stocktakeId,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancel() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.cancelInventoryStocktake(
        stocktakeId: widget.stocktakeId,
      );
      if (mounted) Navigator.pop(context, false);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

String _quantityLabel(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(3);
