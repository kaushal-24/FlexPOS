import 'dart:convert';

import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/core/security/crud_permissions.dart';
import 'package:flexpos/core/widgets/data_list_controls.dart';
import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/features/enterprise/data/enterprise_repository.dart';
import 'package:flexpos/features/enterprise/domain/enterprise_record.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class EnterpriseOperationsPage extends ConsumerStatefulWidget {
  const EnterpriseOperationsPage({super.key});

  @override
  ConsumerState<EnterpriseOperationsPage> createState() =>
      _EnterpriseOperationsPageState();
}

class _EnterpriseOperationsPageState
    extends ConsumerState<EnterpriseOperationsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  String _type = 'all';
  String _query = '';
  String _sort = 'updated';
  int _page = 0;
  static const _pageSize = 20;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    if (workspace == null) {
      return const EmptyState(
        icon: Icons.add_business_outlined,
        title: 'Select a business',
        message:
            'A business workspace is required to manage enterprise operations.',
      );
    }
    if (!workspace.canRead('enterprise') && !workspace.canRead('integrations')) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Enterprise operations are restricted',
        message: 'Your role does not include permission to view enterprise operations.',
      );
    }
    if (!workspace.isFeatureEnabled('enterprise_operations')) {
      return EmptyState(
        icon: Icons.business_center_outlined,
        title: 'Enable enterprise operations',
        message: 'Loyalty, workforce, approvals, integrations, and SaaS controls are disabled for this workspace.',
        action: FilledButton.icon(
          onPressed: () => context.go('/modules'),
          icon: const Icon(Icons.tune_rounded),
          label: const Text('Open module settings'),
        ),
      );
    }
    final canCreate = workspace.canCreate('enterprise');
    final canUpdate = workspace.canUpdate('enterprise');
    final records = ref.watch(enterpriseRecordsProvider(workspace.businessId));
    final integrations = ref.watch(
      integrationConnectionsProvider(workspace.businessId),
    );
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
                    'Enterprise operations',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Manage tenant-scoped enterprise workflows with auditable status changes and safe provider references.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (canCreate)
              FilledButton.icon(
                onPressed: () => _createRecord(context, workspace.businessId),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New record'),
              ),
          ],
        ),
        const SizedBox(height: 18),
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(
              text: 'Enterprise records',
              icon: Icon(Icons.account_tree_outlined),
            ),
            Tab(
              text: 'Integrations and status',
              icon: Icon(Icons.hub_outlined),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 720,
          child: TabBarView(
            controller: _tabs,
            children: [
              records.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _ErrorPanel(
                  message: 'Could not load enterprise records: $error',
                  onRetry: () => ref.invalidate(
                    enterpriseRecordsProvider(workspace.businessId),
                  ),
                ),
                data: (items) => _buildRecords(
                  context,
                  workspace.businessId,
                  items,
                  canUpdate,
                ),
              ),
              integrations.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _ErrorPanel(
                  message: 'Could not load integrations: $error',
                  onRetry: () => ref.invalidate(
                    integrationConnectionsProvider(workspace.businessId),
                  ),
                ),
                data: (items) => _buildIntegrations(
                  context,
                  workspace.businessId,
                  items,
                  workspace.canUpdate('integrations'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecords(
    BuildContext context,
    String businessId,
    List<EnterpriseRecord> allItems,
    bool canManage,
  ) {
    final filtered = allItems.where((item) {
      if (_type != 'all' && item.recordType != _type) return false;
      final query = _query.trim().toLowerCase();
      return query.isEmpty ||
          item.title.toLowerCase().contains(query) ||
          item.referenceCode.toLowerCase().contains(query) ||
          item.status.toLowerCase().contains(query) ||
          enterpriseRecordTypeLabel(item.recordType)
              .toLowerCase()
              .contains(query);
    }).toList();
    filtered.sort((a, b) {
      if (_sort == 'title')
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      if (_sort == 'status') return a.status.compareTo(b.status);
      if (_sort == 'amount') return b.amount.compareTo(a.amount);
      return b.createdAt.compareTo(a.createdAt);
    });
    final totalPages = pageCountFor(filtered.length, pageSize: _pageSize);
    final page = _page.clamp(0, totalPages - 1);
    final visible = pageItems(filtered, page, pageSize: _pageSize);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('All'),
              selected: _type == 'all',
              onSelected: (_) => setState(() {
                _type = 'all';
                _page = 0;
              }),
            ),
            for (final type in enterpriseRecordTypes)
              ChoiceChip(
                label: Text(type.label),
                selected: _type == type.code,
                onSelected: (_) => setState(() {
                  _type = type.code;
                  _page = 0;
                }),
              ),
          ],
        ),
        const SizedBox(height: 14),
        DataListControls(
          searchLabel: 'Search enterprise records',
          query: _query,
          onSearchChanged: (value) => setState(() {
            _query = value;
            _page = 0;
          }),
          sortOptions: const [
            DataListSortOption('updated', 'Recently created'),
            DataListSortOption('title', 'Title'),
            DataListSortOption('status', 'Status'),
            DataListSortOption('amount', 'Amount'),
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
              icon: Icons.inbox_outlined,
              title: 'No enterprise records',
              message: 'Create a record for a loyalty, staffing, approval, forecast, integration, or SaaS workflow.',
            ),
          )
        else
          for (final item in visible) ...[
            _RecordCard(
              record: item,
              canManage: canManage,
              onTransition: (status) =>
                  _transition(context, businessId, item, status),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _buildIntegrations(
    BuildContext context,
    String businessId,
    List<IntegrationConnection> items,
    bool canManage,
  ) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        AppPanel(
          child: Row(
            children: [
              const Icon(Icons.lock_outline_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Only provider metadata and an opaque secret reference are stored here. API keys and signing secrets must be kept in a server-side secret store.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (canManage)
                FilledButton.icon(
                  onPressed: () => _configureIntegration(context, businessId),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Configure'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(40),
            child: EmptyState(
              icon: Icons.hub_outlined,
              title: 'No integration connections',
              message: 'Add a provider status record when a secure adapter is configured.',
            ),
          )
        else
          for (final item in items) ...[
            AppPanel(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer,
                  child: Icon(
                    Icons.hub_outlined,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                title: Text(item.displayName),
                subtitle: Text(
                  '${integrationProviderLabel(item.providerCode)} · ${item.secretRef == null ? 'No secret reference' : 'Secret reference stored'}${item.lastError == null ? '' : '\n${item.lastError}'}',
                ),
                trailing: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _StatusChip(status: item.status),
                    if (canManage)
                      IconButton(
                        tooltip: 'Update status',
                        onPressed: () => _configureIntegration(
                          context,
                          businessId,
                          existing: item,
                        ),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Future<void> _createRecord(BuildContext context, String businessId) async {
    final draft = await showDialog<_RecordDraft>(
      context: context,
      builder: (_) => const _CreateRecordDialog(),
    );
    if (!mounted || draft == null) return;
    try {
      await ref
          .read(enterpriseRepositoryProvider)
          .createRecord(
            businessId: businessId,
            branchId: ref
                .read(selectedWorkspaceProvider)
                .value
                ?.branches
                .firstOrNull
                ?.id,
            recordType: draft.recordType,
            referenceCode: draft.referenceCode,
            title: draft.title,
            status: draft.status,
            amount: draft.amount,
            payload: draft.payload,
          );
      ref.invalidate(enterpriseRecordsProvider(businessId));
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enterprise record created')),
        );
    } catch (error) {
      if (context.mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _transition(
    BuildContext context,
    String businessId,
    EnterpriseRecord record,
    String status,
  ) async {
    try {
      await ref
          .read(enterpriseRepositoryProvider)
          .transitionRecord(
            businessId: businessId,
            recordId: record.id,
            status: status,
          );
      ref.invalidate(enterpriseRecordsProvider(businessId));
    } catch (error) {
      if (context.mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _configureIntegration(
    BuildContext context,
    String businessId, {
    IntegrationConnection? existing,
  }) async {
    final draft = await showDialog<_IntegrationDraft>(
      context: context,
      builder: (_) => _ConfigureIntegrationDialog(existing: existing),
    );
    if (!mounted || draft == null) return;
    try {
      await ref
          .read(enterpriseRepositoryProvider)
          .upsertIntegration(
            businessId: businessId,
            providerCode: draft.providerCode,
            displayName: draft.displayName,
            status: draft.status,
            secretRef: draft.secretRef,
            config: draft.config,
            lastError: draft.lastError,
          );
      ref.invalidate(integrationConnectionsProvider(businessId));
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Integration status saved')),
        );
    } catch (error) {
      if (context.mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.record,
    required this.canManage,
    required this.onTransition,
  });
  final EnterpriseRecord record;
  final bool canManage;
  final ValueChanged<String> onTransition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppPanel(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(
              Icons.business_center_outlined,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${record.referenceCode} · ${enterpriseRecordTypeLabel(record.recordType)}',
                  style: theme.textTheme.bodySmall,
                ),
                if (record.amount > 0)
                  Text(
                    'Amount ${record.amount.toStringAsFixed(2)}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          _StatusChip(status: record.status),
          if (canManage)
            PopupMenuButton<String>(
              tooltip: 'Change status',
              onSelected: onTransition,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'in_progress', child: Text('In progress')),
                PopupMenuItem(value: 'pending', child: Text('Pending review')),
                PopupMenuItem(value: 'approved', child: Text('Approved')),
                PopupMenuItem(value: 'completed', child: Text('Completed')),
                PopupMenuItem(value: 'disabled', child: Text('Disabled')),
              ],
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
      'completed' || 'approved' || 'verified' || 'active' => Colors.green,
      'cancelled' || 'rejected' || 'error' || 'disabled' => Colors.red,
      'in_progress' || 'pending' || 'configured' || 'verifying' => Colors.blue,
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

class _RecordDraft {
  const _RecordDraft({
    required this.recordType,
    required this.referenceCode,
    required this.title,
    required this.status,
    required this.amount,
    required this.payload,
  });
  final String recordType;
  final String referenceCode;
  final String title;
  final String status;
  final double amount;
  final Map<String, dynamic> payload;
}

class _CreateRecordDialog extends StatefulWidget {
  const _CreateRecordDialog();

  @override
  State<_CreateRecordDialog> createState() => _CreateRecordDialogState();
}

class _CreateRecordDialogState extends State<_CreateRecordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reference = TextEditingController();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _payload = TextEditingController(text: '{}');
  String _type = enterpriseRecordTypes.first.code;
  String _status = 'draft';

  @override
  void dispose() {
    for (final controller in [_reference, _title, _amount, _payload])
      controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New enterprise record'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Record type'),
                  items: [
                    for (final item in enterpriseRecordTypes)
                      DropdownMenuItem(
                        value: item.code,
                        child: Text(item.label),
                      ),
                  ],
                  onChanged: (value) => setState(() => _type = value ?? _type),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reference,
                  decoration: const InputDecoration(
                    labelText: 'Reference code',
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _status,
                        decoration: const InputDecoration(
                          labelText: 'Initial status',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'draft',
                            child: Text('Draft'),
                          ),
                          DropdownMenuItem(
                            value: 'pending',
                            child: Text('Pending'),
                          ),
                          DropdownMenuItem(
                            value: 'active',
                            child: Text('Active'),
                          ),
                          DropdownMenuItem(
                            value: 'planned',
                            child: Text('Planned'),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _status = value ?? _status),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _amount,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Amount (optional)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _payload,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Details JSON object',
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
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(_payload.text.trim());
      if (decoded is! Map) throw const FormatException();
      payload = Map<String, dynamic>.from(decoded);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Details must be a valid JSON object')),
      );
      return;
    }
    Navigator.pop(
      context,
      _RecordDraft(
        recordType: _type,
        referenceCode: _reference.text,
        title: _title.text,
        status: _status,
        amount: amount,
        payload: payload,
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;
}

class _IntegrationDraft {
  const _IntegrationDraft({
    required this.providerCode,
    required this.displayName,
    required this.status,
    required this.secretRef,
    required this.config,
    this.lastError,
  });
  final String providerCode;
  final String displayName;
  final String status;
  final String secretRef;
  final Map<String, dynamic> config;
  final String? lastError;
}

class _ConfigureIntegrationDialog extends StatefulWidget {
  const _ConfigureIntegrationDialog({this.existing});
  final IntegrationConnection? existing;

  @override
  State<_ConfigureIntegrationDialog> createState() =>
      _ConfigureIntegrationDialogState();
}

class _ConfigureIntegrationDialogState
    extends State<_ConfigureIntegrationDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _provider;
  late String _status;
  late final TextEditingController _name;
  late final TextEditingController _secretRef;
  late final TextEditingController _config;
  late final TextEditingController _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _provider = existing?.providerCode ?? integrationProviders.first.code;
    _status = existing?.status ?? 'not_configured';
    _name = TextEditingController(text: existing?.displayName ?? '');
    _secretRef = TextEditingController(text: existing?.secretRef ?? '');
    _config = TextEditingController(
      text: jsonEncode(existing?.config ?? <String, dynamic>{}),
    );
    _error = TextEditingController(text: existing?.lastError ?? '');
  }

  @override
  void dispose() {
    for (final controller in [_name, _secretRef, _config, _error])
      controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'Configure integration'
            : 'Update integration',
      ),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _provider,
                  decoration: const InputDecoration(labelText: 'Provider'),
                  items: [
                    for (final item in integrationProviders)
                      DropdownMenuItem(
                        value: item.code,
                        child: Text(item.label),
                      ),
                  ],
                  onChanged: widget.existing == null
                      ? (value) =>
                            setState(() => _provider = value ?? _provider)
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Connection name',
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(
                      value: 'not_configured',
                      child: Text('Not configured'),
                    ),
                    DropdownMenuItem(
                      value: 'configured',
                      child: Text('Configured'),
                    ),
                    DropdownMenuItem(
                      value: 'verifying',
                      child: Text('Verifying'),
                    ),
                    DropdownMenuItem(
                      value: 'verified',
                      child: Text('Verified'),
                    ),
                    DropdownMenuItem(
                      value: 'disabled',
                      child: Text('Disabled'),
                    ),
                    DropdownMenuItem(value: 'error', child: Text('Error')),
                  ],
                  onChanged: (value) =>
                      setState(() => _status = value ?? _status),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _secretRef,
                  decoration: const InputDecoration(
                    labelText:
                        'Opaque secret reference (never paste an API key)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _config,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Non-secret configuration JSON',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _error,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Last error (optional)',
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
        FilledButton(onPressed: _submit, child: const Text('Save status')),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Map<String, dynamic> config;
    try {
      final decoded = jsonDecode(_config.text.trim());
      if (decoded is! Map) throw const FormatException();
      config = Map<String, dynamic>.from(decoded);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configuration must be a valid JSON object'),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      _IntegrationDraft(
        providerCode: _provider,
        displayName: _name.text,
        status: _status,
        secretRef: _secretRef.text,
        config: config,
        lastError: _error.text,
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => AppPanel(
    child: ListTile(
      leading: const Icon(Icons.error_outline),
      title: const Text('Enterprise data unavailable'),
      subtitle: Text(message),
      trailing: IconButton(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
      ),
    ),
  );
}
