class BusinessWorkspace {
  const BusinessWorkspace({
    required this.businessId,
    required this.businessName,
    required this.businessType,
    required this.currencyCode,
    required this.timezone,
    required this.membershipId,
    required this.roleId,
    required this.roleName,
    required this.permissionCodes,
    required this.branches,
    required this.hasAllBranchAccess,
    this.enabledFeatureCodes = const {},
    this.countryCode,
  });

  factory BusinessWorkspace.fromMembership(
    Map<String, dynamic> membership,
    List<BusinessBranch> branches, {
    Set<String> enabledFeatureCodes = const {},
  }) {
    final business = membership['businesses'] as Map<String, dynamic>;
    final role = membership['roles'] as Map<String, dynamic>;
    return BusinessWorkspace(
      businessId: business['id'] as String,
      businessName: business['name'] as String,
      businessType: business['business_type'] as String,
      currencyCode: business['currency_code'] as String,
      timezone: business['timezone'] as String,
      countryCode: business['country_code'] as String?,
      membershipId: membership['id'] as String,
      roleId: role['id'] as String,
      roleName: role['name'] as String,
      permissionCodes: (role['role_permissions'] as List? ?? const [])
          .map(
            (item) =>
                Map<String, dynamic>.from(item as Map)['permission_code']
                    as String,
          )
          .toSet(),
      branches: branches,
      hasAllBranchAccess: membership['branch_access_all'] as bool? ?? false,
      enabledFeatureCodes: enabledFeatureCodes,
    );
  }

  final String businessId;
  final String businessName;
  final String businessType;
  final String currencyCode;
  final String timezone;
  final String? countryCode;
  final String membershipId;
  final String roleId;
  final String roleName;
  final Set<String> permissionCodes;
  final List<BusinessBranch> branches;
  final bool hasAllBranchAccess;
  final Set<String> enabledFeatureCodes;

  bool isFeatureEnabled(String code) => enabledFeatureCodes.contains(code);
}

class BusinessBranch {
  const BusinessBranch({
    required this.id,
    required this.businessId,
    required this.name,
    required this.code,
    required this.timezone,
  });

  factory BusinessBranch.fromJson(Map<String, dynamic> json) {
    return BusinessBranch(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      name: json['name'] as String,
      code: json['code'] as String,
      timezone: json['timezone'] as String,
    );
  }

  final String id;
  final String businessId;
  final String name;
  final String code;
  final String timezone;
}

class CreateBusinessRequest {
  const CreateBusinessRequest({
    required this.businessName,
    required this.businessType,
    required this.currencyCode,
    required this.timezone,
    required this.branchName,
    required this.branchCode,
    required this.countryCode,
  });

  final String businessName;
  final String businessType;
  final String currencyCode;
  final String timezone;
  final String branchName;
  final String branchCode;
  final String countryCode;

  Map<String, dynamic> toRpcParameters() => {
    'business_name': businessName.trim(),
    'selected_business_type': businessType,
    'selected_currency_code': currencyCode,
    'selected_timezone': timezone,
    'branch_name': branchName.trim(),
    'branch_code': branchCode.trim().toUpperCase(),
    'selected_country_code': countryCode,
  };
}
