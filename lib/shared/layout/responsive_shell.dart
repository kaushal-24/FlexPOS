import 'package:flexpos/app/theme/theme_controller.dart';
import 'package:flexpos/app/theme/app_motion.dart';
import 'package:flexpos/app/theme/app_tokens.dart';
import 'package:flexpos/core/security/crud_permissions.dart';
import 'package:flexpos/core/providers/core_providers.dart';
import 'package:flexpos/features/auth/data/auth_repository.dart';
import 'package:flexpos/features/tenants/domain/feature_entitlement.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flexpos/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ResponsiveShell extends ConsumerStatefulWidget {
  const ResponsiveShell({
    required this.location,
    required this.child,
    super.key,
  });

  final String location;
  final Widget child;

  @override
  ConsumerState<ResponsiveShell> createState() => _ResponsiveShellState();
}

class _ResponsiveShellState extends ConsumerState<ResponsiveShell> {
  bool _navRailCollapsed = false;

  int _selectedIndex(List<_ShellDestination> items) {
    final index = items.indexWhere(
      (item) => widget.location.startsWith(item.route),
    );
    if (index >= 0) return index;
    final fallback = items.indexWhere((item) => item.route == '/more');
    return fallback >= 0 ? fallback : 0;
  }

  void _navigate(
    BuildContext context,
    List<_ShellDestination> items,
    int index,
  ) => context.go(items[index].route);

  Widget _flexPosMark({double size = 44}) => SizedBox(
    width: size,
    height: size,
    child: Image.asset(
      'assets/branding/flexpos_favicon.png',
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'FlexPOS logo',
    ),
  );

  Widget _buildNavigationItem(
    BuildContext context,
    _ShellDestination item, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = IconTheme(
      data: IconThemeData(
        color: selected
            ? colorScheme.onSecondaryContainer
            : colorScheme.onSurfaceVariant,
      ),
      child: selected ? item.selectedIcon : item.icon,
    );
    final tile = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          height: 48,
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: EdgeInsets.symmetric(horizontal: _navRailCollapsed ? 0 : 14),
          alignment: _navRailCollapsed
              ? Alignment.center
              : Alignment.centerLeft,
          decoration: BoxDecoration(
            color: selected ? colorScheme.secondaryContainer : null,
            borderRadius: BorderRadius.circular(24),
          ),
          child: _navRailCollapsed
              ? icon
              : Row(
                  children: [
                    icon,
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        item.label,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: selected
                              ? colorScheme.onSecondaryContainer
                              : colorScheme.onSurface,
                          fontWeight: selected ? FontWeight.w700 : null,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
    return _navRailCollapsed ? Tooltip(message: item.label, child: tile) : tile;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    final coreItems = <_ShellDestination>[
      _ShellDestination(
        route: '/dashboard',
        icon: const Icon(Icons.dashboard_outlined),
        selectedIcon: const Icon(Icons.dashboard_rounded),
        label: l10n.dashboard,
      ),
      _ShellDestination(
        route: '/pos',
        icon: const Icon(Icons.point_of_sale_outlined),
        selectedIcon: const Icon(Icons.point_of_sale_rounded),
        label: l10n.pos,
      ),
      _ShellDestination(
        route: '/products',
        icon: const Icon(Icons.inventory_2_outlined),
        selectedIcon: const Icon(Icons.inventory_2_rounded),
        label: l10n.products,
      ),
      if ((workspace?.isFeatureEnabled(FeatureCodes.inventory) ?? false) &&
          (workspace?.canRead('inventory') ?? false))
        _ShellDestination(
          route: '/inventory',
          icon: const Icon(Icons.warehouse_outlined),
          selectedIcon: const Icon(Icons.warehouse_rounded),
          label: l10n.inventory,
        ),
      _ShellDestination(
        route: '/orders',
        icon: const Icon(Icons.receipt_long_outlined),
        selectedIcon: const Icon(Icons.receipt_long_rounded),
        label: 'Sales',
      ),
    ];
    final moduleItems = <_ShellDestination>[
      if (workspace?.canRead('customers') ?? false)
        _ShellDestination(
          route: '/customers',
          icon: const Icon(Icons.people_alt_outlined),
          selectedIcon: const Icon(Icons.people_alt_rounded),
          label: 'Customers',
        ),
      if ((workspace?.isFeatureEnabled(FeatureCodes.purchasing) ?? false) &&
          (workspace?.canRead('purchases') ?? false))
        _ShellDestination(
          route: '/purchases',
          icon: const Icon(Icons.shopping_cart_checkout_outlined),
          selectedIcon: const Icon(Icons.shopping_cart_checkout_rounded),
          label: 'Purchasing',
        ),
      if ((workspace?.isFeatureEnabled(FeatureCodes.crm) ?? false) &&
          (workspace?.canRead('crm') ?? false))
        _ShellDestination(
          route: '/crm',
          icon: const Icon(Icons.handshake_outlined),
          selectedIcon: const Icon(Icons.handshake_rounded),
          label: 'CRM',
        ),
      if (workspace?.canRead('expenses') ?? false)
        _ShellDestination(
          route: '/expenses',
          icon: const Icon(Icons.payments_outlined),
          selectedIcon: const Icon(Icons.payments_rounded),
          label: 'Expenses',
        ),
      if (workspace?.canRead('accounting') ?? false)
        _ShellDestination(
          route: '/accounting',
          icon: const Icon(Icons.account_balance_outlined),
          selectedIcon: const Icon(Icons.account_balance_rounded),
          label: 'Accounting',
        ),
      if (workspace?.canRead('reports') ?? false)
        _ShellDestination(
          route: '/reports',
          icon: const Icon(Icons.insights_outlined),
          selectedIcon: const Icon(Icons.insights_rounded),
          label: 'Reports',
        ),
      if (workspace?.canRead('sales') ?? false)
        _ShellDestination(
          route: '/promotions',
          icon: const Icon(Icons.local_offer_outlined),
          selectedIcon: const Icon(Icons.local_offer_rounded),
          label: 'Promotions',
        ),
      if ((workspace?.isFeatureEnabled(FeatureCodes.registers) ?? false) &&
          (workspace?.canRead('registers') ?? false))
        _ShellDestination(
          route: '/registers',
          icon: const Icon(Icons.point_of_sale_outlined),
          selectedIcon: const Icon(Icons.point_of_sale_rounded),
          label: 'Registers',
        ),
      if (workspace?.canRead('branches') ?? false)
        _ShellDestination(
          route: '/branches',
          icon: const Icon(Icons.account_tree_outlined),
          selectedIcon: const Icon(Icons.account_tree_rounded),
          label: 'Branches',
        ),
      if (workspace?.canRead('business') ?? false)
        _ShellDestination(
          route: '/businesses',
          icon: const Icon(Icons.storefront_outlined),
          selectedIcon: const Icon(Icons.storefront_rounded),
          label: 'Businesses',
        ),
      if (workspace?.canRead('staff') ?? false)
        _ShellDestination(
          route: '/access-control',
          icon: const Icon(Icons.groups_2_outlined),
          selectedIcon: const Icon(Icons.groups_2_rounded),
          label: 'Staff & roles',
        ),
      if (workspace?.canRead('audit') ?? false)
        _ShellDestination(
          route: '/audit-log',
          icon: const Icon(Icons.history_outlined),
          selectedIcon: const Icon(Icons.history_rounded),
          label: 'Audit log',
        ),
      if (workspace?.canManage('business') ?? false)
        _ShellDestination(
          route: '/business-settings',
          icon: const Icon(Icons.tune_outlined),
          selectedIcon: const Icon(Icons.tune_rounded),
          label: 'Business settings',
        ),
      if (workspace?.canManage('business') ?? false)
        _ShellDestination(
          route: '/modules',
          icon: const Icon(Icons.extension_outlined),
          selectedIcon: const Icon(Icons.extension_rounded),
          label: 'Module settings',
        ),
      if (workspace?.canManage('products') ?? false)
        _ShellDestination(
          route: '/catalog-management',
          icon: const Icon(Icons.category_outlined),
          selectedIcon: const Icon(Icons.category_rounded),
          label: 'Catalog tools',
        ),
      if ((workspace?.canRead('industry') ?? false) &&
          (workspace?.enabledFeatureCodes.any(
                FeatureCodes.isIndustryOperations,
              ) ??
              false))
        _ShellDestination(
          route: '/industry-operations',
          icon: const Icon(Icons.account_tree_outlined),
          selectedIcon: const Icon(Icons.account_tree_rounded),
          label: 'Industry operations',
        ),
      if ((workspace?.isFeatureEnabled(FeatureCodes.enterpriseOperations) ??
              false) &&
          (workspace?.canRead('enterprise') ?? false))
        _ShellDestination(
          route: '/enterprise-operations',
          icon: const Icon(Icons.business_center_outlined),
          selectedIcon: const Icon(Icons.business_center_rounded),
          label: 'Enterprise operations',
        ),
      if ((workspace?.isFeatureEnabled(FeatureCodes.hardwareOperations) ??
              false) &&
          (workspace?.canRead('hardware') ?? false))
        _ShellDestination(
          route: '/hardware',
          icon: const Icon(Icons.devices_other_outlined),
          selectedIcon: const Icon(Icons.devices_other_rounded),
          label: 'Hardware',
        ),
      if (workspace?.canRead('platform_admin') ?? false)
        _ShellDestination(
          route: '/platform-admin',
          icon: const Icon(Icons.admin_panel_settings_outlined),
          selectedIcon: const Icon(Icons.admin_panel_settings_rounded),
          label: 'Platform admin',
        ),
    ];
    final moreItem = _ShellDestination(
      route: '/more',
      icon: const Icon(Icons.grid_view_outlined),
      selectedIcon: const Icon(Icons.grid_view_rounded),
      label: l10n.more,
    );
    final desktopItems = <_ShellDestination>[
      ...coreItems,
      ...moduleItems,
      moreItem,
    ];
    // Phones keep a compact bottom navigation; the complete destination list
    // is available from the left drawer so administration never disappears
    // behind an unlabeled or overflowing tab bar.
    final phoneItems = <_ShellDestination>[...coreItems, moreItem];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1180;
        final isTablet = constraints.maxWidth >= 700;
        // Keep every permission-aware destination in the left navigation on
        // tablet and desktop; phones also surface the primary CRUD destinations
        // while retaining More for the remaining modules.
        final items = isTablet ? desktopItems : phoneItems;
        final destinations = items
            .map(
              (item) => NavigationDestination(
                icon: item.icon,
                selectedIcon: item.selectedIcon,
                label: item.label,
              ),
            )
            .toList(growable: false);
        final selectedIndex = _selectedIndex(items);
        final scaffold = Scaffold(
          drawer: isTablet
              ? null
              : Drawer(
                  child: SafeArea(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 12, 16, 16),
                          child: Text(
                            'Main menu',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        for (final item in desktopItems)
                          ListTile(
                            leading: item.icon,
                            title: Text(item.label),
                            selected: widget.location.startsWith(item.route),
                            onTap: () {
                              Navigator.pop(context);
                              context.go(item.route);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
          appBar: AppBar(
            title: Row(
              children: [
                Text(ref.watch(appConfigProvider).appName),
                const SizedBox(width: AppSpacing.sm),
                if (isTablet) const Flexible(child: _WorkspaceSwitcher()),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Cycle theme',
                onPressed: () => ref.read(themeModeProvider.notifier).cycle(),
                icon: Icon(switch (ref.watch(themeModeProvider)) {
                  ThemeMode.light => Icons.light_mode_outlined,
                  ThemeMode.dark => Icons.dark_mode_outlined,
                  ThemeMode.system => Icons.brightness_auto_outlined,
                }),
              ),
              PopupMenuButton<String>(
                tooltip: 'Account menu',
                onSelected: (value) async {
                  if (value == 'sign-out') {
                    await ref.read(authRepositoryProvider).signOut();
                  } else if (value == 'access-control') {
                    if (context.mounted) context.go('/access-control');
                  }
                },
                itemBuilder: (context) => [
                  if (workspace?.canRead('staff') ?? false)
                    const PopupMenuItem(
                      value: 'access-control',
                      child: Row(
                        children: [
                          Icon(Icons.manage_accounts_outlined),
                          SizedBox(width: 12),
                          Text('User management'),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 'sign-out',
                    child: Row(
                      children: [
                        const Icon(Icons.logout_rounded),
                        const SizedBox(width: 12),
                        Text(l10n.signOut),
                      ],
                    ),
                  ),
                ],
                icon: const CircleAvatar(child: Icon(Icons.person_outline)),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
          ),
          body: AppMotionSwitcher(
            motionKey: ValueKey(widget.location),
            child: widget.child,
          ),
          bottomNavigationBar: isTablet
              ? null
              : NavigationBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) =>
                      _navigate(context, items, index),
                  labelBehavior:
                      NavigationDestinationLabelBehavior.onlyShowSelected,
                  destinations: destinations,
                ),
        );

        if (!isTablet) return scaffold;
        final navigation = AnimatedContainer(
          duration: AppMotion.standard,
          curve: Curves.easeOutCubic,
          width: _navRailCollapsed ? 76 : (isDesktop ? 272 : 240),
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              right: false,
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      _navRailCollapsed ? 4 : 18,
                      14,
                      _navRailCollapsed ? 4 : 12,
                      12,
                    ),
                    child: Row(
                      mainAxisAlignment: _navRailCollapsed
                          ? MainAxisAlignment.center
                          : MainAxisAlignment.spaceBetween,
                      children: [
                        if (_navRailCollapsed)
                          Tooltip(
                            message: 'Expand navigation',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () =>
                                  setState(() => _navRailCollapsed = false),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: _flexPosMark(size: 56),
                              ),
                            ),
                          )
                        else
                          Expanded(
                            child: Row(
                              children: [
                                _flexPosMark(),
                                const SizedBox(width: 8),
                                Text(
                                  'Main menu',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ],
                            ),
                          ),
                        if (!_navRailCollapsed)
                          IconButton(
                            tooltip: 'Collapse navigation',
                            onPressed: () =>
                                setState(() => _navRailCollapsed = true),
                            icon: const Icon(Icons.view_sidebar_outlined),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.symmetric(
                        horizontal: _navRailCollapsed ? 8 : 12,
                        vertical: 4,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) => _buildNavigationItem(
                        context,
                        items[index],
                        selected: index == selectedIndex,
                        onTap: () => _navigate(context, items, index),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        return Row(
          children: [
            navigation,
            VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
            Expanded(child: scaffold),
          ],
        );
      },
    );
  }
}

class _ShellDestination {
  const _ShellDestination({
    required this.route,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final String route;
  final Widget icon;
  final Widget selectedIcon;
  final String label;
}

class _WorkspaceSwitcher extends ConsumerWidget {
  const _WorkspaceSwitcher();

  static const _createWorkspaceValue = '__create_workspace__';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaces = ref.watch(workspacesProvider);
    final selectedId = ref.watch(selectedBusinessIdProvider);

    return workspaces.when(
      loading: () => const SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, _) => Text(
        'Workspace unavailable',
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      data: (items) {
        if (items.isEmpty) {
          return TextButton.icon(
            onPressed: () => context.go('/onboarding'),
            icon: const Icon(Icons.add_business_outlined, size: 18),
            label: const Text('Create business'),
          );
        }

        final selected = items
            .where((item) => item.businessId == selectedId)
            .firstOrNull;
        final active = selected ?? items.first;
        return PopupMenuButton<String>(
          tooltip: 'Switch business',
          onSelected: (value) {
            if (value == _createWorkspaceValue) {
              context.go('/onboarding');
              return;
            }
            ref.read(selectedBusinessIdProvider.notifier).select(value);
          },
          itemBuilder: (context) => [
            for (final workspace in items)
              PopupMenuItem(
                value: workspace.businessId,
                child: Row(
                  children: [
                    Icon(
                      workspace.businessId == active.businessId
                          ? Icons.check_circle_rounded
                          : Icons.storefront_outlined,
                      size: 19,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(workspace.businessName)),
                  ],
                ),
              ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: _createWorkspaceValue,
              child: Row(
                children: [
                  Icon(Icons.add_business_outlined, size: 19),
                  SizedBox(width: 12),
                  Text('Create another business'),
                ],
              ),
            ),
          ],
          child: Container(
            constraints: const BoxConstraints(maxWidth: 280),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storefront_outlined, size: 18),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: AppMotionSwitcher(
                    motionKey: ValueKey(active.businessId),
                    alignment: Alignment.centerLeft,
                    duration: AppMotion.quick,
                    child: Text(
                      active.businessName,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                const Icon(Icons.arrow_drop_down_rounded, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}
