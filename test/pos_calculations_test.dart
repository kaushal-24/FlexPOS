import 'package:flexpos/features/catalog/domain/catalog_models.dart';
import 'package:flexpos/features/pos/domain/pos_calculations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const product = CatalogProduct(
    productId: 'product-1',
    variantId: 'variant-1',
    name: 'Taxed item',
    variantName: 'Default',
    sku: 'TAX-1',
    priceMinor: 10000,
    costMinor: 5000,
    taxRateBasisPoints: 1800,
    trackInventory: true,
    allowFractionalQuantity: false,
    barcodes: [],
  );

  test('POS totals keep tax and discounts in exact minor units', () {
    final totals = calculatePosTotals([
      (product: product, quantity: 2),
    ], orderDiscountMinor: 2500);

    expect(totals.subtotalMinor, 20000);
    expect(totals.taxMinor, 3600);
    expect(totals.orderDiscountMinor, 2500);
    expect(totals.totalMinor, 21100);
  });

  test('tax-inclusive shelf prices split into net subtotal and tax', () {
    const inclusiveProduct = CatalogProduct(
      productId: 'product-inclusive',
      variantId: 'variant-inclusive',
      name: 'Tax-inclusive item',
      variantName: 'Default',
      sku: 'INCLUSIVE-1',
      priceMinor: 11800,
      costMinor: 5000,
      taxRateBasisPoints: 1800,
      taxInclusive: true,
      trackInventory: true,
      allowFractionalQuantity: false,
      barcodes: [],
    );

    final totals = calculatePosTotals([
      (product: inclusiveProduct, quantity: 1),
    ]);

    expect(totals.subtotalMinor, 10000);
    expect(totals.taxMinor, 1800);
    expect(totals.totalMinor, 11800);
  });

  test('service charges are added after discounts in exact minor units', () {
    final totals = calculatePosTotals(
      [(product: product, quantity: 1)],
      orderDiscountMinor: 500,
      serviceChargeMinor: 1250,
    );

    expect(totals.subtotalMinor, 10000);
    expect(totals.taxMinor, 1800);
    expect(totals.orderDiscountMinor, 500);
    expect(totals.serviceChargeMinor, 1250);
    expect(totals.totalMinor, 12550);
  });

  test('cash rounding chooses the nearest configured denomination', () {
    expect(cashRoundingMinor(123, 5), 2);
    expect(cashRoundingMinor(122, 5), -2);
    expect(cashRoundingMinor(120, 5), 0);
  });

  test(
    'tax-inclusive totals preserve the gross shelf price after rounding',
    () {
      const inclusiveProduct = CatalogProduct(
        productId: 'product-inclusive',
        variantId: 'variant-inclusive',
        name: 'Tax-inclusive item',
        variantName: 'Default',
        sku: 'INCLUSIVE-1',
        priceMinor: 10000,
        costMinor: 5000,
        taxRateBasisPoints: 1800,
        taxInclusive: true,
        trackInventory: true,
        allowFractionalQuantity: false,
        barcodes: [],
      );

      final totals = calculatePosTotals([
        (product: inclusiveProduct, quantity: 2),
      ]);

      expect(totals.subtotalMinor, 16949);
      expect(totals.taxMinor, 3051);
      expect(totals.totalMinor, 20000);
    },
  );

  test('percentage discounts round deterministically', () {
    expect(percentageDiscountMinor(9999, 1250), 1250);
    expect(percentageDiscountMinor(10000, 10000), 10000);
  });

  test('discount cannot exceed the pre-tax subtotal', () {
    expect(
      () => calculatePosTotals([
        (product: product, quantity: 1),
      ], orderDiscountMinor: 10001),
      throwsArgumentError,
    );
  });

  test('split payment allocations total exact minor units', () {
    const lines = [
      PosPaymentLine(method: 'cash', amountMinor: 4000),
      PosPaymentLine(method: 'card', amountMinor: 3500),
      PosPaymentLine(method: 'wallet', amountMinor: 2500),
    ];

    expect(allocatedPaymentMinor(lines), 10000);
    expect(
      () => validatePosPaymentLines(lines, totalMinor: 10000),
      returnsNormally,
    );
  });

  test('split payment rejects an under-allocation', () {
    expect(
      () => validatePosPaymentLines(const [
        PosPaymentLine(method: 'cash', amountMinor: 9999),
      ], totalMinor: 10000),
      throwsArgumentError,
    );
  });

  test('cash change is exact and rejects insufficient tender', () {
    expect(
      calculateCashChangeMinor(cashDueMinor: 7350, cashTenderedMinor: 10000),
      2650,
    );
    expect(
      () =>
          calculateCashChangeMinor(cashDueMinor: 7350, cashTenderedMinor: 7000),
      throwsArgumentError,
    );
  });

  test('partial payment assigns the exact balance to customer credit', () {
    final lines = buildPartialPaymentLines(
      immediateMethod: 'cash',
      paidNowMinor: 6000,
      totalMinor: 11800,
    );

    expect(lines, hasLength(2));
    expect(lines.first.method, 'cash');
    expect(lines.first.amountMinor, 6000);
    expect(lines.last.method, 'customer_credit');
    expect(lines.last.amountMinor, 5800);
    expect(allocatedPaymentMinor(lines), 11800);
  });

  test('partial payment rejects zero or fully paid amounts', () {
    expect(
      () => buildPartialPaymentLines(
        immediateMethod: 'cash',
        paidNowMinor: 0,
        totalMinor: 11800,
      ),
      throwsArgumentError,
    );
    expect(
      () => buildPartialPaymentLines(
        immediateMethod: 'cash',
        paidNowMinor: 11800,
        totalMinor: 11800,
      ),
      throwsArgumentError,
    );
  });
}
