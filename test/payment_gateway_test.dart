import 'package:flexpos/features/payments/domain/payment_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UPI and Razorpay keep distinct provider audit values', () {
    expect(providerCodeForPaymentMethod('upi'), 'upi_manual');
    expect(providerCodeForPaymentMethod(' UPI '), 'upi_manual');
    expect(providerCodeForPaymentMethod('razorpay'), 'razorpay_upi');
    expect(backendPaymentMethodForPos('razorpay'), 'upi');
  });

  test('internal tenders do not select an external gateway', () {
    for (final method in [
      'cash',
      'card',
      'bank_transfer',
      'wallet',
      'gift_card',
    ]) {
      expect(providerCodeForPaymentMethod(method), isNull);
    }
  });
}
