class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.creditLimitMinor,
    this.code,
    this.phone,
    this.email,
    this.gstin,
    this.groupId,
    this.groupName,
    this.loyaltyPoints = 0,
  });

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
    id: json['id'] as String,
    name: json['name'] as String,
    code: json['code'] as String?,
    phone: json['phone'] as String?,
    email: json['email'] as String?,
    gstin: json['gstin'] as String?,
    groupId: json['group_id'] as String?,
    groupName: json['group_name'] as String?,
    loyaltyPoints: _decimal(json['loyalty_points']),
    creditLimitMinor: _minorUnits(json['credit_limit']),
  );

  final String id;
  final String name;
  final String? code;
  final String? phone;
  final String? email;
  final String? gstin;
  final String? groupId;
  final String? groupName;
  final double loyaltyPoints;
  final int creditLimitMinor;

  String get searchText =>
      '$name ${code ?? ''} ${phone ?? ''} ${email ?? ''} ${groupName ?? ''}'
          .toLowerCase();
}

class LoyaltyTransaction {
  const LoyaltyTransaction({
    required this.id,
    required this.transactionType,
    required this.pointsDelta,
    required this.balanceAfter,
    required this.createdAt,
    this.note,
  });

  factory LoyaltyTransaction.fromJson(Map<String, dynamic> json) =>
      LoyaltyTransaction(
        id: json['id'] as String,
        transactionType: json['transaction_type'] as String,
        pointsDelta: _decimal(json['points_delta']),
        balanceAfter: _decimal(json['balance_after']),
        note: json['note'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );

  final String id;
  final String transactionType;
  final double pointsDelta;
  final double balanceAfter;
  final String? note;
  final DateTime createdAt;
}

class CustomerGroup {
  const CustomerGroup({
    required this.id,
    required this.name,
    this.code,
    this.description,
    this.isActive = true,
  });

  factory CustomerGroup.fromJson(Map<String, dynamic> json) => CustomerGroup(
    id: json['id'] as String,
    name: json['name'] as String,
    code: json['code'] as String?,
    description: json['description'] as String?,
    isActive: json['is_active'] as bool? ?? true,
  );

  final String id;
  final String name;
  final String? code;
  final String? description;
  final bool isActive;
}

class CustomerPurchase {
  const CustomerPurchase({
    required this.saleId,
    required this.invoiceNumber,
    required this.grandTotalMinor,
    required this.refundedMinor,
    required this.paymentStatus,
    required this.status,
    required this.completedAt,
    required this.itemCount,
  });

  factory CustomerPurchase.fromJson(Map<String, dynamic> json) {
    final refundedMinor = (json['sale_returns'] as List? ?? const [])
        .whereType<Map>()
        .fold<int>(0, (total, row) => total + _minorUnits(row['refund_total']));
    return CustomerPurchase(
      saleId: json['id'] as String,
      invoiceNumber: json['invoice_number'] as String,
      grandTotalMinor: _minorUnits(json['grand_total']),
      refundedMinor: refundedMinor,
      paymentStatus: json['payment_status'] as String,
      status: json['status'] as String,
      completedAt: DateTime.parse(json['completed_at'] as String).toLocal(),
      itemCount: (json['sale_items'] as List? ?? const []).length,
    );
  }

  final String saleId;
  final String invoiceNumber;
  final int grandTotalMinor;
  final int refundedMinor;
  final String paymentStatus;
  final String status;
  final DateTime completedAt;
  final int itemCount;

  int get netTotalMinor => grandTotalMinor - refundedMinor;
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
