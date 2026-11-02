import 'package:flexpos/features/accounting/application/sales_aggregation.dart';
import 'package:flexpos/features/accounting/domain/accounting_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final points = [
    DailySalesPoint(date: DateTime(2025, 12, 31), totalMinor: 10000, orders: 1),
    DailySalesPoint(date: DateTime(2026, 1, 1), totalMinor: 25000, orders: 2),
    DailySalesPoint(date: DateTime(2026, 2, 15), totalMinor: -5000, orders: 0),
    DailySalesPoint(date: DateTime(2026, 4, 2), totalMinor: 40000, orders: 4),
  ];

  test('weekly aggregation uses Monday calendar boundaries', () {
    final result = aggregateSales(
      points.take(2).toList(),
      SalesInterval.weekly,
    );

    expect(result, hasLength(1));
    expect(result.single.periodStart, DateTime(2025, 12, 29));
    expect(result.single.totalMinor, 35000);
    expect(result.single.orders, 3);
  });

  test('monthly aggregation preserves totals and chronological order', () {
    final result = aggregateSales(points, SalesInterval.monthly);

    expect(result.map((item) => item.periodStart), [
      DateTime(2025, 12),
      DateTime(2026, 1),
      DateTime(2026, 2),
      DateTime(2026, 4),
    ]);
    expect(result.fold<int>(0, (sum, item) => sum + item.totalMinor), 70000);
    expect(result.fold<int>(0, (sum, item) => sum + item.orders), 7);
  });

  test('quarterly aggregation groups calendar quarters', () {
    final result = aggregateSales(points, SalesInterval.quarterly);

    expect(result, hasLength(3));
    expect(result[0].periodStart, DateTime(2025, 10));
    expect(result[1].periodStart, DateTime(2026, 1));
    expect(result[1].totalMinor, 20000);
    expect(result[2].periodStart, DateTime(2026, 4));
    expect(
      formatSalesPeriod(result[2].periodStart, SalesInterval.quarterly),
      'Q2 2026',
    );
  });

  test('yearly aggregation groups and labels calendar years', () {
    final result = aggregateSales(points, SalesInterval.yearly);

    expect(result, hasLength(2));
    expect(result[0].periodStart, DateTime(2025));
    expect(result[0].totalMinor, 10000);
    expect(result[1].periodStart, DateTime(2026));
    expect(result[1].totalMinor, 60000);
    expect(
      formatSalesPeriod(result[1].periodStart, SalesInterval.yearly),
      '2026',
    );
  });
}
