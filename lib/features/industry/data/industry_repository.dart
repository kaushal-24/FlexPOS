import 'package:flexpos/core/data/repository_contract.dart';
import 'package:flexpos/features/auth/data/auth_repository.dart';
import 'package:flexpos/features/industry/domain/industry_workflow.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final industryRepositoryProvider = Provider<IndustryRepository>(
  (ref) => IndustryRepository(ref.watch(supabaseClientProvider)),
);

final industryWorkflowsProvider = FutureProvider.autoDispose
    .family<List<IndustryWorkflow>, String>((ref, businessId) async {
      return ref.watch(industryRepositoryProvider).fetchWorkflows(businessId);
    });

class IndustryRepository implements SupabaseRepositoryContract {
  IndustryRepository(this._client);
  final SupabaseClient _client;

  @override
  SupabaseClient get client => _client;

  Future<List<IndustryWorkflow>> fetchWorkflows(String businessId) async {
    final rows = await _client
        .from('industry_workflows')
        .select(
          'id,business_id,branch_id,module_code,workflow_kind,reference_code,title,status,customer_id,product_id,assigned_to,scheduled_at,due_at,quantity,unit_price,total_amount,deposit_amount,payload,created_at',
        )
        .eq('business_id', businessId)
        .order('updated_at', ascending: false)
        .limit(500);
    return rows
        .map((row) => IndustryWorkflow.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<String> createWorkflow({
    required String businessId,
    required String? branchId,
    required String kind,
    required String referenceCode,
    required String title,
    required String status,
    required Map<String, dynamic> payload,
    DateTime? scheduledAt,
    DateTime? dueAt,
    double quantity = 0,
    double unitPrice = 0,
    double totalAmount = 0,
    double depositAmount = 0,
  }) async {
    final result = await _client.rpc(
      'create_industry_workflow',
      params: {
        'target_business_id': businessId,
        'target_branch_id': branchId,
        'target_kind': kind,
        'target_reference_code': referenceCode.trim(),
        'target_title': title.trim(),
        'target_status': status,
        'target_scheduled_at': scheduledAt?.toUtc().toIso8601String(),
        'target_due_at': dueAt?.toUtc().toIso8601String(),
        'target_quantity': quantity,
        'target_unit_price': unitPrice,
        'target_total_amount': totalAmount,
        'target_deposit_amount': depositAmount,
        'target_payload': payload,
      },
    );
    return result as String;
  }

  Future<void> transitionWorkflow({
    required String businessId,
    required String workflowId,
    required String status,
    String? note,
  }) async {
    await _client.rpc(
      'transition_industry_workflow',
      params: {
        'target_business_id': businessId,
        'target_workflow_id': workflowId,
        'target_status': status,
        'target_note': note,
        'target_metadata': const <String, dynamic>{},
      },
    );
  }
}
