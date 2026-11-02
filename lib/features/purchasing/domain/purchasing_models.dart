class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    this.code,
    this.contactName,
    this.phone,
    this.email,
    this.gstin,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
    id: json['id'] as String,
    name: json['name'] as String,
    code: json['code'] as String?,
    contactName: json['contact_name'] as String?,
    phone: json['phone'] as String?,
    email: json['email'] as String?,
    gstin: json['gstin'] as String?,
  );

  final String id;
  final String name;
  final String? code;
  final String? contactName;
  final String? phone;
  final String? email;
  final String? gstin;
}

class PurchaseOrderLine {
  const PurchaseOrderLine({
    required this.id,
    required this.variantId,
    required this.productName,
    required this.sku,
    required this.orderedQuantity,
    required this.receivedQuantity,
    required this.returnedQuantity,
    required this.unitCostMinor,
    required this.taxRateBasisPoints,
    this.trackingMode = 'none',
  });

  factory PurchaseOrderLine.fromJson(Map<String, dynamic> json) {
    final variant = json['product_variants'] == null
        ? null
        : Map<String, dynamic>.from(json['product_variants'] as Map);
    return PurchaseOrderLine(
      id: json['id'] as String,
      variantId: json['variant_id'] as String,
      productName: json['product_name'] as String,
      sku: json['sku'] as String,
      orderedQuantity: _decimal(json['ordered_quantity']),
      receivedQuantity: _decimal(json['received_quantity']),
      returnedQuantity: (json['purchase_return_items'] as List? ?? const [])
          .fold<double>(
            0,
            (total, row) => total + _decimal((row as Map)['quantity']),
          ),
      unitCostMinor: _minorUnits(json['unit_cost']),
      taxRateBasisPoints: (_decimal(json['tax_rate']) * 100).round(),
      trackingMode: variant?['tracking_mode'] as String? ?? 'none',
    );
  }

  final String id;
  final String variantId;
  final String productName;
  final String sku;
  final double orderedQuantity;
  final double receivedQuantity;
  final double returnedQuantity;
  final int unitCostMinor;
  final int taxRateBasisPoints;
  final String trackingMode;

  double get remainingQuantity => orderedQuantity - receivedQuantity;
  double get returnableQuantity => receivedQuantity - returnedQuantity;
  bool get isSerialized => trackingMode == 'serial' || trackingMode == 'imei';
  String get identifierLabel =>
      trackingMode == 'imei' ? 'IMEI' : 'serial number';
}

class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.orderNumber,
    required this.supplierName,
    required this.warehouseName,
    required this.status,
    required this.grandTotalMinor,
    required this.orderedAt,
    required this.lines,
  });

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    final supplier = Map<String, dynamic>.from(json['suppliers'] as Map);
    final warehouse = Map<String, dynamic>.from(json['warehouses'] as Map);
    return PurchaseOrder(
      id: json['id'] as String,
      orderNumber: json['order_number'] as String,
      supplierName: supplier['name'] as String,
      warehouseName: warehouse['name'] as String,
      status: json['status'] as String,
      grandTotalMinor: _minorUnits(json['grand_total']),
      orderedAt: DateTime.parse(json['ordered_at'] as String).toLocal(),
      lines: (json['purchase_order_items'] as List? ?? const [])
          .map(
            (row) => PurchaseOrderLine.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  final String id;
  final String orderNumber;
  final String supplierName;
  final String warehouseName;
  final String status;
  final int grandTotalMinor;
  final DateTime orderedAt;
  final List<PurchaseOrderLine> lines;

  bool get canReceive => status == 'ordered' || status == 'partially_received';
  bool get canReturn =>
      (status == 'partially_received' || status == 'received') &&
      lines.any((line) => line.returnableQuantity > 0);
}

double _decimal(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;
int _minorUnits(Object? value) => (_decimal(value) * 100).round();
