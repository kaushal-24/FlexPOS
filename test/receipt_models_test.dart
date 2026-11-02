import 'package:flexpos/features/receipts/application/receipt_pdf.dart';
import 'package:flexpos/features/receipts/domain/receipt_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final receipt = ReceiptDocument.fromRows(
    sale: {
      'id': 'sale-1',
      'invoice_number': 'FP-1001',
      'completed_at': '2026-10-20T10:30:00Z',
      'currency_code': 'INR',
      'status': 'completed',
      'payment_status': 'paid',
      'subtotal': '200.00',
      'discount_total': '25.00',
      'tax_total': '36.00',
      'service_charge_total': '0.00',
      'rounding_amount': '0.00',
      'grand_total': '211.00',
      'paid_total': '211.00',
      'due_total': '0.00',
      'notes': 'Counter sale',
    },
    business: {
      'name': 'FlexPOS Demo',
      'tax_registration_number': 'GST-123',
      'receipt_footer': 'Please visit again.',
    },
    branch: {
      'name': 'Main Branch',
      'phone': '+91 555 0100',
      'email': 'shop@example.test',
      'address_line_1': '1 Market Road',
      'address_line_2': null,
      'city': 'Bengaluru',
      'state_region': 'Karnataka',
      'postal_code': '560001',
      'country_code': 'IN',
    },
    customer: {'name': 'Sample Customer', 'phone': '555-0110', 'gstin': null},
    items: [
      {
        'product_name': 'Coffee Beans',
        'variant_name': 'Default',
        'sku': 'COF-1',
        'quantity': '2.000000',
        'unit_price': '100.0000',
        'discount_amount': '0.00',
        'tax_rate': '18.0000',
        'tax_amount': '36.00',
        'line_total': '236.00',
        'note': null,
      },
    ],
    payments: [
      {
        'payment_method': 'cash',
        'status': 'settled',
        'amount': '211.00',
        'reference': null,
      },
    ],
  );

  test('receipt reconstructs exact persisted totals and labels', () {
    expect(receipt.businessName, 'FlexPOS Demo');
    expect(
      receipt.branchAddress,
      '1 Market Road, Bengaluru, Karnataka, 560001, IN',
    );
    expect(receipt.subtotalMinor, 20000);
    expect(receipt.discountMinor, 2500);
    expect(receipt.taxMinor, 3600);
    expect(receipt.grandTotalMinor, 21100);
    expect(receipt.items.single.quantityText, '2');
    expect(receipt.payments.single.methodLabel, 'Cash');
    expect(receipt.fileName, 'FlexPOS-FP-1001.pdf');
  });

  test('receipt PDF generator emits a valid 80 mm receipt', () async {
    expect(flexPosReceiptPageFormat.width, closeTo(80 * 72 / 25.4, 0.001));
    final bytes = await buildReceiptPdf(receipt);
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('receipt PDF generator emits a valid 58 mm receipt', () async {
    expect(
      ReceiptPaperSize.mm58.pageFormat.width,
      closeTo(58 * 72 / 25.4, 0.001),
    );
    final bytes = await buildReceiptPdf(
      receipt,
      ReceiptPaperSize.mm58.pageFormat,
    );
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
