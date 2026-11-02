import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flexpos/core/utils/csv_export.dart';
import 'package:flexpos/core/utils/money.dart';
import 'package:flexpos/core/utils/pdf_export.dart';
import 'package:flexpos/core/security/crud_permissions.dart';
import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/core/widgets/data_page_skeleton.dart';
import 'package:flexpos/core/widgets/data_list_controls.dart';
import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/core/widgets/product_image.dart';
import 'package:flexpos/features/catalog/data/catalog_repository.dart';
import 'package:flexpos/features/catalog/domain/catalog_models.dart';
import 'package:flexpos/features/customers/data/customer_repository.dart';
import 'package:flexpos/features/customers/domain/customer_models.dart';
import 'package:flexpos/features/tenants/domain/business_workspace.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProductsPage extends ConsumerStatefulWidget {
  const ProductsPage({super.key});

  @override
  ConsumerState<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends ConsumerState<ProductsPage> {
  String _query = '';
  String _sort = 'name_asc';
  int _page = 0;
  final Set<String> _selectedProductIds = {};
  final Set<String> _updatingFavorites = {};

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    if (workspace != null && !workspace.canRead('products')) {
      return const Scaffold(
        body: EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Products are restricted',
          message: 'Your role does not include permission to view products.',
        ),
      );
    }
    final snapshot = ref.watch(catalogSnapshotProvider);
    final customerGroups =
        ref.watch(customerGroupsProvider).value ?? const <CustomerGroup>[];
    final customers = ref.watch(customersProvider).value ?? const <Customer>[];
    final canCreate = workspace?.canCreate('products') ?? false;
    final canUpdate = workspace?.canUpdate('products') ?? false;
    final canDelete = workspace?.canDelete('products') ?? false;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: workspace != null && canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _showCreateProduct(context, workspace),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New product'),
            )
          : null,
      body: snapshot.when(
        loading: () => const DataPageSkeleton(sectionLabel: 'products'),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load products',
          message: error.toString(),
          action: FilledButton.icon(
            onPressed: () => ref.invalidate(catalogSnapshotProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ),
        data: (data) {
          final filteredProducts = data.products
              .where((product) => product.searchText.contains(_query))
              .toList();
          filteredProducts.sort(
            (a, b) => switch (_sort) {
              'price_desc' => b.priceMinor.compareTo(a.priceMinor),
              'price_asc' => a.priceMinor.compareTo(b.priceMinor),
              'sku_asc' => a.sku.compareTo(b.sku),
              _ => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            },
          );
          final pageCount = pageCountFor(filteredProducts.length);
          if (_page >= pageCount) _page = pageCount - 1;
          final products = pageItems(filteredProducts, _page);
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 96),
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 8,
                children: [
                  Text(
                    'Products',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _exportProductsCsv(data.products),
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Export CSV'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _exportProductsPdf(data.products),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Export PDF'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${data.products.length} active SKU${data.products.length == 1 ? '' : 's'}',
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
                searchLabel: 'Search name, SKU, or barcode',
                sortValue: _sort,
                sortOptions: const [
                  DataListSortOption('name_asc', 'Name (A–Z)'),
                  DataListSortOption('sku_asc', 'SKU (A–Z)'),
                  DataListSortOption('price_asc', 'Price (low–high)'),
                  DataListSortOption('price_desc', 'Price (high–low)'),
                ],
                onSortChanged: (value) => setState(() {
                  _sort = value;
                  _page = 0;
                }),
                page: _page,
                pageCount: pageCount,
                totalCount: filteredProducts.length,
                onPageChanged: (value) => setState(() => _page = value),
                selectedCount: _selectedProductIds.length,
                allSelected:
                    products.isNotEmpty &&
                    products.every(
                      (product) =>
                          _selectedProductIds.contains(product.productId),
                    ),
                onSelectAll: products.isEmpty
                    ? null
                    : (selected) => setState(() {
                        if (selected ?? false) {
                          _selectedProductIds.addAll(
                            products.map((product) => product.productId),
                          );
                        } else {
                          _selectedProductIds.removeAll(
                            products.map((product) => product.productId),
                          );
                        }
                      }),
                onClearSelection: () =>
                    setState(() => _selectedProductIds.clear()),
                bulkActions: [
                  FilledButton.tonalIcon(
                    onPressed: canUpdate
                        ? () => _bulkSetFavorite(
                            workspace!,
                            data.products
                                .where(
                                  (product) => _selectedProductIds.contains(
                                    product.productId,
                                  ),
                                )
                                .toList(growable: false),
                            true,
                          )
                        : null,
                    icon: const Icon(Icons.star_rounded),
                    label: const Text('Add selected to POS'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: canUpdate && _selectedProductIds.isNotEmpty
                        ? () => _showBulkEdit(
                            context,
                            workspace!,
                            data.products
                                .where(
                                  (product) => _selectedProductIds.contains(
                                    product.productId,
                                  ),
                                )
                                .toList(growable: false),
                          )
                        : null,
                    icon: const Icon(Icons.edit_note_rounded),
                    label: const Text('Bulk edit'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (products.isEmpty)
                EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: _query.isEmpty
                      ? 'No products yet'
                      : 'No matching products',
                  message: _query.isEmpty
                      ? 'Create the first sellable item for this business.'
                      : 'Try a different name, SKU, or barcode.',
                )
              else
                for (final product in products) ...[
                  AppPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'SKU ${product.sku}${product.barcodes.isEmpty ? '' : '  •  ${product.barcodes.first}'}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (canUpdate)
                              IconButton(
                                tooltip: product.isFavorite
                                    ? 'Remove from POS favorites'
                                    : 'Add to POS favorites',
                                onPressed:
                                    _updatingFavorites.contains(
                                      product.productId,
                                    )
                                    ? null
                                    : () => _setFavorite(
                                        workspace!,
                                        product,
                                        !product.isFavorite,
                                      ),
                                icon:
                                    _updatingFavorites.contains(
                                      product.productId,
                                    )
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        product.isFavorite
                                            ? Icons.star_rounded
                                            : Icons.star_border_rounded,
                                      ),
                              ),
                            if (canUpdate && customerGroups.isNotEmpty)
                              IconButton(
                                tooltip: 'Set wholesale/group price',
                                onPressed: () => _showGroupPriceDialog(
                                  context,
                                  workspace!,
                                  product,
                                  customerGroups,
                                  data,
                                ),
                                icon: const Icon(Icons.sell_outlined),
                              ),
                            if (canUpdate && customers.isNotEmpty)
                              IconButton(
                                tooltip: 'Set customer-specific price',
                                onPressed: () => _showCustomerPriceDialog(
                                  context,
                                  workspace!,
                                  product,
                                  customers,
                                  data,
                                ),
                                icon: const Icon(Icons.person_search_outlined),
                              ),
                            const SizedBox(width: 4),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  formatMoney(
                                    workspace?.currencyCode ?? 'USD',
                                    product.priceMinor,
                                  ),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                Text(
                                  product.trackInventory
                                      ? 'Stock tracked'
                                      : 'Service item',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (canUpdate || canDelete) ...[
                          const Divider(height: 20),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (canUpdate)
                                OutlinedButton.icon(
                                  onPressed: () => _showProductDetails(
                                    context,
                                    workspace!,
                                    product,
                                    canUpdate: canUpdate,
                                    canDelete: canDelete,
                                  ),
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('Edit product'),
                                ),
                              if (canDelete)
                                TextButton.icon(
                                  onPressed: () => _archiveProduct(
                                    context,
                                    workspace!,
                                    product,
                                  ),
                                  icon: const Icon(Icons.archive_outlined),
                                  label: const Text('Archive'),
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

  Future<void> _bulkSetFavorite(
    BusinessWorkspace workspace,
    List<CatalogProduct> products,
    bool isFavorite,
  ) async {
    if (products.isEmpty) return;
    for (final product in products) {
      await ref
          .read(catalogRepositoryProvider)
          .setProductFavorite(
            businessId: workspace.businessId,
            productId: product.productId,
            isFavorite: isFavorite,
          );
    }
    if (!mounted) return;
    setState(() => _selectedProductIds.clear());
    ref.invalidate(catalogSnapshotProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${products.length} product${products.length == 1 ? '' : 's'} added to POS favorites.',
        ),
      ),
    );
  }

  Future<void> _exportProductsPdf(List<CatalogProduct> products) async {
    try {
      final path = await savePdfExport(
        fileName: 'flexpos-products.pdf',
        title: 'FlexPOS products',
        headers: const [
          'Product',
          'Variant',
          'SKU',
          'Barcode(s)',
          'Selling price (minor)',
          'Cost price (minor)',
          'Tax (bps)',
          'Category',
          'Tracked',
          'POS favorite',
        ],
        rows: [
          for (final product in products)
            [
              product.name,
              product.variantName,
              product.sku,
              product.barcodes.join(' | '),
              product.priceMinor,
              product.costMinor,
              product.taxRateBasisPoints,
              product.categoryName,
              product.trackInventory,
              product.isFavorite,
            ],
        ],
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Products PDF exported.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not export products: $error')),
      );
    }
  }

  Future<void> _exportProductsCsv(List<CatalogProduct> products) async {
    try {
      final path = await saveCsvExport(
        fileName: 'flexpos-products.csv',
        rows: [
          const [
            'Product',
            'Variant',
            'SKU',
            'Barcode(s)',
            'Selling price (minor)',
            'Cost price (minor)',
            'Tax (bps)',
            'Category',
            'Tracked',
            'POS favorite',
          ],
          for (final product in products)
            [
              product.name,
              product.variantName,
              product.sku,
              product.barcodes.join(' | '),
              product.priceMinor,
              product.costMinor,
              product.taxRateBasisPoints,
              product.categoryName,
              product.trackInventory,
              product.isFavorite,
            ],
        ],
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Products CSV exported.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not export products: $error')),
      );
    }
  }

  Future<void> _archiveProduct(
    BuildContext context,
    BusinessWorkspace workspace,
    CatalogProduct product,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive product?'),
        content: Text(
          'Archive “${product.name}”? It will disappear from active catalog and POS searches while historical sales remain unchanged.',
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
      await ref
          .read(catalogRepositoryProvider)
          .archiveProduct(
            businessId: workspace.businessId,
            productId: product.productId,
          );
      ref.invalidate(catalogSnapshotProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Product archived.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not archive product: $error')),
        );
      }
    }
  }

  Future<void> _showCreateProduct(
    BuildContext context,
    BusinessWorkspace workspace,
  ) async {
    final snapshot = ref.read(catalogSnapshotProvider).value;
    if (snapshot == null || snapshot.units.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Product units are still loading. Try again.'),
        ),
      );
      return;
    }
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CreateProductDialog(
        workspace: workspace,
        snapshot: snapshot,
        repository: ref.read(catalogRepositoryProvider),
      ),
    );
    if (created == true) {
      ref.invalidate(catalogSnapshotProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Product created.')));
      }
    }
  }

  Future<void> _showCustomerPriceDialog(
    BuildContext context,
    BusinessWorkspace workspace,
    CatalogProduct product,
    List<Customer> customers,
    CatalogSnapshot snapshot,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CustomerPriceDialog(
        workspace: workspace,
        product: product,
        customers: customers,
        snapshot: snapshot,
        repository: ref.read(catalogRepositoryProvider),
      ),
    );
    if (saved == true && context.mounted) {
      ref.invalidate(catalogSnapshotProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer-specific price saved.')),
      );
    }
  }

  Future<void> _setFavorite(
    BusinessWorkspace workspace,
    CatalogProduct product,
    bool isFavorite,
  ) async {
    setState(() => _updatingFavorites.add(product.productId));
    try {
      await ref
          .read(catalogRepositoryProvider)
          .setProductFavorite(
            businessId: workspace.businessId,
            productId: product.productId,
            isFavorite: isFavorite,
          );
      ref.invalidate(catalogSnapshotProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isFavorite
                  ? '${product.name} added to POS favorites.'
                  : '${product.name} removed from POS favorites.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update favorite: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _updatingFavorites.remove(product.productId));
      }
    }
  }

  Future<void> _showGroupPriceDialog(
    BuildContext context,
    BusinessWorkspace workspace,
    CatalogProduct product,
    List<CustomerGroup> groups,
    CatalogSnapshot snapshot,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CustomerGroupPriceDialog(
        workspace: workspace,
        product: product,
        groups: groups,
        snapshot: snapshot,
        repository: ref.read(catalogRepositoryProvider),
      ),
    );
    if (saved == true) {
      ref.invalidate(catalogSnapshotProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Customer-group price saved.')),
        );
      }
    }
  }

  Future<void> _showBulkEdit(
    BuildContext context,
    BusinessWorkspace workspace,
    List<CatalogProduct> products,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _BulkCatalogEditDialog(
        products: products,
        repository: ref.read(catalogRepositoryProvider),
        businessId: workspace.businessId,
      ),
    );
    if (saved == true) {
      setState(() => _selectedProductIds.clear());
      ref.invalidate(catalogSnapshotProvider);
    }
  }

  Future<void> _showProductDetails(
    BuildContext context,
    BusinessWorkspace workspace,
    CatalogProduct product, {
    required bool canUpdate,
    required bool canDelete,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ProductDetailsDialog(
        product: product,
        businessId: workspace.businessId,
        repository: ref.read(catalogRepositoryProvider),
        canUpdate: canUpdate,
        canDelete: canDelete,
      ),
    );
    if (saved == true) ref.invalidate(catalogSnapshotProvider);
  }
}

class _BulkCatalogEditDialog extends StatefulWidget {
  const _BulkCatalogEditDialog({
    required this.products,
    required this.repository,
    required this.businessId,
  });

  final List<CatalogProduct> products;
  final CatalogRepository repository;
  final String businessId;

  @override
  State<_BulkCatalogEditDialog> createState() => _BulkCatalogEditDialogState();
}

class _BulkCatalogEditDialogState extends State<_BulkCatalogEditDialog> {
  final _price = TextEditingController();
  final _cost = TextEditingController();
  String _favorite = 'unchanged';
  bool _saving = false;

  @override
  void dispose() {
    _price.dispose();
    _cost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Bulk edit · ${widget.products.length} SKU(s)'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MoneyField(controller: _price, label: 'Selling price (optional)'),
          const SizedBox(height: 12),
          _MoneyField(controller: _cost, label: 'Cost price (optional)'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _favorite,
            decoration: const InputDecoration(labelText: 'POS favorite'),
            items: const [
              DropdownMenuItem(
                value: 'unchanged',
                child: Text('Leave unchanged'),
              ),
              DropdownMenuItem(
                value: 'true',
                child: Text('Add to POS favorites'),
              ),
              DropdownMenuItem(
                value: 'false',
                child: Text('Remove from POS favorites'),
              ),
            ],
            onChanged: _saving
                ? null
                : (value) => setState(() => _favorite = value ?? _favorite),
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
        child: const Text('Apply'),
      ),
    ],
  );

  Future<void> _save() async {
    final priceText = _price.text.trim();
    final costText = _cost.text.trim();
    final price = priceText.isEmpty ? null : parseMoneyToMinor(priceText);
    final cost = costText.isEmpty ? null : parseMoneyToMinor(costText);
    if ((priceText.isNotEmpty && price == null) ||
        (costText.isNotEmpty && cost == null) ||
        (price == null && cost == null && _favorite == 'unchanged')) {
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.bulkUpdateProductCatalog(
        businessId: widget.businessId,
        variantIds: widget.products
            .map((product) => product.variantId)
            .toList(),
        priceMinor: price,
        costMinor: cost,
        isFavorite: _favorite == 'unchanged' ? null : _favorite == 'true',
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update product: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ProductDetailsDialog extends StatefulWidget {
  const _ProductDetailsDialog({
    required this.product,
    required this.businessId,
    required this.repository,
    required this.canUpdate,
    required this.canDelete,
  });

  final CatalogProduct product;
  final String businessId;
  final CatalogRepository repository;
  final bool canUpdate;
  final bool canDelete;

  @override
  State<_ProductDetailsDialog> createState() => _ProductDetailsDialogState();
}

class _ProductDetailsDialogState extends State<_ProductDetailsDialog> {
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _barcode;
  late final TextEditingController _cost;
  late final TextEditingController _price;
  late final TextEditingController _attributes;
  String? _imageUrl;
  late bool _trackInventory;
  late bool _allowFractionalQuantity;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.product.name);
    _sku = TextEditingController(text: widget.product.sku);
    _barcode = TextEditingController(
      text: widget.product.barcodes.firstOrNull ?? '',
    );
    _cost = TextEditingController(
      text: (widget.product.costMinor / 100).toStringAsFixed(2),
    );
    _price = TextEditingController(
      text: (widget.product.priceMinor / 100).toStringAsFixed(2),
    );
    _attributes = TextEditingController(
      text: widget.product.attributes.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join('\n'),
    );
    _trackInventory = widget.product.trackInventory;
    _allowFractionalQuantity = widget.product.allowFractionalQuantity;
    if (widget.product.imagePath != null) {
      widget.repository
          .createSignedProductImageUrl(widget.product.imagePath!)
          .then((url) {
            if (mounted) setState(() => _imageUrl = url);
          });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _barcode.dispose();
    _cost.dispose();
    _price.dispose();
    _attributes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.product.name),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  _imageUrl!,
                  height: 180,
                  fit: BoxFit.contain,
                ),
              )
            else
              const SizedBox(
                height: 120,
                child: Center(child: Icon(Icons.image_outlined, size: 52)),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              readOnly: !widget.canUpdate,
              decoration: const InputDecoration(
                labelText: 'Product name',
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sku,
              readOnly: !widget.canUpdate,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'SKU',
                prefixIcon: Icon(Icons.qr_code_2_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _barcode,
              readOnly: !widget.canUpdate,
              decoration: const InputDecoration(
                labelText: 'Primary barcode',
                helperText: 'Enter the exact value returned by your scanner. Leave empty to remove it.',
                prefixIcon: Icon(Icons.qr_code_scanner_outlined),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MoneyField(controller: _cost, label: 'Cost price'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MoneyField(
                    controller: _price,
                    label: 'Selling price',
                  ),
                ),
              ],
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _trackInventory,
              title: const Text('Track inventory'),
              onChanged: widget.canUpdate
                  ? (value) => setState(() => _trackInventory = value)
                  : null,
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _allowFractionalQuantity,
              title: const Text('Allow fractional quantity'),
              onChanged: widget.canUpdate
                  ? (value) => setState(() => _allowFractionalQuantity = value)
                  : null,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _attributes,
              readOnly: !widget.canUpdate,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Custom attributes',
                helperText: 'One key=value pair per line.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: widget.canUpdate && !_saving ? _pickImage : null,
                  icon: const Icon(Icons.upload_outlined),
                  label: const Text('Upload image'),
                ),
                if (widget.product.imagePath != null)
                  TextButton.icon(
                    onPressed: widget.canUpdate && !_saving
                        ? _removeImage
                        : null,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Remove image'),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
    actions: [
      if (widget.canDelete)
        TextButton.icon(
          onPressed: _saving ? null : _archive,
          icon: const Icon(Icons.archive_outlined),
          label: const Text('Archive'),
        ),
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: widget.canUpdate && !_saving ? _save : null,
        child: const Text('Save'),
      ),
    ],
  );

  Future<void> _pickImage() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;
    final extension = (file.extension ?? 'png').toLowerCase();
    final contentType = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/png',
    };
    final bytes = await file.readAsBytes();
    setState(() => _saving = true);
    try {
      final path = await widget.repository.uploadProductImage(
        businessId: widget.businessId,
        productId: widget.product.productId,
        bytes: bytes,
        extension: extension,
        contentType: contentType,
      );
      final url = await widget.repository.createSignedProductImageUrl(path);
      if (mounted) setState(() => _imageUrl = url);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeImage() async {
    setState(() => _saving = true);
    try {
      await widget.repository.removeProductImage(
        businessId: widget.businessId,
        productId: widget.product.productId,
        imagePath: widget.product.imagePath,
      );
      if (mounted) setState(() => _imageUrl = null);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final sku = _sku.text.trim();
    final cost = parseMoneyToMinor(_cost.text);
    final price = parseMoneyToMinor(_price.text);
    if (name.length < 2 || sku.isEmpty || cost == null || price == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Enter a name, SKU, and valid cost and selling prices.',
            ),
          ),
        );
      }
      return;
    }
    final attributes = <String, String>{};
    for (final line in _attributes.text.split('\n')) {
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      final key = line.substring(0, separator).trim();
      final value = line.substring(separator + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) attributes[key] = value;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.updateProductCatalog(
        businessId: widget.businessId,
        productId: widget.product.productId,
        variantId: widget.product.variantId,
        name: name,
        sku: sku,
        costMinor: cost,
        priceMinor: price,
        trackInventory: _trackInventory,
        allowFractionalQuantity: _allowFractionalQuantity,
        attributes: attributes,
        barcode: _barcode.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update product: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _archive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive product?'),
        content: Text(
          '“${widget.product.name}” will be hidden from active catalog and POS lists. Historical sales are preserved.',
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
    setState(() => _saving = true);
    try {
      await widget.repository.archiveProduct(
        businessId: widget.businessId,
        productId: widget.product.productId,
      );
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _CustomerGroupPriceDialog extends StatefulWidget {
  const _CustomerGroupPriceDialog({
    required this.workspace,
    required this.product,
    required this.groups,
    required this.snapshot,
    required this.repository,
  });

  final BusinessWorkspace workspace;
  final CatalogProduct product;
  final List<CustomerGroup> groups;
  final CatalogSnapshot snapshot;
  final CatalogRepository repository;

  @override
  State<_CustomerGroupPriceDialog> createState() =>
      _CustomerGroupPriceDialogState();
}

class _CustomerGroupPriceDialogState extends State<_CustomerGroupPriceDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _groupId;
  late final TextEditingController _amount;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _groupId = widget.groups.first.id;
    final existing = _existingPrice(_groupId);
    _amount = TextEditingController(
      text: existing == null
          ? ''
          : (existing.amountMinor / 100).toStringAsFixed(2),
    );
  }

  CatalogPrice? _existingPrice(String groupId) => widget.snapshot.prices
      .where(
        (price) =>
            price.variantId == widget.product.variantId &&
            price.customerGroupId == groupId &&
            price.priceType == 'customer_group' &&
            price.branchId == null,
      )
      .firstOrNull;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Wholesale/group price · ${widget.product.name}'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _groupId,
              decoration: const InputDecoration(labelText: 'Customer group'),
              items: widget.groups
                  .map(
                    (group) => DropdownMenuItem(
                      value: group.id,
                      child: Text(group.name),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        _groupId = value;
                        final existing = _existingPrice(value);
                        _amount.text = existing?.amountMinor == null
                            ? ''
                            : (existing!.amountMinor / 100).toStringAsFixed(2);
                      });
                    },
            ),
            const SizedBox(height: 12),
            _MoneyField(
              controller: _amount,
              label: 'Wholesale/group price (global)',
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Leave blank to remove the override. POS uses this price when the selected customer belongs to the group.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
            : const Text('Save price'),
      ),
    ],
  );

  Future<void> _save() async {
    final amountText = _amount.text.trim();
    final amount = amountText.isEmpty ? null : parseMoneyToMinor(amountText);
    if (amountText.isNotEmpty && amount == null) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (amount == null) {
        await widget.repository.deleteCustomerGroupPrice(
          businessId: widget.workspace.businessId,
          variantId: widget.product.variantId,
          customerGroupId: _groupId,
        );
      } else {
        await widget.repository.upsertCustomerGroupPrice(
          businessId: widget.workspace.businessId,
          variantId: widget.product.variantId,
          customerGroupId: _groupId,
          amountMinor: amount,
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

class _CustomerPriceDialog extends StatefulWidget {
  const _CustomerPriceDialog({
    required this.workspace,
    required this.product,
    required this.customers,
    required this.snapshot,
    required this.repository,
  });

  final BusinessWorkspace workspace;
  final CatalogProduct product;
  final List<Customer> customers;
  final CatalogSnapshot snapshot;
  final CatalogRepository repository;

  @override
  State<_CustomerPriceDialog> createState() => _CustomerPriceDialogState();
}

class _CustomerPriceDialogState extends State<_CustomerPriceDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _customerId;
  late final TextEditingController _amount;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _customerId = widget.customers.first.id;
    final existing = _existingPrice(_customerId);
    _amount = TextEditingController(
      text: existing == null
          ? ''
          : (existing.amountMinor / 100).toStringAsFixed(2),
    );
  }

  CatalogPrice? _existingPrice(String customerId) => widget.snapshot.prices
      .where(
        (price) =>
            price.variantId == widget.product.variantId &&
            price.customerId == customerId &&
            price.priceType == 'customer' &&
            price.branchId == null,
      )
      .firstOrNull;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Customer-specific price · ${widget.product.name}'),
    content: SizedBox(
      width: 460,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _customerId,
              decoration: const InputDecoration(labelText: 'Customer'),
              items: widget.customers
                  .map(
                    (customer) => DropdownMenuItem(
                      value: customer.id,
                      child: Text(
                        customer.phone == null || customer.phone!.isEmpty
                            ? customer.name
                            : '${customer.name} · ${customer.phone}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        _customerId = value;
                        final existing = _existingPrice(value);
                        _amount.text = existing == null
                            ? ''
                            : (existing.amountMinor / 100).toStringAsFixed(2);
                      });
                    },
            ),
            const SizedBox(height: 12),
            _MoneyField(
              controller: _amount,
              label: 'Customer-specific price (global)',
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Leave blank to remove the override. POS uses this price before the customer\'s group price.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
            : const Text('Save price'),
      ),
    ],
  );

  Future<void> _save() async {
    final amountText = _amount.text.trim();
    final amount = amountText.isEmpty ? null : parseMoneyToMinor(amountText);
    if (amountText.isNotEmpty && amount == null) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (amount == null) {
        await widget.repository.deleteCustomerPrice(
          businessId: widget.workspace.businessId,
          variantId: widget.product.variantId,
          customerId: _customerId,
        );
      } else {
        await widget.repository.upsertCustomerPrice(
          businessId: widget.workspace.businessId,
          variantId: widget.product.variantId,
          customerId: _customerId,
          amountMinor: amount,
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

class _CreateProductDialog extends StatefulWidget {
  const _CreateProductDialog({
    required this.workspace,
    required this.snapshot,
    required this.repository,
  });

  final BusinessWorkspace workspace;
  final CatalogSnapshot snapshot;
  final CatalogRepository repository;

  @override
  State<_CreateProductDialog> createState() => _CreateProductDialogState();
}

class _CreateProductDialogState extends State<_CreateProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _sku = TextEditingController();
  final _barcode = TextEditingController();
  final _cost = TextEditingController(text: '0.00');
  final _price = TextEditingController();
  late String _unitId = widget.snapshot.units.first.id;
  String? _taxRateId;
  String _productType = 'goods';
  bool _saving = false;
  String? _error;
  Uint8List? _imageBytes;
  String? _imageExtension;
  String? _imageContentType;

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _barcode.dispose();
    _cost.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create product'),
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
                  decoration: const InputDecoration(labelText: 'Product name'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _sku,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'SKU'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _barcode,
                  decoration: const InputDecoration(
                    labelText: 'Barcode (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                if (_imageBytes != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.memory(
                      _imageBytes!,
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.contain,
                    ),
                  )
                else
                  const SizedBox(
                    height: 100,
                    child: Center(child: Icon(Icons.image_outlined, size: 46)),
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _pickImage,
                        icon: const Icon(Icons.upload_outlined),
                        label: const Text('Add product image'),
                      ),
                      if (_imageBytes != null)
                        TextButton.icon(
                          onPressed: _saving
                              ? null
                              : () => setState(() {
                                  _imageBytes = null;
                                  _imageExtension = null;
                                  _imageContentType = null;
                                }),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('Remove image'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _productType,
                  decoration: const InputDecoration(labelText: 'Product type'),
                  items: const [
                    DropdownMenuItem(value: 'goods', child: Text('Goods')),
                    DropdownMenuItem(value: 'service', child: Text('Service')),
                    DropdownMenuItem(
                      value: 'bundle',
                      child: Text('Bundle / kit'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _productType = value ?? _productType),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _unitId,
                  decoration: const InputDecoration(labelText: 'Unit'),
                  items: widget.snapshot.units
                      .map(
                        (unit) => DropdownMenuItem(
                          value: unit.id,
                          child: Text(unit.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _unitId = value ?? _unitId),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _taxRateId,
                  decoration: const InputDecoration(labelText: 'Tax rate'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('No tax'),
                    ),
                    ...widget.snapshot.taxRates.map(
                      (tax) => DropdownMenuItem<String?>(
                        value: tax.id,
                        child: Text(
                          '${tax.name} (${tax.rateBasisPoints / 100}%)${tax.isInclusive ? ' · prices include tax' : ''}',
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _taxRateId = value),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _MoneyField(
                        controller: _cost,
                        label: 'Cost price',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MoneyField(
                        controller: _price,
                        label: 'Selling price',
                      ),
                    ),
                  ],
                ),
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
              : const Text('Create'),
        ),
      ],
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final cost = parseMoneyToMinor(_cost.text);
    final price = parseMoneyToMinor(_price.text);
    if (cost == null || price == null) {
      setState(
        () => _error = 'Enter valid amounts with at most two decimal places.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final productId = await widget.repository.createProduct(
        businessId: widget.workspace.businessId,
        name: _name.text,
        sku: _sku.text,
        unitId: _unitId,
        costMinor: cost,
        priceMinor: price,
        barcode: _barcode.text,
        productType: _productType,
        trackInventory: _productType != 'bundle',
        taxRateId: _taxRateId,
      );
      if (_imageBytes != null &&
          _imageExtension != null &&
          _imageContentType != null) {
        await widget.repository.uploadProductImage(
          businessId: widget.workspace.businessId,
          productId: productId,
          bytes: _imageBytes!,
          extension: _imageExtension!,
          contentType: _imageContentType!,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickImage() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;
    final extension = (file.extension ?? 'png').toLowerCase();
    final contentType = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/png',
    };
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _imageBytes = bytes;
      _imageExtension = extension;
      _imageContentType = contentType;
    });
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label),
    validator: (value) =>
        parseMoneyToMinor(value ?? '') == null ? 'Invalid amount' : null,
  );
}
