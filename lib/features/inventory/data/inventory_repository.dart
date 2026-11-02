import 'package:flexpos/core/data/repository_contract.dart';
import 'package:flexpos/features/auth/data/auth_repository.dart';
import 'package:flexpos/features/catalog/data/catalog_repository.dart'
    show createUuidV4;
import 'package:flexpos/features/inventory/domain/inventory_models.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final inventoryRepositoryProvider = Provider<InventoryRepository>(
  (ref) => InventoryRepository(ref.watch(supabaseClientProvider)),
);

final stockLossEventsProvider =
    FutureProvider.autoDispose<List<StockLossEvent>>((ref) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('inventory.view')) {
        return const [];
      }
      return ref
          .watch(inventoryRepositoryProvider)
          .fetchStockLossEvents(workspace.businessId);
    });

final serializedInventoryUnitsProvider =
    FutureProvider.autoDispose<List<SerializedInventoryUnit>>((ref) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('inventory.view')) {
        return const [];
      }
      return ref
          .watch(inventoryRepositoryProvider)
          .fetchSerializedInventoryUnits(workspace.businessId);
    });

final inventoryTransferRequestsProvider =
    FutureProvider.autoDispose<List<InventoryTransferRequest>>((ref) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('inventory.view')) {
        return const [];
      }
      return ref
          .watch(inventoryRepositoryProvider)
          .fetchInventoryTransferRequests(workspace.businessId);
    });

final inventoryStocktakeItemsProvider = FutureProvider.autoDispose
    .family<List<InventoryStocktakeItem>, String>(
      (ref, stocktakeId) => ref
          .watch(inventoryRepositoryProvider)
          .fetchInventoryStocktakeItems(stocktakeId),
    );

class InventoryRepository implements SupabaseRepositoryContract {
  InventoryRepository(this._client);

  final SupabaseClient _client;

  @override
  SupabaseClient get client => _client;

  Future<List<StockLossEvent>> fetchStockLossEvents(String businessId) async {
    final rows = await _client
        .from('stock_loss_events')
        .select(
          'id,event_number,loss_type,product_name,variant_name,sku,quantity,'
          'unit_cost,loss_value,reason,notes,recorded_at,warehouses(name)',
        )
        .eq('business_id', businessId)
        .order('recorded_at', ascending: false)
        .limit(50);
    return rows
        .map((row) => StockLossEvent.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<SerializedInventoryUnit>> fetchSerializedInventoryUnits(
    String businessId,
  ) async {
    final rows = await _client
        .from('serialized_inventory_units')
        .select(
          'id,variant_id,warehouse_id,tracking_mode,identifier,status,'
          'product_name,variant_name,sku,'
          'registered_at,warehouses(name)',
        )
        .eq('business_id', businessId)
        .order('registered_at', ascending: false)
        .limit(100);
    return rows
        .map(
          (row) =>
              SerializedInventoryUnit.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<List<InventoryTransferRequest>> fetchInventoryTransferRequests(
    String businessId,
  ) async {
    final rows = await _client
        .from('inventory_transfer_requests')
        .select(
          'id,request_number,status,quantity,reason,requested_at,'
          'source_warehouse_id,destination_warehouse_id,variant_id',
        )
        .eq('business_id', businessId)
        .order('requested_at', ascending: false)
        .limit(50);
    return rows
        .map(
          (row) =>
              InventoryTransferRequest.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<List<InventoryStocktakeItem>> fetchInventoryStocktakeItems(
    String stocktakeId,
  ) async {
    final rows = await _client
        .from('inventory_stocktake_items')
        .select(
          'id,stocktake_id,variant_id,batch_id,system_quantity,counted_quantity,'
          'batch:inventory_batches(batch_number,expires_on)',
        )
        .eq('stocktake_id', stocktakeId)
        .order('variant_id')
        .order('batch_id');
    return rows
        .map(
          (row) =>
              InventoryStocktakeItem.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> setInventoryThreshold({
    required String businessId,
    required String warehouseId,
    required String variantId,
    required double reorderPoint,
  }) async {
    final response = await _client.rpc(
      'set_inventory_threshold',
      params: {
        'target_business_id': businessId,
        'target_warehouse_id': warehouseId,
        'target_variant_id': variantId,
        'target_reorder_point': reorderPoint,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> startInventoryStocktake({
    required String businessId,
    required String warehouseId,
    String? reason,
  }) async {
    final response = await _client.rpc(
      'start_inventory_stocktake',
      params: {
        'target_business_id': businessId,
        'target_warehouse_id': warehouseId,
        'operation_id': createUuidV4(),
        'stocktake_reason': _nullable(reason),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> recordInventoryStocktakeCount({
    required String stocktakeId,
    required String variantId,
    required double countedQuantity,
    String? batchId,
    String? note,
  }) async {
    final response = await _client.rpc(
      'record_inventory_stocktake_count',
      params: {
        'target_stocktake_id': stocktakeId,
        'target_variant_id': variantId,
        'counted_quantity': countedQuantity,
        'target_batch_id': batchId,
        'count_note': _nullable(note),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> finalizeInventoryStocktake({
    required String stocktakeId,
  }) async {
    final response = await _client.rpc(
      'finalize_inventory_stocktake',
      params: {
        'target_stocktake_id': stocktakeId,
        'operation_id': createUuidV4(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> cancelInventoryStocktake({
    required String stocktakeId,
  }) async {
    final response = await _client.rpc(
      'cancel_inventory_stocktake',
      params: {
        'target_stocktake_id': stocktakeId,
        'operation_id': createUuidV4(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> recordStockLoss({
    required String businessId,
    required String warehouseId,
    required String variantId,
    required String lossType,
    required double quantity,
    required String reason,
    String? notes,
    List<String> serializedUnitIds = const [],
  }) async {
    final params = <String, dynamic>{
      'target_business_id': businessId,
      'target_warehouse_id': warehouseId,
      'target_variant_id': variantId,
      'selected_loss_type': lossType,
      'loss_quantity': quantity,
      'loss_reason': reason.trim(),
      'operation_id': createUuidV4(),
      'loss_notes': _nullable(notes),
    };
    if (serializedUnitIds.isNotEmpty) {
      params['serialized_unit_ids'] = serializedUnitIds;
    }
    final response = await _client.rpc('record_stock_loss', params: params);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> registerSerializedInventory({
    required String businessId,
    required String warehouseId,
    required String variantId,
    required String trackingMode,
    required List<String> identifiers,
  }) async {
    final response = await _client.rpc(
      'register_serialized_inventory',
      params: {
        'target_business_id': businessId,
        'target_warehouse_id': warehouseId,
        'target_variant_id': variantId,
        'selected_tracking_mode': trackingMode,
        'identifiers': identifiers,
        'operation_id': createUuidV4(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> executeInventoryTransfer({
    required String businessId,
    required String sourceWarehouseId,
    required String destinationWarehouseId,
    required String variantId,
    required double quantity,
    required String reason,
    String? notes,
    List<String> serializedUnitIds = const [],
  }) async {
    final response = await _client.rpc(
      'execute_inventory_transfer',
      params: {
        'target_business_id': businessId,
        'target_source_warehouse_id': sourceWarehouseId,
        'target_destination_warehouse_id': destinationWarehouseId,
        'target_variant_id': variantId,
        'transfer_quantity': quantity,
        'transfer_reason': reason.trim(),
        'operation_id': createUuidV4(),
        'transfer_notes': _nullable(notes),
        'serialized_unit_ids': serializedUnitIds,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> requestInventoryTransfer({
    required String businessId,
    required String sourceWarehouseId,
    required String destinationWarehouseId,
    required String variantId,
    required double quantity,
    required String reason,
    String? notes,
    List<String> serializedUnitIds = const [],
  }) async {
    final response = await _client.rpc(
      'request_inventory_transfer',
      params: {
        'target_business_id': businessId,
        'target_source_warehouse_id': sourceWarehouseId,
        'target_destination_warehouse_id': destinationWarehouseId,
        'target_variant_id': variantId,
        'transfer_quantity': quantity,
        'transfer_reason': reason.trim(),
        'operation_id': createUuidV4(),
        'transfer_notes': _nullable(notes),
        'serialized_unit_ids': serializedUnitIds,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> approveInventoryTransfer({
    required String businessId,
    required String requestId,
  }) => _advanceInventoryTransfer(
    'approve_inventory_transfer',
    businessId: businessId,
    requestId: requestId,
  );

  Future<Map<String, dynamic>> dispatchInventoryTransfer({
    required String businessId,
    required String requestId,
  }) => _advanceInventoryTransfer(
    'dispatch_inventory_transfer',
    businessId: businessId,
    requestId: requestId,
  );

  Future<Map<String, dynamic>> receiveInventoryTransfer({
    required String businessId,
    required String requestId,
  }) => _advanceInventoryTransfer(
    'receive_inventory_transfer',
    businessId: businessId,
    requestId: requestId,
  );

  Future<Map<String, dynamic>> cancelInventoryTransfer({
    required String businessId,
    required String requestId,
  }) => _advanceInventoryTransfer(
    'cancel_inventory_transfer',
    businessId: businessId,
    requestId: requestId,
  );

  Future<Map<String, dynamic>> _advanceInventoryTransfer(
    String functionName, {
    required String businessId,
    required String requestId,
  }) async {
    final response = await _client.rpc(
      functionName,
      params: {
        'target_business_id': businessId,
        'target_request_id': requestId,
        'operation_id': createUuidV4(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }
}

String? _nullable(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
