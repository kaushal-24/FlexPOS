import 'dart:convert';

import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/core/security/crud_permissions.dart';
import 'package:flexpos/core/widgets/data_list_controls.dart';
import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/features/hardware/data/hardware_repository.dart';
import 'package:flexpos/features/hardware/domain/hardware_device.dart';
import 'package:flexpos/features/tenants/domain/business_workspace.dart';
import 'package:flexpos/features/tenants/domain/feature_entitlement.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HardwareOperationsPage extends ConsumerStatefulWidget {
  const HardwareOperationsPage({super.key});

  @override
  ConsumerState<HardwareOperationsPage> createState() =>
      _HardwareOperationsPageState();
}

class _HardwareOperationsPageState
    extends ConsumerState<HardwareOperationsPage> {
  String _kind = 'all';
  String _query = '';
  String _sort = 'updated';
  int _page = 0;
  static const _pageSize = 20;

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    if (workspace == null) {
      return const EmptyState(
        icon: Icons.add_business_outlined,
        title: 'Select a business',
        message: 'A business workspace is required to manage hardware.',
      );
    }
    if (!workspace.canRead('hardware')) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Hardware is restricted',
        message: 'Your role does not include permission to view hardware.',
      );
    }
    if (!workspace.isFeatureEnabled(FeatureCodes.hardwareOperations)) {
      return EmptyState(
        icon: Icons.devices_other_outlined,
        title: 'Enable hardware operations',
        message: 'Online scanner, printer, scale, display, and cash-drawer setup is disabled for this workspace.',
        action: FilledButton.icon(
          onPressed: () => context.go('/modules'),
          icon: const Icon(Icons.tune_rounded),
          label: const Text('Open module settings'),
        ),
      );
    }
    final canCreate = workspace.canCreate('hardware');
    final canUpdate = workspace.canUpdate('hardware');
    final canDelete = workspace.canDelete('hardware');
    final devices = ref.watch(hardwareDevicesProvider(workspace.businessId));
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hardware operations',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Configure online hardware adapters without storing offline queues or device data caches.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (canCreate)
              FilledButton.icon(
                onPressed: () => _setupDevice(context, workspace),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Register hardware'),
              ),
          ],
        ),
        const SizedBox(height: 18),
        AppPanel(
          child: Row(
            children: [
              Icon(
                Icons.cloud_done_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Online-only mode is active. Scanner input, print bridges, device heartbeats, and connectivity tests require an authenticated connection. Offline cache, transaction queues, deferred sync, and offline sales are intentionally unavailable.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              IconButton(
                tooltip: 'Refresh devices',
                onPressed: () => ref.invalidate(
                  hardwareDevicesProvider(workspace.businessId),
                ),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _CompatibilityPanel(),
        const SizedBox(height: 18),
        devices.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => AppPanel(
            child: ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Could not load hardware devices'),
              subtitle: Text('$error'),
              trailing: IconButton(
                onPressed: () => ref.invalidate(
                  hardwareDevicesProvider(workspace.businessId),
                ),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
          ),
          data: (items) =>
              _buildDeviceList(
                context,
                workspace.businessId,
                items,
                canUpdate,
                canDelete,
              ),
        ),
      ],
    );
  }

  Widget _buildDeviceList(
    BuildContext context,
    String businessId,
    List<HardwareDevice> allItems,
    bool canUpdate,
    bool canDelete,
  ) {
    final filtered = allItems.where((item) {
      if (_kind != 'all' && item.deviceKind != _kind) {
        return false;
      }
      final query = _query.trim().toLowerCase();
      return query.isEmpty ||
          item.displayName.toLowerCase().contains(query) ||
          item.deviceKind.toLowerCase().contains(query) ||
          item.status.toLowerCase().contains(query) ||
          (item.endpoint ?? '').toLowerCase().contains(query);
    }).toList();
    filtered.sort((a, b) {
      if (_sort == 'name') {
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      }
      if (_sort == 'status') {
        return a.status.compareTo(b.status);
      }
      return b.createdAt.compareTo(a.createdAt);
    });
    final totalPages = pageCountFor(filtered.length, pageSize: _pageSize);
    final page = _page.clamp(0, totalPages - 1);
    final visible = pageItems(filtered, page, pageSize: _pageSize);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('All devices'),
              selected: _kind == 'all',
              onSelected: (_) => setState(() {
                _kind = 'all';
                _page = 0;
              }),
            ),
            for (final definition in hardwareDeviceDefinitions)
              ChoiceChip(
                label: Text(definition.label),
                selected: _kind == definition.code,
                onSelected: (_) => setState(() {
                  _kind = definition.code;
                  _page = 0;
                }),
              ),
          ],
        ),
        const SizedBox(height: 14),
        DataListControls(
          searchLabel: 'Search hardware',
          query: _query,
          onSearchChanged: (value) => setState(() {
            _query = value;
            _page = 0;
          }),
          sortOptions: const [
            DataListSortOption('updated', 'Recently registered'),
            DataListSortOption('name', 'Name'),
            DataListSortOption('status', 'Status'),
          ],
          sortValue: _sort,
          onSortChanged: (value) => setState(() {
            _sort = value;
            _page = 0;
          }),
          page: page,
          pageCount: totalPages,
          totalCount: filtered.length,
          onPageChanged: (value) => setState(() => _page = value),
        ),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.all(40),
            child: EmptyState(
              icon: Icons.devices_other_outlined,
              title: 'No hardware registered',
              message: 'Register a scanner, printer, drawer, scale, or customer display to begin online connectivity testing.',
            ),
          )
        else
          for (final device in visible) ...[
            _DeviceCard(
              device: device,
              canUpdate: canUpdate,
              canDelete: canDelete,
              onTest: () => _testDevice(context, businessId, device),
              onDelete: () => _deleteDevice(context, businessId, device),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Future<void> _setupDevice(
    BuildContext context,
    BusinessWorkspace workspace,
  ) async {
    final draft = await showDialog<_DeviceDraft>(
      context: context,
      builder: (_) => _SetupDeviceDialog(workspace: workspace),
    );
    if (!mounted || draft == null) return;
    try {
      await ref
          .read(hardwareRepositoryProvider)
          .registerDevice(
            businessId: workspace.businessId,
            branchId: draft.branchId,
            deviceKind: draft.deviceKind,
            connectionType: draft.connectionType,
            displayName: draft.displayName,
            endpoint: draft.endpoint,
            capabilities: draft.capabilities,
            metadata: const {'mode': 'online_only'},
          );
      ref.invalidate(hardwareDevicesProvider(workspace.businessId));
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Hardware registered')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _testDevice(
    BuildContext context,
    String businessId,
    HardwareDevice device,
  ) async {
    final result = await showDialog<_HardwareTestDraft>(
      context: context,
      builder: (_) => _HardwareTestDialog(device: device),
    );
    if (!mounted || result == null) return;
    try {
      await ref
          .read(hardwareRepositoryProvider)
          .recordTest(
            businessId: businessId,
            deviceId: device.id,
            status: result.status,
            error: result.error,
            metadata: {
              'mode': 'online_only',
              'transport': device.connectionType,
              'source': 'authenticated_app',
            },
          );
      ref.invalidate(hardwareDevicesProvider(businessId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connectivity result saved')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _deleteDevice(
    BuildContext context,
    String businessId,
    HardwareDevice device,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove hardware?'),
        content: Text('Remove “${device.displayName}” and its connectivity history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(hardwareRepositoryProvider).deleteDevice(
            businessId: businessId,
            deviceId: device.id,
          );
      ref.invalidate(hardwareDevicesProvider(businessId));
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

IconData _hardwareIcon(String code) => switch (code) {
  'barcode_camera' => Icons.camera_alt_outlined,
  'barcode_bluetooth' || 'barcode_usb' => Icons.qr_code_scanner_rounded,
  'thermal_bluetooth' ||
  'thermal_usb' ||
  'thermal_network' => Icons.print_outlined,
  'cash_drawer' => Icons.point_of_sale_outlined,
  'label_printer' => Icons.label_outline,
  'weighing_scale' => Icons.scale_outlined,
  'customer_display' => Icons.desktop_windows_outlined,
  _ => Icons.devices_other_outlined,
};

class _CompatibilityPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) => AppPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Adapter compatibility',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Camera scanning and HID barcode input are active in POS. Receipts use 58/80 mm PDF/system print bridges; ESC/POS, cash-drawer, label, scale, and display transports use the registered online adapter boundary.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final definition in hardwareDeviceDefinitions)
              Chip(
                avatar: Icon(_hardwareIcon(definition.code), size: 18),
                label: Text(
                  '${definition.label} · ${hardwareConnectionLabel(definition.connectionType)}',
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.canUpdate,
    required this.canDelete,
    required this.onTest,
    required this.onDelete,
  });
  final HardwareDevice device;
  final bool canUpdate;
  final bool canDelete;
  final VoidCallback onTest;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final definition = hardwareDeviceDefinition(device.deviceKind);
    return AppPanel(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(
              _hardwareIcon(definition.code),
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.displayName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${definition.label} · ${hardwareConnectionLabel(device.connectionType)}',
                  style: theme.textTheme.bodySmall,
                ),
                if (device.endpoint != null)
                  Text(device.endpoint!, style: theme.textTheme.bodySmall),
                if (device.lastError != null)
                  Text(
                    device.lastError!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
              ],
            ),
          ),
          _StatusChip(status: device.status),
          if (canUpdate)
            IconButton(
              tooltip: 'Test connectivity',
              onPressed: onTest,
              icon: const Icon(Icons.network_check_rounded),
            ),
          if (canDelete)
            IconButton(
              tooltip: 'Remove hardware',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'online' => Colors.green,
      'error' || 'offline' || 'disabled' => Colors.red,
      'testing' => Colors.blue,
      _ => Theme.of(context).colorScheme.secondary,
    };
    return Chip(
      label: Text(status.replaceAll('_', ' ')),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
      side: BorderSide(color: color.withValues(alpha: .35)),
      backgroundColor: color.withValues(alpha: .08),
    );
  }
}

class _DeviceDraft {
  const _DeviceDraft({
    required this.deviceKind,
    required this.connectionType,
    required this.displayName,
    required this.branchId,
    required this.endpoint,
    required this.capabilities,
  });
  final String deviceKind;
  final String connectionType;
  final String displayName;
  final String? branchId;
  final String? endpoint;
  final Map<String, dynamic> capabilities;
}

class _SetupDeviceDialog extends StatefulWidget {
  const _SetupDeviceDialog({required this.workspace});
  final BusinessWorkspace workspace;

  @override
  State<_SetupDeviceDialog> createState() => _SetupDeviceDialogState();
}

class _SetupDeviceDialogState extends State<_SetupDeviceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _endpoint = TextEditingController();
  final _capabilities = TextEditingController(text: '{}');
  late String _kind;
  late String _connection;
  String? _branchId;

  @override
  void initState() {
    super.initState();
    final definition = hardwareDeviceDefinitions.first;
    _kind = definition.code;
    _connection = definition.connectionType;
    _branchId = widget.workspace.branches.firstOrNull?.id;
  }

  @override
  void dispose() {
    _name.dispose();
    _endpoint.dispose();
    _capabilities.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Register online hardware'),
    content: SizedBox(
      width: 560,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Hardware type'),
                items: [
                  for (final definition in hardwareDeviceDefinitions)
                    DropdownMenuItem(
                      value: definition.code,
                      child: Text(definition.label),
                    ),
                ],
                onChanged: (value) {
                  final selected = hardwareDeviceDefinition(value ?? _kind);
                  setState(() {
                    _kind = selected.code;
                    _connection = selected.connectionType;
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _branchId,
                decoration: const InputDecoration(labelText: 'Branch'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All branches'),
                  ),
                  for (final branch in widget.workspace.branches)
                    DropdownMenuItem<String?>(
                      value: branch.id,
                      child: Text(branch.name),
                    ),
                ],
                onChanged: (value) => setState(() => _branchId = value),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Display name'),
                validator: (value) => value == null || value.trim().length < 2
                    ? 'Enter a name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _endpoint,
                decoration: InputDecoration(
                  labelText: _connection == 'tcp'
                      ? 'Network endpoint'
                      : 'Endpoint / identifier (optional)',
                  hintText: _connection == 'tcp' ? 'printer.local:9100' : null,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _capabilities,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Capabilities JSON object',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Do not put passwords, API keys, or offline data in endpoint or capabilities.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Register')),
    ],
  );

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Map<String, dynamic> capabilities;
    try {
      final decoded = jsonDecode(_capabilities.text.trim());
      if (decoded is! Map) throw const FormatException();
      capabilities = Map<String, dynamic>.from(decoded);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Capabilities must be a JSON object')),
      );
      return;
    }
    Navigator.pop(
      context,
      _DeviceDraft(
        deviceKind: _kind,
        connectionType: _connection,
        displayName: _name.text,
        branchId: _branchId,
        endpoint: _endpoint.text,
        capabilities: capabilities,
      ),
    );
  }
}

class _HardwareTestDraft {
  const _HardwareTestDraft({required this.status, this.error});
  final String status;
  final String? error;
}

class _HardwareTestDialog extends StatefulWidget {
  const _HardwareTestDialog({required this.device});
  final HardwareDevice device;

  @override
  State<_HardwareTestDialog> createState() => _HardwareTestDialogState();
}

class _HardwareTestDialogState extends State<_HardwareTestDialog> {
  final _error = TextEditingController();
  String _status = 'online';

  @override
  void dispose() {
    _error.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Test ${widget.device.displayName}'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'This records an authenticated online adapter result. It does not create an offline queue.',
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: _status,
          decoration: const InputDecoration(labelText: 'Result'),
          items: const [
            DropdownMenuItem(value: 'online', child: Text('Online / passed')),
            DropdownMenuItem(value: 'error', child: Text('Error')),
            DropdownMenuItem(
              value: 'offline',
              child: Text('Offline / unavailable'),
            ),
            DropdownMenuItem(value: 'disabled', child: Text('Disabled')),
          ],
          onChanged: (value) => setState(() => _status = value ?? _status),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _error,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Error detail (optional)',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _HardwareTestDraft(status: _status, error: _error.text),
        ),
        child: const Text('Save test'),
      ),
    ],
  );
}
