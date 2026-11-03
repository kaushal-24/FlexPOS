import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/core/security/crud_permissions.dart';
import 'package:flexpos/core/widgets/data_page_skeleton.dart';
import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/core/widgets/data_list_controls.dart';
import 'package:flexpos/features/tenants/data/tenant_repository.dart';
import 'package:flexpos/features/tenants/domain/business_workspace.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BranchManagementPage extends ConsumerWidget {
  const BranchManagementPage({super.key});

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    BusinessWorkspace workspace, [
    BusinessBranch? branch,
  ]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _BranchDialog(workspace: workspace, branch: branch),
    );
    if (saved == true) ref.invalidate(workspacesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(selectedWorkspaceProvider)
        .when(
          loading: () => const DataPageSkeleton(sectionLabel: 'branches'),
          error: (error, _) => EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Branches unavailable',
            message: error.toString(),
          ),
          data: (workspace) {
            if (workspace == null) {
              return EmptyState(
                icon: Icons.add_business_outlined,
                title: 'Create a business first',
                message: 'Every branch belongs to a business workspace.',
                action: FilledButton(
                  onPressed: () => context.go('/onboarding'),
                  child: const Text('Create business'),
                ),
              );
            }
            final canCreate = workspace.canCreate('branches');
            final canUpdate = workspace.canUpdate('branches');
            final canDelete = workspace.canDelete('branches');
            final canManage = canCreate || canUpdate || canDelete;
            var query = '';
            var sort = 'name';
            var page = 0;
            final selected = <String>{};
            return StatefulBuilder(
              builder: (context, setState) {
                final filtered = workspace.branches
                    .where(
                      (branch) =>
                          '${branch.name} ${branch.code} ${branch.timezone}'
                              .toLowerCase()
                              .contains(query),
                    )
                    .toList();
                filtered.sort((a, b) {
                  final comparison = a.name.toLowerCase().compareTo(
                    b.name.toLowerCase(),
                  );
                  return sort == 'name_desc' ? -comparison : comparison;
                });
                final pageCount = pageCountFor(filtered.length);
                if (page >= pageCount) page = pageCount - 1;
                final visible = pageItems(filtered, page);
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
                            Text(
                              'Branches',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            Text(
                              '${workspace.businessName} • ${workspace.branches.length} active branch(es)',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                        if (canCreate)
                          FilledButton.icon(
                            onPressed: () =>
                                _openEditor(context, ref, workspace),
                            icon: const Icon(Icons.add_location_alt_outlined),
                            label: const Text('Add branch'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    DataListControls(
                      query: query,
                      onSearchChanged: (value) => setState(() {
                        query = value.trim().toLowerCase();
                        page = 0;
                      }),
                      searchLabel: 'Search branch name, code, or timezone',
                      sortValue: sort,
                      sortOptions: const [
                        DataListSortOption('name', 'Name A–Z'),
                        DataListSortOption('name_desc', 'Name Z–A'),
                      ],
                      onSortChanged: (value) => setState(() {
                        sort = value;
                        page = 0;
                      }),
                      page: page,
                      pageCount: pageCount,
                      totalCount: filtered.length,
                      onPageChanged: (value) => setState(() => page = value),
                      selectedCount: selected.length,
                      allSelected:
                          visible.isNotEmpty &&
                          visible.every(
                            (branch) => selected.contains(branch.id),
                          ),
                      onSelectAll: visible.isEmpty
                          ? null
                          : (value) => setState(() {
                              if (value ?? false) {
                                selected.addAll(
                                  visible.map((branch) => branch.id),
                                );
                              } else {
                                selected.removeAll(
                                  visible.map((branch) => branch.id),
                                );
                              }
                            }),
                      onClearSelection: () => setState(selected.clear),
                      bulkActions: [
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(
                                text: workspace.branches
                                    .where(
                                      (branch) => selected.contains(branch.id),
                                    )
                                    .map(
                                      (branch) =>
                                          '${branch.name}\t${branch.code}',
                                    )
                                    .join('\n'),
                              ),
                            );
                            setState(selected.clear);
                          },
                          icon: const Icon(Icons.copy_all_rounded),
                          label: const Text('Copy branches'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    for (final branch in visible) ...[
                      AppPanel(
                        onTap: canUpdate
                            ? () => _openEditor(context, ref, workspace, branch)
                            : null,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Checkbox(
                                  value: selected.contains(branch.id),
                                  onChanged: (value) => setState(() {
                                    if (value ?? false) {
                                      selected.add(branch.id);
                                    } else {
                                      selected.remove(branch.id);
                                    }
                                  }),
                                ),
                                const CircleAvatar(
                                  child: Icon(Icons.store_outlined),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        branch.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      Text(
                                        '${branch.code} • ${branch.timezone}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (canManage) ...[
                              const Divider(height: 20),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (canUpdate)
                                    OutlinedButton.icon(
                                      onPressed: () => _openEditor(
                                        context,
                                        ref,
                                        workspace,
                                        branch,
                                      ),
                                      icon: const Icon(Icons.edit_outlined),
                                      label: const Text('Edit branch'),
                                    ),
                                  if (canDelete)
                                    TextButton.icon(
                                      onPressed: () =>
                                          _deleteBranch(context, ref, branch),
                                      icon: const Icon(Icons.delete_outline_rounded),
                                      label: const Text('Delete'),
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
              },
            );
          },
        );
  }

  Future<void> _deleteBranch(
    BuildContext context,
    WidgetRef ref,
    BusinessBranch branch,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete branch?'),
        content: Text(
          'Delete “${branch.name}”? It will no longer be available for new operations.',
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
      await ref
          .read(tenantRepositoryProvider)
          .updateBranch(
            branchId: branch.id,
            name: branch.name,
            code: branch.code,
            timezone: branch.timezone,
            isActive: false,
          );
      ref.invalidate(workspacesProvider);
    } on PostgrestException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete branch: ${error.message}')),
        );
      }
    }
  }
}

class _BranchDialog extends ConsumerStatefulWidget {
  const _BranchDialog({required this.workspace, this.branch});
  final BusinessWorkspace workspace;
  final BusinessBranch? branch;
  @override
  ConsumerState<_BranchDialog> createState() => _BranchDialogState();
}

class _BranchDialogState extends ConsumerState<_BranchDialog> {
  late final TextEditingController _name;
  late final TextEditingController _code;
  late String _timezone;
  bool _active = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.branch?.name);
    _code = TextEditingController(text: widget.branch?.code);
    _timezone = widget.branch?.timezone ?? widget.workspace.timezone;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) return _error('Enter a branch name.');
    if (!RegExp(r'^[A-Za-z0-9-]{1,16}$').hasMatch(_code.text.trim())) {
      return _error('Use 1–16 letters, numbers, or hyphens for the code.');
    }
    setState(() => _saving = true);
    try {
      final repository = ref.read(tenantRepositoryProvider);
      if (widget.branch == null) {
        await repository.createBranch(
          businessId: widget.workspace.businessId,
          name: _name.text,
          code: _code.text,
          timezone: _timezone,
          countryCode: widget.workspace.countryCode ?? 'IN',
        );
      } else {
        await repository.updateBranch(
          branchId: widget.branch!.id,
          name: _name.text,
          code: _code.text,
          timezone: _timezone,
          isActive: _active,
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.branch == null ? 'Add branch' : 'Edit branch'),
    content: SizedBox(
      width: 500,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Branch name'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _code,
            decoration: const InputDecoration(labelText: 'Branch code'),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _timezone,
            decoration: const InputDecoration(labelText: 'Timezone'),
            items: const [
              DropdownMenuItem(
                value: 'Asia/Kolkata',
                child: Text('Asia/Kolkata (IST)'),
              ),
              DropdownMenuItem(value: 'UTC', child: Text('UTC')),
              DropdownMenuItem(value: 'Asia/Dubai', child: Text('Asia/Dubai')),
            ],
            onChanged: (value) => setState(() => _timezone = value!),
          ),
          if (widget.branch != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              title: const Text('Branch active'),
              onChanged: (value) => setState(() => _active = value),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save branch'),
      ),
    ],
  );
}
