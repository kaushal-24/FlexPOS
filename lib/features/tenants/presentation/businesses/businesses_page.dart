import 'package:flexpos/core/security/crud_permissions.dart';
import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/core/widgets/data_page_skeleton.dart';
import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/features/tenants/data/tenant_repository.dart';
import 'package:flexpos/features/tenants/domain/business_workspace.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BusinessesPage extends ConsumerWidget {
  const BusinessesPage({super.key});

  Future<void> _editBusiness(
    BuildContext context,
    WidgetRef ref,
    BusinessWorkspace workspace,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _BusinessDialog(workspace: workspace),
    );
    if (saved == true) ref.invalidate(workspacesProvider);
  }

  Future<void> _deleteBusiness(
    BuildContext context,
    WidgetRef ref,
    BusinessWorkspace workspace,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete business?'),
        content: Text(
          'Delete “${workspace.businessName}”? It will be removed from your active business list and cannot receive new sales.',
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
          .deleteBusiness(workspace.businessId);
      ref.invalidate(workspacesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Business deleted.')));
      }
    } on PostgrestException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not delete business: ${error.message}'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedWorkspace = ref.watch(selectedWorkspaceProvider).value;
    if (selectedWorkspace != null && !selectedWorkspace.canRead('business')) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Business management is restricted',
        message: 'Your role does not include permission to view businesses.',
      );
    }
    final workspaces = ref.watch(workspacesProvider);
    final selectedId = ref.watch(selectedBusinessIdProvider);
    final canCreateBusiness = selectedWorkspace?.canCreate('business') ?? true;
    return workspaces.when(
      loading: () => const DataPageSkeleton(sectionLabel: 'businesses'),
      error: (error, _) => EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Businesses unavailable',
        message: error.toString(),
        action: FilledButton.icon(
          onPressed: () => ref.invalidate(workspacesProvider),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.add_business_outlined,
            title: 'No active businesses',
            message: 'Create a business workspace to start using FlexPOS.',
            action: FilledButton.icon(
              onPressed: () => context.go('/onboarding'),
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Create business'),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
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
                      'Businesses',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text(
                      '${items.length} active workspace${items.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (canCreateBusiness)
                  FilledButton.icon(
                    onPressed: () => context.go('/onboarding'),
                    icon: const Icon(Icons.add_business_outlined),
                    label: const Text('New business'),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            for (final workspace in items) ...[
              AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          child: Icon(
                            workspace.businessId == selectedId
                                ? Icons.check_rounded
                                : Icons.storefront_outlined,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                workspace.businessName,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${workspace.businessType} • ${workspace.currencyCode} • ${workspace.timezone}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                '${workspace.branches.length} branch(es) • ${workspace.roleName}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (workspace.canManage('business')) ...[
                      const Divider(height: 20),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () =>
                                _editBusiness(context, ref, workspace),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Edit business'),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                _deleteBusiness(context, ref, workspace),
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('Delete'),
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
    );
  }
}

class _BusinessDialog extends ConsumerStatefulWidget {
  const _BusinessDialog({required this.workspace});

  final BusinessWorkspace workspace;

  @override
  ConsumerState<_BusinessDialog> createState() => _BusinessDialogState();
}

class _BusinessDialogState extends ConsumerState<_BusinessDialog> {
  late final TextEditingController _name;
  late String _businessType;
  late String _currency;
  late String _timezone;
  late String _country;
  bool _saving = false;

  static const _businessTypes = {
    'retail': 'Retail store',
    'grocery': 'Supermarket or grocery',
    'restaurant': 'Restaurant, cafe, or bakery',
    'wholesale': 'Wholesale distributor',
    'fashion': 'Clothing and fashion',
    'electronics': 'Electronics and mobile',
    'hardware': 'Hardware and electrical',
    'auto_parts': 'Auto parts',
    'salon': 'Salon or beauty service',
    'service': 'Repair or service center',
    'pharmacy': 'Pharmacy',
    'warehouse': 'Warehouse',
    'manufacturing': 'Manufacturing or assembly',
    'other': 'Other business',
  };

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.workspace.businessName);
    _businessType = widget.workspace.businessType;
    _currency = widget.workspace.currencyCode;
    _timezone = widget.workspace.timezone;
    _country = widget.workspace.countryCode ?? 'IN';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(tenantRepositoryProvider)
          .updateBusiness(
            businessId: widget.workspace.businessId,
            name: _name.text,
            businessType: _businessType,
            currencyCode: _currency,
            timezone: _timezone,
            countryCode: _country,
          );
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not update business: ${error.message}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit business'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Business name',
                prefixIcon: Icon(Icons.storefront_outlined),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _businessType,
              decoration: const InputDecoration(labelText: 'Business type'),
              items: _businessTypes.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _businessType = value!),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _currency,
                    decoration: const InputDecoration(labelText: 'Currency'),
                    items: const [
                      DropdownMenuItem(value: 'INR', child: Text('INR')),
                      DropdownMenuItem(value: 'USD', child: Text('USD')),
                      DropdownMenuItem(value: 'AED', child: Text('AED')),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _currency = value!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _country,
                    decoration: const InputDecoration(labelText: 'Country'),
                    items: const [
                      DropdownMenuItem(value: 'IN', child: Text('India')),
                      DropdownMenuItem(
                        value: 'US',
                        child: Text('United States'),
                      ),
                      DropdownMenuItem(
                        value: 'AE',
                        child: Text('United Arab Emirates'),
                      ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _country = value!),
                  ),
                ),
              ],
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
                DropdownMenuItem(
                  value: 'Asia/Dubai',
                  child: Text('Asia/Dubai'),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _timezone = value!),
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
