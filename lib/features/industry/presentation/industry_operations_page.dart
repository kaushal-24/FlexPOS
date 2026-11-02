import 'dart:convert';

import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/core/security/crud_permissions.dart';
import 'package:flexpos/core/widgets/data_list_controls.dart';
import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/features/industry/data/industry_repository.dart';
import 'package:flexpos/features/industry/domain/industry_workflow.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class IndustryOperationsPage extends ConsumerStatefulWidget {
  const IndustryOperationsPage({super.key});

  @override
  ConsumerState<IndustryOperationsPage> createState() =>
      _IndustryOperationsPageState();
}

class _IndustryOperationsPageState
    extends ConsumerState<IndustryOperationsPage> {
  String? _selectedModule;
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
        message:
            'A business workspace is required to manage industry operations.',
      );
    }
    if (!workspace.canRead('industry')) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Industry operations are restricted',
        message: 'Your role does not include permission to view industry workflows.',
      );
    }
    final modules = industryModuleDefinitions
        .where((module) => workspace.isFeatureEnabled(module.code))
        .toList(growable: false);
    final canCreate = workspace.canCreate('industry');
    final canUpdate = workspace.canUpdate('industry');
    if (modules.isEmpty) {
      return EmptyState(
        icon: Icons.extension_outlined,
        title: 'Enable an industry module',
        message: 'Industry workflows are disabled for this workspace. Enable the modules that match your business type from Module settings.',
        action: FilledButton.icon(
          onPressed: () => context.go('/modules'),
          icon: const Icon(Icons.tune_rounded),
          label: const Text('Open module settings'),
        ),
      );
    }
    final selected = modules.any((module) => module.code == _selectedModule)
        ? _selectedModule!
        : modules.first.code;
    if (_selectedModule != selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedModule = selected);
      });
    }
    final workflows = ref.watch(
      industryWorkflowsProvider(workspace.businessId),
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
                    'Industry operations',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Run typed workflows for your enabled industry modules. Every status change is recorded for audit and branch reporting.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (canCreate)
              FilledButton.icon(
                onPressed: () =>
                    _createWorkflow(context, workspace.businessId, selected),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New workflow'),
              ),
          ],
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final module in modules)
              ChoiceChip(
                selected: module.code == selected,
                onSelected: (_) => setState(() {
                  _selectedModule = module.code;
                  _page = 0;
                  _query = '';
                }),
                avatar: const Icon(Icons.account_tree_outlined, size: 18),
                label: Text(module.name),
              ),
          ],
        ),
        const SizedBox(height: 18),
        AppPanel(
          child: Row(
            children: [
              const Icon(Icons.account_tree_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  modules
                      .firstWhere((item) => item.code == selected)
                      .description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              IconButton(
                tooltip: 'Refresh workflows',
                onPressed: () => ref.invalidate(
                  industryWorkflowsProvider(workspace.businessId),
                ),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        workflows.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(48),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error, _) => AppPanel(
            child: ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Could not load industry workflows'),
              subtitle: Text('$error'),
              trailing: IconButton(
                tooltip: 'Retry',
                onPressed: () => ref.invalidate(
                  industryWorkflowsProvider(workspace.businessId),
                ),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
          ),
          data: (items) => _buildWorkflowList(
            context,
            workspace.businessId,
            selected,
            items,
            canUpdate,
          ),
        ),
      ],
    );
  }

  Widget _buildWorkflowList(
    BuildContext context,
    String businessId,
    String moduleCode,
    List<IndustryWorkflow> allItems,
    bool canUpdate,
  ) {
    final filtered = allItems.where((item) {
      if (item.moduleCode != moduleCode) return false;
      final query = _query.trim().toLowerCase();
      return query.isEmpty ||
          item.title.toLowerCase().contains(query) ||
          item.referenceCode.toLowerCase().contains(query) ||
          industryKindLabel(item.workflowKind).toLowerCase().contains(query) ||
          item.status.toLowerCase().contains(query);
    }).toList();
    filtered.sort((a, b) {
      if (_sort == 'title') {
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
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
        DataListControls(
          searchLabel: 'Search workflows',
          query: _query,
          onSearchChanged: (value) => setState(() {
            _query = value;
            _page = 0;
          }),
          sortOptions: const [
            DataListSortOption('updated', 'Recently created'),
            DataListSortOption('title', 'Title'),
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
              icon: Icons.inbox_outlined,
              title: 'No workflows yet',
              message:
                  'Create the first typed workflow for this industry module.',
            ),
          )
        else
          for (final workflow in visible) ...[
            _WorkflowCard(
              workflow: workflow,
              canUpdate: canUpdate,
              onTransition: (status) =>
                  _transition(context, businessId, workflow, status),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Future<void> _createWorkflow(
    BuildContext context,
    String businessId,
    String moduleCode,
  ) async {
    final module = industryModuleDefinitions.firstWhere(
      (item) => item.code == moduleCode,
    );
    final values = await showDialog<_WorkflowDraft>(
      context: context,
      builder: (_) => _CreateWorkflowDialog(module: module),
    );
    if (!mounted || values == null) return;
    try {
      await ref
          .read(industryRepositoryProvider)
          .createWorkflow(
            businessId: businessId,
            branchId: ref
                .read(selectedWorkspaceProvider)
                .value
                ?.branches
                .firstOrNull
                ?.id,
            kind: values.kind,
            referenceCode: values.referenceCode,
            title: values.title,
            status: values.status,
            payload: values.payload,
            quantity: values.quantity,
            unitPrice: values.unitPrice,
            totalAmount: values.totalAmount,
            depositAmount: values.depositAmount,
          );
      ref.invalidate(industryWorkflowsProvider(businessId));
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Workflow created')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _transition(
    BuildContext context,
    String businessId,
    IndustryWorkflow workflow,
    String status,
  ) async {
    try {
      await ref
          .read(industryRepositoryProvider)
          .transitionWorkflow(
            businessId: businessId,
            workflowId: workflow.id,
            status: status,
          );
      ref.invalidate(industryWorkflowsProvider(businessId));
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

class _WorkflowCard extends StatelessWidget {
  const _WorkflowCard({
    required this.workflow,
    required this.canUpdate,
    required this.onTransition,
  });

  final IndustryWorkflow workflow;
  final bool canUpdate;
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
              Icons.work_outline_rounded,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workflow.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${workflow.referenceCode} · ${industryKindLabel(workflow.workflowKind)}',
                  style: theme.textTheme.bodySmall,
                ),
                if (workflow.totalAmount > 0 || workflow.depositAmount > 0)
                  Text(
                    'Total ${workflow.totalAmount.toStringAsFixed(2)} · Deposit ${workflow.depositAmount.toStringAsFixed(2)}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          _StatusChip(status: workflow.status),
          if (canUpdate)
            PopupMenuButton<String>(
              tooltip: 'Change status',
              onSelected: onTransition,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'in_progress', child: Text('In progress')),
                PopupMenuItem(value: 'ready', child: Text('Ready')),
                PopupMenuItem(value: 'completed', child: Text('Completed')),
                PopupMenuItem(value: 'cancelled', child: Text('Cancelled')),
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
      'completed' || 'paid' || 'received' => Colors.green,
      'cancelled' || 'rejected' || 'damaged' => Colors.red,
      'in_progress' || 'ready' || 'confirmed' => Colors.blue,
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

class _WorkflowDraft {
  const _WorkflowDraft({
    required this.kind,
    required this.referenceCode,
    required this.title,
    required this.status,
    required this.payload,
    this.quantity = 0,
    this.unitPrice = 0,
    this.totalAmount = 0,
    this.depositAmount = 0,
  });

  final String kind;
  final String referenceCode;
  final String title;
  final String status;
  final Map<String, dynamic> payload;
  final double quantity;
  final double unitPrice;
  final double totalAmount;
  final double depositAmount;
}

class _CreateWorkflowDialog extends StatefulWidget {
  const _CreateWorkflowDialog({required this.module});
  final IndustryModuleDefinition module;

  @override
  State<_CreateWorkflowDialog> createState() => _CreateWorkflowDialogState();
}

class _CreateWorkflowDialogState extends State<_CreateWorkflowDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reference = TextEditingController();
  final _title = TextEditingController();
  final _payload = TextEditingController(text: '{}');
  final _quantity = TextEditingController(text: '0');
  final _unitPrice = TextEditingController(text: '0');
  final _total = TextEditingController(text: '0');
  final _deposit = TextEditingController(text: '0');
  late String _kind;
  String _status = 'draft';

  @override
  void initState() {
    super.initState();
    _kind = widget.module.kinds.first.value;
  }

  @override
  void dispose() {
    for (final controller in [
      _reference,
      _title,
      _payload,
      _quantity,
      _unitPrice,
      _total,
      _deposit,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('New ${widget.module.name} workflow'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _kind,
                  decoration: const InputDecoration(labelText: 'Workflow type'),
                  items: [
                    for (final kind in widget.module.kinds)
                      DropdownMenuItem(
                        value: kind.value,
                        child: Text(kind.label),
                      ),
                  ],
                  onChanged: (value) => setState(() => _kind = value ?? _kind),
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
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Initial status',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'draft', child: Text('Draft')),
                    DropdownMenuItem(value: 'planned', child: Text('Planned')),
                    DropdownMenuItem(value: 'open', child: Text('Open')),
                    DropdownMenuItem(
                      value: 'confirmed',
                      child: Text('Confirmed'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _status = value ?? _status),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _quantity,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Quantity',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _unitPrice,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Unit price',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _total,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Total amount',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _deposit,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Deposit'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _payload,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Details (JSON)',
                    alignLabelWithHint: true,
                  ),
                  validator: (value) {
                    try {
                      final decoded = jsonDecode(value ?? '{}');
                      if (decoded is! Map) return 'Use a JSON object';
                    } catch (_) {
                      return 'Enter valid JSON';
                    }
                    return null;
                  },
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

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Map<String, dynamic> payload;
    try {
      payload = Map<String, dynamic>.from(jsonDecode(_payload.text) as Map);
    } catch (_) {
      payload = const {};
    }
    double parse(TextEditingController controller) =>
        double.tryParse(controller.text.trim()) ?? 0;
    Navigator.pop(
      context,
      _WorkflowDraft(
        kind: _kind,
        referenceCode: _reference.text,
        title: _title.text,
        status: _status,
        payload: payload,
        quantity: parse(_quantity),
        unitPrice: parse(_unitPrice),
        totalAmount: parse(_total),
        depositAmount: parse(_deposit),
      ),
    );
  }
}
