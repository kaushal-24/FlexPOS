class StockLossEvent {
  const StockLossEvent({
    required this.id,
    required this.eventNumber,
    required this.lossType,
    required this.productName,
    required this.variantName,
    required this.sku,
    required this.warehouseName,
    required this.quantity,
    required this.unitCostMinor,
    required this.lossValueMinor,
    required this.reason,
    required this.recordedAt,
    this.notes,
  });

  factory StockLossEvent.fromJson(Map<String, dynamic> json) {
    final warehouse = Map<String, dynamic>.from(json['warehouses'] as Map);
    return StockLossEvent(
      id: json['id'] as String,
      eventNumber: json['event_number'] as String,
      lossType: json['loss_type'] as String,
      productName: json['product_name'] as String,
      variantName: json['variant_name'] as String,
      sku: json['sku'] as String,
      warehouseName: warehouse['name'] as String,
      quantity: _decimal(json['quantity']),
      unitCostMinor: _minorUnits(json['unit_cost']),
      lossValueMinor: _minorUnits(json['loss_value']),
      reason: json['reason'] as String,
      notes: json['notes'] as String?,
      recordedAt: DateTime.parse(json['recorded_at'] as String).toLocal(),
    );
  }

  final String id;
  final String eventNumber;
  final String lossType;
  final String productName;
  final String variantName;
  final String sku;
  final String warehouseName;
  final double quantity;
  final int unitCostMinor;
  final int lossValueMinor;
  final String reason;
  final String? notes;
  final DateTime recordedAt;

  String get typeLabel => lossType == 'damage' ? 'Damage' : 'Wastage';
}

class SerializedInventoryUnit {
  const SerializedInventoryUnit({
    required this.id,
    required this.variantId,
    required this.warehouseId,
    required this.trackingMode,
    required this.identifier,
    required this.status,
    required this.productName,
    required this.variantName,
    required this.sku,
    required this.warehouseName,
    required this.registeredAt,
  });

  factory SerializedInventoryUnit.fromJson(Map<String, dynamic> json) {
    final warehouse = Map<String, dynamic>.from(json['warehouses'] as Map);
    return SerializedInventoryUnit(
      id: json['id'] as String,
      variantId: json['variant_id'] as String? ?? '',
      warehouseId: json['warehouse_id'] as String? ?? '',
      trackingMode: json['tracking_mode'] as String,
      identifier: json['identifier'] as String,
      status: json['status'] as String,
      productName: json['product_name'] as String,
      variantName: json['variant_name'] as String,
      sku: json['sku'] as String,
      warehouseName: warehouse['name'] as String,
      registeredAt: DateTime.parse(json['registered_at'] as String).toLocal(),
    );
  }

  final String id;
  final String variantId;
  final String warehouseId;
  final String trackingMode;
  final String identifier;
  final String status;
  final String productName;
  final String variantName;
  final String sku;
  final String warehouseName;
  final DateTime registeredAt;

  String get trackingLabel => trackingMode == 'imei' ? 'IMEI' : 'Serial';
  String get statusLabel => status
      .split('_')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
}

class InventoryTransferRequest {
  const InventoryTransferRequest({
    required this.id,
    required this.requestNumber,
    required this.status,
    required this.quantity,
    required this.reason,
    required this.sourceWarehouseId,
    required this.destinationWarehouseId,
    required this.variantId,
    required this.requestedAt,
  });

  factory InventoryTransferRequest.fromJson(Map<String, dynamic> json) {
    return InventoryTransferRequest(
      id: json['id'] as String,
      requestNumber: json['request_number'] as String,
      status: json['status'] as String,
      quantity: _decimal(json['quantity']),
      reason: json['reason'] as String,
      sourceWarehouseId: json['source_warehouse_id'] as String,
      destinationWarehouseId: json['destination_warehouse_id'] as String,
      variantId: json['variant_id'] as String,
      requestedAt: DateTime.parse(json['requested_at'] as String).toLocal(),
    );
  }

  final String id;
  final String requestNumber;
  final String status;
  final double quantity;
  final String reason;
  final String sourceWarehouseId;
  final String destinationWarehouseId;
  final String variantId;
  final DateTime requestedAt;

  String get statusLabel => status
      .split('_')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
}

class InventoryStocktakeItem {
  const InventoryStocktakeItem({
    required this.id,
    required this.stocktakeId,
    required this.variantId,
    required this.batchId,
    required this.systemQuantity,
    required this.countedQuantity,
    this.batchNumber,
    this.expiresOn,
  });

  factory InventoryStocktakeItem.fromJson(Map<String, dynamic> json) {
    final batch = json['batch'] is Map
        ? Map<String, dynamic>.from(json['batch'] as Map)
        : null;
    return InventoryStocktakeItem(
      id: json['id'] as String,
      stocktakeId: json['stocktake_id'] as String,
      variantId: json['variant_id'] as String,
      batchId: json['batch_id'] as String?,
      systemQuantity: _decimal(json['system_quantity']),
      countedQuantity: json['counted_quantity'] == null
          ? null
          : _decimal(json['counted_quantity']),
      batchNumber: batch?['batch_number'] as String?,
      expiresOn: batch?['expires_on'] as String?,
    );
  }

  final String id;
  final String stocktakeId;
  final String variantId;
  final String? batchId;
  final double systemQuantity;
  final double? countedQuantity;
  final String? batchNumber;
  final String? expiresOn;
}

double _decimal(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;

int _minorUnits(Object? value) => (_decimal(value) * 100).round();
