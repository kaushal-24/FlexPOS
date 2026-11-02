class EnterpriseRecord {
  const EnterpriseRecord({
    required this.id,
    required this.businessId,
    required this.recordType,
    required this.referenceCode,
    required this.title,
    required this.status,
    required this.amount,
    required this.createdAt,
    this.branchId,
    this.assignedTo,
    this.effectiveAt,
    this.dueAt,
    this.payload = const {},
  });

  factory EnterpriseRecord.fromJson(Map<String, dynamic> json) {
    return EnterpriseRecord(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      branchId: json['branch_id'] as String?,
      recordType: json['record_type'] as String,
      referenceCode: json['reference_code'] as String,
      title: json['title'] as String,
      status: json['status'] as String,
      assignedTo: json['assigned_to'] as String?,
      effectiveAt: _date(json['effective_at']),
      dueAt: _date(json['due_at']),
      amount: _number(json['amount']),
      payload: Map<String, dynamic>.from(
        (json['payload'] as Map?) ?? const <String, dynamic>{},
      ),
      createdAt: _date(json['created_at']) ?? DateTime.now(),
    );
  }

  final String id;
  final String businessId;
  final String? branchId;
  final String recordType;
  final String referenceCode;
  final String title;
  final String status;
  final String? assignedTo;
  final DateTime? effectiveAt;
  final DateTime? dueAt;
  final double amount;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

  static double _number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
}

class IntegrationConnection {
  const IntegrationConnection({
    required this.id,
    required this.businessId,
    required this.providerCode,
    required this.displayName,
    required this.status,
    required this.config,
    required this.updatedAt,
    this.secretRef,
    this.lastCheckedAt,
    this.lastError,
  });

  factory IntegrationConnection.fromJson(Map<String, dynamic> json) {
    return IntegrationConnection(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      providerCode: json['provider_code'] as String,
      displayName: json['display_name'] as String,
      status: json['status'] as String,
      secretRef: json['secret_ref'] as String?,
      config: Map<String, dynamic>.from(
        (json['config'] as Map?) ?? const <String, dynamic>{},
      ),
      lastCheckedAt: _date(json['last_checked_at']),
      lastError: json['last_error'] as String?,
      updatedAt: _date(json['updated_at']) ?? DateTime.now(),
    );
  }

  final String id;
  final String businessId;
  final String providerCode;
  final String displayName;
  final String status;
  final String? secretRef;
  final Map<String, dynamic> config;
  final DateTime? lastCheckedAt;
  final String? lastError;
  final DateTime updatedAt;

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toLocal();
}

class EnterpriseRecordType {
  const EnterpriseRecordType(this.code, this.label, this.description);

  final String code;
  final String label;
  final String description;
}

const enterpriseRecordTypes = <EnterpriseRecordType>[
  EnterpriseRecordType(
    'loyalty_tier',
    'Loyalty tier',
    'Points, benefits, and earn rules.',
  ),
  EnterpriseRecordType(
    'staff_schedule',
    'Staff schedule',
    'Shifts, availability, and assignments.',
  ),
  EnterpriseRecordType(
    'attendance',
    'Attendance',
    'Clock-in, clock-out, and exceptions.',
  ),
  EnterpriseRecordType(
    'staff_commission',
    'Staff commission',
    'Commission plan and payout review.',
  ),
  EnterpriseRecordType(
    'multi_register_snapshot',
    'Register dashboard',
    'Cross-register cash and shift health.',
  ),
  EnterpriseRecordType(
    'multi_branch_snapshot',
    'Branch dashboard',
    'Cross-branch operational health.',
  ),
  EnterpriseRecordType(
    'approval_workflow',
    'Approval workflow',
    'Review and approval state machine.',
  ),
  EnterpriseRecordType(
    'notification_alert',
    'Notification / alert',
    'Durable notification and escalation record.',
  ),
  EnterpriseRecordType(
    'customer_catalog',
    'Customer catalog',
    'Customer-facing product catalog publication.',
  ),
  EnterpriseRecordType(
    'online_order_request',
    'Online order request',
    'Stock-aware online order intake.',
  ),
  EnterpriseRecordType(
    'subscription_plan',
    'Subscription plan',
    'Tenant plan and entitlement record.',
  ),
  EnterpriseRecordType(
    'saas_admin',
    'SaaS administration',
    'Tenant lifecycle and administration action.',
  ),
  EnterpriseRecordType(
    'import_export_job',
    'Import / export job',
    'Validated data movement job.',
  ),
  EnterpriseRecordType(
    'backup_recovery_run',
    'Backup / recovery run',
    'Backup evidence and restore rehearsal.',
  ),
  EnterpriseRecordType(
    'barcode_label_job',
    'Barcode / label job',
    'Barcode and label generation batch.',
  ),
  EnterpriseRecordType(
    'gujarati_translation',
    'Gujarati translation',
    'Gujarati translation asset and review.',
  ),
  EnterpriseRecordType(
    'business_rule',
    'Business rule',
    'Configurable tenant rule.',
  ),
  EnterpriseRecordType(
    'integration_setting',
    'Integration setting',
    'Integration configuration metadata.',
  ),
  EnterpriseRecordType(
    'demand_forecast',
    'Demand forecast',
    'Forecast snapshot and confidence.',
  ),
  EnterpriseRecordType(
    'reorder_suggestion',
    'Reorder suggestion',
    'Intelligent replenishment recommendation.',
  ),
  EnterpriseRecordType(
    'sms_provider',
    'SMS provider',
    'Secure SMS adapter configuration boundary.',
  ),
  EnterpriseRecordType(
    'whatsapp_provider',
    'WhatsApp provider',
    'Secure WhatsApp adapter configuration boundary.',
  ),
  EnterpriseRecordType(
    'payment_gateway',
    'Payment gateway',
    'Secure payment adapter configuration boundary.',
  ),
  EnterpriseRecordType(
    'tax_service',
    'Tax service',
    'Secure tax adapter configuration boundary.',
  ),
  EnterpriseRecordType(
    'ai_provider',
    'AI provider',
    'Secure AI adapter configuration boundary.',
  ),
  EnterpriseRecordType(
    'integration_status',
    'Integration status',
    'Provider health and verification result.',
  ),
];

String enterpriseRecordTypeLabel(String code) => enterpriseRecordTypes
    .firstWhere(
      (item) => item.code == code,
      orElse: () => EnterpriseRecordType(code, code, ''),
    )
    .label;

class IntegrationProvider {
  const IntegrationProvider(this.code, this.label, this.description);

  final String code;
  final String label;
  final String description;
}

const integrationProviders = <IntegrationProvider>[
  IntegrationProvider('sms', 'SMS', 'Transactional SMS provider.'),
  IntegrationProvider('whatsapp', 'WhatsApp', 'WhatsApp Business provider.'),
  IntegrationProvider(
    'payment_gateway',
    'Payment gateway',
    'Payment adapter and webhook status.',
  ),
  IntegrationProvider(
    'tax_service',
    'Tax service',
    'Tax calculation / filing adapter.',
  ),
  IntegrationProvider(
    'ai',
    'AI provider',
    'AI-assisted forecasting or operations adapter.',
  ),
];

String integrationProviderLabel(String code) => integrationProviders
    .firstWhere(
      (item) => item.code == code,
      orElse: () => IntegrationProvider(code, code, ''),
    )
    .label;
