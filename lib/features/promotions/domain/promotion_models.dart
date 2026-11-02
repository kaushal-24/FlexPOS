class Promotion {
  const Promotion({
    required this.id,
    required this.businessId,
    required this.code,
    required this.name,
    required this.discountType,
    required this.discountValue,
    required this.minimumSubtotalMinor,
    required this.redeemedCount,
    required this.isActive,
    required this.createdAt,
    this.branchId,
    this.usageLimit,
    this.startsAt,
    this.endsAt,
  });

  factory Promotion.fromJson(Map<String, dynamic> json) => Promotion(
    id: json['id'] as String,
    businessId: json['business_id'] as String,
    branchId: json['branch_id'] as String?,
    code: json['code'] as String,
    name: json['name'] as String,
    discountType: json['discount_type'] as String,
    discountValue: _decimal(json['discount_value']),
    minimumSubtotalMinor: _minorUnits(json['minimum_subtotal']),
    usageLimit: (json['usage_limit'] as num?)?.toInt(),
    redeemedCount: (json['redeemed_count'] as num?)?.toInt() ?? 0,
    startsAt: _date(json['starts_at']),
    endsAt: _date(json['ends_at']),
    isActive: json['is_active'] as bool? ?? true,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
  );

  final String id;
  final String businessId;
  final String? branchId;
  final String code;
  final String name;
  final String discountType;
  final double discountValue;
  final int minimumSubtotalMinor;
  final int? usageLimit;
  final int redeemedCount;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool isActive;
  final DateTime createdAt;

  bool get isPercentage => discountType == 'percentage';

  String get discountLabel => isPercentage
      ? '${discountValue.toStringAsFixed(discountValue.truncateToDouble() == discountValue ? 0 : 2)}% off'
      : '${(discountValue).toStringAsFixed(2)} off';

  bool get hasReachedUsageLimit =>
      usageLimit != null && redeemedCount >= usageLimit!;
}

class CouponPreview {
  const CouponPreview({
    required this.promotionId,
    required this.code,
    required this.name,
    required this.discountMinor,
  });

  factory CouponPreview.fromJson(Map<String, dynamic> json) => CouponPreview(
    promotionId: json['promotion_id'] as String,
    code: json['promotion_code'] as String,
    name: json['promotion_name'] as String,
    discountMinor: _minorUnits(json['discount_amount']),
  );

  final String promotionId;
  final String code;
  final String name;
  final int discountMinor;
}

int _minorUnits(Object? value) {
  final amount = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
  return (amount * 100).round();
}

double _decimal(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();
