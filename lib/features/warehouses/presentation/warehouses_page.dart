import 'package:flexpos/core/security/crud_permissions.dart';
import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/core/widgets/data_list_controls.dart';
import 'package:flexpos/core/widgets/data_page_skeleton.dart';
import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/features/tenants/domain/business_workspace.dart';
import 'package:flexpos/features/tenants/domain/feature_entitlement.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flexpos/features/catalog/data/catalog_repository.dart';
import 'package:flexpos/features/warehouses/data/warehouse_repository.dart';
import 'package:flexpos/features/warehouses/domain/warehouse_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WarehousesPage extends ConsumerStatefulWidget {
  const WarehousesPage({super.key});

  @override
  ConsumerState<WarehousesPage> createState() => _WarehousesPageState();
}

class _WarehousesPageState extends ConsumerState<WarehousesPage> {
  String _query = '';
  String _sort = 'name';
  int _page = 0;

  Future<void> _openEditor(
    BusinessWorkspace workspace,
    WarehouseRecord? warehouse,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _WarehouseDialog(
        workspace: workspace,
        warehouse: warehouse,
      ),
    );
    if (saved == true) {
      ref.invalidate(warehousesProvider(workspace.businessId));
      ref.invalidate(workspacesProvider);
      ref.invalidate(catalogSnapshotProvider);
    }
  }

  Future<void> _deleteWarehouse(
    BusinessWorkspace workspace,
    WarehouseRecord warehouse,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete warehouse?'),
        content: Text(
          'Delete “${warehouse.name}”? It will be hidden from new operations while preserving stock and movement history.',
        ),
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
    );
    if (confirmed != true) return;
    try {
      await ref.read(warehouseRepositoryProvider).deleteWarehouse(warehouse);
      _refresh(workspace.businessId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Warehouse deleted.')),
        );
      }
    } on PostgrestException catch (error) {
      _showError('Could not delete warehouse: ${error.message}');
    }
  }

  Future<void> _restoreWarehouse(
    BusinessWorkspace workspace,
    WarehouseRecord warehouse,
  ) async {
    try {
      await ref.read(warehouseRepositoryProvider).restoreWarehouse(warehouse);
      _refresh(workspace.businessId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Warehouse restored.')),
        );
      }
    } on PostgrestException catch (error) {
      _showError('Could not restore warehouse: ${error.message}');
    }
  }

  void _refresh(String businessId) {
    ref.invalidate(warehousesProvider(businessId));
    ref.invalidate(workspacesProvider);
    ref.invalidate(catalogSnapshotProvider);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final workspaceValue = ref.watch(selectedWorkspaceProvider);
    return workspaceValue.when(
      loading: () => const DataPageSkeleton(sectionLabel: 'warehouses'),
      error: (error, _) => EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Warehouses unavailable',
        message: error.toString(),
      ),
      data: (workspace) {
        if (workspace == null) {
          return EmptyState(
            icon: Icons.add_business_outlined,
            title: 'Create a business first',
            message: 'Every warehouse belongs to a business and branch.',
            action: FilledButton(
              onPressed: () => context.go('/onboarding'),
              child: const Text('Create business'),
            ),
          );
        }
        if (!workspace.isFeatureEnabled(FeatureCodes.inventory) ||
            !workspace.canRead('inventory') ||
            workspace.roleName.trim().toLowerCase() == 'cashier') {
          return const EmptyState(
            icon: Icons.lock_outline_rounded,
            title: 'Warehouse access is restricted',
            message:
                'Cashiers can see availability in POS. Inventory and warehouse details are limited to stock-management roles.',
          );
        }
        final warehouses = ref.watch(warehousesProvider(workspace.businessId));
        return warehouses.when(
          loading: () => const DataPageSkeleton(sectionLabel: 'warehouses'),
          error: (error, _) => EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Warehouses unavailable',
            message: error.toString(),
            action: FilledButton.icon(
              onPressed: () => ref.invalidate(
                warehousesProvider(workspace.businessId),
              ),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ),
          data: (items) => _buildContent(context, workspace, items),
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    BusinessWorkspace workspace,
    List<WarehouseRecord> items,
  ) {
    final canCreate = workspace.canCreate('inventory');
    final canUpdate = workspace.canUpdate('inventory');
    final canDelete = workspace.canDelete('inventory');
    final branchNames = {
      for (final branch in workspace.branches) branch.id: branch.name,
    };
    final query = _query.toLowerCase();
    final filtered = items.where((warehouse) {
      final branch = branchNames[warehouse.branchId] ?? 'Unknown branch';
      return '$branch ${warehouse.name} ${warehouse.code}'
          .toLowerCase()
          .contains(query);
    }).toList();
    filtered.sort((a, b) {
      final branchA = branchNames[a.branchId] ?? '';
      final branchB = branchNames[b.branchId] ?? '';
      return switch (_sort) {
        'code' => a.code.toLowerCase().compareTo(b.code.toLowerCase()),
        'branch' => branchA.toLowerCase().compareTo(branchB.toLowerCase()),
        'status' => (a.isActive ? 0 : 1).compareTo(b.isActive ? 0 : 1),
        _ => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      };
    });
    final pageCount = pageCountFor(filtered.length);
    if (_page >= pageCount) _page = pageCount - 1;
    final visible = pageItems(filtered, _page);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 12,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Warehouses', style: Theme.of(context).textTheme.headlineMedium),
                Text(
                  '${workspace.businessName} • ${items.length} warehouse${items.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
            if (canCreate)
              FilledButton.icon(
                onPressed: () => _openEditor(workspace, null),
                icon: const Icon(Icons.add_business_outlined),
                label: const Text('Add warehouse'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Warehouses hold stock for one branch. Delete deactivates a warehouse so inventory history remains auditable.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 22),
        DataListControls(
          query: _query,
          onSearchChanged: (value) => setState(() {
            _query = value.trim();
            _page = 0;
          }),
          searchLabel: 'Search warehouse, code, or branch',
          sortValue: _sort,
          sortOptions: const [
            DataListSortOption('name', 'Name A–Z'),
            DataListSortOption('code', 'Code A–Z'),
            DataListSortOption('branch', 'Branch A–Z'),
            DataListSortOption('status', 'Active first'),
          ],
          onSortChanged: (value) => setState(() {
            _sort = value;
            _page = 0;
          }),
          page: _page,
          pageCount: pageCount,
          totalCount: filtered.length,
          onPageChanged: (value) => setState(() => _page = value),
        ),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          const EmptyState(
            icon: Icons.warehouse_outlined,
            title: 'No warehouses found',
            message: 'Create a warehouse or adjust your search.',
          ),
        for (final warehouse in visible) ...[
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      child: Icon(
                        warehouse.isActive
                            ? Icons.warehouse_rounded
                            : Icons.warehouse_outlined,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            warehouse.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${branchNames[warehouse.branchId] ?? 'Unknown branch'} • ${warehouse.code}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (warehouse.isDefault)
                      const Chip(
                        avatar: Icon(Icons.star_rounded, size: 16),
                        label: Text('Default'),
                      ),
                    const SizedBox(width: 8),
                    Chip(
                      label: Text(warehouse.isActive ? 'Active' : 'Deleted'),
                      backgroundColor: warehouse.isActive
                          ? Theme.of(context).colorScheme.secondaryContainer
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
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
                          onPressed: () => _openEditor(workspace, warehouse),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit warehouse'),
                        ),
                      if (canDelete && warehouse.isActive)
                        TextButton.icon(
                          onPressed: () => _deleteWarehouse(workspace, warehouse),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('Delete'),
                        ),
                      if (canUpdate && !warehouse.isActive)
                        FilledButton.tonalIcon(
                          onPressed: () => _restoreWarehouse(workspace, warehouse),
                          icon: const Icon(Icons.restore_rounded),
                          label: const Text('Restore'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _WarehouseDialog extends ConsumerStatefulWidget {
  const _WarehouseDialog({required this.workspace, this.warehouse});

  final BusinessWorkspace workspace;
  final WarehouseRecord? warehouse;

  @override
  ConsumerState<_WarehouseDialog> createState() => _WarehouseDialogState();
}

class _WarehouseDialogState extends ConsumerState<_WarehouseDialog> {
  late final TextEditingController _name;
  late final TextEditingController _code;
  late String _branchId;
  late bool _isDefault;
  late bool _isActive;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.warehouse?.name ?? '');
    _code = TextEditingController(text: widget.warehouse?.code ?? '');
    _branchId = widget.warehouse?.branchId ??
        (widget.workspace.branches.firstOrNull?.id ?? '');
    _isDefault = widget.warehouse?.isDefault ?? false;
    _isActive = widget.warehouse?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) {
      return _error('Enter a warehouse name.');
    }
    if (_branchId.isEmpty) return _error('Select a branch.');
    if (!RegExp(r'^[A-Za-z0-9-]{1,30}$').hasMatch(_code.text.trim())) {
      return _error('Use 1–30 letters, numbers, or hyphens for the code.');
    }
    setState(() => _saving = true);
    try {
      final repository = ref.read(warehouseRepositoryProvider);
      if (widget.warehouse == null) {
        await repository.createWarehouse(
          businessId: widget.workspace.businessId,
          branchId: _branchId,
          name: _name.text,
          code: _code.text,
          isDefault: _isDefault,
        );
      } else {
        await repository.updateWarehouse(
          warehouse: widget.warehouse!,
          branchId: _branchId,
          name: _name.text,
          code: _code.text,
          isDefault: _isDefault,
          isActive: _isActive,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (error) {
      if (mounted) _error(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _error(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.warehouse == null ? 'Add warehouse' : 'Edit warehouse'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Warehouse name'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Warehouse code',
                helperText: 'Unique within this business',
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _branchId.isEmpty ? null : _branchId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Branch'),
              items: widget.workspace.branches
                  .map(
                    (branch) => DropdownMenuItem<String>(
                      value: branch.id,
                      child: Text('${branch.name} (${branch.code})'),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _branchId = value ?? ''),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isDefault,
              title: const Text('Default warehouse for this branch'),
              subtitle: const Text('Only one active default is allowed per branch.'),
              onChanged: (value) => setState(() => _isDefault = value),
            ),
            if (widget.warehouse != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isActive,
                title: const Text('Warehouse active'),
                onChanged: (value) => setState(() => _isActive = value),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save warehouse'),
      ),
    ],
  );
}
