import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/core/security/crud_permissions.dart';
import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/features/tenants/domain/feature_entitlement.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    if (workspace == null) {
      return const EmptyState(
        icon: Icons.add_business_outlined,
        title: 'Select a business',
        message: 'A business workspace is required to view its modules.',
      );
    }
    final modules = [
      if (workspace.canRead('customers'))
        (Icons.people_alt_outlined, 'Customers', '/customers'),
      if (workspace.isFeatureEnabled(FeatureCodes.crm) &&
          workspace.canRead('crm'))
        (Icons.handshake_outlined, 'CRM', '/crm'),
      if (workspace.isFeatureEnabled(FeatureCodes.purchasing) &&
          workspace.canRead('purchases'))
        (
          Icons.shopping_cart_checkout_outlined,
          'Suppliers and purchases',
          '/purchases',
        ),
      if (workspace.canRead('expenses'))
        (Icons.receipt_long_outlined, 'Expenses', '/expenses'),
      if (workspace.canRead('accounting'))
        (Icons.account_balance_outlined, 'Accounting and tax', '/accounting'),
      if (workspace.canRead('reports'))
        (Icons.insights_outlined, 'Reports and analytics', '/reports'),
      if (workspace.canRead('sales'))
        (Icons.local_offer_outlined, 'Coupons and promotions', '/promotions'),
      if (workspace.isFeatureEnabled(FeatureCodes.registers) &&
          workspace.canRead('registers'))
        (Icons.point_of_sale_outlined, 'Registers and shifts', '/registers'),
      if (workspace.canRead('branches'))
        (Icons.account_tree_outlined, 'Branches', '/branches'),
      if (workspace.isFeatureEnabled(FeatureCodes.inventory) &&
          workspace.canRead('inventory') &&
          workspace.roleName.trim().toLowerCase() != 'cashier')
        (Icons.warehouse_outlined, 'Warehouses', '/warehouses'),
      if (workspace.canRead('business'))
        (Icons.storefront_outlined, 'Businesses', '/businesses'),
      if (workspace.canRead('staff') || workspace.canRead('roles'))
        (Icons.groups_2_outlined, 'Staff and permissions', '/access-control'),
      if (workspace.canRead('audit'))
        (Icons.history_rounded, 'Audit log', '/audit-log'),
      if (workspace.canManage('business'))
        (Icons.tune_rounded, 'Module settings', '/modules'),
      if ((workspace.canRead('industry') || workspace.canManage('industry')) &&
          workspace.enabledFeatureCodes.any(FeatureCodes.isIndustryOperations))
        (
          Icons.account_tree_outlined,
          'Industry operations',
          '/industry-operations',
        ),
      if (workspace.isFeatureEnabled(FeatureCodes.enterpriseOperations) &&
          (workspace.canRead('enterprise') ||
              workspace.canManage('enterprise') ||
              workspace.canRead('integrations')))
        (
          Icons.business_center_outlined,
          'Enterprise operations',
          '/enterprise-operations',
        ),
      if (workspace.isFeatureEnabled(FeatureCodes.hardwareOperations) &&
          (workspace.canRead('hardware') || workspace.canManage('hardware')))
        (Icons.devices_other_outlined, 'Hardware operations', '/hardware'),
      if (workspace.canManage('business'))
        (
          Icons.receipt_long_rounded,
          'Business receipt settings',
          '/business-settings',
        ),
      if (workspace.canRead('platform_admin'))
        (
          Icons.admin_panel_settings_outlined,
          'Platform administration',
          '/platform-admin',
        ),
      if (workspace.canManage('products'))
        (Icons.category_outlined, 'Catalog tools', '/catalog-management'),
    ];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('More modules', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Manage the operational structure and access to this business.',
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 22),
        for (final module in modules) ...[
          AppPanel(
            onTap: () => context.go(module.$3),
            child: Row(
              children: [
                Icon(module.$1, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    module.$2,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
