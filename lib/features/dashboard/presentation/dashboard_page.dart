import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/core/security/crud_permissions.dart';
import 'package:flexpos/core/widgets/data_page_skeleton.dart';
import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/core/widgets/status_badge.dart';
import 'package:flexpos/core/utils/money.dart';
import 'package:flexpos/features/auth/data/auth_repository.dart';
import 'package:flexpos/features/accounting/data/accounting_repository.dart';
import 'package:flexpos/features/accounting/domain/accounting_models.dart';
import 'package:flexpos/features/tenants/domain/business_workspace.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authRepositoryProvider).currentUser;
    final workspace = ref.watch(selectedWorkspaceProvider);
    return workspace.when(
      loading: () => const DataPageSkeleton(sectionLabel: 'dashboard'),
      error: (error, _) => EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load your workspace',
        message: error.toString(),
        action: FilledButton.icon(
          onPressed: () => ref.invalidate(workspacesProvider),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      ),
      data: (value) {
        if (value == null) {
          return EmptyState(
            icon: Icons.add_business_outlined,
            title: 'Create your first business',
            message:
                'Set up a business and its first branch to unlock your secure '
                'tenant workspace.',
            action: Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => context.go('/onboarding'),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Create business'),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.go('/join-business'),
                  icon: const Icon(Icons.mark_email_read_outlined),
                  label: const Text('Use invitation'),
                ),
              ],
            ),
          );
        }
        return _WorkspaceDashboard(workspace: value, email: user?.email);
      },
    );
  }
}

class _WorkspaceDashboard extends ConsumerWidget {
  const _WorkspaceDashboard({required this.workspace, this.email});

  final BusinessWorkspace workspace;
  final String? email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportPeriod = ReportPeriod.lastDays(30);
    final canViewReports = workspace.canRead('reports');
    final dashboard = canViewReports
        ? ref.watch(accountingDashboardProvider(reportPeriod))
        : null;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome${email == null ? '' : ', ${email!.split('@').first}'}',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '${workspace.businessName} is secured by tenant-aware roles '
                  'and row-level access policies.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: AppPanel(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 28,
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      runAlignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 36,
                      runSpacing: 24,
                      children: [
                        _WorkspaceFact(
                          icon: Icons.badge_outlined,
                          label: 'Role',
                          value: workspace.roleName,
                        ),
                        _WorkspaceFact(
                          icon: Icons.location_on_outlined,
                          label: 'Branches',
                          value: workspace.branches.length.toString(),
                        ),
                        _WorkspaceFact(
                          icon: Icons.payments_outlined,
                          label: 'Currency',
                          value: workspace.currencyCode,
                        ),
                        _WorkspaceFact(
                          icon: Icons.schedule_outlined,
                          label: 'Timezone',
                          value: workspace.timezone,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (canViewReports)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            sliver: SliverToBoxAdapter(
              child: _DashboardMetrics(
                dashboard: dashboard,
                currencyCode: workspace.currencyCode,
                onRetry: () =>
                    ref.invalidate(accountingDashboardProvider(reportPeriod)),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          sliver: SliverToBoxAdapter(
            child: _DashboardQuickActions(workspace: workspace),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.crossAxisExtent >= 1100
                  ? 4
                  : constraints.crossAxisExtent >= 620
                  ? 2
                  : 1;
              return SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  mainAxisExtent: 164,
                ),
                delegate: SliverChildListDelegate.fixed(const [
                  _FoundationCard(
                    icon: Icons.cloud_done_outlined,
                    title: 'Supabase',
                    detail: 'Connected with PKCE sessions',
                    badge: 'Connected',
                    tone: StatusTone.success,
                  ),
                  _FoundationCard(
                    icon: Icons.security_outlined,
                    title: 'Tenant security',
                    detail: 'Businesses, branches, roles, membership, and RLS',
                    badge: 'Secured',
                    tone: StatusTone.success,
                  ),
                  _FoundationCard(
                    icon: Icons.palette_outlined,
                    title: 'Design system',
                    detail: 'Responsive Material 3, light and dark modes',
                    badge: 'Ready',
                    tone: StatusTone.success,
                  ),
                  _FoundationCard(
                    icon: Icons.language_outlined,
                    title: 'Localization',
                    detail: 'English and Hindi resource architecture',
                    badge: 'Ready',
                    tone: StatusTone.success,
                  ),
                ]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DashboardMetrics extends StatelessWidget {
  const _DashboardMetrics({
    required this.dashboard,
    required this.currencyCode,
    required this.onRetry,
  });

  final AsyncValue<AccountingDashboard>? dashboard;
  final String currencyCode;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final value = dashboard;
    if (value == null) return const SizedBox.shrink();
    return value.when(
      loading: () => const AppPanel(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, _) => AppPanel(
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined),
            const SizedBox(width: 12),
            Expanded(child: Text('Could not load dashboard KPIs: $error')),
            IconButton(
              tooltip: 'Retry dashboard KPIs',
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ),
      data: (data) {
        final cards = [
          _DashboardKpi(
            icon: Icons.trending_up_rounded,
            label: 'Net sales · 30 days',
            value: formatMoney(currencyCode, data.salesTotalMinor),
            detail: '${data.orderCount} completed orders',
          ),
          _DashboardKpi(
            icon: Icons.insights_outlined,
            label: 'Gross profit',
            value: data.grossProfitMinor == null
                ? '—'
                : formatMoney(currencyCode, data.grossProfitMinor!),
            detail: 'Before operating expenses',
          ),
          _DashboardKpi(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Customer dues',
            value: formatMoney(currencyCode, data.outstandingReceivablesMinor),
            detail: 'Outstanding receivables',
          ),
          _DashboardKpi(
            icon: Icons.inventory_2_outlined,
            label: 'Low stock',
            value: data.lowStockCount.toString(),
            detail: 'Items at reorder point',
          ),
          _DashboardKpi(
            icon: Icons.receipt_long_outlined,
            label: 'Tax collected',
            value: formatMoney(currencyCode, data.taxTotalMinor),
            detail: 'Included in completed sales',
          ),
          _DashboardKpi(
            icon: Icons.payments_outlined,
            label: 'Expenses',
            value: formatMoney(currencyCode, data.expensesTotalMinor),
            detail: 'Net of reversals',
          ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Business snapshot',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1000
                    ? 3
                    : constraints.maxWidth >= 620
                    ? 2
                    : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: cards.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent: 120,
                  ),
                  itemBuilder: (_, index) => cards[index],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _DashboardKpi extends StatelessWidget {
  const _DashboardKpi({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) => AppPanel(
    child: Row(
      children: [
        CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
          child: Icon(icon),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
}

class _DashboardQuickActions extends StatelessWidget {
  const _DashboardQuickActions({required this.workspace});

  final BusinessWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    final actions = <({IconData icon, String label, String route})>[
      if (workspace.canRead('sales'))
        (icon: Icons.point_of_sale_rounded, label: 'Open POS', route: '/pos'),
      if (workspace.canCreate('products'))
        (
          icon: Icons.add_box_outlined,
          label: 'New product',
          route: '/products',
        ),
      if (workspace.canUpdate('inventory'))
        (
          icon: Icons.inventory_2_outlined,
          label: 'Adjust stock',
          route: '/inventory',
        ),
      if (workspace.canRead('sales'))
        (
          icon: Icons.receipt_long_outlined,
          label: 'View orders',
          route: '/orders',
        ),
      if (workspace.canCreate('customers'))
        (
          icon: Icons.person_add_alt_1_outlined,
          label: 'New customer',
          route: '/customers',
        ),
      if (workspace.canRead('reports'))
        (
          icon: Icons.insights_outlined,
          label: 'Open reports',
          route: '/reports',
        ),
      if (workspace.canCreate('purchases'))
        (
          icon: Icons.local_shipping_outlined,
          label: 'New purchase',
          route: '/purchases',
        ),
      if (workspace.canCreate('expenses'))
        (
          icon: Icons.payments_outlined,
          label: 'Add expense',
          route: '/expenses',
        ),
      if (workspace.canRead('staff'))
        (
          icon: Icons.manage_accounts_outlined,
          label: 'Manage staff',
          route: '/access-control',
        ),
    ];
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Quick actions',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final action in actions)
                FilledButton.tonalIcon(
                  onPressed: () => context.go(action.route),
                  icon: Icon(action.icon),
                  label: Text(action.label),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${workspace.branches.length} branch${workspace.branches.length == 1 ? '' : 'es'} · ${workspace.roleName}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceFact extends StatelessWidget {
  const _WorkspaceFact({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodyMedium),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FoundationCard extends StatelessWidget {
  const _FoundationCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.badge,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String badge;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
                size: 30,
              ),
              StatusBadge(label: badge, tone: tone),
            ],
          ),
          const Spacer(),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 5),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
