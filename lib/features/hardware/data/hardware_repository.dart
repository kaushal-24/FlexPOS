import 'package:flexpos/core/data/repository_contract.dart';
import 'package:flexpos/features/auth/data/auth_repository.dart';
import 'package:flexpos/features/hardware/domain/hardware_device.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final hardwareRepositoryProvider = Provider<HardwareRepository>(
  (ref) => HardwareRepository(ref.watch(supabaseClientProvider)),
);

final hardwareDevicesProvider = FutureProvider.autoDispose
    .family<List<HardwareDevice>, String>((ref, businessId) async {
      return ref.watch(hardwareRepositoryProvider).fetchDevices(businessId);
    });

class HardwareRepository implements SupabaseRepositoryContract {
  HardwareRepository(this._client);
  final SupabaseClient _client;

  @override
  SupabaseClient get client => _client;

  Future<List<HardwareDevice>> fetchDevices(String businessId) async {
    final rows = await _client
        .from('hardware_devices')
        .select(
          'id,business_id,branch_id,device_kind,connection_type,display_name,endpoint,status,capabilities,metadata,last_seen_at,last_tested_at,last_error,created_at',
        )
        .eq('business_id', businessId)
        .order('updated_at', ascending: false)
        .limit(500);
    return rows
        .map((row) => HardwareDevice.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<String> registerDevice({
    required String businessId,
    String? branchId,
    required String deviceKind,
    required String connectionType,
    required String displayName,
    String? endpoint,
    Map<String, dynamic> capabilities = const {},
    Map<String, dynamic> metadata = const {},
  }) async {
    final result = await _client.rpc(
      'register_hardware_device',
      params: {
        'target_business_id': businessId,
        'target_branch_id': branchId,
        'target_device_kind': deviceKind,
        'target_connection_type': connectionType,
        'target_display_name': displayName.trim(),
        'target_endpoint': endpoint?.trim().isEmpty == true
            ? null
            : endpoint?.trim(),
        'target_capabilities': capabilities,
        'target_metadata': metadata,
      },
    );
    return result as String;
  }

  Future<void> recordTest({
    required String businessId,
    required String deviceId,
    required String status,
    String? error,
    Map<String, dynamic> metadata = const {},
  }) async {
    await _client.rpc(
      'record_hardware_device_test',
      params: {
        'target_business_id': businessId,
        'target_device_id': deviceId,
        'target_status': status,
        'target_error': error?.trim().isEmpty == true ? null : error?.trim(),
        'target_metadata': metadata,
      },
    );
  }

  Future<void> updateDevice({
    required String businessId,
    required String deviceId,
    String? branchId,
    required String deviceKind,
    required String connectionType,
    required String displayName,
    String? endpoint,
    Map<String, dynamic> capabilities = const {},
    Map<String, dynamic> metadata = const {},
  }) async {
    await _client
        .from('hardware_devices')
        .update({
          'branch_id': branchId,
          'device_kind': deviceKind,
          'connection_type': connectionType,
          'display_name': displayName.trim(),
          'endpoint': endpoint?.trim().isEmpty == true ? null : endpoint?.trim(),
          'capabilities': capabilities,
          'metadata': metadata,
          'updated_by': _client.auth.currentUser?.id,
        })
        .eq('id', deviceId)
        .eq('business_id', businessId);
  }

  Future<void> deleteDevice({
    required String businessId,
    required String deviceId,
  }) async {
    await _client
        .from('hardware_devices')
        .delete()
        .eq('id', deviceId)
        .eq('business_id', businessId);
  }
}
