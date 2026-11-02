import 'package:flexpos/core/providers/core_providers.dart';
import 'package:flexpos/features/tenants/data/tenant_repository.dart';
import 'package:flexpos/features/tenants/domain/business_workspace.dart';
import 'package:flexpos/features/tenants/domain/business_receipt_settings.dart';
import 'package:flexpos/features/tenants/domain/feature_entitlement.dart';
import 'package:flexpos/features/tenants/domain/tenant_audit_log.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final workspacesProvider = FutureProvider<List<BusinessWorkspace>>(
  (ref) => ref.watch(tenantRepositoryProvider).fetchWorkspaces(),
);

final featureEntitlementsProvider = FutureProvider.autoDispose
    .family<List<BusinessFeatureEntitlement>, String>(
      (ref, businessId) => ref
          .watch(tenantRepositoryProvider)
          .fetchFeatureEntitlements(businessId),
    );

final businessReceiptSettingsProvider = FutureProvider.autoDispose
    .family<BusinessReceiptSettings, String>(
      (ref, businessId) => ref
          .watch(tenantRepositoryProvider)
          .fetchBusinessReceiptSettings(businessId),
    );

final auditLogsProvider = FutureProvider.autoDispose
    .family<List<TenantAuditLog>, String>(
      (ref, businessId) =>
          ref.watch(tenantRepositoryProvider).fetchAuditLogs(businessId),
    );

final businessDevicesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>(
      (ref, businessId) =>
          ref.watch(tenantRepositoryProvider).fetchBusinessDevices(businessId),
    );

final selectedBusinessIdProvider =
    NotifierProvider<SelectedBusinessController, String?>(
      SelectedBusinessController.new,
    );

final selectedWorkspaceProvider = Provider<AsyncValue<BusinessWorkspace?>>((
  ref,
) {
  final workspaces = ref.watch(workspacesProvider);
  final selectedId = ref.watch(selectedBusinessIdProvider);
  return workspaces.whenData((items) {
    if (items.isEmpty) return null;
    return items.where((item) => item.businessId == selectedId).firstOrNull ??
        items.first;
  });
});

class SelectedBusinessController extends Notifier<String?> {
  static const _key = 'selected_business_id';

  @override
  String? build() => ref.watch(sharedPreferencesProvider).getString(_key);

  Future<void> select(String businessId) async {
    state = businessId;
    await ref.read(sharedPreferencesProvider).setString(_key, businessId);
  }
}
