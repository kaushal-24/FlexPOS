import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/core/security/crud_permissions.dart';
import 'package:flexpos/core/widgets/data_page_skeleton.dart';
import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/core/widgets/product_image.dart';
import 'package:flexpos/features/catalog/data/catalog_repository.dart';
import 'package:flexpos/features/catalog/domain/catalog_models.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CatalogManagementPage extends ConsumerWidget {
  const CatalogManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    final snapshot = ref.watch(catalogSnapshotProvider);
    if (workspace == null) {
      return const EmptyState(
        icon: Icons.add_business_outlined,
        title: 'Select a business',
        message: 'A business workspace is required for catalog tools.',
      );
    }
    if (!workspace.canManage('products')) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Catalog tools are restricted',
        message: 'Your role cannot manage products and inventory definitions.',
      );
    }
    return snapshot.when(
      loading: () => const DataPageSkeleton(sectionLabel: 'catalog tools'),
      error: (error, _) => EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load catalog tools',
        message: error.toString(),
        action: FilledButton.icon(
          onPressed: () => ref.invalidate(catalogSnapshotProvider),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      ),
      data: (data) => _CatalogManagementBody(
        workspaceId: workspace.businessId,
        snapshot: data,
        repository: ref.read(catalogRepositoryProvider),
        onChanged: () => ref.invalidate(catalogSnapshotProvider),
      ),
    );
  }
}

class _CatalogManagementBody extends StatefulWidget {
  const _CatalogManagementBody({
    required this.workspaceId,
    required this.snapshot,
    required this.repository,
    required this.onChanged,
  });

  final String workspaceId;
  final CatalogSnapshot snapshot;
  final CatalogRepository repository;
  final VoidCallback onChanged;

  @override
  State<_CatalogManagementBody> createState() => _CatalogManagementBodyState();
}

class _CatalogManagementBodyState extends State<_CatalogManagementBody> {
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
        children: [
          Text(
            'Catalog tools',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Manage conversions and bundle recipes, or move catalog data through a reviewed CSV file.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _working ? null : _export,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Export CSV'),
              ),
              FilledButton.tonalIcon(
                onPressed: _working ? null : _import,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Import CSV'),
              ),
            ],
          ),
          if (_working) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 18),
          const TabBar(
            tabs: [
              Tab(text: 'Unit conversions'),
              Tab(text: 'Bundles / kits'),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 560,
            child: TabBarView(
              children: [
                _ConversionsTab(
                  snapshot: widget.snapshot,
                  repository: widget.repository,
                  businessId: widget.workspaceId,
                  onChanged: widget.onChanged,
                ),
                _BundlesTab(
                  snapshot: widget.snapshot,
                  repository: widget.repository,
                  businessId: widget.workspaceId,
                  onChanged: widget.onChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _export() async {
    setState(() => _working = true);
    try {
      final csv = await widget.repository.exportCatalogCsv(
        businessId: widget.workspaceId,
      );
      final path = await FilePicker.saveFile(
        dialogTitle: 'Export catalog CSV',
        fileName: 'flexpos-catalog.csv',
        bytes: Uint8List.fromList(utf8.encode(csv)),
        mimeType: 'text/csv',
        type: FileType.custom,
        allowedExtensions: const ['csv'],
      );
      if (mounted && path != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Catalog CSV exported.')));
      }
    } catch (error) {
      if (mounted) _showError('Could not export catalog: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _import() async {
    if (widget.snapshot.units.isEmpty) {
      _showError('Create a unit before importing products.');
      return;
    }
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    if (file == null) return;
    final rows = _parseCsv(utf8.decode(await file.readAsBytes()));
    if (rows.length < 2) {
      _showError('The CSV contains no product rows.');
      return;
    }
    final header = rows.first
        .map((value) => value.trim().toLowerCase())
        .toList();
    final index = {for (var i = 0; i < header.length; i++) header[i]: i};
    final repository = widget.repository;
    setState(() => _working = true);
    var imported = 0;
    try {
      for (final row in rows.skip(1)) {
        String value(String key) {
          final position = index[key];
          return position == null || position >= row.length
              ? ''
              : row[position].trim();
        }

        final name = value('product_name');
        final sku = value('sku');
        final price = double.tryParse(value('selling_price'));
        final cost = double.tryParse(value('cost_price')) ?? 0;
        if (name.isEmpty ||
            sku.isEmpty ||
            price == null ||
            price < 0 ||
            cost < 0) {
          continue;
        }
        Map<String, String> attributes = const {};
        final rawAttributes = value('attributes');
        if (rawAttributes.isNotEmpty) {
          final decoded = jsonDecode(rawAttributes);
          if (decoded is Map) {
            attributes = {
              for (final entry in decoded.entries)
                entry.key.toString(): entry.value.toString(),
            };
          }
        }
        final requestedUnit = value('base_unit_id');
        final requestedUnitName = value('base_unit_name').toLowerCase();
        final unit = widget.snapshot.units.firstWhere(
          (candidate) =>
              candidate.id == requestedUnit ||
              candidate.name.toLowerCase() == requestedUnitName,
          orElse: () => widget.snapshot.units.first,
        );
        await repository.createProduct(
          businessId: widget.workspaceId,
          name: name,
          sku: sku,
          unitId: unit.id,
          costMinor: (cost * 100).round(),
          priceMinor: (price * 100).round(),
          barcode: value('barcode'),
          productType: value('product_type').isEmpty
              ? 'goods'
              : value('product_type'),
          attributes: attributes,
          trackInventory: value('track_inventory').toLowerCase() != 'false',
        );
        imported++;
      }
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$imported product(s) imported.')),
        );
      }
    } catch (error) {
      if (mounted) {
        _showError('Import stopped after $imported product(s): $error');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ConversionsTab extends StatelessWidget {
  const _ConversionsTab({
    required this.snapshot,
    required this.repository,
    required this.businessId,
    required this.onChanged,
  });

  final CatalogSnapshot snapshot;
  final CatalogRepository repository;
  final String businessId;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final units = {for (final unit in snapshot.units) unit.id: unit};
    return ListView(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: snapshot.units.length < 2
                ? null
                : () => _showEditor(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add conversion'),
          ),
        ),
        const SizedBox(height: 12),
        if (snapshot.unitConversions.isEmpty)
          const EmptyState(
            icon: Icons.swap_horiz_rounded,
            title: 'No conversions yet',
            message:
                'Define how purchasing or selling units convert to each other.',
          )
        else
          for (final conversion in snapshot.unitConversions) ...[
            AppPanel(
              child: ListTile(
                title: Text(
                  '${units[conversion.fromUnitId]?.name ?? 'Unknown'} → ${units[conversion.toUnitId]?.name ?? 'Unknown'}',
                ),
                subtitle: Text(
                  '1 ${units[conversion.fromUnitId]?.symbol ?? ''} = ${conversion.multiplier} ${units[conversion.toUnitId]?.symbol ?? ''}',
                ),
                trailing: IconButton(
                  tooltip: 'Delete conversion',
                  onPressed: () async {
                    await repository.deleteUnitConversion(
                      businessId: businessId,
                      conversionId: conversion.id,
                    );
                    onChanged();
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  Future<void> _showEditor(BuildContext context) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ConversionDialog(
        units: snapshot.units,
        repository: repository,
        businessId: businessId,
      ),
    );
    if (saved == true) onChanged();
  }
}

class _ConversionDialog extends StatefulWidget {
  const _ConversionDialog({
    required this.units,
    required this.repository,
    required this.businessId,
  });

  final List<CatalogOption> units;
  final CatalogRepository repository;
  final String businessId;

  @override
  State<_ConversionDialog> createState() => _ConversionDialogState();
}

class _ConversionDialogState extends State<_ConversionDialog> {
  late String _from = widget.units.first.id;
  late String _to = widget.units.length > 1
      ? widget.units[1].id
      : widget.units.first.id;
  final _multiplier = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _multiplier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add unit conversion'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _from,
            decoration: const InputDecoration(labelText: 'From unit'),
            items: widget.units
                .map(
                  (unit) =>
                      DropdownMenuItem(value: unit.id, child: Text(unit.name)),
                )
                .toList(),
            onChanged: _saving
                ? null
                : (value) => setState(() => _from = value ?? _from),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _to,
            decoration: const InputDecoration(labelText: 'To unit'),
            items: widget.units
                .map(
                  (unit) =>
                      DropdownMenuItem(value: unit.id, child: Text(unit.name)),
                )
                .toList(),
            onChanged: _saving
                ? null
                : (value) => setState(() => _to = value ?? _to),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _multiplier,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Multiplier',
              helperText: '1 from-unit equals this many to-units.',
            ),
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
        child: const Text('Save'),
      ),
    ],
  );

  Future<void> _save() async {
    final multiplier = double.tryParse(_multiplier.text.trim());
    if (_from == _to || multiplier == null || multiplier <= 0) return;
    setState(() => _saving = true);
    try {
      await widget.repository.upsertUnitConversion(
        businessId: widget.businessId,
        fromUnitId: _from,
        toUnitId: _to,
        multiplier: multiplier,
      );
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _BundlesTab extends StatelessWidget {
  const _BundlesTab({
    required this.snapshot,
    required this.repository,
    required this.businessId,
    required this.onChanged,
  });

  final CatalogSnapshot snapshot;
  final CatalogRepository repository;
  final String businessId;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final products = {
      for (final product in snapshot.products) product.variantId: product,
    };
    final bundles = snapshot.products
        .where((product) => product.productType == 'bundle')
        .toList();
    return ListView(
      children: [
        if (bundles.isEmpty)
          const EmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'No bundles yet',
            message: 'Create a product with type Bundle, then add its component SKUs here.',
          )
        else
          for (final bundle in bundles) ...[
            AppPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ProductImage(
                      imagePath: bundle.imagePath,
                      width: 48,
                      height: 48,
                      borderRadius: 10,
                      fit: BoxFit.contain,
                      iconSize: 22,
                    ),
                    title: Text(bundle.name),
                    subtitle: Text(bundle.sku),
                    trailing: FilledButton.tonalIcon(
                      onPressed: () => _showEditor(context, bundle),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Component'),
                    ),
                  ),
                  for (final component in snapshot.bundleComponents.where(
                    (item) => item.bundleVariantId == bundle.variantId,
                  ))
                    ListTile(
                      dense: true,
                      leading: ProductImage(
                        imagePath:
                            products[component.componentVariantId]?.imagePath,
                        width: 36,
                        height: 36,
                        borderRadius: 8,
                        fit: BoxFit.contain,
                        iconSize: 18,
                      ),
                      title: Text(
                        products[component.componentVariantId]?.name ??
                            'Unknown SKU',
                      ),
                      subtitle: Text('Quantity ${component.quantity}'),
                      trailing: IconButton(
                        tooltip: 'Remove component',
                        onPressed: () async {
                          await repository.deleteBundleComponent(
                            businessId: businessId,
                            componentId: component.id,
                          );
                          onChanged();
                        },
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Future<void> _showEditor(BuildContext context, CatalogProduct bundle) async {
    final components = snapshot.products
        .where(
          (product) =>
              product.variantId != bundle.variantId &&
              product.productType != 'bundle',
        )
        .toList(growable: false);
    if (components.isEmpty) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _BundleComponentDialog(
        bundle: bundle,
        components: components,
        repository: repository,
        businessId: businessId,
      ),
    );
    if (saved == true) onChanged();
  }
}

class _BundleComponentDialog extends StatefulWidget {
  const _BundleComponentDialog({
    required this.bundle,
    required this.components,
    required this.repository,
    required this.businessId,
  });

  final CatalogProduct bundle;
  final List<CatalogProduct> components;
  final CatalogRepository repository;
  final String businessId;

  @override
  State<_BundleComponentDialog> createState() => _BundleComponentDialogState();
}

class _BundleComponentDialogState extends State<_BundleComponentDialog> {
  late String _component = widget.components.first.variantId;
  final _quantity = TextEditingController(text: '1');
  bool _saving = false;

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Add component · ${widget.bundle.name}'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _component,
            decoration: const InputDecoration(labelText: 'Component SKU'),
            items: widget.components
                .map(
                  (product) => DropdownMenuItem(
                    value: product.variantId,
                    child: Text(
                      '${product.name} · ${product.sku}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _saving
                ? null
                : (value) => setState(() => _component = value ?? _component),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _quantity,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Quantity per bundle'),
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
        child: const Text('Save'),
      ),
    ],
  );

  Future<void> _save() async {
    final quantity = double.tryParse(_quantity.text.trim());
    if (quantity == null || quantity <= 0) return;
    setState(() => _saving = true);
    try {
      await widget.repository.upsertBundleComponent(
        businessId: widget.businessId,
        bundleVariantId: widget.bundle.variantId,
        componentVariantId: _component,
        quantity: quantity,
      );
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

List<List<String>> _parseCsv(String input) {
  final rows = <List<String>>[];
  var row = <String>[];
  var cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < input.length; i++) {
    final char = input[i];
    if (char == '"') {
      if (quoted && i + 1 < input.length && input[i + 1] == '"') {
        cell.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (char == ',' && !quoted) {
      row.add(cell.toString());
      cell = StringBuffer();
    } else if ((char == '\n' || char == '\r') && !quoted) {
      if (char == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
      row.add(cell.toString());
      if (row.any((value) => value.isNotEmpty)) rows.add(row);
      row = <String>[];
      cell = StringBuffer();
    } else {
      cell.write(char);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    if (row.any((value) => value.isNotEmpty)) rows.add(row);
  }
  return rows;
}
