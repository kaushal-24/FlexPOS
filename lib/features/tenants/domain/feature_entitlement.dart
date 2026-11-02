abstract final class FeatureCodes {
  static const inventory = 'inventory';
  static const purchasing = 'purchasing';
  static const registers = 'registers';
  static const crm = 'crm';
  static const enterpriseOperations = 'enterprise_operations';
  static const hardwareOperations = 'hardware_operations';
  static const serviceRepair = 'service_repair';

  static bool isIndustryOperations(String code) =>
      code != enterpriseOperations &&
      code != hardwareOperations &&
      (code == serviceRepair || code.endsWith('_operations'));
}

class BusinessFeatureEntitlement {
  const BusinessFeatureEntitlement({
    required this.code,
    required this.name,
    required this.description,
    required this.category,
    required this.sortOrder,
    required this.isCore,
    required this.isEnabled,
    required this.source,
  });

  factory BusinessFeatureEntitlement.fromJson(Map<String, dynamic> json) {
    final feature = Map<String, dynamic>.from(json['feature_modules'] as Map);
    return BusinessFeatureEntitlement(
      code: feature['code'] as String,
      name: feature['name'] as String,
      description: feature['description'] as String,
      category: feature['category'] as String,
      sortOrder: feature['sort_order'] as int,
      isCore: feature['is_core'] as bool? ?? false,
      isEnabled: json['is_enabled'] as bool? ?? false,
      source: json['source'] as String? ?? 'business_type',
    );
  }

  final String code;
  final String name;
  final String description;
  final String category;
  final int sortOrder;
  final bool isCore;
  final bool isEnabled;
  final String source;
}
