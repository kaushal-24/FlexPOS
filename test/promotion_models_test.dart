import 'package:flexpos/features/promotions/domain/promotion_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('promotion parses discount, usage, and lifecycle fields', () {
    final promotion = Promotion.fromJson({
      'id': 'promotion-1',
      'business_id': 'business-1',
      'branch_id': null,
      'code': 'WELCOME10',
      'name': 'Welcome ten percent',
      'discount_type': 'percentage',
      'discount_value': '10.0000',
      'minimum_subtotal': '250.00',
      'usage_limit': 50,
      'redeemed_count': 7,
      'starts_at': '2026-10-01T00:00:00Z',
      'ends_at': '2026-12-31T00:00:00Z',
      'is_active': true,
      'created_at': '2026-10-01T00:00:00Z',
    });

    expect(promotion.code, 'WELCOME10');
    expect(promotion.discountValue, 10);
    expect(promotion.minimumSubtotalMinor, 25000);
    expect(promotion.discountLabel, '10% off');
    expect(promotion.redeemedCount, 7);
    expect(promotion.hasReachedUsageLimit, isFalse);
    expect(promotion.startsAt, isNotNull);
  });

  test('coupon preview preserves exact discount minor units', () {
    final preview = CouponPreview.fromJson({
      'promotion_id': 'promotion-1',
      'promotion_code': 'SAVE25',
      'promotion_name': 'Save twenty five',
      'discount_amount': '25.50',
    });

    expect(preview.code, 'SAVE25');
    expect(preview.discountMinor, 2550);
  });
}
