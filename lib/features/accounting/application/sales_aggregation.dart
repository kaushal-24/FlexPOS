import 'package:flexpos/features/accounting/domain/accounting_models.dart';
import 'package:intl/intl.dart';

enum SalesInterval { daily, weekly, monthly, quarterly, yearly }

extension SalesIntervalX on SalesInterval {
  String get label => switch (this) {
    SalesInterval.daily => 'Daily',
    SalesInterval.weekly => 'Weekly',
    SalesInterval.monthly => 'Monthly',
    SalesInterval.quarterly => 'Quarterly',
    SalesInterval.yearly => 'Yearly',
  };
}

class SalesAggregate {
  const SalesAggregate({
    required this.periodStart,
    required this.totalMinor,
    required this.orders,
  });

  final DateTime periodStart;
  final int totalMinor;
  final int orders;
}

List<SalesAggregate> aggregateSales(
  List<DailySalesPoint> points,
  SalesInterval interval,
) {
  final totals = <DateTime, ({int totalMinor, int orders})>{};
  for (final point in points) {
    final periodStart = salesPeriodStart(point.date, interval);
    final current = totals[periodStart];
    totals[periodStart] = (
      totalMinor: (current?.totalMinor ?? 0) + point.totalMinor,
      orders: (current?.orders ?? 0) + point.orders,
    );
  }

  final starts = totals.keys.toList()..sort();
  return [
    for (final start in starts)
      SalesAggregate(
        periodStart: start,
        totalMinor: totals[start]!.totalMinor,
        orders: totals[start]!.orders,
      ),
  ];
}

DateTime salesPeriodStart(DateTime date, SalesInterval interval) {
  final day = DateTime(date.year, date.month, date.day);
  return switch (interval) {
    SalesInterval.daily => day,
    SalesInterval.weekly => day.subtract(Duration(days: day.weekday - 1)),
    SalesInterval.monthly => DateTime(day.year, day.month),
    SalesInterval.quarterly => DateTime(
      day.year,
      ((day.month - 1) ~/ 3) * 3 + 1,
    ),
    SalesInterval.yearly => DateTime(day.year),
  };
}

String formatSalesPeriod(DateTime periodStart, SalesInterval interval) =>
    switch (interval) {
      SalesInterval.daily => DateFormat.MMMd().format(periodStart),
      SalesInterval.weekly =>
        'Week of ${DateFormat.MMMd().format(periodStart)}',
      SalesInterval.monthly => DateFormat.yMMM().format(periodStart),
      SalesInterval.quarterly =>
        'Q${((periodStart.month - 1) ~/ 3) + 1} ${periodStart.year}',
      SalesInterval.yearly => periodStart.year.toString(),
    };
