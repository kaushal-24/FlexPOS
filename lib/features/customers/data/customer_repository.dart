import 'dart:math';

import 'package:flexpos/core/data/repository_contract.dart';
import 'package:flexpos/features/auth/data/auth_repository.dart';
import 'package:flexpos/features/customers/domain/customer_models.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final customerRepositoryProvider = Provider<CustomerRepository>(
  (ref) => CustomerRepository(ref.watch(supabaseClientProvider)),
);

final customersProvider = FutureProvider.autoDispose<List<Customer>>((
  ref,
) async {
  final workspace = ref.watch(selectedWorkspaceProvider).value;
  if (workspace == null ||
      !workspace.permissionCodes.contains('customers.view')) {
    return const [];
  }
  return ref
      .watch(customerRepositoryProvider)
      .fetchCustomers(workspace.businessId);
});

final customerGroupsProvider = FutureProvider.autoDispose<List<CustomerGroup>>((
  ref,
) async {
  final workspace = ref.watch(selectedWorkspaceProvider).value;
  if (workspace == null ||
      !workspace.permissionCodes.contains('customers.view')) {
    return const [];
  }
  return ref
      .watch(customerRepositoryProvider)
      .fetchCustomerGroups(workspace.businessId);
});

final customerPurchaseHistoryProvider = FutureProvider.autoDispose
    .family<List<CustomerPurchase>, String>((ref, customerId) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('sales.view')) {
        return const [];
      }
      return ref
          .watch(customerRepositoryProvider)
          .fetchPurchaseHistory(workspace.businessId, customerId);
    });

final customerLoyaltyTransactionsProvider = FutureProvider.autoDispose
    .family<List<LoyaltyTransaction>, String>((ref, customerId) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('customers.view')) {
        return const [];
      }
      return ref
          .watch(customerRepositoryProvider)
          .fetchLoyaltyTransactions(workspace.businessId, customerId);
    });

class CustomerRepository implements SupabaseRepositoryContract {
  CustomerRepository(this._client);

  final SupabaseClient _client;

  @override
  SupabaseClient get client => _client;

  Future<List<Customer>> fetchCustomers(String businessId) async {
    final rows = await _client
        .from('customers')
        .select(
          'id,code,name,phone,email,gstin,credit_limit,loyalty_points,group_id',
        )
        .eq('business_id', businessId)
        .eq('is_active', true)
        .isFilter('archived_at', null)
        .order('name');
    final groupRows = await _client
        .from('customer_groups')
        .select('id,name')
        .eq('business_id', businessId)
        .eq('is_active', true);
    final groupNames = {
      for (final row in groupRows) row['id'] as String: row['name'] as String,
    };
    return rows
        .map((row) {
          final json = Map<String, dynamic>.from(row);
          json['group_name'] = groupNames[json['group_id']];
          return Customer.fromJson(json);
        })
        .toList(growable: false);
  }

  Future<List<CustomerGroup>> fetchCustomerGroups(String businessId) async {
    final rows = await _client
        .from('customer_groups')
        .select('id,name,code,description,is_active')
        .eq('business_id', businessId)
        .eq('is_active', true)
        .order('name');
    return rows
        .map((row) => CustomerGroup.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<void> createCustomerGroup({
    required String businessId,
    required String name,
    String? code,
    String? description,
  }) async {
    await _client.from('customer_groups').insert({
      'business_id': businessId,
      'name': name.trim(),
      'code': _nullable(code)?.toUpperCase(),
      'description': _nullable(description),
    });
  }

  Future<void> updateCustomerGroup({
    required String businessId,
    required String customerId,
    String? groupId,
  }) async {
    await _client
        .from('customers')
        .update({'group_id': groupId})
        .eq('business_id', businessId)
        .eq('id', customerId);
  }

  Future<void> createCustomer({
    required String businessId,
    required String name,
    String? code,
    String? phone,
    String? email,
    String? gstin,
    int creditLimitMinor = 0,
    String? groupId,
  }) async {
    await _client.from('customers').insert({
      'business_id': businessId,
      'name': name.trim(),
      'code': _nullable(code)?.toUpperCase(),
      'phone': _nullable(phone),
      'email': _nullable(email)?.toLowerCase(),
      'gstin': _nullable(gstin)?.toUpperCase(),
      'credit_limit': creditLimitMinor / 100,
      'group_id': groupId,
    });
  }

  Future<void> updateCustomer({
    required String businessId,
    required String customerId,
    required String name,
    String? code,
    String? phone,
    String? email,
    String? gstin,
    int creditLimitMinor = 0,
    String? groupId,
  }) async {
    await _client
        .from('customers')
        .update({
          'name': name.trim(),
          'code': _nullable(code)?.toUpperCase(),
          'phone': _nullable(phone),
          'email': _nullable(email)?.toLowerCase(),
          'gstin': _nullable(gstin)?.toUpperCase(),
          'credit_limit': creditLimitMinor / 100,
          'group_id': groupId,
        })
        .eq('business_id', businessId)
        .eq('id', customerId);
  }

  /// Deletes a customer from active lists while preserving historical sales
  /// and customer-ledger references.
  Future<void> deleteCustomer({
    required String businessId,
    required String customerId,
  }) async {
    await _client
        .from('customers')
        .update({
          'is_active': false,
          'archived_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('business_id', businessId)
        .eq('id', customerId);
  }

  Future<void> deleteCustomerGroup({
    required String businessId,
    required String groupId,
  }) async {
    await _client
        .from('customer_groups')
        .update({
          'is_active': false,
        })
        .eq('business_id', businessId)
        .eq('id', groupId);
  }

  Future<List<CustomerPurchase>> fetchPurchaseHistory(
    String businessId,
    String customerId,
  ) async {
    final rows = await _client
        .from('sales')
        .select(
          'id,invoice_number,grand_total,payment_status,status,completed_at,'
          'sale_items(id),sale_returns(refund_total)',
        )
        .eq('business_id', businessId)
        .eq('customer_id', customerId)
        .order('completed_at', ascending: false)
        .limit(250);
    return rows
        .map((row) => CustomerPurchase.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<LoyaltyTransaction>> fetchLoyaltyTransactions(
    String businessId,
    String customerId,
  ) async {
    final rows = await _client
        .from('customer_loyalty_transactions')
        .select(
          'id,transaction_type,points_delta,balance_after,note,created_at',
        )
        .eq('business_id', businessId)
        .eq('customer_id', customerId)
        .order('created_at', ascending: false)
        .limit(100);
    return rows
        .map(
          (row) => LoyaltyTransaction.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> adjustLoyaltyPoints({
    required String businessId,
    required String customerId,
    required double pointsDelta,
    required String transactionType,
    String? branchId,
    String? note,
  }) async {
    final response = await _client.rpc(
      'adjust_customer_loyalty_points',
      params: {
        'target_business_id': businessId,
        'target_customer_id': customerId,
        'target_branch_id': branchId,
        'target_operation_id': _uuidV4(),
        'target_points_delta': pointsDelta,
        'target_transaction_type': transactionType,
        'target_transaction_note': note?.trim().isEmpty ?? true
            ? null
            : note!.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }
}

String? _nullable(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final value = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
      '${value.substring(12, 16)}-${value.substring(16, 20)}-${value.substring(20)}';
}
