import 'package:flexpos/core/data/repository_contract.dart';
import 'package:flexpos/features/auth/data/auth_repository.dart';
import 'package:flexpos/features/crm/domain/crm_models.dart';
import 'package:flexpos/features/tenants/domain/feature_entitlement.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final crmRepositoryProvider = Provider<CrmRepository>(
  (ref) => CrmRepository(ref.watch(supabaseClientProvider)),
);

final crmLeadsProvider = FutureProvider.autoDispose<List<CrmLead>>((ref) async {
  final workspace = ref.watch(selectedWorkspaceProvider).value;
  if (workspace == null ||
      !workspace.isFeatureEnabled(FeatureCodes.crm) ||
      !workspace.permissionCodes.contains(CrmPermissionCodes.view)) {
    return const [];
  }
  return ref.watch(crmRepositoryProvider).fetchLeads(workspace.businessId);
});

final crmOpportunitiesProvider =
    FutureProvider.autoDispose<List<CrmOpportunity>>((ref) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.isFeatureEnabled(FeatureCodes.crm) ||
          !workspace.permissionCodes.contains(CrmPermissionCodes.view)) {
        return const [];
      }
      return ref
          .watch(crmRepositoryProvider)
          .fetchOpportunities(workspace.businessId);
    });

final crmQuotationsProvider = FutureProvider.autoDispose<List<CrmQuotation>>((
  ref,
) async {
  final workspace = ref.watch(selectedWorkspaceProvider).value;
  if (workspace == null ||
      !workspace.isFeatureEnabled(FeatureCodes.crm) ||
      !workspace.permissionCodes.contains(CrmPermissionCodes.view)) {
    return const [];
  }
  return ref.watch(crmRepositoryProvider).fetchQuotations(workspace.businessId);
});

final crmFollowUpsProvider = FutureProvider.autoDispose<List<CrmFollowUp>>((
  ref,
) async {
  final workspace = ref.watch(selectedWorkspaceProvider).value;
  if (workspace == null ||
      !workspace.isFeatureEnabled(FeatureCodes.crm) ||
      !workspace.permissionCodes.contains(CrmPermissionCodes.view)) {
    return const [];
  }
  return ref.watch(crmRepositoryProvider).fetchFollowUps(workspace.businessId);
});

final crmCustomerNotesProvider = FutureProvider.autoDispose
    .family<List<CrmCustomerNote>, String>((ref, customerId) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.isFeatureEnabled(FeatureCodes.crm) ||
          !workspace.permissionCodes.contains(CrmPermissionCodes.view)) {
        return const [];
      }
      return ref
          .watch(crmRepositoryProvider)
          .fetchCustomerNotes(workspace.businessId, customerId);
    });

final crmRemindersProvider = FutureProvider.autoDispose<List<CrmReminder>>((
  ref,
) async {
  final workspace = ref.watch(selectedWorkspaceProvider).value;
  if (workspace == null ||
      !workspace.isFeatureEnabled(FeatureCodes.crm) ||
      !workspace.permissionCodes.contains(CrmPermissionCodes.view)) {
    return const [];
  }
  return ref.watch(crmRepositoryProvider).fetchReminders(workspace.businessId);
});

final overdueRemindersProvider = FutureProvider.autoDispose<List<CrmReminder>>((
  ref,
) async {
  final workspace = ref.watch(selectedWorkspaceProvider).value;
  if (workspace == null ||
      !workspace.isFeatureEnabled(FeatureCodes.crm) ||
      !workspace.permissionCodes.contains(CrmPermissionCodes.view)) {
    return const [];
  }
  final now = DateTime.now().toUtc().toIso8601String();
  final rows = await ref
      .watch(crmRepositoryProvider)
      ._client
      .from('crm_reminders')
      .select('*')
      .eq('business_id', workspace.businessId)
      .eq('is_completed', false)
      .lt('due_at', now)
      .order('due_at');
  return rows
      .map((row) => CrmReminder.fromJson(Map<String, dynamic>.from(row)))
      .toList(growable: false);
});

class CrmRepository implements SupabaseRepositoryContract {
  CrmRepository(this._client);

  final SupabaseClient _client;

  @override
  SupabaseClient get client => _client;

  Future<List<CrmLead>> fetchLeads(String businessId) async {
    final rows = await _client
        .from('crm_leads')
        .select('*')
        .eq('business_id', businessId)
        .isFilter('archived_at', null)
        .order('created_at', ascending: false);
    return rows
        .map((row) => CrmLead.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<CrmLead> createLead({
    required String businessId,
    required String title,
    String? source,
    String? status,
    String? salespersonId,
    String? customerId,
    int? estimatedValueMinor,
    DateTime? expectedCloseAt,
    String? notes,
  }) async {
    final inserted = await _client
        .from('crm_leads')
        .insert({
          'business_id': businessId,
          'title': title.trim(),
          'source': _nullable(source),
          'status': _nullable(status) ?? 'new',
          'salesperson_id': _nullable(salespersonId),
          'customer_id': _nullable(customerId),
          'estimated_value': estimatedValueMinor == null
              ? null
              : estimatedValueMinor / 100,
          'expected_close_at': expectedCloseAt?.toUtc().toIso8601String(),
          'notes': _nullable(notes),
        })
        .select()
        .single();
    return CrmLead.fromJson(Map<String, dynamic>.from(inserted));
  }

  Future<void> updateLead({
    required String id,
    required String businessId,
    required String title,
    String? source,
    String? status,
    String? salespersonId,
    String? customerId,
    int? estimatedValueMinor,
    DateTime? expectedCloseAt,
    String? notes,
  }) async {
    await _client
        .from('crm_leads')
        .update({
          'title': title.trim(),
          'source': _nullable(source),
          'status': _nullable(status) ?? 'new',
          'salesperson_id': _nullable(salespersonId),
          'customer_id': _nullable(customerId),
          'estimated_value': estimatedValueMinor == null
              ? null
              : estimatedValueMinor / 100,
          'expected_close_at': expectedCloseAt?.toUtc().toIso8601String(),
          'notes': _nullable(notes),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('business_id', businessId);
  }

  Future<void> archiveLead({
    required String id,
    required String businessId,
  }) async {
    await _client
        .from('crm_leads')
        .update({
          'archived_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('business_id', businessId);
  }

  Future<List<CrmOpportunity>> fetchOpportunities(String businessId) async {
    final rows = await _client
        .from('crm_opportunities')
        .select('*')
        .eq('business_id', businessId)
        .isFilter('archived_at', null)
        .order('created_at', ascending: false);
    return rows
        .map((row) => CrmOpportunity.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<CrmOpportunity> createOpportunity({
    required String businessId,
    required String title,
    String? stage,
    int probability = 0,
    int valueMinor = 0,
    DateTime? expectedCloseAt,
    String? notes,
    String? salespersonId,
    String? customerId,
    String? leadId,
  }) async {
    final inserted = await _client
        .from('crm_opportunities')
        .insert({
          'business_id': businessId,
          'title': title.trim(),
          'stage': _nullable(stage) ?? 'prospecting',
          'probability': probability,
          'value_minor': valueMinor,
          'expected_close_at': expectedCloseAt?.toUtc().toIso8601String(),
          'notes': _nullable(notes),
          'salesperson_id': _nullable(salespersonId),
          'customer_id': _nullable(customerId),
          'lead_id': _nullable(leadId),
        })
        .select()
        .single();
    return CrmOpportunity.fromJson(Map<String, dynamic>.from(inserted));
  }

  Future<void> updateOpportunity({
    required String id,
    required String businessId,
    required String title,
    String? stage,
    int probability = 0,
    int valueMinor = 0,
    DateTime? expectedCloseAt,
    DateTime? actualCloseAt,
    String? notes,
    String? salespersonId,
    String? customerId,
    String? leadId,
  }) async {
    await _client
        .from('crm_opportunities')
        .update({
          'title': title.trim(),
          'stage': _nullable(stage) ?? 'prospecting',
          'probability': probability,
          'value_minor': valueMinor,
          'expected_close_at': expectedCloseAt?.toUtc().toIso8601String(),
          'actual_close_at': actualCloseAt?.toUtc().toIso8601String(),
          'notes': _nullable(notes),
          'salesperson_id': _nullable(salespersonId),
          'customer_id': _nullable(customerId),
          'lead_id': _nullable(leadId),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('business_id', businessId);
  }

  Future<void> archiveOpportunity({
    required String id,
    required String businessId,
  }) async {
    await _client
        .from('crm_opportunities')
        .update({
          'archived_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('business_id', businessId);
  }

  Future<List<CrmQuotation>> fetchQuotations(String businessId) async {
    final rows = await _client
        .from('crm_quotations')
        .select('*')
        .eq('business_id', businessId)
        .isFilter('archived_at', null)
        .order('created_at', ascending: false);
    return rows
        .map((row) => CrmQuotation.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<CrmQuotation> createQuotation({
    required String businessId,
    required String quotationNumber,
    required String title,
    String? status,
    int subtotalMinor = 0,
    int taxMinor = 0,
    int discountMinor = 0,
    int grandTotalMinor = 0,
    DateTime? validUntil,
    String? notes,
    String? salespersonId,
    String? customerId,
    String? opportunityId,
  }) async {
    final inserted = await _client
        .from('crm_quotations')
        .insert({
          'business_id': businessId,
          'quotation_number': quotationNumber.trim(),
          'title': title.trim(),
          'status': _nullable(status) ?? 'draft',
          'subtotal_minor': subtotalMinor,
          'tax_minor': taxMinor,
          'discount_minor': discountMinor,
          'grand_total_minor': grandTotalMinor,
          'valid_until': validUntil?.toUtc().toIso8601String(),
          'notes': _nullable(notes),
          'salesperson_id': _nullable(salespersonId),
          'customer_id': _nullable(customerId),
          'opportunity_id': _nullable(opportunityId),
        })
        .select()
        .single();
    return CrmQuotation.fromJson(Map<String, dynamic>.from(inserted));
  }

  Future<void> updateQuotation({
    required String id,
    required String businessId,
    required String quotationNumber,
    required String title,
    String? status,
    int subtotalMinor = 0,
    int taxMinor = 0,
    int discountMinor = 0,
    int grandTotalMinor = 0,
    DateTime? validUntil,
    String? notes,
    String? salespersonId,
    String? customerId,
    String? opportunityId,
  }) async {
    await _client
        .from('crm_quotations')
        .update({
          'quotation_number': quotationNumber.trim(),
          'title': title.trim(),
          'status': _nullable(status) ?? 'draft',
          'subtotal_minor': subtotalMinor,
          'tax_minor': taxMinor,
          'discount_minor': discountMinor,
          'grand_total_minor': grandTotalMinor,
          'valid_until': validUntil?.toUtc().toIso8601String(),
          'notes': _nullable(notes),
          'salesperson_id': _nullable(salespersonId),
          'customer_id': _nullable(customerId),
          'opportunity_id': _nullable(opportunityId),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('business_id', businessId);
  }

  Future<void> archiveQuotation({
    required String id,
    required String businessId,
  }) async {
    await _client
        .from('crm_quotations')
        .update({
          'archived_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('business_id', businessId);
  }

  Future<List<CrmFollowUp>> fetchFollowUps(String businessId) async {
    final rows = await _client
        .from('crm_follow_ups')
        .select('*')
        .eq('business_id', businessId)
        .order('due_at');
    return rows
        .map((row) => CrmFollowUp.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<CrmFollowUp> createFollowUp({
    required String businessId,
    required String title,
    String? type,
    required DateTime dueAt,
    String? notes,
    String? salespersonId,
    String? leadId,
    String? opportunityId,
    String? quotationId,
  }) async {
    final inserted = await _client
        .from('crm_follow_ups')
        .insert({
          'business_id': businessId,
          'title': title.trim(),
          'type': _nullable(type) ?? 'call',
          'due_at': dueAt.toUtc().toIso8601String(),
          'notes': _nullable(notes),
          'salesperson_id': _nullable(salespersonId),
          'lead_id': _nullable(leadId),
          'opportunity_id': _nullable(opportunityId),
          'quotation_id': _nullable(quotationId),
        })
        .select()
        .single();
    return CrmFollowUp.fromJson(Map<String, dynamic>.from(inserted));
  }

  Future<void> completeFollowUp({
    required String id,
    required String businessId,
  }) async {
    await _client
        .from('crm_follow_ups')
        .update({
          'completed_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('business_id', businessId);
  }

  Future<void> updateFollowUp({
    required String id,
    required String businessId,
    required String title,
    required String type,
    required DateTime dueAt,
    String? notes,
    String? salespersonId,
    String? leadId,
    String? opportunityId,
    String? quotationId,
  }) async {
    await _client
        .from('crm_follow_ups')
        .update({
          'title': title.trim(),
          'type': type,
          'due_at': dueAt.toUtc().toIso8601String(),
          'notes': _nullable(notes),
          'salesperson_id': _nullable(salespersonId),
          'lead_id': _nullable(leadId),
          'opportunity_id': _nullable(opportunityId),
          'quotation_id': _nullable(quotationId),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('business_id', businessId);
  }

  Future<void> deleteFollowUp({
    required String id,
    required String businessId,
  }) async {
    await _client
        .from('crm_follow_ups')
        .delete()
        .eq('id', id)
        .eq('business_id', businessId);
  }

  Future<List<CrmCustomerNote>> fetchCustomerNotes(
    String businessId,
    String customerId,
  ) async {
    final rows = await _client
        .from('crm_customer_notes')
        .select('*')
        .eq('business_id', businessId)
        .eq('customer_id', customerId)
        .order('created_at', ascending: false);
    return rows
        .map((row) => CrmCustomerNote.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<CrmCustomerNote> createCustomerNote({
    required String businessId,
    required String customerId,
    required String note,
    bool isPrivate = true,
    String? salespersonId,
  }) async {
    final inserted = await _client
        .from('crm_customer_notes')
        .insert({
          'business_id': businessId,
          'customer_id': customerId,
          'note': note.trim(),
          'is_private': isPrivate,
          'salesperson_id': _nullable(salespersonId),
        })
        .select()
        .single();
    return CrmCustomerNote.fromJson(Map<String, dynamic>.from(inserted));
  }

  Future<void> updateCustomerNote({
    required String id,
    required String businessId,
    required String note,
    required bool isPrivate,
    String? salespersonId,
  }) async {
    await _client
        .from('crm_customer_notes')
        .update({
          'note': note.trim(),
          'is_private': isPrivate,
          'salesperson_id': _nullable(salespersonId),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('business_id', businessId);
  }

  Future<void> deleteCustomerNote({
    required String id,
    required String businessId,
  }) async {
    await _client
        .from('crm_customer_notes')
        .delete()
        .eq('id', id)
        .eq('business_id', businessId);
  }

  Future<List<CrmReminder>> fetchReminders(String businessId) async {
    final rows = await _client
        .from('crm_reminders')
        .select('*')
        .eq('business_id', businessId)
        .order('due_at');
    return rows
        .map((row) => CrmReminder.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<CrmReminder> createReminder({
    required String businessId,
    required String title,
    String? description,
    required DateTime dueAt,
    String? salespersonId,
    String? relatedTable,
    String? relatedId,
  }) async {
    final inserted = await _client
        .from('crm_reminders')
        .insert({
          'business_id': businessId,
          'title': title.trim(),
          'description': _nullable(description),
          'due_at': dueAt.toUtc().toIso8601String(),
          'salesperson_id': _nullable(salespersonId),
          'related_table': _nullable(relatedTable),
          'related_id': _nullable(relatedId),
        })
        .select()
        .single();
    return CrmReminder.fromJson(Map<String, dynamic>.from(inserted));
  }

  Future<void> completeReminder({
    required String id,
    required String businessId,
  }) async {
    await _client
        .from('crm_reminders')
        .update({
          'is_completed': true,
          'completed_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('business_id', businessId);
  }

  Future<void> updateReminder({
    required String id,
    required String businessId,
    required String title,
    String? description,
    required DateTime dueAt,
    String? salespersonId,
    String? relatedTable,
    String? relatedId,
  }) async {
    await _client
        .from('crm_reminders')
        .update({
          'title': title.trim(),
          'description': _nullable(description),
          'due_at': dueAt.toUtc().toIso8601String(),
          'salesperson_id': _nullable(salespersonId),
          'related_table': _nullable(relatedTable),
          'related_id': _nullable(relatedId),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('business_id', businessId);
  }

  Future<void> deleteReminder({
    required String id,
    required String businessId,
  }) async {
    await _client
        .from('crm_reminders')
        .delete()
        .eq('id', id)
        .eq('business_id', businessId);
  }
}

String? _nullable(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
