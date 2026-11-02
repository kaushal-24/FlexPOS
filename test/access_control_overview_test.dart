import 'package:flexpos/features/tenants/domain/access_control_overview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('role summary preserves the exact permission set', () {
    final role = RoleSummary.fromJson({
      'id': 'role-1',
      'name': 'Cashier',
      'description': 'Checkout access',
      'is_system': true,
      'role_permissions': [
        {'permission_code': 'sales.view'},
        {'permission_code': 'sales.create'},
      ],
    });

    expect(role.isSystem, isTrue);
    expect(role.permissionCodes, ['sales.view', 'sales.create']);
  });

  test('member summary maps profile and branch-scoped access', () {
    final member = MemberSummary.fromJson({
      'id': 'membership-1',
      'user_id': 'user-1',
      'status': 'active',
      'branch_access_all': false,
      'profile_email': 'cashier@example.com',
      'profile_name': 'Store Cashier',
      'roles': {'id': 'role-1', 'name': 'Cashier'},
      'member_branch_access': [
        {'branch_id': 'branch-1'},
        {'branch_id': 'branch-2'},
      ],
    });

    expect(member.email, 'cashier@example.com');
    expect(member.roleId, 'role-1');
    expect(member.roleName, 'Cashier');
    expect(member.hasAllBranchAccess, isFalse);
    expect(member.branchIds, ['branch-1', 'branch-2']);
  });

  test('staff invitation result maps the one-time code response', () {
    final invitation = StaffInvitationResult.fromJson({
      'invitation_id': 'invitation-1',
      'email': 'staff@example.com',
      'token': '012345678901234567890123456789012345678901234567',
      'expires_at': '2026-10-26T12:00:00Z',
    });

    expect(invitation.email, 'staff@example.com');
    expect(invitation.token, hasLength(48));
    expect(invitation.expiresAt.isUtc, isTrue);
  });
}
