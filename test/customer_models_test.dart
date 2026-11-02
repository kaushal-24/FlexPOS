import 'package:flexpos/features/customers/domain/customer_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('customer maps contact details and exact credit minor units', () {
    final customer = Customer.fromJson({
      'id': 'customer-1',
      'code': 'C-001',
      'name': 'Acme Retail',
      'phone': '9000000000',
      'email': 'accounts@example.test',
      'gstin': 'GSTIN-1',
      'credit_limit': '1250.75',
    });

    expect(customer.creditLimitMinor, 125075);
    expect(customer.searchText, contains('9000000000'));
    expect(customer.searchText, contains('accounts@example.test'));
  });

  test('purchase history maps refunds, item count, and exact net spend', () {
    final purchase = CustomerPurchase.fromJson({
      'id': 'sale-1',
      'invoice_number': 'FP-1001',
      'grand_total': '125.50',
      'payment_status': 'paid',
      'status': 'partially_refunded',
      'completed_at': '2026-10-24T08:30:00Z',
      'sale_items': [
        {'id': 'line-1'},
        {'id': 'line-2'},
      ],
      'sale_returns': [
        {'refund_total': '20.25'},
        {'refund_total': '5.00'},
      ],
    });

    expect(purchase.itemCount, 2);
    expect(purchase.grandTotalMinor, 12550);
    expect(purchase.refundedMinor, 2525);
    expect(purchase.netTotalMinor, 10025);
    expect(purchase.completedAt.isUtc, isFalse);
  });
}
