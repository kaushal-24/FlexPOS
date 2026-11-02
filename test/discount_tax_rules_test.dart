import 'package:flexpos/features/catalog/domain/catalog_models.dart';
import 'package:flexpos/features/pos/domain/pos_calculations.dart';
import 'package:flexpos/features/promotions/domain/promotion_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const taxableProduct = CatalogProduct(
    productId: 'product-tax',
    variantId: 'variant-tax',
    name: 'Taxable item',
    variantName: 'Default',
    sku: 'TAX-1',
    priceMinor: 9999,
    costMinor: 5000,
    taxRateBasisPoints: 1750,
    trackInventory: true,
    allowFractionalQuantity: false,
    barcodes: [],
  );

  test('tax-exclusive lines apply the configured rate with cent rounding', () {
    final totals = calculatePosTotals([(product: taxableProduct, quantity: 1)]);

    expect(totals.subtotalMinor, 9999);
    expect(totals.taxMinor, 1750);
    expect(totals.totalMinor, 11749);
  });

  test('inclusive tax preserves gross quantity totals at repeating rates', () {
    const product = CatalogProduct(
      productId: 'product-inclusive',
      variantId: 'variant-inclusive',
      name: 'Inclusive item',
      variantName: 'Default',
      sku: 'INC-1',
      priceMinor: 10000,
      costMinor: 5000,
      taxRateBasisPoints: 1750,
      taxInclusive: true,
      trackInventory: true,
      allowFractionalQuantity: false,
      barcodes: [],
    );

    final totals = calculatePosTotals([(product: product, quantity: 3)]);

    expect(totals.subtotalMinor + totals.taxMinor, 30000);
    expect(totals.taxMinor, product.taxInclusiveTaxMinorForQuantity(3));
  });

  test(
    'order discounts accept the subtotal boundary and reject invalid values',
    () {
      expect(
        calculatePosTotals([
          (product: taxableProduct, quantity: 1),
        ], orderDiscountMinor: taxableProduct.priceMinor).totalMinor,
        1750,
      );
      expect(
        () => calculatePosTotals([
          (product: taxableProduct, quantity: 1),
        ], orderDiscountMinor: -1),
        throwsArgumentError,
      );
    },
  );

  test('percentage discount boundaries and rounding are deterministic', () {
    expect(percentageDiscountMinor(9999, 0), 0);
    expect(percentageDiscountMinor(9999, 10000), 9999);
    expect(percentageDiscountMinor(9999, 3333), 3333);
    expect(() => percentageDiscountMinor(10000, 10001), throwsArgumentError);
    expect(() => percentageDiscountMinor(10000, -1), throwsArgumentError);
  });

  test(
    'promotion usage limits distinguish unlimited, exact, and exhausted',
    () {
      Promotion promotion(Map<String, dynamic> values) => Promotion.fromJson({
        'id': 'promotion-1',
        'business_id': 'business-1',
        'branch_id': null,
        'code': 'SAVE10',
        'name': 'Save ten',
        'discount_type': 'percentage',
        'discount_value': '10.0000',
        'minimum_subtotal': '100.00',
        'usage_limit': values['usage_limit'],
        'redeemed_count': values['redeemed_count'] ?? 0,
        'starts_at': null,
        'ends_at': null,
        'is_active': true,
        'created_at': '2026-10-30T00:00:00Z',
      });

      expect(promotion({'usage_limit': null}).hasReachedUsageLimit, isFalse);
      expect(
        promotion({'usage_limit': 10, 'redeemed_count': 9})
            .hasReachedUsageLimit,
        isFalse,
      );
      expect(
        promotion({'usage_limit': 10, 'redeemed_count': 10})
            .hasReachedUsageLimit,
        isTrue,
      );
      expect(
        promotion({'usage_limit': 10, 'redeemed_count': 11})
            .hasReachedUsageLimit,
        isTrue,
      );
    },
  );
}
