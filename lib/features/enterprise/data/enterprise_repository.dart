import 'package:flexpos/core/data/repository_contract.dart';
import 'package:flexpos/features/auth/data/auth_repository.dart';
import 'package:flexpos/features/enterprise/domain/enterprise_record.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final enterpriseRepositoryProvider = Provider<EnterpriseRepository>(
  (ref) => EnterpriseRepository(ref.watch(supabaseClientProvider)),
);

final enterpriseRecordsProvider = FutureProvider.autoDispose
    .family<List<EnterpriseRecord>, String>((ref, businessId) async {
      return ref.watch(enterpriseRepositoryProvider).fetchRecords(businessId);
    });

final integrationConnectionsProvider = FutureProvider.autoDispose
    .family<List<IntegrationConnection>, String>((ref, businessId) async {
      return ref
          .watch(enterpriseRepositoryProvider)
          .fetchIntegrations(businessId);
    });

class EnterpriseRepository implements SupabaseRepositoryContract {
  EnterpriseRepository(this._client);
  final SupabaseClient _client;

  @override
  SupabaseClient get client => _client;

  Future<List<EnterpriseRecord>> fetchRecords(String businessId) async {
    final rows = await _client
        .from('enterprise_records')
        .select(
          'id,business_id,branch_id,record_type,reference_code,title,status,assigned_to,effective_at,due_at,amount,payload,created_at',
        )
        .eq('business_id', businessId)
        .order('updated_at', ascending: false)
        .limit(1000);
    return rows
        .map((row) => EnterpriseRecord.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<IntegrationConnection>> fetchIntegrations(
    String businessId,
  ) async {
    final rows = await _client
        .from('integration_connections')
        .select(
          'id,business_id,provider_code,display_name,status,secret_ref,config,last_checked_at,last_error,updated_at',
        )
        .eq('business_id', businessId)
        .order('updated_at', ascending: false);
    return rows
        .map(
          (row) =>
              IntegrationConnection.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<String> createRecord({
    required String businessId,
    String? branchId,
    required String recordType,
    required String referenceCode,
    required String title,
    required String status,
    required Map<String, dynamic> payload,
    double amount = 0,
    DateTime? effectiveAt,
    DateTime? dueAt,
  }) async {
    final result = await _client.rpc(
      'create_enterprise_record',
      params: {
        'target_business_id': businessId,
        'target_branch_id': branchId,
        'target_record_type': recordType,
        'target_reference_code': referenceCode.trim(),
        'target_title': title.trim(),
        'target_status': status.trim(),
        'target_amount': amount,
        'target_effective_at': effectiveAt?.toUtc().toIso8601String(),
        'target_due_at': dueAt?.toUtc().toIso8601String(),
        'target_payload': payload,
      },
    );
    return result as String;
  }

  Future<void> transitionRecord({
    required String businessId,
    required String recordId,
    required String status,
    String? note,
  }) async {
    await _client.rpc(
      'transition_enterprise_record',
      params: {
        'target_business_id': businessId,
        'target_record_id': recordId,
        'target_status': status,
        'target_note': note,
        'target_metadata': const <String, dynamic>{},
      },
    );
  }

  Future<String> upsertIntegration({
    required String businessId,
    required String providerCode,
    required String displayName,
    required String status,
    required String secretRef,
    required Map<String, dynamic> config,
    String? lastError,
  }) async {
    final result = await _client.rpc(
      'upsert_integration_connection',
      params: {
        'target_business_id': businessId,
        'target_provider_code': providerCode,
        'target_display_name': displayName.trim(),
        'target_status': status,
        'target_secret_ref': secretRef.trim().isEmpty ? null : secretRef.trim(),
        'target_config': config,
        'target_last_error': lastError?.trim().isEmpty == true
            ? null
            : lastError?.trim(),
      },
    );
    return result as String;
  }
}
