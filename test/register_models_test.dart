import 'package:flexpos/features/registers/domain/register_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('register shift maps exact reconciliation amounts', () {
    final shift = RegisterShift.fromJson({
      'id': 'shift-1',
      'register_id': 'register-1',
      'opened_by': 'user-1',
      'closed_by': 'user-1',
      'status': 'closed',
      'opening_cash': '500.00',
      'expected_cash': '724.20',
      'closing_cash': '700.00',
      'difference_amount': '-24.20',
      'opened_at': '2026-10-20T08:00:00Z',
      'closed_at': '2026-10-20T17:00:00Z',
      'notes': 'Short close',
      'registers': {
        'name': 'Front Counter',
        'code': 'FRONT-1',
        'branch_id': 'branch-1',
      },
    });

    expect(shift.isOpen, isFalse);
    expect(shift.openingCashMinor, 50000);
    expect(shift.expectedCashMinor, 72420);
    expect(shift.closingCashMinor, 70000);
    expect(shift.differenceMinor, -2420);
  });

  test('register close result preserves over and short values', () {
    final result = RegisterCloseResult.fromJson({
      'shift_id': 'shift-1',
      'expected_cash': 724.20,
      'closing_cash': 725.00,
      'difference': 0.80,
    });

    expect(result.expectedCashMinor, 72420);
    expect(result.closingCashMinor, 72500);
    expect(result.differenceMinor, 80);
  });

  test('X report maps exact cash movements, refunds, and payments', () {
    final report = RegisterShiftReport.fromJson({
      'report_type': 'X',
      'shift_id': 'shift-1',
      'status': 'open',
      'register_name': 'Front Counter',
      'register_code': 'FRONT-1',
      'opened_at': '2026-10-20T08:00:00Z',
      'sale_count': 1,
      'total_sales': '224.20',
      'total_refunds': '112.10',
      'opening_cash': '500.00',
      'cash_sales': '224.20',
      'cash_refunds': '112.10',
      'cash_in': '100.00',
      'cash_out': '50.00',
      'expected_cash': '662.10',
      'closing_cash': null,
      'difference': null,
      'payment_breakdown': [
        {'method': 'cash', 'amount': '112.10'},
      ],
    });

    expect(report.reportType, 'X');
    expect(report.saleCount, 1);
    expect(report.totalSalesMinor, 22420);
    expect(report.totalRefundsMinor, 11210);
    expect(report.cashInMinor, 10000);
    expect(report.cashOutMinor, 5000);
    expect(report.expectedCashMinor, 66210);
    expect(report.paymentBreakdown.single.amountMinor, 11210);
  });
}
