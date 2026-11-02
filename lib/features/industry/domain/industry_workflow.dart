class IndustryWorkflow {
  const IndustryWorkflow({
    required this.id,
    required this.businessId,
    required this.moduleCode,
    required this.workflowKind,
    required this.referenceCode,
    required this.title,
    required this.status,
    required this.createdAt,
    this.branchId,
    this.customerId,
    this.productId,
    this.assignedTo,
    this.scheduledAt,
    this.dueAt,
    this.quantity = 0,
    this.unitPrice = 0,
    this.totalAmount = 0,
    this.depositAmount = 0,
    this.payload = const {},
  });

  factory IndustryWorkflow.fromJson(Map<String, dynamic> json) {
    return IndustryWorkflow(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      branchId: json['branch_id'] as String?,
      moduleCode: json['module_code'] as String,
      workflowKind: json['workflow_kind'] as String,
      referenceCode: json['reference_code'] as String,
      title: json['title'] as String,
      status: json['status'] as String,
      customerId: json['customer_id'] as String?,
      productId: json['product_id'] as String?,
      assignedTo: json['assigned_to'] as String?,
      scheduledAt: _date(json['scheduled_at']),
      dueAt: _date(json['due_at']),
      quantity: _number(json['quantity']),
      unitPrice: _number(json['unit_price']),
      totalAmount: _number(json['total_amount']),
      depositAmount: _number(json['deposit_amount']),
      payload: Map<String, dynamic>.from(
        (json['payload'] as Map?) ?? const <String, dynamic>{},
      ),
      createdAt: _date(json['created_at']) ?? DateTime.now(),
    );
  }

  final String id;
  final String businessId;
  final String? branchId;
  final String moduleCode;
  final String workflowKind;
  final String referenceCode;
  final String title;
  final String status;
  final String? customerId;
  final String? productId;
  final String? assignedTo;
  final DateTime? scheduledAt;
  final DateTime? dueAt;
  final double quantity;
  final double unitPrice;
  final double totalAmount;
  final double depositAmount;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

  static double _number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
}

class IndustryModuleDefinition {
  const IndustryModuleDefinition({
    required this.code,
    required this.name,
    required this.description,
    required this.icon,
    required this.kinds,
  });

  final String code;
  final String name;
  final String description;
  final int icon;
  final List<IndustryWorkflowKind> kinds;
}

class IndustryWorkflowKind {
  const IndustryWorkflowKind(this.value, this.label);

  final String value;
  final String label;
}

const industryModuleDefinitions = <IndustryModuleDefinition>[
  IndustryModuleDefinition(
    code: 'restaurant_operations',
    name: 'Restaurant and cafe',
    description:
        'Tables, orders, kitchen, modifiers, recipes, bills, and tips.',
    icon: 0xe56c,
    kinds: [
      IndustryWorkflowKind('restaurant_table', 'Table'),
      IndustryWorkflowKind('floor_plan', 'Floor plan'),
      IndustryWorkflowKind('dine_in_order', 'Dine-in order'),
      IndustryWorkflowKind('takeaway_order', 'Takeaway order'),
      IndustryWorkflowKind('delivery_order', 'Delivery order'),
      IndustryWorkflowKind('kitchen_ticket', 'Kitchen ticket / KDS'),
      IndustryWorkflowKind('menu_modifier', 'Menu modifier'),
      IndustryWorkflowKind('split_bill', 'Split bill'),
      IndustryWorkflowKind('recipe', 'Recipe'),
      IndustryWorkflowKind('tip', 'Tip'),
      IndustryWorkflowKind('restaurant_order', 'Restaurant order'),
    ],
  ),
  IndustryModuleDefinition(
    code: 'service_repair',
    name: 'Service and repair center',
    description:
        'Job cards, serials, warranties, diagnostics, quotes, and delivery.',
    icon: 0xe8b8,
    kinds: [
      IndustryWorkflowKind('service_job', 'Job card'),
      IndustryWorkflowKind('serial_warranty', 'Serial / warranty'),
      IndustryWorkflowKind('technician_assignment', 'Technician allocation'),
      IndustryWorkflowKind('diagnostic', 'Diagnostic'),
      IndustryWorkflowKind('repair_quote', 'Repair quotation'),
      IndustryWorkflowKind('spare_part', 'Spare part'),
      IndustryWorkflowKind('labor', 'Labor'),
      IndustryWorkflowKind('repair_stage', 'Repair stage'),
      IndustryWorkflowKind('maintenance_contract', 'Maintenance contract'),
      IndustryWorkflowKind('customer_delivery', 'Customer delivery'),
    ],
  ),
  IndustryModuleDefinition(
    code: 'wholesale_b2b',
    name: 'Wholesale and B2B',
    description:
        'Dealer pricing, quotations, credit terms, fulfillment, and dispatch.',
    icon: 0xe8f8,
    kinds: [
      IndustryWorkflowKind('dealer_price', 'Dealer price'),
      IndustryWorkflowKind('bulk_discount', 'Bulk discount'),
      IndustryWorkflowKind('b2b_quote', 'B2B quotation'),
      IndustryWorkflowKind('b2b_order', 'B2B order'),
      IndustryWorkflowKind('credit_term', 'Credit term'),
      IndustryWorkflowKind('partial_fulfillment', 'Partial fulfillment'),
      IndustryWorkflowKind('challan', 'Challan'),
      IndustryWorkflowKind('dispatch', 'Dispatch'),
    ],
  ),
  IndustryModuleDefinition(
    code: 'grocery_operations',
    name: 'Grocery',
    description:
        'Weight sales, conversions, batches, expiry, and barcode checkout.',
    icon: 0xe56b,
    kinds: [
      IndustryWorkflowKind('weight_sale', 'Weight-based sale'),
      IndustryWorkflowKind('unit_conversion', 'Unit conversion'),
      IndustryWorkflowKind('inventory_batch', 'Batch / expiry'),
      IndustryWorkflowKind('barcode_checkout', 'Barcode checkout'),
    ],
  ),
  IndustryModuleDefinition(
    code: 'fashion_operations',
    name: 'Fashion',
    description:
        'Size and color matrices, exchanges, and seasonal collections.',
    icon: 0xe54c,
    kinds: [
      IndustryWorkflowKind('size_color_matrix', 'Size / color matrix'),
      IndustryWorkflowKind('fashion_exchange', 'Fashion exchange'),
      IndustryWorkflowKind('seasonal_collection', 'Seasonal collection'),
    ],
  ),
  IndustryModuleDefinition(
    code: 'electronics_operations',
    name: 'Electronics',
    description: 'IMEI, warranty, serial-linked returns, and repairs.',
    icon: 0xe1a4,
    kinds: [
      IndustryWorkflowKind('imei_unit', 'IMEI unit'),
      IndustryWorkflowKind('electronics_warranty', 'Warranty'),
      IndustryWorkflowKind(
        'serialized_return_repair',
        'Serial return / repair',
      ),
    ],
  ),
  IndustryModuleDefinition(
    code: 'pharmacy_operations',
    name: 'Pharmacy',
    description: 'Batches, prescriptions, restrictions, and recalls.',
    icon: 0xe3f4,
    kinds: [
      IndustryWorkflowKind('pharmacy_batch', 'Batch / expiry'),
      IndustryWorkflowKind('prescription_reference', 'Prescription reference'),
      IndustryWorkflowKind('product_restriction', 'Product restriction'),
      IndustryWorkflowKind('product_recall', 'Recall'),
    ],
  ),
  IndustryModuleDefinition(
    code: 'salon_operations',
    name: 'Salon',
    description:
        'Appointments, services, packages, schedules, and commissions.',
    icon: 0xe87c,
    kinds: [
      IndustryWorkflowKind('appointment', 'Appointment'),
      IndustryWorkflowKind('salon_service', 'Service catalog'),
      IndustryWorkflowKind('salon_package', 'Package'),
      IndustryWorkflowKind('salon_commission', 'Commission'),
    ],
  ),
  IndustryModuleDefinition(
    code: 'manufacturing_operations',
    name: 'Light manufacturing',
    description:
        'BOMs, assembly, component consumption, costing, and production.',
    icon: 0xe332,
    kinds: [
      IndustryWorkflowKind('bill_of_materials', 'Bill of materials'),
      IndustryWorkflowKind('assembly_order', 'Assembly order'),
      IndustryWorkflowKind('component_consumption', 'Component consumption'),
      IndustryWorkflowKind('finished_goods_receipt', 'Finished-goods receipt'),
      IndustryWorkflowKind('manufacturing_cost', 'Manufacturing costing'),
      IndustryWorkflowKind('production_run', 'Production tracking'),
    ],
  ),
  IndustryModuleDefinition(
    code: 'rental_operations',
    name: 'Rental',
    description:
        'Asset availability, deposits, duration, returns, and damage charges.',
    icon: 0xe8b0,
    kinds: [
      IndustryWorkflowKind('rental_asset', 'Rental asset'),
      IndustryWorkflowKind('rental_deposit', 'Deposit'),
      IndustryWorkflowKind('rental_contract', 'Rental duration / pricing'),
      IndustryWorkflowKind('rental_return', 'Rental return'),
      IndustryWorkflowKind('damage_charge', 'Damage charge'),
    ],
  ),
];

String industryKindLabel(String value) {
  for (final module in industryModuleDefinitions) {
    for (final kind in module.kinds) {
      if (kind.value == value) return kind.label;
    }
  }
  return value.replaceAll('_', ' ');
}
