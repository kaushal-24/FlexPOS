import 'dart:async';

import 'package:flexpos/features/auth/data/auth_repository.dart';
import 'package:flexpos/features/auth/presentation/forgot_password_page.dart';
import 'package:flexpos/features/auth/presentation/login_page.dart';
import 'package:flexpos/features/auth/presentation/register_page.dart';
import 'package:flexpos/features/auth/presentation/update_password_page.dart';
import 'package:flexpos/features/auth/presentation/verify_email_page.dart';
import 'package:flexpos/features/accounting/presentation/expenses_page.dart';
import 'package:flexpos/features/accounting/presentation/accounting_page.dart';
import 'package:flexpos/features/accounting/presentation/reports_page.dart';
import 'package:flexpos/features/catalog/presentation/products_page.dart';
import 'package:flexpos/features/catalog/presentation/catalog_management_page.dart';
import 'package:flexpos/features/crm/presentation/crm_page.dart';
import 'package:flexpos/features/customers/presentation/customers_page.dart';
import 'package:flexpos/features/dashboard/presentation/dashboard_page.dart';
import 'package:flexpos/features/foundation/presentation/more_page.dart';
import 'package:flexpos/features/inventory/presentation/inventory_page.dart';
import 'package:flexpos/features/warehouses/presentation/warehouses_page.dart';
import 'package:flexpos/features/industry/presentation/industry_operations_page.dart';
import 'package:flexpos/features/enterprise/presentation/enterprise_operations_page.dart';
import 'package:flexpos/features/hardware/presentation/hardware_operations_page.dart';
import 'package:flexpos/features/orders/presentation/orders_page.dart';
import 'package:flexpos/features/pos/presentation/pos_page.dart';
import 'package:flexpos/features/purchasing/presentation/purchasing_page.dart';
import 'package:flexpos/features/promotions/presentation/promotions_page.dart';
import 'package:flexpos/features/registers/presentation/registers_page.dart';
import 'package:flexpos/features/tenants/presentation/onboarding/business_onboarding_page.dart';
import 'package:flexpos/features/tenants/presentation/access_control/access_control_page.dart';
import 'package:flexpos/features/tenants/presentation/audit_log/audit_log_page.dart';
import 'package:flexpos/features/tenants/presentation/branches/branch_management_page.dart';
import 'package:flexpos/features/tenants/presentation/businesses/businesses_page.dart';
import 'package:flexpos/features/tenants/presentation/business_settings/business_settings_page.dart';
import 'package:flexpos/features/tenants/presentation/feature_entitlements/feature_entitlements_page.dart';
import 'package:flexpos/features/tenants/presentation/platform_admin/platform_admin_page.dart';
import 'package:flexpos/features/tenants/presentation/invitations/accept_invitation_page.dart';
import 'package:flexpos/shared/layout/responsive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  final refresh = _AuthRefreshNotifier(authRepository.authStateChanges);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: refresh,
    redirect: (context, state) {
      final isAuthenticated = authRepository.currentSession != null;
      final isAuthRoute = {
        '/login',
        '/register',
        '/forgot-password',
        '/verify-email',
      }.contains(state.matchedLocation);
      final isPasswordRecoveryRoute =
          state.matchedLocation == '/update-password';

      if (!isAuthenticated && !isAuthRoute && !isPasswordRecoveryRoute) {
        return '/login';
      }
      if (isAuthenticated && isAuthRoute) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterPage()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: '/verify-email',
        builder: (_, state) =>
            VerifyEmailPage(email: state.uri.queryParameters['email'] ?? ''),
      ),
      GoRoute(
        path: '/update-password',
        builder: (_, _) => const UpdatePasswordPage(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (_, _) => const BusinessOnboardingPage(),
      ),
      GoRoute(
        path: '/join-business',
        builder: (_, state) => AcceptInvitationPage(
          initialToken: state.uri.queryParameters['token'],
        ),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            ResponsiveShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (_, _) => const DashboardPage()),
          GoRoute(path: '/pos', builder: (_, _) => const PosPage()),
          GoRoute(path: '/products', builder: (_, _) => const ProductsPage()),
          GoRoute(
            path: '/catalog-management',
            builder: (_, _) => const CatalogManagementPage(),
          ),
          GoRoute(path: '/inventory', builder: (_, _) => const InventoryPage()),
          GoRoute(
            path: '/warehouses',
            builder: (_, _) => const WarehousesPage(),
          ),
          GoRoute(
            path: '/industry-operations',
            builder: (_, _) => const IndustryOperationsPage(),
          ),
          GoRoute(
            path: '/enterprise-operations',
            builder: (_, _) => const EnterpriseOperationsPage(),
          ),
          GoRoute(
            path: '/hardware',
            builder: (_, _) => const HardwareOperationsPage(),
          ),
          GoRoute(path: '/orders', builder: (_, _) => const OrdersPage()),
          GoRoute(path: '/customers', builder: (_, _) => const CustomersPage()),
          GoRoute(path: '/crm', builder: (_, _) => const CrmPage()),
          GoRoute(
            path: '/purchases',
            builder: (_, _) => const PurchasingPage(),
          ),
          GoRoute(path: '/expenses', builder: (_, _) => const ExpensesPage()),
          GoRoute(
            path: '/accounting',
            builder: (_, _) => const AccountingPage(),
          ),
          GoRoute(path: '/reports', builder: (_, _) => const ReportsPage()),
          GoRoute(
            path: '/promotions',
            builder: (_, _) => const PromotionsPage(),
          ),
          GoRoute(path: '/registers', builder: (_, _) => const RegistersPage()),
          GoRoute(path: '/more', builder: (_, _) => const MorePage()),
          GoRoute(
            path: '/access-control',
            builder: (_, _) => const AccessControlPage(),
          ),
          GoRoute(path: '/audit-log', builder: (_, _) => const AuditLogPage()),
          GoRoute(
            path: '/branches',
            builder: (_, _) => const BranchManagementPage(),
          ),
          GoRoute(
            path: '/businesses',
            builder: (_, _) => const BusinessesPage(),
          ),
          GoRoute(
            path: '/modules',
            builder: (_, _) => const FeatureEntitlementsPage(),
          ),
          GoRoute(
            path: '/business-settings',
            builder: (_, _) => const BusinessSettingsPage(),
          ),
          GoRoute(
            path: '/platform-admin',
            builder: (_, _) => const PlatformAdminPage(),
          ),
        ],
      ),
    ],
  );
});

class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Stream<Object?> stream) {
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
