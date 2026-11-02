import 'package:flexpos/features/tenants/domain/feature_entitlement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('feature entitlement maps the nested Supabase response', () {
    final feature = BusinessFeatureEntitlement.fromJson({
      'is_enabled': true,
      'source': 'administrator',
      'feature_modules': {
        'code': FeatureCodes.inventory,
        'name': 'Inventory',
        'description': 'Stock tracking and adjustments.',
        'category': 'operations',
        'sort_order': 100,
        'is_core': false,
        'is_available': true,
      },
    });

    expect(feature.code, FeatureCodes.inventory);
    expect(feature.isEnabled, isTrue);
    expect(feature.isCore, isFalse);
    expect(feature.source, 'administrator');
    expect(feature.sortOrder, 100);
    expect(FeatureCodes.crm, 'crm');
  });

  test('industry navigation recognizes only industry entitlements', () {
    expect(
      FeatureCodes.isIndustryOperations(FeatureCodes.serviceRepair),
      isTrue,
    );
    expect(FeatureCodes.isIndustryOperations('restaurant_operations'), isTrue);
    expect(
      FeatureCodes.isIndustryOperations(FeatureCodes.enterpriseOperations),
      isFalse,
    );
    expect(
      FeatureCodes.isIndustryOperations(FeatureCodes.hardwareOperations),
      isFalse,
    );
  });
}
