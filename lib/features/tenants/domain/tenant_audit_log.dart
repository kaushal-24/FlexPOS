class TenantAuditLog {
  const TenantAuditLog({
    required this.id,
    required this.businessId,
    required this.actorUserId,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.details,
    required this.createdAt,
  });

  factory TenantAuditLog.fromJson(Map<String, dynamic> json) {
    return TenantAuditLog(
      id: (json['id'] as num).toInt(),
      businessId: json['business_id'] as String,
      actorUserId: json['actor_user_id'] as String?,
      action: json['action'] as String,
      targetType: json['target_type'] as String,
      targetId: json['target_id'] as String?,
      details: Map<String, dynamic>.from(json['details'] as Map? ?? const {}),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final int id;
  final String businessId;
  final String? actorUserId;
  final String action;
  final String targetType;
  final String? targetId;
  final Map<String, dynamic> details;
  final DateTime createdAt;
}
