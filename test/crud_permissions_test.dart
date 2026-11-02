import 'package:flexpos/core/security/crud_permissions.dart';
import 'package:flexpos/features/tenants/domain/business_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const branch = BusinessBranch(
    id: 'branch-1',
    businessId: 'business-1',
    name: 'Main',
    code: 'MAIN',
    timezone: 'Asia/Kolkata',
  );

  BusinessWorkspace workspace(Set<String> permissions) =>
      BusinessWorkspace(
        businessId: 'business-1',
        businessName: 'FlexPOS',
        businessType: 'retail',
        currencyCode: 'INR',
        timezone: 'Asia/Kolkata',
        membershipId: 'membership-1',
        roleId: 'role-1',
        roleName: 'Custom role',
        permissionCodes: permissions,
        branches: const [branch],
        hasAllBranchAccess: true,
      );

  test('manage grants complete CRUD while view remains read-only', () {
    final manager = workspace({'customers.manage'});
    final auditor = workspace({'customers.view'});

    expect(manager.canCreate('customers'), isTrue);
    expect(manager.canRead('customers'), isTrue);
    expect(manager.canUpdate('customers'), isTrue);
    expect(manager.canDelete('customers'), isTrue);
    expect(auditor.canRead('customers'), isTrue);
    expect(auditor.canCreate('customers'), isFalse);
    expect(auditor.canUpdate('customers'), isFalse);
    expect(auditor.canDelete('customers'), isFalse);
  });

  test('narrow permissions are supported independently', () {
    final workspaceWithNarrowPermissions = workspace({
      'suppliers.view',
      'suppliers.create',
      'suppliers.update',
    });

    expect(workspaceWithNarrowPermissions.canRead('suppliers'), isTrue);
    expect(workspaceWithNarrowPermissions.canCreate('suppliers'), isTrue);
    expect(workspaceWithNarrowPermissions.canUpdate('suppliers'), isTrue);
    expect(workspaceWithNarrowPermissions.canDelete('suppliers'), isFalse);
  });

  test('quotation resource uses its dedicated permission', () {
    final workspaceWithQuotationAccess = workspace({'crm.quotations.manage'});
    expect(workspaceWithQuotationAccess.canCreate('crm.quotations'), isTrue);
    expect(workspaceWithQuotationAccess.canDelete('quotations'), isTrue);
  });

  test('promotion reads inherit the sales view audience', () {
    final salesViewer = workspace({'sales.view'});
    expect(salesViewer.canRead('promotions'), isTrue);
    expect(salesViewer.canCreate('promotions'), isFalse);
    expect(workspace({'promotions.manage'}).canRead('promotions'), isFalse);
  });
}

