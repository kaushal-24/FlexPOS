class AccessControlOverview {
  const AccessControlOverview({
    required this.roles,
    required this.members,
    required this.permissions,
    required this.invitations,
  });

  final List<RoleSummary> roles;
  final List<MemberSummary> members;
  final List<PermissionSummary> permissions;
  final List<InvitationSummary> invitations;
}

class RoleSummary {
  const RoleSummary({
    required this.id,
    required this.name,
    required this.isSystem,
    required this.permissionCodes,
    this.description,
  });

  factory RoleSummary.fromJson(Map<String, dynamic> json) {
    return RoleSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      isSystem: json['is_system'] as bool? ?? false,
      permissionCodes: (json['role_permissions'] as List? ?? const [])
          .map(
            (item) =>
                Map<String, dynamic>.from(item as Map)['permission_code']
                    as String,
          )
          .toList(growable: false),
    );
  }

  final String id;
  final String name;
  final String? description;
  final bool isSystem;
  final List<String> permissionCodes;
}

class MemberSummary {
  const MemberSummary({
    required this.id,
    required this.userId,
    required this.roleId,
    required this.roleName,
    required this.status,
    required this.hasAllBranchAccess,
    required this.branchIds,
    this.email,
    this.fullName,
  });

  factory MemberSummary.fromJson(Map<String, dynamic> json) {
    final role = Map<String, dynamic>.from(json['roles'] as Map);
    return MemberSummary(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      roleId: role['id'] as String,
      roleName: role['name'] as String,
      status: json['status'] as String,
      hasAllBranchAccess: json['branch_access_all'] as bool? ?? false,
      branchIds: (json['member_branch_access'] as List? ?? const [])
          .map(
            (item) =>
                Map<String, dynamic>.from(item as Map)['branch_id'] as String,
          )
          .toList(growable: false),
      email: json['profile_email'] as String?,
      fullName: json['profile_name'] as String?,
    );
  }

  final String id;
  final String userId;
  final String roleId;
  final String roleName;
  final String status;
  final bool hasAllBranchAccess;
  final List<String> branchIds;
  final String? email;
  final String? fullName;
}

class PermissionSummary {
  const PermissionSummary({
    required this.code,
    required this.category,
    required this.description,
  });

  factory PermissionSummary.fromJson(Map<String, dynamic> json) {
    return PermissionSummary(
      code: json['code'] as String,
      category: json['category'] as String,
      description: json['description'] as String,
    );
  }

  final String code;
  final String category;
  final String description;
}

class InvitationSummary {
  const InvitationSummary({
    required this.id,
    required this.email,
    required this.roleName,
    required this.status,
    required this.expiresAt,
  });

  factory InvitationSummary.fromJson(Map<String, dynamic> json) {
    final role = Map<String, dynamic>.from(json['roles'] as Map);
    return InvitationSummary(
      id: json['id'] as String,
      email: json['email'] as String,
      roleName: role['name'] as String,
      status: json['status'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  final String id;
  final String email;
  final String roleName;
  final String status;
  final DateTime expiresAt;
}

class StaffInvitationResult {
  const StaffInvitationResult({
    required this.id,
    required this.email,
    required this.token,
    required this.expiresAt,
  });

  factory StaffInvitationResult.fromJson(Map<String, dynamic> json) {
    return StaffInvitationResult(
      id: json['invitation_id'] as String,
      email: json['email'] as String,
      token: json['token'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  final String id;
  final String email;
  final String token;
  final DateTime expiresAt;
}
