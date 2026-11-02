import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/core/widgets/data_page_skeleton.dart';
import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/features/tenants/domain/business_workspace.dart';
import 'package:flexpos/features/tenants/domain/feature_entitlement.dart';
import 'package:flexpos/features/tenants/data/tenant_repository.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flexpos/core/security/crud_permissions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FeatureEntitlementsPage extends ConsumerStatefulWidget {
  const FeatureEntitlementsPage({super.key});

  @override
  ConsumerState<FeatureEntitlementsPage> createState() =>
      _FeatureEntitlementsPageState();
}

class _FeatureEntitlementsPageState
    extends ConsumerState<FeatureEntitlementsPage> {
  final Set<String> _saving = {};

  Future<void> _setEnabled(
    BusinessWorkspace workspace,
    BusinessFeatureEntitlement feature,
    bool enabled,
  ) async {
    setState(() => _saving.add(feature.code));
    try {
      await ref
          .read(tenantRepositoryProvider)
          .setFeatureEntitlement(
            businessId: workspace.businessId,
            moduleCode: feature.code,
            enabled: enabled,
          );
      ref.invalidate(featureEntitlementsProvider(workspace.businessId));
      ref.invalidate(workspacesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${feature.name} ${enabled ? 'enabled' : 'disabled'}.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update module: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving.remove(feature.code));
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    if (workspace == null) {
      return const EmptyState(
        icon: Icons.add_business_outlined,
        title: 'Select a business',
        message: 'A business workspace is required to configure modules.',
      );
    }
    if (!workspace.canManage('business')) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Module settings are restricted',
        message: 'Your role cannot change business module settings.',
      );
    }

    final entitlements = ref.watch(
      featureEntitlementsProvider(workspace.businessId),
    );
    return entitlements.when(
      loading: () => const DataPageSkeleton(sectionLabel: 'module settings'),
      error: (error, _) => EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load module settings',
        message: error.toString(),
        action: FilledButton.icon(
          onPressed: () =>
              ref.invalidate(featureEntitlementsProvider(workspace.businessId)),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      ),
      data: (features) => _FeatureEntitlementsContent(
        workspace: workspace,
        features: features,
        saving: _saving,
        onChanged: (feature, value) => _setEnabled(workspace, feature, value),
      ),
    );
  }
}

class _FeatureEntitlementsContent extends StatelessWidget {
  const _FeatureEntitlementsContent({
    required this.workspace,
    required this.features,
    required this.saving,
    required this.onChanged,
  });

  final BusinessWorkspace workspace;
  final List<BusinessFeatureEntitlement> features;
  final Set<String> saving;
  final void Function(BusinessFeatureEntitlement feature, bool enabled)
  onChanged;

  @override
  Widget build(BuildContext context) {
    final core = features.where((feature) => feature.isCore).toList();
    final optional = features.where((feature) => !feature.isCore).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
      children: [
        Text(
          'Module settings',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'Modules for ${workspace.businessName} are initialized from the '
          '${_businessTypeLabel(workspace.businessType)} profile. Core modules '
          'stay enabled; optional operations can be tailored here.',
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        _Section(
          title: 'Core platform',
          description: 'Required for secure day-to-day FlexPOS operation.',
          features: core,
          saving: saving,
          onChanged: onChanged,
        ),
        const SizedBox(height: 24),
        _Section(
          title: 'Optional operations',
          description: 'Disabled modules disappear from navigation and are rejected by server-side permission checks.',
          features: optional,
          saving: saving,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.description,
    required this.features,
    required this.saving,
    required this.onChanged,
  });

  final String title;
  final String description;
  final List<BusinessFeatureEntitlement> features;
  final Set<String> saving;
  final void Function(BusinessFeatureEntitlement feature, bool enabled)
  onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          description,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        for (final feature in features) ...[
          AppPanel(
            child: Row(
              children: [
                Icon(
                  feature.isCore
                      ? Icons.verified_user_outlined
                      : Icons.extension_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        feature.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        feature.description,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (saving.contains(feature.code))
                  const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Semantics(
                    label: '${feature.name} module',
                    child: Switch(
                      value: feature.isEnabled,
                      onChanged: feature.isCore
                          ? null
                          : (value) => onChanged(feature, value),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

String _businessTypeLabel(String value) => switch (value) {
  'auto_parts' => 'auto parts',
  _ => value.replaceAll('_', ' '),
};
