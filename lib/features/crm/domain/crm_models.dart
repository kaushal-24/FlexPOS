abstract final class CrmModuleCodes {
  static const crm = 'crm';
}

abstract final class CrmPermissionCodes {
  static const view = 'crm.view';
  static const manage = 'crm.manage';
  static const quotationsManage = 'crm.quotations.manage';
}

class CrmLead {
  const CrmLead({
    required this.id,
    required this.title,
    this.source,
    required this.status,
    this.salespersonId,
    this.customerId,
    this.estimatedValueMinor,
    this.expectedCloseAt,
    this.notes,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
  });

  factory CrmLead.fromJson(Map<String, dynamic> json) => CrmLead(
    id: json['id'] as String,
    title: json['title'] as String,
    source: json['source'] as String?,
    status: json['status'] as String,
    salespersonId: json['salesperson_id'] as String?,
    customerId: json['customer_id'] as String?,
    estimatedValueMinor: _minorUnits(json['estimated_value']),
    expectedCloseAt: json['expected_close_at'] == null
        ? null
        : DateTime.parse(json['expected_close_at'] as String),
    notes: json['notes'] as String?,
    createdBy: json['created_by'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
    archivedAt: json['archived_at'] == null
        ? null
        : DateTime.parse(json['archived_at'] as String).toLocal(),
  );

  final String id;
  final String title;
  final String? source;
  final String status;
  final String? salespersonId;
  final String? customerId;
  final int? estimatedValueMinor;
  final DateTime? expectedCloseAt;
  final String? notes;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;
}

class CrmOpportunity {
  const CrmOpportunity({
    required this.id,
    required this.title,
    required this.stage,
    required this.probability,
    required this.valueMinor,
    this.expectedCloseAt,
    this.actualCloseAt,
    this.notes,
    this.salespersonId,
    this.customerId,
    this.leadId,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
  });

  factory CrmOpportunity.fromJson(Map<String, dynamic> json) => CrmOpportunity(
    id: json['id'] as String,
    title: json['title'] as String,
    stage: json['stage'] as String,
    probability: (json['probability'] as num).toInt(),
    valueMinor: (json['value_minor'] as num).toInt(),
    expectedCloseAt: json['expected_close_at'] == null
        ? null
        : DateTime.parse(json['expected_close_at'] as String),
    actualCloseAt: json['actual_close_at'] == null
        ? null
        : DateTime.parse(json['actual_close_at'] as String),
    notes: json['notes'] as String?,
    salespersonId: json['salesperson_id'] as String?,
    customerId: json['customer_id'] as String?,
    leadId: json['lead_id'] as String?,
    createdBy: json['created_by'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
    archivedAt: json['archived_at'] == null
        ? null
        : DateTime.parse(json['archived_at'] as String).toLocal(),
  );

  final String id;
  final String title;
  final String stage;
  final int probability;
  final int valueMinor;
  final DateTime? expectedCloseAt;
  final DateTime? actualCloseAt;
  final String? notes;
  final String? salespersonId;
  final String? customerId;
  final String? leadId;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;
  bool get isClosed => stage == 'closed_won' || stage == 'closed_lost';
}

class CrmQuotation {
  const CrmQuotation({
    required this.id,
    required this.quotationNumber,
    required this.title,
    required this.status,
    required this.subtotalMinor,
    required this.taxMinor,
    required this.discountMinor,
    required this.grandTotalMinor,
    this.validUntil,
    this.convertedSaleId,
    this.notes,
    this.salespersonId,
    this.customerId,
    this.opportunityId,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
  });

  factory CrmQuotation.fromJson(Map<String, dynamic> json) => CrmQuotation(
    id: json['id'] as String,
    quotationNumber: json['quotation_number'] as String,
    title: json['title'] as String,
    status: json['status'] as String,
    subtotalMinor: (json['subtotal_minor'] as num).toInt(),
    taxMinor: (json['tax_minor'] as num).toInt(),
    discountMinor: (json['discount_minor'] as num).toInt(),
    grandTotalMinor: (json['grand_total_minor'] as num).toInt(),
    validUntil: json['valid_until'] == null
        ? null
        : DateTime.parse(json['valid_until'] as String),
    convertedSaleId: json['converted_sale_id'] as String?,
    notes: json['notes'] as String?,
    salespersonId: json['salesperson_id'] as String?,
    customerId: json['customer_id'] as String?,
    opportunityId: json['opportunity_id'] as String?,
    createdBy: json['created_by'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
    archivedAt: json['archived_at'] == null
        ? null
        : DateTime.parse(json['archived_at'] as String).toLocal(),
  );

  final String id;
  final String quotationNumber;
  final String title;
  final String status;
  final int subtotalMinor;
  final int taxMinor;
  final int discountMinor;
  final int grandTotalMinor;
  final DateTime? validUntil;
  final String? convertedSaleId;
  final String? notes;
  final String? salespersonId;
  final String? customerId;
  final String? opportunityId;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;
  bool get isConverted => status == 'converted';
}

class CrmFollowUp {
  const CrmFollowUp({
    required this.id,
    required this.title,
    required this.type,
    required this.dueAt,
    this.completedAt,
    this.notes,
    this.salespersonId,
    this.leadId,
    this.opportunityId,
    this.quotationId,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CrmFollowUp.fromJson(Map<String, dynamic> json) => CrmFollowUp(
    id: json['id'] as String,
    title: json['title'] as String,
    type: json['type'] as String,
    dueAt: DateTime.parse(json['due_at'] as String).toLocal(),
    completedAt: json['completed_at'] == null
        ? null
        : DateTime.parse(json['completed_at'] as String).toLocal(),
    notes: json['notes'] as String?,
    salespersonId: json['salesperson_id'] as String?,
    leadId: json['lead_id'] as String?,
    opportunityId: json['opportunity_id'] as String?,
    quotationId: json['quotation_id'] as String?,
    createdBy: json['created_by'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
  );

  final String id;
  final String title;
  final String type;
  final DateTime dueAt;
  final DateTime? completedAt;
  final String? notes;
  final String? salespersonId;
  final String? leadId;
  final String? opportunityId;
  final String? quotationId;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isCompleted => completedAt != null;
  bool get isOverdue => !isCompleted && dueAt.isBefore(DateTime.now());
}

class CrmCustomerNote {
  const CrmCustomerNote({
    required this.id,
    required this.customerId,
    required this.note,
    required this.isPrivate,
    this.salespersonId,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CrmCustomerNote.fromJson(Map<String, dynamic> json) =>
      CrmCustomerNote(
        id: json['id'] as String,
        customerId: json['customer_id'] as String,
        note: json['note'] as String,
        isPrivate: json['is_private'] as bool? ?? true,
        salespersonId: json['salesperson_id'] as String?,
        createdBy: json['created_by'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
      );

  final String id;
  final String customerId;
  final String note;
  final bool isPrivate;
  final String? salespersonId;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class CrmReminder {
  const CrmReminder({
    required this.id,
    required this.title,
    this.description,
    required this.dueAt,
    required this.isCompleted,
    this.completedAt,
    this.relatedTable,
    this.relatedId,
    this.salespersonId,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CrmReminder.fromJson(Map<String, dynamic> json) => CrmReminder(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String?,
    dueAt: DateTime.parse(json['due_at'] as String).toLocal(),
    isCompleted: json['is_completed'] as bool? ?? false,
    completedAt: json['completed_at'] == null
        ? null
        : DateTime.parse(json['completed_at'] as String).toLocal(),
    relatedTable: json['related_table'] as String?,
    relatedId: json['related_id'] as String?,
    salespersonId: json['salesperson_id'] as String?,
    createdBy: json['created_by'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
  );

  final String id;
  final String title;
  final String? description;
  final DateTime dueAt;
  final bool isCompleted;
  final DateTime? completedAt;
  final String? relatedTable;
  final String? relatedId;
  final String? salespersonId;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isOverdue => !isCompleted && dueAt.isBefore(DateTime.now());
}

int? _minorUnits(Object? value) {
  if (value == null) return null;
  final amount = value is num
      ? value.toDouble()
      : double.tryParse(value.toString()) ?? 0;
  return (amount * 100).round();
}
