import 'package:flexpos/core/data/repository_contract.dart';
import 'package:flexpos/features/auth/data/auth_repository.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flexpos/features/warehouses/domain/warehouse_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final warehouseRepositoryProvider = Provider<WarehouseRepository>(
  (ref) => WarehouseRepository(ref.watch(supabaseClientProvider)),
);

final warehousesProvider = FutureProvider.autoDispose
    .family<List<WarehouseRecord>, String>((ref, businessId) {
      return ref.watch(warehouseRepositoryProvider).fetchWarehouses(businessId);
    });

class WarehouseRepository implements SupabaseRepositoryContract {
  WarehouseRepository(this._client);

  final SupabaseClient _client;

  @override
  SupabaseClient get client => _client;

  Future<List<WarehouseRecord>> fetchWarehouses(String businessId) async {
    final rows = await _client
        .from('warehouses')
        .select(
          'id,business_id,branch_id,name,code,is_default,is_active,created_at,updated_at',
        )
        .eq('business_id', businessId)
        .order('name');
    return rows
        .map((row) => WarehouseRecord.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<void> createWarehouse({
    required String businessId,
    required String branchId,
    required String name,
    required String code,
    required bool isDefault,
  }) async {
    if (isDefault) {
      await _clearDefault(businessId: businessId, branchId: branchId);
    }
    await _client.from('warehouses').insert({
      'business_id': businessId,
      'branch_id': branchId,
      'name': name.trim(),
      'code': code.trim().toUpperCase(),
      'is_default': isDefault,
      'is_active': true,
    });
  }

  Future<void> updateWarehouse({
    required WarehouseRecord warehouse,
    required String branchId,
    required String name,
    required String code,
    required bool isDefault,
    required bool isActive,
  }) async {
    if (isDefault) {
      await _clearDefault(
        businessId: warehouse.businessId,
        branchId: branchId,
        exceptId: warehouse.id,
      );
    }
    await _client
        .from('warehouses')
        .update({
          'branch_id': branchId,
          'name': name.trim(),
          'code': code.trim().toUpperCase(),
          'is_default': isDefault,
          'is_active': isActive,
        })
        .eq('id', warehouse.id)
        .eq('business_id', warehouse.businessId);
  }

  /// Warehouse deletion is intentionally reversible: balances and movement
  /// history reference the warehouse, so deleting the row would break audit
  /// history. The UI presents this as Delete and keeps the row inactive.
  Future<void> deleteWarehouse(WarehouseRecord warehouse) async {
    await _client
        .from('warehouses')
        .update({'is_active': false, 'is_default': false})
        .eq('id', warehouse.id)
        .eq('business_id', warehouse.businessId);
  }

  Future<void> restoreWarehouse(WarehouseRecord warehouse) async {
    await _client
        .from('warehouses')
        .update({'is_active': true})
        .eq('id', warehouse.id)
        .eq('business_id', warehouse.businessId);
  }

  Future<void> _clearDefault({
    required String businessId,
    required String branchId,
    String? exceptId,
  }) async {
    final query = _client
        .from('warehouses')
        .update({'is_default': false})
        .eq('business_id', businessId)
        .eq('branch_id', branchId)
        .eq('is_default', true);
    if (exceptId == null) {
      await query;
    } else {
      await query.neq('id', exceptId);
    }
  }
}
