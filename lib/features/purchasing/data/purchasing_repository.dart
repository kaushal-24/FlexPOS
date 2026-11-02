import 'package:flexpos/core/data/repository_contract.dart';
import 'package:flexpos/features/auth/data/auth_repository.dart';
import 'package:flexpos/features/catalog/data/catalog_repository.dart';
import 'package:flexpos/features/purchasing/domain/purchasing_models.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final purchasingRepositoryProvider = Provider<PurchasingRepository>(
  (ref) => PurchasingRepository(ref.watch(supabaseClientProvider)),
);

final suppliersProvider = FutureProvider.autoDispose<List<Supplier>>((
  ref,
) async {
  final workspace = ref.watch(selectedWorkspaceProvider).value;
  if (workspace == null ||
      !workspace.permissionCodes.contains('purchases.view')) {
    return const [];
  }
  return ref
      .watch(purchasingRepositoryProvider)
      .fetchSuppliers(workspace.businessId);
});

final purchaseOrdersProvider = FutureProvider.autoDispose<List<PurchaseOrder>>((
  ref,
) async {
  final workspace = ref.watch(selectedWorkspaceProvider).value;
  if (workspace == null ||
      !workspace.permissionCodes.contains('purchases.view')) {
    return const [];
  }
  return ref
      .watch(purchasingRepositoryProvider)
      .fetchOrders(workspace.businessId);
});

final purchaseRequisitionsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('purchases.view')) {
        return const [];
      }
      return ref
          .watch(purchasingRepositoryProvider)
          .fetchPurchaseRequisitions(workspace.businessId);
    });

final purchaseInvoicesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('purchases.view')) {
        return const [];
      }
      return ref
          .watch(purchasingRepositoryProvider)
          .fetchPurchaseInvoices(workspace.businessId);
    });

class PurchasingRepository implements SupabaseRepositoryContract {
  PurchasingRepository(this._client);

  final SupabaseClient _client;

  @override
  SupabaseClient get client => _client;

  Future<List<Supplier>> fetchSuppliers(String businessId) async {
    final rows = await _client
        .from('suppliers')
        .select('id,code,name,contact_name,phone,email,gstin')
        .eq('business_id', businessId)
        .eq('is_active', true)
        .isFilter('archived_at', null)
        .order('name');
    return rows
        .map((row) => Supplier.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<PurchaseOrder>> fetchOrders(String businessId) async {
    final rows = await _client
        .from('purchase_orders')
        .select(
          'id,order_number,status,grand_total,ordered_at,'
          'suppliers(name),warehouses(name),'
          'purchase_order_items(id,variant_id,product_name,sku,'
          'ordered_quantity,received_quantity,unit_cost,tax_rate,'
          'purchase_return_items(quantity),product_variants(tracking_mode))',
        )
        .eq('business_id', businessId)
        .order('ordered_at', ascending: false)
        .limit(100);
    return rows
        .map((row) => PurchaseOrder.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<void> createSupplier({
    required String businessId,
    required String name,
    String? code,
    String? contactName,
    String? phone,
    String? email,
    String? gstin,
  }) async {
    await _client.from('suppliers').insert({
      'business_id': businessId,
      'name': name.trim(),
      'code': _nullable(code)?.toUpperCase(),
      'contact_name': _nullable(contactName),
      'phone': _nullable(phone),
      'email': _nullable(email)?.toLowerCase(),
      'gstin': _nullable(gstin)?.toUpperCase(),
    });
  }

  Future<void> updateSupplier({
    required String businessId,
    required String supplierId,
    required String name,
    String? code,
    String? contactName,
    String? phone,
    String? email,
    String? gstin,
  }) async {
    await _client
        .from('suppliers')
        .update({
          'name': name.trim(),
          'code': _nullable(code)?.toUpperCase(),
          'contact_name': _nullable(contactName),
          'phone': _nullable(phone),
          'email': _nullable(email)?.toLowerCase(),
          'gstin': _nullable(gstin)?.toUpperCase(),
        })
        .eq('business_id', businessId)
        .eq('id', supplierId);
  }

  /// Supplier deletion is a reversible archive to preserve purchase history.
  Future<void> archiveSupplier({
    required String businessId,
    required String supplierId,
  }) async {
    await _client
        .from('suppliers')
        .update({
          'is_active': false,
          'archived_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('business_id', businessId)
        .eq('id', supplierId);
  }

  Future<Map<String, dynamic>> createPurchaseOrder({
    required String businessId,
    required String supplierId,
    required String warehouseId,
    required List<
      ({
        String variantId,
        double quantity,
        int unitCostMinor,
        int taxBasisPoints,
      })
    >
    lines,
    String? supplierReference,
    String? notes,
  }) async {
    final response = await _client.rpc(
      'create_purchase_order',
      params: {
        'target_business_id': businessId,
        'target_supplier_id': supplierId,
        'target_warehouse_id': warehouseId,
        'operation_id': createUuidV4(),
        'line_items': lines
            .map(
              (line) => {
                'variant_id': line.variantId,
                'quantity': line.quantity,
                'unit_cost': line.unitCostMinor / 100,
                'tax_rate': line.taxBasisPoints / 100,
              },
            )
            .toList(growable: false),
        'expected_delivery_at': null,
        'supplier_document_reference': _nullable(supplierReference),
        'order_notes': _nullable(notes),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> receivePurchaseOrder({
    required String purchaseOrderId,
    required Map<String, double> quantities,
    Map<String, List<String>> identifiersByLine = const {},
    Map<String, Map<String, String?>> batchDetailsByLine = const {},
    String? supplierReference,
    String? notes,
  }) async {
    final response = await _client.rpc(
      'receive_purchase_order',
      params: {
        'target_purchase_order_id': purchaseOrderId,
        'operation_id': createUuidV4(),
        'received_items': quantities.entries
            .where((entry) => entry.value > 0)
            .map(
              (entry) => {
                'purchase_order_item_id': entry.key,
                'quantity': entry.value,
                'identifiers': identifiersByLine[entry.key] ?? const <String>[],
                ...?batchDetailsByLine[entry.key],
              },
            )
            .toList(growable: false),
        'supplier_document_reference': _nullable(supplierReference),
        'receipt_notes': _nullable(notes),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> returnPurchaseOrder({
    required String purchaseOrderId,
    required Map<String, double> quantities,
    required String reason,
    String? notes,
  }) async {
    final response = await _client.rpc(
      'return_purchase_order',
      params: {
        'target_purchase_order_id': purchaseOrderId,
        'operation_id': createUuidV4(),
        'returned_items': quantities.entries
            .where((entry) => entry.value > 0)
            .map(
              (entry) => {
                'purchase_order_item_id': entry.key,
                'quantity': entry.value,
              },
            )
            .toList(growable: false),
        'return_reason': reason.trim(),
        'return_notes': _nullable(notes),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<List<Map<String, dynamic>>> fetchPurchaseRequisitions(
    String businessId,
  ) async {
    final rows = await _client
        .from('purchase_requisitions')
        .select(
          'id,branch_id,status,notes,requested_by,approved_by,approved_at,decision_note,created_at,'
          'branches(name),purchase_requisition_items(id,variant_id,product_name,sku,quantity,notes)',
        )
        .eq('business_id', businessId)
        .order('created_at', ascending: false)
        .limit(100);
    return rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> fetchPurchaseInvoices(
    String businessId,
  ) async {
    final rows = await _client
        .from('purchase_invoices')
        .select(
          'id,purchase_order_id,supplier_id,invoice_number,invoice_date,due_date,subtotal,tax_total,total,paid_total,status,notes,created_at,'
          'suppliers(name),purchase_orders(order_number),purchase_invoice_payments(id,amount,payment_method,reference,paid_at)',
        )
        .eq('business_id', businessId)
        .order('created_at', ascending: false)
        .limit(200);
    return rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createPurchaseRequisition({
    required String businessId,
    required String branchId,
    required List<({String variantId, double quantity, String? notes})> items,
    String? notes,
  }) async {
    final response = await _client.rpc(
      'create_purchase_requisition',
      params: {
        'target_business_id': businessId,
        'target_branch_id': branchId,
        'operation_id': createUuidV4(),
        'requested_items': items
            .map(
              (item) => {
                'variant_id': item.variantId,
                'quantity': item.quantity,
                'notes': _nullable(item.notes),
              },
            )
            .toList(growable: false),
        'requisition_notes': _nullable(notes),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<void> decidePurchaseRequisition({
    required String requisitionId,
    required bool approve,
    String? notes,
  }) async {
    await _client.rpc(
      'decide_purchase_requisition',
      params: {
        'target_requisition_id': requisitionId,
        'approve_request': approve,
        'decision_notes': _nullable(notes),
      },
    );
  }

  Future<Map<String, dynamic>> createPurchaseInvoice({
    required String businessId,
    required String purchaseOrderId,
    required String invoiceNumber,
    required DateTime invoiceDate,
    DateTime? dueDate,
    required int subtotalMinor,
    required int taxMinor,
    String? notes,
  }) async {
    final response = await _client.rpc(
      'create_purchase_invoice',
      params: {
        'target_business_id': businessId,
        'target_purchase_order_id': purchaseOrderId,
        'invoice_number': invoiceNumber.trim(),
        'invoice_date': invoiceDate.toIso8601String().substring(0, 10),
        'due_date': dueDate?.toIso8601String().substring(0, 10),
        'subtotal_amount': subtotalMinor / 100,
        'tax_amount': taxMinor / 100,
        'invoice_notes': _nullable(notes),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> recordPurchaseInvoicePayment({
    required String invoiceId,
    required int amountMinor,
    required String paymentMethod,
    String? reference,
    String? notes,
  }) async {
    final response = await _client.rpc(
      'record_purchase_invoice_payment',
      params: {
        'target_invoice_id': invoiceId,
        'operation_id': createUuidV4(),
        'payment_amount': amountMinor / 100,
        'payment_method': paymentMethod,
        'payment_reference': _nullable(reference),
        'payment_notes': _nullable(notes),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> addPurchaseLandedCost({
    required String purchaseOrderId,
    required int amountMinor,
    required String allocationMethod,
    String? notes,
  }) async {
    final response = await _client.rpc(
      'add_purchase_landed_cost',
      params: {
        'target_purchase_order_id': purchaseOrderId,
        'operation_id': createUuidV4(),
        'cost_amount': amountMinor / 100,
        'allocation_method': allocationMethod,
        'cost_notes': _nullable(notes),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }
}

String? _nullable(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
