class PosRegister {
  const PosRegister({
    required this.id,
    required this.branchId,
    required this.name,
    required this.code,
    required this.isActive,
    this.assignedUserId,
  });

  factory PosRegister.fromJson(Map<String, dynamic> json) => PosRegister(
    id: json['id'] as String,
    branchId: json['branch_id'] as String,
    name: json['name'] as String,
    code: json['code'] as String,
    isActive: json['is_active'] as bool? ?? true,
    assignedUserId: json['assigned_user_id'] as String?,
  );

  final String id;
  final String branchId;
  final String name;
  final String code;
  final bool isActive;
  final String? assignedUserId;
}

class RegisterStaff {
  const RegisterStaff({
    required this.userId,
    required this.email,
    this.fullName,
    this.roleName,
  });

  final String userId;
  final String email;
  final String? fullName;
  final String? roleName;

  String get displayName =>
      (fullName?.trim().isNotEmpty ?? false) ? fullName!.trim() : email;
}

class RegisterShift {
  const RegisterShift({
    required this.id,
    required this.registerId,
    required this.registerName,
    required this.registerCode,
    required this.branchId,
    required this.openedBy,
    required this.status,
    required this.openingCashMinor,
    required this.openedAt,
    this.closedBy,
    this.expectedCashMinor,
    this.closingCashMinor,
    this.differenceMinor,
    this.closedAt,
    this.notes,
  });

  factory RegisterShift.fromJson(Map<String, dynamic> json) {
    final register = Map<String, dynamic>.from(json['registers'] as Map);
    return RegisterShift(
      id: json['id'] as String,
      registerId: json['register_id'] as String,
      registerName: register['name'] as String,
      registerCode: register['code'] as String,
      branchId: register['branch_id'] as String,
      openedBy: json['opened_by'] as String,
      closedBy: json['closed_by'] as String?,
      status: json['status'] as String,
      openingCashMinor: _minorUnits(json['opening_cash']) ?? 0,
      expectedCashMinor: _minorUnits(json['expected_cash']),
      closingCashMinor: _minorUnits(json['closing_cash']),
      differenceMinor: _minorUnits(json['difference_amount']),
      openedAt: DateTime.parse(json['opened_at'] as String).toLocal(),
      closedAt: json['closed_at'] == null
          ? null
          : DateTime.parse(json['closed_at'] as String).toLocal(),
      notes: _optionalText(json['notes']),
    );
  }

  final String id;
  final String registerId;
  final String registerName;
  final String registerCode;
  final String branchId;
  final String openedBy;
  final String? closedBy;
  final String status;
  final int openingCashMinor;
  final int? expectedCashMinor;
  final int? closingCashMinor;
  final int? differenceMinor;
  final DateTime openedAt;
  final DateTime? closedAt;
  final String? notes;

  bool get isOpen => status == 'open';
}

class RegisterOperationsSnapshot {
  const RegisterOperationsSnapshot({
    required this.registers,
    required this.shifts,
    required this.staff,
  });

  static const empty = RegisterOperationsSnapshot(
    registers: [],
    shifts: [],
    staff: [],
  );

  final List<PosRegister> registers;
  final List<RegisterShift> shifts;
  final List<RegisterStaff> staff;

  List<RegisterShift> get openShifts =>
      shifts.where((shift) => shift.isOpen).toList(growable: false);

  List<RegisterShift> get closedShifts =>
      shifts.where((shift) => !shift.isOpen).toList(growable: false);

  RegisterShift? openShiftFor(String registerId) =>
      openShifts.where((shift) => shift.registerId == registerId).firstOrNull;
}

class RegisterCloseResult {
  const RegisterCloseResult({
    required this.shiftId,
    required this.expectedCashMinor,
    required this.closingCashMinor,
    required this.differenceMinor,
  });

  factory RegisterCloseResult.fromJson(Map<String, dynamic> json) =>
      RegisterCloseResult(
        shiftId: json['shift_id'] as String,
        expectedCashMinor: _minorUnits(json['expected_cash']) ?? 0,
        closingCashMinor: _minorUnits(json['closing_cash']) ?? 0,
        differenceMinor: _minorUnits(json['difference']) ?? 0,
      );

  final String shiftId;
  final int expectedCashMinor;
  final int closingCashMinor;
  final int differenceMinor;
}

class RegisterPaymentTotal {
  const RegisterPaymentTotal({required this.method, required this.amountMinor});

  factory RegisterPaymentTotal.fromJson(Map<String, dynamic> json) =>
      RegisterPaymentTotal(
        method: json['method'] as String,
        amountMinor: _minorUnits(json['amount']) ?? 0,
      );

  final String method;
  final int amountMinor;
}

class RegisterShiftReport {
  const RegisterShiftReport({
    required this.reportType,
    required this.shiftId,
    required this.status,
    required this.registerName,
    required this.registerCode,
    required this.openedAt,
    required this.saleCount,
    required this.totalSalesMinor,
    required this.totalRefundsMinor,
    required this.openingCashMinor,
    required this.cashSalesMinor,
    required this.cashRefundsMinor,
    required this.cashInMinor,
    required this.cashOutMinor,
    required this.expectedCashMinor,
    required this.paymentBreakdown,
    this.closedAt,
    this.closingCashMinor,
    this.differenceMinor,
  });

  factory RegisterShiftReport.fromJson(Map<String, dynamic> json) =>
      RegisterShiftReport(
        reportType: json['report_type'] as String,
        shiftId: json['shift_id'] as String,
        status: json['status'] as String,
        registerName: json['register_name'] as String,
        registerCode: json['register_code'] as String,
        openedAt: DateTime.parse(json['opened_at'] as String).toLocal(),
        closedAt: json['closed_at'] == null
            ? null
            : DateTime.parse(json['closed_at'] as String).toLocal(),
        saleCount: (json['sale_count'] as num?)?.toInt() ?? 0,
        totalSalesMinor: _minorUnits(json['total_sales']) ?? 0,
        totalRefundsMinor: _minorUnits(json['total_refunds']) ?? 0,
        openingCashMinor: _minorUnits(json['opening_cash']) ?? 0,
        cashSalesMinor: _minorUnits(json['cash_sales']) ?? 0,
        cashRefundsMinor: _minorUnits(json['cash_refunds']) ?? 0,
        cashInMinor: _minorUnits(json['cash_in']) ?? 0,
        cashOutMinor: _minorUnits(json['cash_out']) ?? 0,
        expectedCashMinor: _minorUnits(json['expected_cash']) ?? 0,
        closingCashMinor: _minorUnits(json['closing_cash']),
        differenceMinor: _minorUnits(json['difference']),
        paymentBreakdown: (json['payment_breakdown'] as List? ?? const [])
            .map(
              (item) => RegisterPaymentTotal.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false),
      );

  final String reportType;
  final String shiftId;
  final String status;
  final String registerName;
  final String registerCode;
  final DateTime openedAt;
  final DateTime? closedAt;
  final int saleCount;
  final int totalSalesMinor;
  final int totalRefundsMinor;
  final int openingCashMinor;
  final int cashSalesMinor;
  final int cashRefundsMinor;
  final int cashInMinor;
  final int cashOutMinor;
  final int expectedCashMinor;
  final int? closingCashMinor;
  final int? differenceMinor;
  final List<RegisterPaymentTotal> paymentBreakdown;
}

int? _minorUnits(Object? value) {
  if (value == null) return null;
  final amount = value is num
      ? value.toDouble()
      : double.tryParse(value.toString());
  return amount == null ? null : (amount * 100).round();
}

String? _optionalText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
