import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flexpos/core/data/repository_contract.dart';
import 'package:flexpos/core/data/server_page.dart';
import 'package:flexpos/features/auth/data/auth_repository.dart';
import 'package:flexpos/features/catalog/domain/catalog_models.dart';
import 'package:flexpos/features/payments/domain/payment_gateway.dart';
import 'package:flexpos/features/pos/domain/pos_calculations.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(ref.watch(supabaseClientProvider)),
);

final catalogSnapshotProvider = FutureProvider.autoDispose<CatalogSnapshot>((
  ref,
) async {
  final workspace = ref.watch(selectedWorkspaceProvider).value;
  if (workspace == null) return CatalogSnapshot.empty;
  return ref
      .watch(catalogRepositoryProvider)
      .fetchSnapshot(workspace.businessId);
});

final salesProvider = FutureProvider.autoDispose<List<SaleSummary>>((
  ref,
) async {
  final workspace = ref.watch(selectedWorkspaceProvider).value;
  if (workspace == null) return const [];
  return ref.watch(catalogRepositoryProvider).fetchSales(workspace.businessId);
});

final heldPosCartsProvider = FutureProvider.autoDispose<List<HeldPosCart>>((
  ref,
) async {
  final workspace = ref.watch(selectedWorkspaceProvider).value;
  if (workspace == null) return const [];
  return ref
      .watch(catalogRepositoryProvider)
      .fetchHeldPosCarts(workspace.businessId);
});

final posDraftsProvider = FutureProvider.autoDispose<List<PosDraft>>((
  ref,
) async {
  final workspace = ref.watch(selectedWorkspaceProvider).value;
  if (workspace == null) return const [];
  return ref
      .watch(catalogRepositoryProvider)
      .fetchPosDrafts(workspace.businessId);
});

final salesQuotesProvider = FutureProvider.autoDispose<List<SalesQuote>>((
  ref,
) async {
  final workspace = ref.watch(selectedWorkspaceProvider).value;
  if (workspace == null) return const [];
  return ref
      .watch(catalogRepositoryProvider)
      .fetchSalesQuotes(workspace.businessId);
});

final salesOrdersProvider = FutureProvider.autoDispose<List<SalesOrder>>((
  ref,
) async {
  final workspace = ref.watch(selectedWorkspaceProvider).value;
  if (workspace == null) return const [];
  return ref
      .watch(catalogRepositoryProvider)
      .fetchSalesOrders(workspace.businessId);
});

final filteredSalesProvider = FutureProvider.autoDispose
    .family<List<SaleSummary>, SaleHistoryFilter>((ref, filter) {
      return ref
          .watch(catalogRepositoryProvider)
          .fetchSales(
            filter.businessId,
            search: filter.search,
            status: filter.status,
            from: filter.fromInclusiveUtc,
            throughExclusive: filter.throughExclusiveUtc,
          );
    });

class CatalogRepository implements SupabaseRepositoryContract {
  CatalogRepository(this._client);
  final SupabaseClient _client;

  @override
  SupabaseClient get client => _client;

  Future<CatalogSnapshot> fetchSnapshot(String businessId) async {
    final rows = await Future.wait([
      _client
          .from('units')
          .select('id,name,symbol,precision')
          .eq('business_id', businessId)
          .eq('is_active', true)
          .order('name'),
      _client
          .from('categories')
          .select('id,name')
          .eq('business_id', businessId)
          .eq('is_active', true)
          .order('name'),
      _client
          .from('brands')
          .select('id,name')
          .eq('business_id', businessId)
          .eq('is_active', true)
          .order('name'),
      _client
          .from('tax_rates')
          .select('id,name,rate,is_inclusive')
          .eq('business_id', businessId)
          .eq('is_active', true)
          .order('name'),
      _client
          .from('warehouses')
          .select('id,name,branch_id')
          .eq('business_id', businessId)
          .eq('is_active', true)
          .order('name'),
      _client
          .from('registers')
          .select('id,name,branch_id')
          .eq('business_id', businessId)
          .eq('is_active', true)
          .order('name'),
      _client
          .from('product_variants')
          .select(
            'id,name,sku,cost_price,selling_price,tracking_mode,product_barcodes(barcode),products!inner(id,name,product_type,image_path,attributes,is_favorite,track_inventory,allow_fractional_quantity,categories(id,name),tax_rates(rate,is_inclusive))',
          )
          .eq('business_id', businessId)
          .eq('is_active', true)
          .isFilter('archived_at', null)
          .order('sku'),
      _client
          .from('inventory_balances')
          .select(
            'variant_id,warehouse_id,quantity_on_hand,quantity_reserved,reorder_point',
          )
          .eq('business_id', businessId),
      _client
          .from('product_prices')
          .select(
            'variant_id,branch_id,price_type,customer_group_id,customer_id,amount,minimum_quantity,valid_from,valid_to',
          )
          .eq('business_id', businessId)
          .eq('price_type', 'customer_group'),
      _client
          .from('unit_conversions')
          .select('id,from_unit_id,to_unit_id,multiplier')
          .eq('business_id', businessId)
          .order('from_unit_id')
          .order('to_unit_id'),
      _client
          .from('product_bundle_components')
          .select('id,bundle_variant_id,component_variant_id,quantity')
          .eq('business_id', businessId)
          .order('bundle_variant_id'),
    ]);

    List<Map<String, dynamic>> maps(Object value) => (value as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
    return CatalogSnapshot(
      units: maps(rows[0]).map(CatalogOption.fromJson).toList(growable: false),
      categories: maps(rows[1])
          .map(CatalogOption.fromJson)
          .toList(growable: false),
      brands: maps(rows[2]).map(CatalogOption.fromJson).toList(growable: false),
      taxRates: maps(rows[3])
          .map(TaxRateOption.fromJson)
          .toList(growable: false),
      warehouses: maps(rows[4])
          .map(WarehouseOption.fromJson)
          .toList(growable: false),
      registers: maps(rows[5])
          .map(RegisterOption.fromJson)
          .toList(growable: false),
      products: maps(rows[6])
          .map(CatalogProduct.fromJson)
          .toList(growable: false),
      balances: maps(rows[7])
          .map(StockBalance.fromJson)
          .toList(growable: false),
      prices: maps(rows[8]).map(CatalogPrice.fromJson).toList(growable: false),
      unitConversions: maps(rows[9])
          .map(UnitConversion.fromJson)
          .toList(growable: false),
      bundleComponents: maps(rows[10])
          .map(BundleComponent.fromJson)
          .toList(growable: false),
    );
  }

  Future<void> upsertCustomerGroupPrice({
    required String businessId,
    required String variantId,
    required String customerGroupId,
    required int amountMinor,
    String? branchId,
    double minimumQuantity = 1,
  }) async {
    var deleteRequest = _client
        .from('product_prices')
        .delete()
        .eq('business_id', businessId)
        .eq('variant_id', variantId)
        .eq('price_type', 'customer_group')
        .eq('customer_group_id', customerGroupId)
        .eq('minimum_quantity', minimumQuantity);
    deleteRequest = branchId == null
        ? deleteRequest.isFilter('branch_id', null)
        : deleteRequest.eq('branch_id', branchId);
    await deleteRequest;
    await _client.from('product_prices').insert({
      'business_id': businessId,
      'variant_id': variantId,
      'branch_id': branchId,
      'price_type': 'customer_group',
      'customer_group_id': customerGroupId,
      'amount': amountMinor / 100,
      'minimum_quantity': minimumQuantity,
    });
  }

  Future<void> deleteCustomerGroupPrice({
    required String businessId,
    required String variantId,
    required String customerGroupId,
    String? branchId,
  }) async {
    var request = _client
        .from('product_prices')
        .delete()
        .eq('business_id', businessId)
        .eq('variant_id', variantId)
        .eq('price_type', 'customer_group')
        .eq('customer_group_id', customerGroupId);
    request = branchId == null
        ? request.isFilter('branch_id', null)
        : request.eq('branch_id', branchId);
    await request;
  }

  Future<void> upsertCustomerPrice({
    required String businessId,
    required String variantId,
    required String customerId,
    required int amountMinor,
    String? branchId,
    double minimumQuantity = 1,
  }) async {
    var deleteRequest = _client
        .from('product_prices')
        .delete()
        .eq('business_id', businessId)
        .eq('variant_id', variantId)
        .eq('price_type', 'customer')
        .eq('customer_id', customerId)
        .eq('minimum_quantity', minimumQuantity);
    deleteRequest = branchId == null
        ? deleteRequest.isFilter('branch_id', null)
        : deleteRequest.eq('branch_id', branchId);
    await deleteRequest;
    await _client.from('product_prices').insert({
      'business_id': businessId,
      'variant_id': variantId,
      'branch_id': branchId,
      'price_type': 'customer',
      'customer_id': customerId,
      'amount': amountMinor / 100,
      'minimum_quantity': minimumQuantity,
    });
  }

  Future<void> deleteCustomerPrice({
    required String businessId,
    required String variantId,
    required String customerId,
    String? branchId,
  }) async {
    var request = _client
        .from('product_prices')
        .delete()
        .eq('business_id', businessId)
        .eq('variant_id', variantId)
        .eq('price_type', 'customer')
        .eq('customer_id', customerId);
    request = branchId == null
        ? request.isFilter('branch_id', null)
        : request.eq('branch_id', branchId);
    await request;
  }

  Future<String> createProduct({
    required String businessId,
    required String name,
    required String sku,
    required String unitId,
    required int costMinor,
    required int priceMinor,
    String? barcode,
    String? categoryId,
    String? brandId,
    String? taxRateId,
    String? hsnSac,
    bool trackInventory = true,
    String productType = 'goods',
    Map<String, String> attributes = const {},
  }) async {
    final response = await _client.rpc(
      'create_product_with_default_variant',
      params: {
        'target_business_id': businessId,
        'product_name': name.trim(),
        'product_type': productType,
        'target_category_id': categoryId,
        'target_brand_id': brandId,
        'target_unit_id': unitId,
        'target_tax_rate_id': taxRateId,
        'target_hsn_sac': hsnSac?.trim() ?? '',
        'track_stock': trackInventory,
        'fractional_quantity': false,
        'variant_name': 'Default',
        'variant_sku': sku.trim().toUpperCase(),
        'variant_barcode': barcode?.trim() ?? '',
        'variant_cost': costMinor / 100,
        'variant_price': priceMinor / 100,
        'variant_mrp': null,
      },
    );
    final result = Map<String, dynamic>.from(response as Map);
    if (attributes.isNotEmpty) {
      await _client
          .from('products')
          .update({'attributes': attributes})
          .eq('business_id', businessId)
          .eq('id', result['product_id'] as String)
          .select('id')
          .single();
    }
    return result['product_id'] as String;
  }

  Future<void> updateProductAttributes({
    required String businessId,
    required String productId,
    required Map<String, String> attributes,
  }) async {
    await _client
        .from('products')
        .update({'attributes': attributes})
        .eq('business_id', businessId)
        .eq('id', productId)
        .select('id')
        .single();
  }

  /// Updates the editable catalog fields for an existing product and its
  /// default variant. Sales keep their historical snapshots, while future
  /// POS transactions use the updated catalog values.
  Future<void> updateProductCatalog({
    required String businessId,
    required String productId,
    required String variantId,
    required String name,
    required String sku,
    required int costMinor,
    required int priceMinor,
    required bool trackInventory,
    required bool allowFractionalQuantity,
    required Map<String, String> attributes,
    String? barcode,
  }) async {
    await _client
        .from('products')
        .update({
          'name': name.trim(),
          'track_inventory': trackInventory,
          'allow_fractional_quantity': allowFractionalQuantity,
          'attributes': attributes,
        })
        .eq('business_id', businessId)
        .eq('id', productId)
        .select('id')
        .single();
    await _client
        .from('product_variants')
        .update({
          'sku': sku.trim().toUpperCase(),
          'cost_price': costMinor / 100,
          'selling_price': priceMinor / 100,
        })
        .eq('business_id', businessId)
        .eq('id', variantId)
        .select('id')
        .single();

    final barcodeRows = await _client
        .from('product_barcodes')
        .select('id')
        .eq('business_id', businessId)
        .eq('variant_id', variantId)
        .order('is_primary', ascending: false)
        .limit(1);
    final existingBarcodeId = barcodeRows.isEmpty
        ? null
        : barcodeRows.first['id'] as String;
    final normalizedBarcode = barcode?.trim() ?? '';
    if (normalizedBarcode.isEmpty) {
      if (existingBarcodeId != null) {
        await _client
            .from('product_barcodes')
            .delete()
            .eq('business_id', businessId)
            .eq('id', existingBarcodeId);
      }
    } else if (existingBarcodeId != null) {
      await _client
          .from('product_barcodes')
          .update({'barcode': normalizedBarcode})
          .eq('business_id', businessId)
          .eq('id', existingBarcodeId)
          .select('id')
          .single();
    } else {
      await _client
          .from('product_barcodes')
          .insert({
            'business_id': businessId,
            'variant_id': variantId,
            'barcode': normalizedBarcode,
            'barcode_type': 'code128',
            'is_primary': true,
          })
          .select('id')
          .single();
    }
  }

  Future<String> uploadProductImage({
    required String businessId,
    required String productId,
    required Uint8List bytes,
    required String extension,
    required String contentType,
  }) async {
    final path = '$businessId/$productId/product.$extension';
    await _client.storage
        .from('product-images')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
            cacheControl: '3600',
          ),
        );
    await _client
        .from('products')
        .update({'image_path': path})
        .eq('business_id', businessId)
        .eq('id', productId)
        .select('id')
        .single();
    return path;
  }

  Future<void> removeProductImage({
    required String businessId,
    required String productId,
    required String? imagePath,
  }) async {
    if (imagePath != null && imagePath.isNotEmpty) {
      await _client.storage.from('product-images').remove([imagePath]);
    }
    await _client
        .from('products')
        .update({'image_path': null})
        .eq('business_id', businessId)
        .eq('id', productId)
        .select('id')
        .single();
  }

  /// Deletes a product from active catalog/POS views while preserving
  /// historical sale snapshots and related inventory references.
  Future<void> deleteProduct({
    required String businessId,
    required String productId,
  }) async {
    final archivedAt = DateTime.now().toUtc().toIso8601String();
    await _client
        .from('products')
        .update({'is_active': false, 'archived_at': archivedAt})
        .eq('business_id', businessId)
        .eq('id', productId)
        .select('id')
        .single();
    await _client
        .from('product_variants')
        .update({'is_active': false, 'archived_at': archivedAt})
        .eq('business_id', businessId)
        .eq('product_id', productId);
  }

  Future<String> createSignedProductImageUrl(String imagePath) {
    final uri = Uri.tryParse(imagePath.trim());
    if (uri?.hasScheme == true && (uri?.scheme == 'http' || uri?.scheme == 'https')) {
      return Future.value(imagePath.trim());
    }
    return _client.storage.from('product-images').createSignedUrl(imagePath, 3600);
  }

  Future<void> bulkUpdateProductCatalog({
    required String businessId,
    required List<String> variantIds,
    int? priceMinor,
    int? costMinor,
    bool? isFavorite,
  }) async {
    if (variantIds.isEmpty) return;
    final variantUpdate = <String, dynamic>{};
    if (priceMinor != null) variantUpdate['selling_price'] = priceMinor / 100;
    if (costMinor != null) variantUpdate['cost_price'] = costMinor / 100;
    if (variantUpdate.isNotEmpty) {
      await _client
          .from('product_variants')
          .update(variantUpdate)
          .eq('business_id', businessId)
          .inFilter('id', variantIds);
    }
    if (isFavorite != null) {
      final productIds = await _client
          .from('product_variants')
          .select('product_id')
          .eq('business_id', businessId)
          .inFilter('id', variantIds);
      final ids = productIds
          .map((row) => row['product_id'] as String)
          .toSet()
          .toList(growable: false);
      if (ids.isNotEmpty) {
        await _client
            .from('products')
            .update({'is_favorite': isFavorite})
            .eq('business_id', businessId)
            .inFilter('id', ids);
      }
    }
  }

  Future<void> upsertUnitConversion({
    required String businessId,
    required String fromUnitId,
    required String toUnitId,
    required double multiplier,
  }) async {
    await _client.from('unit_conversions').upsert({
      'business_id': businessId,
      'from_unit_id': fromUnitId,
      'to_unit_id': toUnitId,
      'multiplier': multiplier,
    }, onConflict: 'business_id,from_unit_id,to_unit_id');
  }

  Future<void> deleteUnitConversion({
    required String businessId,
    required String conversionId,
  }) async {
    await _client
        .from('unit_conversions')
        .delete()
        .eq('business_id', businessId)
        .eq('id', conversionId);
  }

  Future<void> upsertBundleComponent({
    required String businessId,
    required String bundleVariantId,
    required String componentVariantId,
    required double quantity,
  }) async {
    await _client.from('product_bundle_components').upsert({
      'business_id': businessId,
      'bundle_variant_id': bundleVariantId,
      'component_variant_id': componentVariantId,
      'quantity': quantity,
    }, onConflict: 'business_id,bundle_variant_id,component_variant_id');
  }

  Future<void> deleteBundleComponent({
    required String businessId,
    required String componentId,
  }) async {
    await _client
        .from('product_bundle_components')
        .delete()
        .eq('business_id', businessId)
        .eq('id', componentId);
  }

  Future<String> exportCatalogCsv({required String businessId}) async {
    final rows = await _client
        .from('product_variants')
        .select(
          'id,name,sku,cost_price,selling_price,mrp,products!inner(id,name,product_type,base_unit_id,hsn_sac,track_inventory,allow_fractional_quantity,attributes,units(name,symbol))',
        )
        .eq('business_id', businessId)
        .eq('is_active', true)
        .isFilter('archived_at', null)
        .order('sku');
    final buffer = StringBuffer(
      'product_id,variant_id,product_name,product_type,base_unit_id,base_unit_name,variant_name,sku,cost_price,selling_price,mrp,hsn_sac,track_inventory,allow_fractional_quantity,attributes\n',
    );
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw);
      final product = Map<String, dynamic>.from(row['products'] as Map);
      final unit = product['units'] == null
          ? null
          : Map<String, dynamic>.from(product['units'] as Map);
      final values = [
        product['id'],
        row['id'],
        product['name'],
        product['product_type'],
        product['base_unit_id'],
        unit?['name'] ?? '',
        row['name'],
        row['sku'],
        row['cost_price'],
        row['selling_price'],
        row['mrp'] ?? '',
        product['hsn_sac'] ?? '',
        product['track_inventory'],
        product['allow_fractional_quantity'],
        jsonEncode(product['attributes'] ?? const {}),
      ];
      buffer.writeln(values.map(_csvCell).join(','));
    }
    return buffer.toString();
  }

  Future<CatalogProduct> createCustomSaleItem({
    required String businessId,
    required String unitId,
    String? taxRateId,
    required String name,
    required int priceMinor,
  }) async {
    final response = await _client.rpc(
      'create_custom_sale_item',
      params: {
        'target_business_id': businessId,
        'target_unit_id': unitId,
        'target_tax_rate_id': taxRateId,
        'item_name': name.trim(),
        'item_price': priceMinor / 100,
        'operation_id': createUuidV4(),
      },
    );
    final result = Map<String, dynamic>.from(response as Map);
    final variantId = result['variant_id'] as String;
    final row = await _client
        .from('product_variants')
        .select(
          'id,name,sku,cost_price,selling_price,tracking_mode,product_barcodes(barcode),products!inner(id,name,is_favorite,track_inventory,allow_fractional_quantity,categories(id,name),tax_rates(rate,is_inclusive))',
        )
        .eq('business_id', businessId)
        .eq('id', variantId)
        .single();
    return CatalogProduct.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> setProductFavorite({
    required String businessId,
    required String productId,
    required bool isFavorite,
  }) async {
    await _client
        .from('products')
        .update({'is_favorite': isFavorite})
        .eq('business_id', businessId)
        .eq('id', productId)
        .select('id')
        .single();
  }

  Future<void> adjustInventory({
    required String businessId,
    required String warehouseId,
    required String variantId,
    required double quantityDelta,
    required String reason,
  }) async {
    await _client.rpc(
      'adjust_inventory',
      params: {
        'target_business_id': businessId,
        'target_warehouse_id': warehouseId,
        'target_variant_id': variantId,
        'quantity_delta': quantityDelta,
        'adjustment_reason': reason.trim(),
        'operation_id': createUuidV4(),
        'target_unit_cost': null,
      },
    );
  }

  Future<List<HeldPosCart>> fetchHeldPosCarts(String businessId) async {
    final rows = await _client
        .from('held_pos_carts')
        .select(
          'id,business_id,branch_id,warehouse_id,customer_id,label,payment_method,order_discount,updated_at,held_pos_cart_items(variant_id,quantity)',
        )
        .eq('business_id', businessId)
        .order('updated_at', ascending: false);
    return rows
        .map((row) => HeldPosCart.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<String> holdPosCart({
    required String businessId,
    required String branchId,
    required String warehouseId,
    required String label,
    required String paymentMethod,
    required int orderDiscountMinor,
    required Map<String, int> quantitiesByVariant,
    String? customerId,
    String? heldCartId,
  }) async {
    final response = await _client.rpc(
      'hold_pos_cart',
      params: {
        'target_business_id': businessId,
        'target_branch_id': branchId,
        'target_warehouse_id': warehouseId,
        'target_customer_id': customerId,
        'operation_id': createUuidV4(),
        'cart_label': label.trim(),
        'selected_payment_method': backendPaymentMethodForPos(paymentMethod),
        'order_discount': orderDiscountMinor / 100,
        'line_items': quantitiesByVariant.entries
            .map((entry) => {'variant_id': entry.key, 'quantity': entry.value})
            .toList(growable: false),
        'target_held_cart_id': heldCartId,
      },
    );
    return Map<String, dynamic>.from(response as Map)['held_cart_id'] as String;
  }

  Future<void> discardHeldPosCart(String heldCartId) async {
    await _client.rpc(
      'discard_held_pos_cart',
      params: {'target_held_cart_id': heldCartId},
    );
  }

  Future<List<PosDraft>> fetchPosDrafts(String businessId) async {
    final rows = await _client
        .from('pos_drafts')
        .select(
          'id,business_id,branch_id,warehouse_id,customer_id,title,payment_method,order_discount,updated_at,pos_draft_items(variant_id,quantity)',
        )
        .eq('business_id', businessId)
        .order('updated_at', ascending: false);
    return rows
        .map((row) => PosDraft.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<String> savePosDraft({
    required String businessId,
    required String branchId,
    required String warehouseId,
    required String title,
    required String paymentMethod,
    required int orderDiscountMinor,
    required Map<String, int> quantitiesByVariant,
    String? customerId,
    String? draftId,
  }) async {
    final response = await _client.rpc(
      'save_pos_draft',
      params: {
        'target_business_id': businessId,
        'target_branch_id': branchId,
        'target_warehouse_id': warehouseId,
        'target_customer_id': customerId,
        'operation_id': createUuidV4(),
        'draft_title': title.trim(),
        'selected_payment_method': backendPaymentMethodForPos(paymentMethod),
        'order_discount': orderDiscountMinor / 100,
        'line_items': quantitiesByVariant.entries
            .map((entry) => {'variant_id': entry.key, 'quantity': entry.value})
            .toList(growable: false),
        'target_draft_id': draftId,
      },
    );
    return Map<String, dynamic>.from(response as Map)['draft_id'] as String;
  }

  Future<void> deletePosDraft(String draftId) async {
    await _client.rpc('delete_pos_draft', params: {'target_draft_id': draftId});
  }

  Future<List<SalesQuote>> fetchSalesQuotes(String businessId) async {
    final rows = await _client
        .from('sales_quotes')
        .select(
          'id,business_id,branch_id,warehouse_id,customer_id,quote_number,title,status,valid_until,subtotal,discount_total,tax_total,grand_total,updated_at,sales_quote_items(variant_id,quantity,unit_price,tax_rate,discount_amount,line_total)',
        )
        .eq('business_id', businessId)
        .eq('status', 'open')
        .order('updated_at', ascending: false);
    return rows
        .map((row) => SalesQuote.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<String> saveSalesQuote({
    required String businessId,
    required String branchId,
    required String warehouseId,
    required String title,
    required DateTime validUntil,
    required List<({CatalogProduct product, int quantity})> items,
    required int orderDiscountMinor,
    String? customerId,
    String? quoteId,
  }) async {
    final response = await _client.rpc(
      'save_sales_quote',
      params: {
        'target_business_id': businessId,
        'target_branch_id': branchId,
        'target_warehouse_id': warehouseId,
        'target_customer_id': customerId,
        'operation_id': createUuidV4(),
        'quote_title': title.trim(),
        'quote_valid_until': DateTime(
          validUntil.year,
          validUntil.month,
          validUntil.day,
        ).toIso8601String().substring(0, 10),
        'line_items': items
            .map(
              (item) => {
                'variant_id': item.product.variantId,
                'quantity': item.quantity,
                'unit_price': item.product.salePriceForRpc,
                'discount_amount': 0,
                'tax_rate': item.product.taxRateBasisPoints / 100,
              },
            )
            .toList(growable: false),
        'order_discount': orderDiscountMinor / 100,
        'target_quote_id': quoteId,
      },
    );
    return Map<String, dynamic>.from(response as Map)['quote_id'] as String;
  }

  Future<void> cancelSalesQuote(String quoteId) async {
    await _client.rpc(
      'cancel_sales_quote',
      params: {'target_quote_id': quoteId},
    );
  }

  Future<void> convertSalesQuote(String quoteId, String saleId) async {
    await _client.rpc(
      'convert_sales_quote',
      params: {'target_quote_id': quoteId, 'target_sale_id': saleId},
    );
  }

  Future<List<SalesOrder>> fetchSalesOrders(String businessId) async {
    final rows = await _client
        .from('sales_orders')
        .select(
          'id,business_id,branch_id,warehouse_id,customer_id,order_number,title,status,requested_delivery_on,subtotal,order_discount,discount_total,tax_total,grand_total,updated_at,sales_order_items(variant_id,quantity,reserved_quantity,track_inventory,unit_price,tax_rate,discount_amount,line_total)',
        )
        .eq('business_id', businessId)
        .eq('status', 'open')
        .order('updated_at', ascending: false);
    return rows
        .map((row) => SalesOrder.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<String> saveSalesOrder({
    required String businessId,
    required String branchId,
    required String warehouseId,
    required String title,
    required DateTime requestedDeliveryOn,
    required List<({CatalogProduct product, int quantity})> items,
    required int orderDiscountMinor,
    String? customerId,
    String? salesOrderId,
  }) async {
    final response = await _client.rpc(
      'save_sales_order',
      params: {
        'target_business_id': businessId,
        'target_branch_id': branchId,
        'target_warehouse_id': warehouseId,
        'target_customer_id': customerId,
        'operation_id': createUuidV4(),
        'order_title': title.trim(),
        'requested_delivery_on': DateTime(
          requestedDeliveryOn.year,
          requestedDeliveryOn.month,
          requestedDeliveryOn.day,
        ).toIso8601String().substring(0, 10),
        'line_items': items
            .map(
              (item) => {
                'variant_id': item.product.variantId,
                'quantity': item.quantity,
                'unit_price': item.product.salePriceForRpc,
                'discount_amount': 0,
                'tax_rate': item.product.taxRateBasisPoints / 100,
              },
            )
            .toList(growable: false),
        'order_discount': orderDiscountMinor / 100,
        'target_order_id': salesOrderId,
      },
    );
    return Map<String, dynamic>.from(response as Map)['order_id'] as String;
  }

  Future<void> cancelSalesOrder(String salesOrderId) async {
    await _client.rpc(
      'cancel_sales_order',
      params: {'target_order_id': salesOrderId},
    );
  }

  Future<Map<String, dynamic>> fulfillSalesOrder({
    required String salesOrderId,
    required List<PosPaymentLine> paymentLines,
    required int totalMinor,
    String? registerId,
    String? shiftId,
  }) async {
    validatePosPaymentLines(paymentLines, totalMinor: totalMinor);
    final response = await _client.rpc(
      'fulfill_sales_order',
      params: {
        'target_order_id': salesOrderId,
        'target_register_id': registerId,
        'target_shift_id': shiftId,
        'operation_id': createUuidV4(),
        'payment_lines': paymentLines
            .map(
              (line) => {
                'payment_method': backendPaymentMethodForPos(line.method),
                'amount': line.amountMinor / 100,
                if ((line.provider ??
                        providerCodeForPaymentMethod(line.method)) !=
                    null)
                  'provider':
                      line.provider ??
                      providerCodeForPaymentMethod(line.method),
                if (line.reference?.trim().isNotEmpty ?? false)
                  'reference': line.reference!.trim(),
              },
            )
            .toList(growable: false),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<IssuedGiftCard> issueGiftCard({
    required String businessId,
    required String branchId,
    required int initialAmountMinor,
    String? customerId,
    DateTime? expiresAt,
  }) async {
    final response = await _client.rpc(
      'issue_gift_card',
      params: {
        'target_business_id': businessId,
        'target_branch_id': branchId,
        'target_customer_id': customerId,
        'operation_id': createUuidV4(),
        'initial_amount': initialAmountMinor / 100,
        'target_expires_at': expiresAt?.toUtc().toIso8601String(),
      },
    );
    return IssuedGiftCard.fromJson(Map<String, dynamic>.from(response as Map));
  }

  Future<GiftCardDetails> lookupGiftCard({
    required String businessId,
    required String cardNumber,
  }) async {
    final response = await _client.rpc(
      'lookup_gift_card',
      params: {
        'target_business_id': businessId,
        'target_card_number': cardNumber.trim(),
      },
    );
    return GiftCardDetails.fromJson(Map<String, dynamic>.from(response as Map));
  }

  Future<Map<String, dynamic>> completeSale({
    required String businessId,
    required String branchId,
    required String warehouseId,
    required List<({CatalogProduct product, int quantity})> items,
    required String paymentMethod,
    List<PosPaymentLine>? paymentLines,
    String? customerId,
    String? registerId,
    String? shiftId,
    String? creditNoteNumber,
    String? giftCardNumber,
    String? couponCode,
    int orderDiscountMinor = 0,
    int serviceChargeMinor = 0,
    int roundingMinor = 0,
    Map<String, int> priceOverrideByVariant = const {},
    Map<String, List<String>> serializedUnitIdsByVariant = const {},
    Map<String, String> noteByVariant = const {},
  }) async {
    final totals = calculatePosTotals(
      items,
      orderDiscountMinor: orderDiscountMinor,
      serviceChargeMinor: serviceChargeMinor,
      roundingMinor: roundingMinor,
    );
    if (serviceChargeMinor > 0 &&
        (paymentMethod == 'credit_note' || paymentMethod == 'gift_card')) {
      throw StateError(
        'Service charges are not supported for credit-note or gift-card redemption.',
      );
    }
    final effectivePaymentLines =
        paymentLines ??
        [PosPaymentLine(method: paymentMethod, amountMinor: totals.totalMinor)];
    if (paymentMethod != 'credit_note') {
      validatePosPaymentLines(
        effectivePaymentLines,
        totalMinor: totals.totalMinor,
      );
    }
    final lines = items
        .map((item) {
          final priceMinor = priceOverrideByVariant[item.product.variantId];
          final salePrice = priceMinor == null
              ? item.product.salePriceForRpc
              : item.product.copyWith(priceMinor: priceMinor).salePriceForRpc;
          return {
            'variant_id': item.product.variantId,
            // Bundles are priced as non-stock parent SKUs, but their
            // components are depleted from the selected warehouse by the
            // database sale trigger. Keep the warehouse on bundle lines so
            // the authoritative component movement uses the cashier's
            // selected location.
            'warehouse_id':
                item.product.trackInventory ||
                    item.product.productType == 'bundle'
                ? warehouseId
                : null,
            'quantity': item.quantity,
            'unit_price': salePrice,
            'discount_amount': 0,
            'tax_rate': item.product.taxRateBasisPoints / 100,
            if (priceOverrideByVariant.containsKey(item.product.variantId))
              'price_override': true,
            if (noteByVariant[item.product.variantId]?.trim().isNotEmpty ??
                false)
              'note': noteByVariant[item.product.variantId]!.trim(),
          };
        })
        .toList(growable: false);
    final paymentParams = effectivePaymentLines
        .asMap()
        .entries
        .map(
          (entry) => {
            'payment_method': backendPaymentMethodForPos(entry.value.method),
            'amount': entry.value.amountMinor / 100,
            if ((entry.value.provider ??
                    providerCodeForPaymentMethod(entry.value.method)) !=
                null)
              'provider':
                  entry.value.provider ??
                  providerCodeForPaymentMethod(entry.value.method),
            if (entry.value.reference?.trim().isNotEmpty ?? false)
              'reference': entry.value.reference!.trim(),
            if (entry.key == 0 && serviceChargeMinor > 0)
              'service_charge_amount': serviceChargeMinor / 100,
            if (entry.key == 0 && roundingMinor != 0)
              'rounding_amount': roundingMinor / 100,
          },
        )
        .toList(growable: false);
    final commonParams = {
      'target_business_id': businessId,
      'target_branch_id': branchId,
      'target_register_id': registerId,
      'target_shift_id': shiftId,
      'target_customer_id': customerId,
      'operation_id': createUuidV4(),
      'line_items': lines,
      'sale_notes': null,
    };
    final Object response;
    if (couponCode?.trim().isNotEmpty ?? false) {
      if (priceOverrideByVariant.isNotEmpty) {
        throw StateError('Coupons cannot be combined with price overrides.');
      }
      if (paymentMethod == 'credit_note' ||
          paymentMethod == 'gift_card' ||
          serializedUnitIdsByVariant.isNotEmpty) {
        throw StateError(
          'Coupons are not supported for this payment or serialized sale.',
        );
      }
      response = await _client.rpc(
        'complete_sale_with_coupon',
        params: {
          ...commonParams,
          'coupon_code': couponCode!.trim().toUpperCase(),
          'payment_lines': paymentParams,
        },
      );
    } else if (paymentMethod == 'credit_note') {
      if (priceOverrideByVariant.isNotEmpty) {
        throw StateError(
          'Price overrides are not supported with credit-note payments.',
        );
      }
      response = await _client.rpc(
        'complete_sale_with_credit_note',
        params: {
          ...commonParams,
          'order_discount': orderDiscountMinor / 100,
          'target_credit_note_number': creditNoteNumber?.trim(),
          'credit_note_amount': totals.totalMinor / 100,
        },
      );
    } else if (paymentMethod == 'gift_card') {
      if (priceOverrideByVariant.isNotEmpty) {
        throw StateError(
          'Price overrides are not supported with gift-card payments.',
        );
      }
      response = await _client.rpc(
        'complete_sale_with_gift_card',
        params: {
          ...commonParams,
          'order_discount': orderDiscountMinor / 100,
          'target_card_number': giftCardNumber?.trim(),
          'gift_card_amount': totals.totalMinor / 100,
        },
      );
    } else {
      response = await _client.rpc(
        'complete_sale_with_price_overrides',
        params: {
          ...commonParams,
          'order_discount': orderDiscountMinor / 100,
          'serialized_unit_ids': serializedUnitIdsByVariant,
          'payment_lines': paymentParams,
        },
      );
    }
    return Map<String, dynamic>.from(response as Map);
  }

  Future<List<SaleSummary>> fetchSales(
    String businessId, {
    String search = '',
    SaleHistoryStatusFilter status = SaleHistoryStatusFilter.all,
    DateTime? from,
    DateTime? throughExclusive,
  }) async {
    var request = _client
        .from('sales')
        .select(
          'id,branch_id,customer_id,notes,invoice_number,grand_total,payment_status,status,completed_at,sale_returns(refund_total),credit_notes!credit_notes_sale_fkey(id,credit_note_number,issued_amount,expires_at,credit_note_redemptions(amount)),payments(id,payment_method,status,amount,reference,provider,created_at)',
        )
        .eq('business_id', businessId);
    final normalizedSearch = search.trim();
    if (normalizedSearch.isNotEmpty) {
      final escapedSearch = normalizedSearch
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      request = request.ilike('invoice_number', '%$escapedSearch%');
    }
    request = switch (status) {
      SaleHistoryStatusFilter.all => request,
      SaleHistoryStatusFilter.paid => request.eq('payment_status', 'paid'),
      SaleHistoryStatusFilter.pending => request.inFilter('payment_status', [
        'unpaid',
        'pending',
        'partially_paid',
      ]),
      SaleHistoryStatusFilter.partiallyRefunded => request.eq(
        'status',
        'partially_refunded',
      ),
      SaleHistoryStatusFilter.refunded => request.eq('status', 'refunded'),
    };
    if (from != null) {
      request = request.gte('completed_at', from.toIso8601String());
    }
    if (throughExclusive != null) {
      request = request.lt('completed_at', throughExclusive.toIso8601String());
    }
    final rows = await request
        .order('completed_at', ascending: false)
        .limit(250);
    return rows
        .map((row) => SaleSummary.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<void> updateSaleMetadata({
    required String saleId,
    required String? customerId,
    required String notes,
  }) async {
    await _client.rpc(
      'update_sale_metadata',
      params: {
        'target_sale_id': saleId,
        'target_customer_id': customerId,
        'sale_notes': notes.trim().isEmpty ? null : notes.trim(),
      },
    );
  }

  /// Fetches a stable, server-backed sales page using the database keyset
  /// cursor. The existing history view can continue to use [fetchSales] for
  /// its filtered summary; new large-data consumers should use this method.
  Future<ServerPage<Map<String, dynamic>>> fetchSalesPage({
    required String businessId,
    DateTime? afterCreatedAt,
    String? afterId,
    int pageSize = 50,
  }) async {
    final boundedPageSize = pageSize.clamp(1, 100).toInt();
    final response = await _client.rpc(
      'list_sales_keyset',
      params: {
        'target_business_id': businessId,
        'after_created_at': afterCreatedAt?.toIso8601String(),
        'after_id': afterId,
        'page_size': boundedPageSize,
      },
    );
    return serverJsonPage(
      response is List<dynamic> ? response : const <dynamic>[],
      pageSize: boundedPageSize,
    );
  }

  /// Fetches a stable, server-backed product page using the database keyset
  /// cursor. The response intentionally stays JSON-shaped so catalog variants
  /// can evolve without coupling the pagination transport to a card model.
  Future<ServerPage<Map<String, dynamic>>> fetchProductsPage({
    required String businessId,
    DateTime? afterCreatedAt,
    String? afterId,
    int pageSize = 50,
  }) async {
    final boundedPageSize = pageSize.clamp(1, 100).toInt();
    final response = await _client.rpc(
      'list_products_keyset',
      params: {
        'target_business_id': businessId,
        'after_created_at': afterCreatedAt?.toIso8601String(),
        'after_id': afterId,
        'page_size': boundedPageSize,
      },
    );
    return serverJsonPage(
      response is List<dynamic> ? response : const <dynamic>[],
      pageSize: boundedPageSize,
    );
  }

  Future<Map<String, dynamic>> reconcilePayment({
    required String paymentId,
    required String operationId,
    required String status,
    required String reference,
    required String note,
  }) async {
    final response = await _client.rpc(
      'reconcile_payment',
      params: {
        'target_payment_id': paymentId,
        'operation_id': operationId,
        'verification_status': status,
        'verification_reference': reference.trim(),
        'reconciliation_note': note.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<String> findPendingUpiPaymentId(String saleId) async {
    final rows = await _client
        .from('payments')
        .select('id')
        .eq('sale_id', saleId)
        .eq('payment_method', 'upi')
        .eq('status', 'pending')
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) {
      throw StateError('The pending UPI payment could not be found.');
    }
    return rows.first['id'] as String;
  }

  Future<Map<String, dynamic>> createRazorpayOrder({
    required String paymentId,
  }) async {
    final response = await _client.functions.invoke(
      'razorpay-order',
      body: {'payment_id': paymentId},
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError(_functionError(response.data, 'Razorpay order failed.'));
    }
    return _functionMap(response.data);
  }

  Future<Map<String, dynamic>> verifyRazorpayPayment({
    required String paymentId,
    required String orderId,
    required String razorpayPaymentId,
    required String signature,
  }) async {
    final response = await _client.functions.invoke(
      'razorpay-verify',
      body: {
        'payment_id': paymentId,
        'razorpay_order_id': orderId,
        'razorpay_payment_id': razorpayPaymentId,
        'razorpay_signature': signature,
      },
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError(
        _functionError(response.data, 'Razorpay verification failed.'),
      );
    }
    return _functionMap(response.data);
  }

  Map<String, dynamic> _functionMap(Object? data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        // The function response is surfaced as a readable error below.
      }
    }
    throw StateError('The Razorpay service returned an invalid response.');
  }

  String _functionError(Object? data, String fallback) {
    if (data is Map && data['error'] is String) {
      final message = (data['error'] as String).trim();
      if (message.isNotEmpty) return message;
    }
    if (data is String && data.trim().isNotEmpty) return data.trim();
    return fallback;
  }

  Future<Map<String, dynamic>> confirmUpiPayment({
    required String paymentId,
    required String operationId,
    required String status,
    required String reference,
    required String note,
  }) async {
    final response = await _client.rpc(
      'confirm_upi_payment',
      params: {
        'target_payment_id': paymentId,
        'operation_id': operationId,
        'verification_status': status,
        'verification_reference': reference.trim(),
        'confirmation_note': note.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<List<ReturnableSaleItem>> fetchReturnableSaleItems(
    String saleId,
  ) async {
    final results = await Future.wait([
      _client
          .from('sale_items')
          .select('id,product_name,variant_name,sku,quantity,line_total')
          .eq('sale_id', saleId)
          .order('created_at'),
      _client.from('sale_returns').select('id').eq('sale_id', saleId),
    ]);
    final returnIds = (results[1] as List)
        .map((row) => (row as Map)['id'] as String)
        .toList(growable: false);
    final returnedByItem = <String, double>{};
    if (returnIds.isNotEmpty) {
      final returnedRows = await _client
          .from('sale_return_items')
          .select('sale_item_id,quantity')
          .inFilter('return_id', returnIds);
      for (final row in returnedRows) {
        final itemId = row['sale_item_id'] as String;
        final quantity = double.tryParse(row['quantity'].toString()) ?? 0;
        returnedByItem[itemId] = (returnedByItem[itemId] ?? 0) + quantity;
      }
    }
    return (results[0] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .map(
          (row) => ReturnableSaleItem.fromJson(
            row,
            returnedByItem[row['id'] as String] ?? 0,
          ),
        )
        .where((item) => item.remainingQuantity > 0)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> processSaleReturn({
    required String saleId,
    required List<({String saleItemId, double quantity})> items,
    required String reason,
    Map<String, List<String>> serializedUnitIdsBySaleItem = const {},
  }) async {
    final params = <String, dynamic>{
      'target_sale_id': saleId,
      'operation_id': createUuidV4(),
      'return_lines': items
          .map(
            (item) => {
              'sale_item_id': item.saleItemId,
              'quantity': item.quantity,
              'restock': true,
            },
          )
          .toList(growable: false),
      'refund_method': 'cash',
      'return_reason': reason.trim(),
    };
    if (serializedUnitIdsBySaleItem.isNotEmpty) {
      params['serialized_unit_ids'] = serializedUnitIdsBySaleItem;
    }
    final response = await _client.rpc('process_sale_return', params: params);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, List<SerializedSaleReturnUnit>>>
  fetchSerializedSaleReturnUnits(String saleId) async {
    final saleItems = await _client
        .from('sale_items')
        .select('id,business_id')
        .eq('sale_id', saleId);
    if (saleItems.isEmpty) return const {};
    final itemRows = saleItems.cast<Map<String, dynamic>>();
    final businessId = itemRows.first['business_id'] as String;
    final itemIds = itemRows.map((row) => row['id'] as String).toList();

    final returnRows = await _client
        .from('sale_returns')
        .select('id')
        .eq('sale_id', saleId);
    final returnIds = returnRows
        .map((row) => (row as Map)['id'] as String)
        .toList(growable: false);
    final returnedUnitIds = <String>{};
    if (returnIds.isNotEmpty) {
      final returnItemRows = await _client
          .from('sale_return_items')
          .select('id,sale_item_id')
          .inFilter('return_id', returnIds);
      final returnItemIds = returnItemRows
          .map((row) => (row as Map)['id'] as String)
          .toList(growable: false);
      if (returnItemIds.isNotEmpty) {
        final returnedRows = await _client
            .from('sale_return_item_serialized_units')
            .select('serialized_unit_id')
            .inFilter('return_item_id', returnItemIds);
        returnedUnitIds.addAll(
          returnedRows.map(
            (row) => (row as Map)['serialized_unit_id'] as String,
          ),
        );
      }
    }

    final links = await _client
        .from('sale_item_serialized_units')
        .select('sale_item_id,serialized_unit_id')
        .eq('business_id', businessId)
        .inFilter('sale_item_id', itemIds);
    final unitIds = links
        .map((row) => (row as Map)['serialized_unit_id'] as String)
        .where((id) => !returnedUnitIds.contains(id))
        .toList(growable: false);
    if (unitIds.isEmpty) return const {};
    final units = await _client
        .from('serialized_inventory_units')
        .select('id,identifier,tracking_mode,status')
        .inFilter('id', unitIds)
        .eq('business_id', businessId)
        .eq('status', 'sold');
    final unitById = <String, Map<String, dynamic>>{
      for (final row in units)
        (row['id'] as String): Map<String, dynamic>.from(row as Map),
    };
    final result = <String, List<SerializedSaleReturnUnit>>{};
    for (final row in links) {
      final link = Map<String, dynamic>.from(row as Map);
      final unitId = link['serialized_unit_id'] as String;
      final unit = unitById[unitId];
      if (unit == null) continue;
      result
          .putIfAbsent(link['sale_item_id'] as String, () => [])
          .add(
            SerializedSaleReturnUnit.fromJson({
              ...unit,
              'sale_item_id': link['sale_item_id'],
            }),
          );
    }
    return result;
  }

  Future<Map<String, dynamic>> processSaleCreditNoteReturn({
    required String saleId,
    required List<({String saleItemId, double quantity})> items,
    required String reason,
  }) async {
    final response = await _client.rpc(
      'process_sale_credit_note_return',
      params: {
        'target_sale_id': saleId,
        'operation_id': createUuidV4(),
        'return_lines': items
            .map(
              (item) => {
                'sale_item_id': item.saleItemId,
                'quantity': item.quantity,
                'restock': true,
              },
            )
            .toList(growable: false),
        'return_reason': reason.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> processSaleExchange({
    required String saleId,
    required String registerId,
    required String shiftId,
    required String warehouseId,
    required List<({String saleItemId, double quantity})> returnedItems,
    required List<PosCartLine> replacementItems,
    required String reason,
  }) async {
    final totals = calculatePosTotals(replacementItems);
    final response = await _client.rpc(
      'process_sale_exchange',
      params: {
        'target_sale_id': saleId,
        'operation_id': createUuidV4(),
        'target_register_id': registerId,
        'target_shift_id': shiftId,
        'return_lines': returnedItems
            .map(
              (item) => {
                'sale_item_id': item.saleItemId,
                'quantity': item.quantity,
                'restock': true,
              },
            )
            .toList(growable: false),
        'replacement_lines': replacementItems
            .map(
              (item) => {
                'variant_id': item.product.variantId,
                'warehouse_id': warehouseId,
                'quantity': item.quantity,
                'unit_price': item.product.salePriceForRpc,
                'discount_amount': 0,
                'tax_rate': item.product.taxRateBasisPoints / 100,
              },
            )
            .toList(growable: false),
        'replacement_payment_total': totals.totalMinor / 100,
        'exchange_reason': reason.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }
}

String _csvCell(Object? value) {
  final text = value?.toString() ?? '';
  if (!text.contains(RegExp(r'[",\n\r]'))) return text;
  return '"${text.replaceAll('"', '""')}"';
}

String createUuidV4() {
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
