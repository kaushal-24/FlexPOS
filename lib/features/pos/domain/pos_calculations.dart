import 'package:flexpos/features/catalog/domain/catalog_models.dart';

typedef PosCartLine = ({CatalogProduct product, int quantity});

class PosTotals {
  const PosTotals({
    required this.subtotalMinor,
    required this.taxMinor,
    required this.orderDiscountMinor,
    this.serviceChargeMinor = 0,
    this.roundingMinor = 0,
  });

  final int subtotalMinor;
  final int taxMinor;
  final int orderDiscountMinor;
  final int serviceChargeMinor;
  final int roundingMinor;

  int get totalMinor =>
      subtotalMinor +
      taxMinor -
      orderDiscountMinor +
      serviceChargeMinor +
      roundingMinor;
}

class PosPaymentLine {
  const PosPaymentLine({
    required this.method,
    required this.amountMinor,
    this.reference,
    this.provider,
  });

  final String method;
  final int amountMinor;
  final String? reference;
  final String? provider;
}

int allocatedPaymentMinor(Iterable<PosPaymentLine> lines) =>
    lines.fold(0, (total, line) => total + line.amountMinor);

void validatePosPaymentLines(
  List<PosPaymentLine> lines, {
  required int totalMinor,
}) {
  if (totalMinor <= 0) {
    throw ArgumentError.value(totalMinor, 'totalMinor', 'Must be positive');
  }
  if (lines.isEmpty) {
    throw ArgumentError.value(
      lines,
      'lines',
      'At least one payment is required',
    );
  }
  if (lines.any((line) => line.amountMinor <= 0)) {
    throw ArgumentError.value(
      lines,
      'lines',
      'Every payment amount must be positive',
    );
  }
  final allocated = allocatedPaymentMinor(lines);
  if (allocated != totalMinor) {
    throw ArgumentError.value(
      allocated,
      'lines',
      'Payment total must equal the sale total',
    );
  }
}

int calculateCashChangeMinor({
  required int cashDueMinor,
  required int cashTenderedMinor,
}) {
  if (cashDueMinor < 0) {
    throw ArgumentError.value(
      cashDueMinor,
      'cashDueMinor',
      'Cannot be negative',
    );
  }
  if (cashTenderedMinor < cashDueMinor) {
    throw ArgumentError.value(
      cashTenderedMinor,
      'cashTenderedMinor',
      'Cannot be less than the cash due',
    );
  }
  return cashTenderedMinor - cashDueMinor;
}

List<PosPaymentLine> buildPartialPaymentLines({
  required String immediateMethod,
  required int paidNowMinor,
  required int totalMinor,
}) {
  if (paidNowMinor <= 0 || paidNowMinor >= totalMinor) {
    throw ArgumentError.value(
      paidNowMinor,
      'paidNowMinor',
      'Must be greater than zero and less than the sale total',
    );
  }
  final lines = [
    PosPaymentLine(method: immediateMethod, amountMinor: paidNowMinor),
    PosPaymentLine(
      method: 'customer_credit',
      amountMinor: totalMinor - paidNowMinor,
    ),
  ];
  validatePosPaymentLines(lines, totalMinor: totalMinor);
  return lines;
}

PosTotals calculatePosTotals(
  List<PosCartLine> items, {
  int orderDiscountMinor = 0,
  int serviceChargeMinor = 0,
  int roundingMinor = 0,
}) {
  var subtotalMinor = 0;
  var taxMinor = 0;
  for (final item in items) {
    if (item.quantity <= 0) {
      throw ArgumentError.value(item.quantity, 'quantity', 'Must be positive');
    }
    final grossLineSubtotal = item.product.priceMinor * item.quantity;
    final lineTax = item.product.taxInclusive
        ? item.product.taxInclusiveTaxMinorForQuantity(item.quantity)
        : ((item.product.salePriceMinor *
                      item.quantity *
                      item.product.taxRateBasisPoints) +
                  5000) ~/
              10000;
    subtotalMinor += item.product.taxInclusive
        ? grossLineSubtotal - lineTax
        : item.product.salePriceMinor * item.quantity;
    taxMinor += lineTax;
  }
  if (orderDiscountMinor < 0 || orderDiscountMinor > subtotalMinor) {
    throw ArgumentError.value(
      orderDiscountMinor,
      'orderDiscountMinor',
      'Must be between zero and the pre-tax subtotal',
    );
  }
  if (serviceChargeMinor < 0) {
    throw ArgumentError.value(
      serviceChargeMinor,
      'serviceChargeMinor',
      'Cannot be negative',
    );
  }
  if (roundingMinor.abs() > 1000) {
    throw ArgumentError.value(
      roundingMinor,
      'roundingMinor',
      'Cash rounding adjustment is too large',
    );
  }
  return PosTotals(
    subtotalMinor: subtotalMinor,
    taxMinor: taxMinor,
    orderDiscountMinor: orderDiscountMinor,
    serviceChargeMinor: serviceChargeMinor,
    roundingMinor: roundingMinor,
  );
}

int cashRoundingMinor(int amountMinor, int incrementMinor) {
  if (amountMinor <= 0) {
    throw ArgumentError.value(amountMinor, 'amountMinor', 'Must be positive');
  }
  if (incrementMinor <= 0) {
    throw ArgumentError.value(
      incrementMinor,
      'incrementMinor',
      'Must be positive',
    );
  }
  final remainder = amountMinor % incrementMinor;
  if (remainder == 0) return 0;
  final down = -remainder;
  final up = incrementMinor - remainder;
  return up < -down ? up : down;
}

int percentageDiscountMinor(int subtotalMinor, int percentageBasisPoints) {
  if (percentageBasisPoints < 0 || percentageBasisPoints > 10000) {
    throw ArgumentError.value(
      percentageBasisPoints,
      'percentageBasisPoints',
      'Must be between 0% and 100%',
    );
  }
  return ((subtotalMinor * percentageBasisPoints) + 5000) ~/ 10000;
}
