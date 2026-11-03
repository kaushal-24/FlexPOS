class WarehouseRecord {
  const WarehouseRecord({
    required this.id,
    required this.businessId,
    required this.branchId,
    required this.name,
    required this.code,
    required this.isDefault,
    required this.isActive,
    this.createdAt,
    this.updatedAt,
  });

  factory WarehouseRecord.fromJson(Map<String, dynamic> json) {
    return WarehouseRecord(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      branchId: json['branch_id'] as String,
      name: json['name'] as String,
      code: json['code'] as String,
      isDefault: json['is_default'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
    );
  }

  final String id;
  final String businessId;
  final String branchId;
  final String name;
  final String code;
  final bool isDefault;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}
