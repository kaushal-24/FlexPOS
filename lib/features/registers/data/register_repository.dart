import 'package:flexpos/core/data/repository_contract.dart';
import 'package:flexpos/features/auth/data/auth_repository.dart';
import 'package:flexpos/features/catalog/data/catalog_repository.dart';
import 'package:flexpos/features/registers/domain/register_models.dart';
import 'package:flexpos/features/tenants/domain/feature_entitlement.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final registerRepositoryProvider = Provider<RegisterRepository>(
  (ref) => RegisterRepository(ref.watch(supabaseClientProvider)),
);

final registerOperationsProvider =
    FutureProvider.autoDispose<RegisterOperationsSnapshot>((ref) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.isFeatureEnabled(FeatureCodes.registers)) {
        return RegisterOperationsSnapshot.empty;
      }
      return ref
          .watch(registerRepositoryProvider)
          .fetchSnapshot(workspace.businessId);
    });

class RegisterRepository implements SupabaseRepositoryContract {
  RegisterRepository(this._client);

  final SupabaseClient _client;

  @override
  SupabaseClient get client => _client;

  Future<RegisterOperationsSnapshot> fetchSnapshot(String businessId) async {
    final rows = await Future.wait([
      _client
          .from('registers')
          .select('id,branch_id,name,code,is_active,assigned_user_id')
          .eq('business_id', businessId)
          .eq('is_active', true)
          .order('name'),
      _client
          .from('register_shifts')
          .select(
            'id,register_id,opened_by,closed_by,status,opening_cash,'
            'expected_cash,closing_cash,difference_amount,opened_at,closed_at,'
            'notes,registers!inner(name,code,branch_id)',
          )
          .eq('business_id', businessId)
          .order('opened_at', ascending: false)
          .limit(100),
      _client
          .from('memberships')
          .select('user_id,roles!inner(name)')
          .eq('business_id', businessId)
          .eq('status', 'active')
          .isFilter('archived_at', null)
          .order('created_at'),
    ]);
    final memberRows = (rows[2] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
    final memberIds = memberRows
        .map((row) => row['user_id'] as String)
        .toList();
    final profileRows = memberIds.isEmpty
        ? <Map<String, dynamic>>[]
        : await _client
              .from('profiles')
              .select('id,email,full_name')
              .inFilter('id', memberIds);
    final profiles = {
      for (final profile in profileRows)
        profile['id'] as String: Map<String, dynamic>.from(profile),
    };

    return RegisterOperationsSnapshot(
      registers: (rows[0] as List)
          .map(
            (row) =>
                PosRegister.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList(growable: false),
      shifts: (rows[1] as List)
          .map(
            (row) =>
                RegisterShift.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList(growable: false),
      staff: memberRows
          .map((map) {
            final role = Map<String, dynamic>.from(map['roles'] as Map);
            final profile = profiles[map['user_id'] as String];
            return RegisterStaff(
              userId: map['user_id'] as String,
              email: profile?['email'] as String? ?? 'Staff member',
              fullName: profile?['full_name'] as String?,
              roleName: role['name'] as String?,
            );
          })
          .toList(growable: false),
    );
  }

  Future<void> createRegister({
    required String businessId,
    required String branchId,
    required String name,
    required String code,
    String? assignedUserId,
  }) async {
    await _client.from('registers').insert({
      'business_id': businessId,
      'branch_id': branchId,
      'name': name.trim(),
      'code': code.trim().toUpperCase(),
      'assigned_user_id': assignedUserId,
      'is_active': true,
    });
  }

  Future<void> updateRegister({
    required String businessId,
    required String registerId,
    required String branchId,
    required String name,
    required String code,
    String? assignedUserId,
  }) async {
    await _client
        .from('registers')
        .update({
          'branch_id': branchId,
          'name': name.trim(),
          'code': code.trim().toUpperCase(),
          'assigned_user_id': assignedUserId,
        })
        .eq('business_id', businessId)
        .eq('id', registerId);
  }

  Future<void> archiveRegister({
    required String businessId,
    required String registerId,
  }) async {
    await _client
        .from('registers')
        .update({'is_active': false})
        .eq('business_id', businessId)
        .eq('id', registerId);
  }

  Future<void> openShift({
    required String businessId,
    required String registerId,
    required int openingCashMinor,
    String? openedByUserId,
    String? notes,
  }) async {
    await _client.rpc(
      'open_register_shift_for_staff',
      params: {
        'target_business_id': businessId,
        'target_register_id': registerId,
        'target_staff_id': openedByUserId,
        'opening_cash_amount': openingCashMinor / 100,
        'shift_notes': _nullable(notes),
      },
    );
  }

  Future<RegisterCloseResult> closeShift({
    required String shiftId,
    required int closingCashMinor,
    String? notes,
  }) async {
    final response = await _client.rpc(
      'close_register_shift',
      params: {
        'target_shift_id': shiftId,
        'closing_cash_amount': closingCashMinor / 100,
        'shift_notes': _nullable(notes),
      },
    );
    return RegisterCloseResult.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  Future<void> recordCashMovement({
    required String shiftId,
    required String movementType,
    required int amountMinor,
    required String reason,
  }) async {
    await _client.rpc(
      'record_register_cash_movement',
      params: {
        'target_shift_id': shiftId,
        'operation_id': createUuidV4(),
        'movement_type': movementType,
        'movement_amount': amountMinor / 100,
        'movement_reason': reason.trim(),
      },
    );
  }

  Future<RegisterShiftReport> fetchShiftReport(String shiftId) async {
    final response = await _client.rpc(
      'get_register_shift_report',
      params: {'target_shift_id': shiftId},
    );
    return RegisterShiftReport.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }
}

String? _nullable(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? null : text;
}
