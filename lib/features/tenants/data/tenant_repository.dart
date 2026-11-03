import 'dart:typed_data';

import 'package:flexpos/core/data/repository_contract.dart';
import 'package:flexpos/features/auth/data/auth_repository.dart';
import 'package:flexpos/features/tenants/domain/access_control_overview.dart';
import 'package:flexpos/features/tenants/domain/business_workspace.dart';
import 'package:flexpos/features/tenants/domain/business_receipt_settings.dart';
import 'package:flexpos/features/tenants/domain/feature_entitlement.dart';
import 'package:flexpos/features/tenants/domain/tenant_audit_log.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final tenantRepositoryProvider = Provider<TenantRepository>(
  (ref) => TenantRepository(ref.watch(supabaseClientProvider)),
);

class TenantRepository implements SupabaseRepositoryContract {
  TenantRepository(this._client);
  final SupabaseClient _client;

  @override
  SupabaseClient get client => _client;

  Future<List<BusinessWorkspace>> fetchWorkspaces() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final rows = await _client
        .from('memberships')
        .select(
          'id, branch_access_all, businesses!inner(id, name, business_type, currency_code, timezone, country_code, archived_at), roles!inner(id, name, role_permissions(permission_code))',
        )
        .eq('user_id', user.id)
        .eq('status', 'active')
        .isFilter('businesses.archived_at', null)
        .isFilter('archived_at', null);
    final workspaces = <BusinessWorkspace>[];
    for (final rawRow in rows) {
      final row = Map<String, dynamic>.from(rawRow);
      final business = Map<String, dynamic>.from(row['businesses'] as Map);
      final branchRows = await _client
          .from('branches')
          .select('id, business_id, name, code, timezone')
          .eq('business_id', business['id'])
          .eq('is_active', true)
          .isFilter('archived_at', null)
          .order('name');
      final entitlementRows = await _client
          .from('business_feature_entitlements')
          .select('module_code,is_enabled,feature_modules!inner(is_available)')
          .eq('business_id', business['id'])
          .eq('is_enabled', true)
          .eq('feature_modules.is_available', true);
      final branches = branchRows
          .map(
            (branch) =>
                BusinessBranch.fromJson(Map<String, dynamic>.from(branch)),
          )
          .toList(growable: false);
      final enabledFeatureCodes = entitlementRows
          .map((item) => item['module_code'] as String)
          .toSet();
      workspaces.add(
        BusinessWorkspace.fromMembership(
          row,
          branches,
          enabledFeatureCodes: enabledFeatureCodes,
        ),
      );
    }
    workspaces.sort((a, b) => a.businessName.compareTo(b.businessName));
    return workspaces;
  }

  Future<String> createBusiness(CreateBusinessRequest request) async {
    final result = await _client.rpc(
      'create_business_with_branch',
      params: request.toRpcParameters(),
    );
    return Map<String, dynamic>.from(result as Map)['business_id'] as String;
  }

  Future<void> updateBusiness({
    required String businessId,
    required String name,
    required String businessType,
    required String currencyCode,
    required String timezone,
    required String countryCode,
  }) async {
    await _client
        .from('businesses')
        .update({
          'name': name.trim(),
          'business_type': businessType,
          'currency_code': currencyCode,
          'timezone': timezone,
          'country_code': countryCode,
        })
        .eq('id', businessId);
  }

  Future<void> deleteBusiness(String businessId) async {
    await _client
        .from('businesses')
        .update({'archived_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', businessId);
  }

  Future<BusinessReceiptSettings> fetchBusinessReceiptSettings(
    String businessId,
  ) async {
    final row = await _client
        .from('businesses')
        .select(
          'id,name,tax_registration_number,invoice_prefix,receipt_footer,'
          'receipt_template,receipt_logo_path,receipt_qr_payload,'
          'receipt_show_logo,receipt_show_qr,receipt_paper_width,'
          'stock_alert_email_enabled,stock_alert_email_recipients',
        )
        .eq('id', businessId)
        .single();
    return BusinessReceiptSettings.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> updateBusinessReceiptSettings({
    required String businessId,
    required String taxRegistrationNumber,
    required String invoicePrefix,
    required String receiptFooter,
    required String receiptTemplate,
    required String? receiptQrPayload,
    required bool receiptShowLogo,
    required bool receiptShowQr,
    required String receiptPaperWidth,
    required bool stockAlertEmailEnabled,
    required String? stockAlertEmailRecipients,
  }) async {
    await _client
        .from('businesses')
        .update({
          'tax_registration_number': taxRegistrationNumber.trim().isEmpty
              ? null
              : taxRegistrationNumber.trim(),
          'invoice_prefix': invoicePrefix.trim().toUpperCase(),
          'receipt_footer': receiptFooter.trim().isEmpty
              ? null
              : receiptFooter.trim(),
          'receipt_template': receiptTemplate,
          'receipt_qr_payload':
              receiptQrPayload == null || receiptQrPayload.trim().isEmpty
              ? null
              : receiptQrPayload.trim(),
          'receipt_show_logo': receiptShowLogo,
          'receipt_show_qr': receiptShowQr,
          'receipt_paper_width': receiptPaperWidth,
          'stock_alert_email_enabled': stockAlertEmailEnabled,
          'stock_alert_email_recipients':
              stockAlertEmailRecipients == null ||
                  stockAlertEmailRecipients.trim().isEmpty
              ? null
              : stockAlertEmailRecipients.trim(),
        })
        .eq('id', businessId);
  }

  Future<String> uploadBusinessReceiptLogo({
    required String businessId,
    required Uint8List bytes,
    required String extension,
    required String contentType,
  }) async {
    final path = '$businessId/receipt-logo.$extension';
    await _client.storage
        .from('business-assets')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    await _client
        .from('businesses')
        .update({'receipt_logo_path': path})
        .eq('id', businessId);
    return path;
  }

  Future<void> removeBusinessReceiptLogo(String businessId) async {
    final row = await _client
        .from('businesses')
        .select('receipt_logo_path')
        .eq('id', businessId)
        .single();
    final path = row['receipt_logo_path'] as String?;
    if (path != null && path.isNotEmpty) {
      await _client.storage.from('business-assets').remove([path]);
    }
    await _client
        .from('businesses')
        .update({'receipt_logo_path': null})
        .eq('id', businessId);
  }

  Future<bool> hasCashierPin(String businessId) async => await _client.rpc(
    'get_cashier_pin_status',
    params: {'target_business_id': businessId},
  ) as bool;

  Future<bool> verifyCashierPin({
    required String businessId,
    required String pin,
  }) async => await _client.rpc(
    'verify_cashier_pin',
    params: {'target_business_id': businessId, 'target_pin': pin},
  ) as bool;

  Future<void> setCashierPin({
    required String businessId,
    required String pin,
  }) async {
    await _client.rpc(
      'set_cashier_pin',
      params: {'target_business_id': businessId, 'target_pin': pin},
    );
  }

  Future<Map<String, dynamic>> fetchPlatformAdminOverview() async =>
      Map<String, dynamic>.from(
        await _client.rpc('get_platform_admin_overview') as Map,
      );

  Future<List<Map<String, dynamic>>> fetchBusinessDevices(
    String businessId,
  ) async {
    final rows = await _client
        .from('business_devices')
        .select(
          'id,device_name,platform,status,last_seen_at,created_at,revoked_at',
        )
        .eq('business_id', businessId)
        .order('last_seen_at', ascending: false);
    return rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<void> registerBusinessDevice({
    required String businessId,
    required String deviceKey,
    required String deviceName,
    required String platform,
  }) async {
    await _client.rpc(
      'register_business_device',
      params: {
        'target_business_id': businessId,
        'target_device_key': deviceKey,
        'target_device_name': deviceName,
        'target_platform': platform,
      },
    );
  }

  Future<void> revokeBusinessDevice(String deviceId) async {
    await _client.rpc(
      'revoke_business_device',
      params: {'target_device_id': deviceId},
    );
  }

  Future<List<BusinessFeatureEntitlement>> fetchFeatureEntitlements(
    String businessId,
  ) async {
    final rows = await _client
        .from('business_feature_entitlements')
        .select(
          'is_enabled,source,feature_modules!inner('
          'code,name,description,category,sort_order,is_core,is_available)',
        )
        .eq('business_id', businessId)
        .eq('feature_modules.is_available', true);
    final features = rows
        .map(
          (row) => BusinessFeatureEntitlement.fromJson(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList(growable: false);
    features.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return features;
  }

  Future<List<TenantAuditLog>> fetchAuditLogs(String businessId) async {
    final rows = await _client
        .from('tenant_audit_logs')
        .select(
          'id,business_id,actor_user_id,action,target_type,target_id,details,created_at',
        )
        .eq('business_id', businessId)
        .order('created_at', ascending: false)
        .limit(250);
    return rows
        .map((row) => TenantAuditLog.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<void> setFeatureEntitlement({
    required String businessId,
    required String moduleCode,
    required bool enabled,
  }) async {
    await _client.rpc(
      'set_business_feature_entitlement',
      params: {
        'target_business_id': businessId,
        'target_module_code': moduleCode,
        'requested_enabled': enabled,
      },
    );
  }

  Future<AccessControlOverview> fetchAccessControlOverview(
    String businessId,
  ) async {
    final results = await Future.wait([
      _client
          .from('roles')
          .select(
            'id, name, description, is_system, role_permissions(permission_code)',
          )
          .eq('business_id', businessId)
          .order('name'),
      _client
          .from('memberships')
          .select(
            'id, user_id, status, branch_access_all, roles!inner(id, name), member_branch_access(branch_id)',
          )
          .eq('business_id', businessId)
          .isFilter('archived_at', null)
          .order('created_at'),
      _client
          .from('permissions')
          .select('code, category, description')
          .order('category')
          .order('code'),
      _client
          .from('business_invitations')
          .select('id, email, status, expires_at, roles!inner(name)')
          .eq('business_id', businessId)
          .order('created_at', ascending: false),
    ]);

    final memberRows = (results[1] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    final userIds = memberRows.map((row) => row['user_id'] as String).toList();
    final profileRows = userIds.isEmpty
        ? <Map<String, dynamic>>[]
        : await _client
              .from('profiles')
              .select('id, email, full_name')
              .inFilter('id', userIds);
    final profiles = {
      for (final profile in profileRows)
        profile['id'] as String: Map<String, dynamic>.from(profile),
    };
    for (final row in memberRows) {
      final profile = profiles[row['user_id']];
      row['profile_email'] = profile?['email'];
      row['profile_name'] = profile?['full_name'];
    }

    return AccessControlOverview(
      roles: (results[0] as List)
          .map(
            (row) =>
                RoleSummary.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList(growable: false),
      members: memberRows.map(MemberSummary.fromJson).toList(growable: false),
      permissions: (results[2] as List)
          .map(
            (row) => PermissionSummary.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(growable: false),
      invitations: (results[3] as List)
          .map(
            (row) => InvitationSummary.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  Future<void> createRole({
    required String businessId,
    required String name,
    required String description,
    required List<String> permissionCodes,
  }) async {
    await _client.rpc(
      'create_role_with_permissions',
      params: {
        'target_business_id': businessId,
        'role_name': name.trim(),
        'role_description': description.trim(),
        'permission_codes': permissionCodes,
      },
    );
  }

  Future<void> updateRole({
    required String roleId,
    required String name,
    required String description,
    required List<String> permissionCodes,
  }) async {
    await _client.rpc(
      'update_role_with_permissions',
      params: {
        'target_role_id': roleId,
        'role_name': name.trim(),
        'role_description': description.trim(),
        'permission_codes': permissionCodes,
      },
    );
  }

  Future<void> deleteRole(String roleId) async {
    await _client.rpc('delete_role', params: {'target_role_id': roleId});
  }

  Future<StaffInvitationResult> createStaffInvitation({
    required String businessId,
    required String email,
    required String roleId,
    required bool allBranches,
    required List<String> branchIds,
  }) async {
    final result = await _client.rpc(
      'create_staff_invitation',
      params: {
        'target_business_id': businessId,
        'target_email': email.trim(),
        'target_role_id': roleId,
        'grants_all_branches': allBranches,
        'target_branch_ids': branchIds,
        'valid_days': 7,
      },
    );
    return StaffInvitationResult.fromJson(
      Map<String, dynamic>.from(result as Map),
    );
  }

  Future<String> sendStaffInvitationEmail({
    required String businessId,
    required String invitationId,
    required String token,
    required String redirectTo,
  }) async {
    final response = await _client.functions.invoke(
      'staff-invite-email',
      body: {
        'business_id': businessId,
        'invitation_id': invitationId,
        'token': token,
        'redirect_to': redirectTo,
      },
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError(
        _functionError(response.data, 'Could not send the invitation email.'),
      );
    }
    final data = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : <String, dynamic>{};
    return data['provider'] as String? ?? 'email provider';
  }

  String _functionError(Object? data, String fallback) {
    if (data is Map && data['error'] is String) {
      final message = (data['error'] as String).trim();
      if (message.isNotEmpty) return message;
    }
    return fallback;
  }

  Future<StaffUserCredentials> createStaffUser({
    required String businessId,
    required String email,
    required String password,
    required String fullName,
    required String roleId,
    required bool allBranches,
    required List<String> branchIds,
  }) async {
    final response = await _client.functions.invoke(
      'staff-user-admin',
      body: {
        'action': 'create',
        'business_id': businessId,
        'email': email.trim().toLowerCase(),
        'password': password,
        'full_name': fullName.trim(),
        'role_id': roleId,
        'all_branches': allBranches,
        'branch_ids': branchIds,
      },
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError(
        _functionError(response.data, 'Could not create staff login.'),
      );
    }
    final data = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : <String, dynamic>{};
    return StaffUserCredentials.fromJson(data);
  }

  Future<void> updateStaffUser({
    required String businessId,
    required String userId,
    String? email,
    String? password,
    String? fullName,
    String? roleId,
    String? status,
    bool? allBranches,
    List<String>? branchIds,
  }) async {
    final body = <String, dynamic>{
      'action': 'update',
      'business_id': businessId,
      'user_id': userId,
    };
    if (email != null) body['email'] = email.trim().toLowerCase();
    if (password != null) body['password'] = password;
    if (fullName != null) body['full_name'] = fullName.trim();
    if (roleId != null) body['role_id'] = roleId;
    if (status != null) body['status'] = status;
    if (allBranches != null) body['all_branches'] = allBranches;
    if (branchIds != null) body['branch_ids'] = branchIds;
    final response = await _client.functions.invoke(
      'staff-user-admin',
      body: body,
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError(
        _functionError(response.data, 'Could not update staff login.'),
      );
    }
  }

  Future<void> deleteStaffUser({
    required String businessId,
    required String userId,
  }) async {
    final response = await _client.functions.invoke(
      'staff-user-admin',
      body: {
        'action': 'delete',
        'business_id': businessId,
        'user_id': userId,
      },
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError(
        _functionError(response.data, 'Could not delete staff login.'),
      );
    }
  }

  Future<String> acceptStaffInvitation(String token) async {
    return await _client.rpc(
      'accept_staff_invitation',
      params: {'invitation_token': token.trim()},
    ) as String;
  }

  Future<void> revokeStaffInvitation(String invitationId) => _client.rpc(
    'revoke_staff_invitation',
    params: {'target_invitation_id': invitationId},
  );

  Future<void> updateMembership({
    required String membershipId,
    required String roleId,
    required String status,
    required bool allBranches,
    required List<String> branchIds,
  }) => _client.rpc(
    'update_membership_access',
    params: {
      'target_membership_id': membershipId,
      'target_role_id': roleId,
      'target_status': status,
      'grants_all_branches': allBranches,
      'target_branch_ids': branchIds,
    },
  );

  Future<void> createBranch({
    required String businessId,
    required String name,
    required String code,
    required String timezone,
    required String countryCode,
  }) async {
    await _client.from('branches').insert({
      'business_id': businessId,
      'name': name.trim(),
      'code': code.trim().toUpperCase(),
      'timezone': timezone,
      'country_code': countryCode,
    });
  }

  Future<void> updateBranch({
    required String branchId,
    required String name,
    required String code,
    required String timezone,
    required bool isActive,
  }) async {
    await _client
        .from('branches')
        .update({
          'name': name.trim(),
          'code': code.trim().toUpperCase(),
          'timezone': timezone,
          'is_active': isActive,
        })
        .eq('id', branchId);
  }
}
