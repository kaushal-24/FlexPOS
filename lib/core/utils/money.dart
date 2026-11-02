import 'package:intl/intl.dart';

String formatMoney(String currencyCode, int minorUnits) =>
    NumberFormat.simpleCurrency(name: currencyCode).format(minorUnits / 100);

int? parseMoneyToMinor(String input) {
  final normalized = input.trim().replaceAll(',', '');
  if (!RegExp(r'^\d+(\.\d{0,2})?$').hasMatch(normalized)) return null;
  final parts = normalized.split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null) return null;
  final fraction = parts.length == 1 ? '' : parts[1];
  final cents = int.tryParse(fraction.padRight(2, '0')) ?? 0;
  return whole * 100 + cents;
}
