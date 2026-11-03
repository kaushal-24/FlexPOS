import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/core/security/crud_permissions.dart';
import 'package:flexpos/core/widgets/data_list_controls.dart';
import 'package:flexpos/core/widgets/data_page_skeleton.dart';
import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/core/widgets/status_badge.dart';
import 'package:flexpos/features/auth/data/auth_repository.dart';
import 'package:flexpos/features/tenants/data/tenant_repository.dart';
import 'package:flexpos/features/tenants/domain/access_control_overview.dart';
import 'package:flexpos/features/tenants/domain/business_workspace.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final accessControlOverviewProvider = FutureProvider.autoDispose
    .family<AccessControlOverview, String>(
      (ref, businessId) => ref
          .watch(tenantRepositoryProvider)
          .fetchAccessControlOverview(businessId),
    );

class AccessControlPage extends ConsumerWidget {
  const AccessControlPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(selectedWorkspaceProvider)
        .when(
          loading: () => const DataPageSkeleton(sectionLabel: 'access control'),
          error: (error, _) => EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Workspace unavailable',
            message: error.toString(),
          ),
          data: (workspace) {
            if (workspace == null) {
              return EmptyState(
                icon: Icons.add_business_outlined,
                title: 'Create a business first',
                message: 'Roles and staff always belong to a secure workspace.',
                action: FilledButton(
                  onPressed: () => context.go('/onboarding'),
                  child: const Text('Create business'),
                ),
              );
            }
            final overview = ref.watch(
              accessControlOverviewProvider(workspace.businessId),
            );
            return overview.when(
              loading: () =>
                  const DataPageSkeleton(sectionLabel: 'access control'),
              error: (error, _) => EmptyState(
                icon: Icons.admin_panel_settings_outlined,
                title: 'Could not load access control',
                message: error.toString(),
                action: FilledButton.icon(
                  onPressed: () => _refresh(ref, workspace.businessId),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
              ),
              data: (data) =>
                  _AccessControlContent(workspace: workspace, data: data),
            );
          },
        );
  }

  void _refresh(WidgetRef ref, String businessId) {
    ref.invalidate(accessControlOverviewProvider(businessId));
  }
}

class _AccessControlContent extends ConsumerWidget {
  const _AccessControlContent({required this.workspace, required this.data});
  final BusinessWorkspace workspace;
  final AccessControlOverview data;

  List<RoleSummary> get _assignableRoles => data.roles
      .where(
        (role) =>
            role.permissionCodes.every(workspace.permissionCodes.contains),
      )
      .toList(growable: false);

  Future<void> _openRole(
    BuildContext context,
    WidgetRef ref, [
    RoleSummary? role,
  ]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RoleDialog(
        businessId: workspace.businessId,
        permissions: data.permissions
            .where(
              (permission) =>
                  workspace.permissionCodes.contains(permission.code),
            )
            .toList(growable: false),
        role: role,
      ),
    );
    if (saved == true) {
      ref.invalidate(accessControlOverviewProvider(workspace.businessId));
    }
  }

  Future<void> _openInvite(BuildContext context, WidgetRef ref) async {
    final roles = _assignableRoles;
    if (roles.isEmpty) {
      _showError(
        context,
        'Create an assignable staff role before adding a staff user.',
      );
      return;
    }
    final result = await showDialog<StaffInvitationResult>(
      context: context,
      builder: (_) => _InviteDialog(workspace: workspace, roles: roles),
    );
    if (result == null || !context.mounted) return;
    ref.invalidate(accessControlOverviewProvider(workspace.businessId));
    String? emailProvider;
    String? emailError;
    try {
      final baseUri = Uri.base;
      final redirectTo = Uri(
        scheme: baseUri.scheme,
        host: baseUri.host,
        port: baseUri.hasPort ? baseUri.port : null,
        path: baseUri.path.isEmpty ? '/' : baseUri.path,
        fragment: '/join-business',
      ).toString();
      emailProvider = await ref
          .read(tenantRepositoryProvider)
          .sendStaffInvitationEmail(
            businessId: workspace.businessId,
            invitationId: result.id,
            token: result.token,
            redirectTo: redirectTo,
          );
    } catch (error) {
      emailError = error.toString();
    }
    if (!context.mounted) return;
    final inviteMessage = emailProvider == null
        ? 'The invitation was created, but the email provider could not send it.\n\n'
              'Share this one-time invitation code securely with ${result.email}:\n\n'
              '${result.token}\n\nIt expires in 7 days.\n\n'
              'Email error: ${emailError ?? 'Unknown email delivery error'}'
        : 'An invitation email was sent to ${result.email} using $emailProvider.\n\n'
              'Fallback code (expires in 7 days):\n\n${result.token}';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          emailProvider == null
              ? 'Invitation created — email not sent'
              : 'Invitation email sent',
        ),
        content: SelectableText(inviteMessage),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _openCreateUser(BuildContext context, WidgetRef ref) async {
    final roles = _assignableRoles;
    if (roles.isEmpty) {
      _showError(
        context,
        'Create an assignable staff role before adding a staff login.',
      );
      return;
    }
    final result = await showDialog<_CreatedStaffLogin>(
      context: context,
      builder: (_) => _CreateStaffUserDialog(
        workspace: workspace,
        roles: roles,
      ),
    );
    if (result == null || !context.mounted) return;
    ref.invalidate(accessControlOverviewProvider(workspace.businessId));
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Staff login created'),
        content: SelectableText(
          'Share these credentials securely with ${result.credentials.fullName.isEmpty ? result.credentials.email : result.credentials.fullName}.\n\n'
          'User ID: ${result.credentials.userId}\n'
          'Email: ${result.credentials.email}\n'
          'Password: ${result.password}\n\n'
          'The password is shown once. Ask the staff member to change it after signing in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(
                  text:
                      'User ID: ${result.credentials.userId}\n'
                      'Email: ${result.credentials.email}\n'
                      'Password: ${result.password}',
                ),
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy credentials'),
          ),
        ],
      ),
    );
  }

  Future<void> _openMember(
    BuildContext context,
    WidgetRef ref,
    MemberSummary member,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _MemberDialog(
        businessId: workspace.businessId,
        member: member,
        roles: _assignableRoles,
        branches: workspace.branches,
      ),
    );
    if (saved == true) {
      ref.invalidate(accessControlOverviewProvider(workspace.businessId));
    }
  }

  Future<void> _viewMember(
    BuildContext context,
    MemberSummary member,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _MemberDetailsDialog(
        member: member,
        branches: workspace.branches,
      ),
    );
  }

  Future<void> _revokeMember(
    BuildContext context,
    WidgetRef ref,
    MemberSummary member,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Revoke staff access?'),
        content: Text(
          '${member.email ?? member.fullName ?? 'This member'} will no longer be able to access this business.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Revoke access'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(tenantRepositoryProvider)
          .updateMembership(
            membershipId: member.id,
            roleId: member.roleId,
            status: 'revoked',
            allBranches: member.hasAllBranchAccess,
            branchIds: member.branchIds,
          );
      ref.invalidate(accessControlOverviewProvider(workspace.businessId));
    } on PostgrestException catch (error) {
      if (context.mounted) _showError(context, error.message);
    }
  }

  Future<void> _deleteStaffLogin(
    BuildContext context,
    WidgetRef ref,
    MemberSummary member,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete staff access?'),
        content: Text(
          'Remove ${member.email ?? member.fullName ?? 'this staff member'} from this business? '
          'Their membership will be removed from this business. If this is their last active business, '
          'the Supabase login will also be disabled; other business memberships are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete login'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(tenantRepositoryProvider).deleteStaffUser(
        businessId: workspace.businessId,
        userId: member.userId,
      );
      ref.invalidate(accessControlOverviewProvider(workspace.businessId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Staff access deleted from this business.')),
        );
      }
    } catch (error) {
      if (context.mounted) _showError(context, error.toString());
    }
  }

  Future<void> _reactivateMember(
    BuildContext context,
    WidgetRef ref,
    MemberSummary member,
  ) async {
    try {
      await ref.read(tenantRepositoryProvider).updateStaffUser(
        businessId: workspace.businessId,
        userId: member.userId,
        roleId: member.roleId,
        status: 'active',
        allBranches: member.hasAllBranchAccess,
        branchIds: member.branchIds,
      );
      ref.invalidate(accessControlOverviewProvider(workspace.businessId));
    } catch (error) {
      if (context.mounted) _showError(context, error.toString());
    }
  }

  Future<void> _deleteRole(
    BuildContext context,
    WidgetRef ref,
    RoleSummary role,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete custom role?'),
        content: Text(
          'Delete “${role.name}”? Roles assigned to members cannot be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(tenantRepositoryProvider).deleteRole(role.id);
      ref.invalidate(accessControlOverviewProvider(workspace.businessId));
    } on PostgrestException catch (error) {
      if (context.mounted) _showError(context, error.message);
    }
  }

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    InvitationSummary invitation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke invitation?'),
        content: Text('${invitation.email} will no longer be able to use it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(tenantRepositoryProvider)
          .revokeStaffInvitation(invitation.id);
      ref.invalidate(accessControlOverviewProvider(workspace.businessId));
    } on PostgrestException catch (error) {
      if (context.mounted) _showError(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId = ref.watch(authRepositoryProvider).currentUser?.id;
    final canCreateRoles = workspace.canCreate('roles');
    final canUpdateRoles = workspace.canUpdate('roles');
    final canDeleteRoles = workspace.canDelete('roles');
    final canCreateStaff = workspace.canCreate('staff');
    final canUpdateStaff = workspace.canUpdate('staff');
    final canDeleteStaff = workspace.canDelete('staff');
    bool canManageMember(MemberSummary member) {
      final role = data.roles
          .where((item) => item.name == member.roleName)
          .firstOrNull;
      return role != null && _assignableRoles.any((item) => item.id == role.id);
    }

    var roleQuery = '';
    var roleSort = 'name';
    var rolePage = 0;
    var memberQuery = '';
    var memberSort = 'name';
    var memberPage = 0;
    final selectedRoles = <String>{};
    final selectedMembers = <String>{};
    return StatefulBuilder(
      builder: (context, setState) {
        final roles = data.roles
            .where(
              (role) => '${role.name} ${role.description ?? ''}'
                  .toLowerCase()
                  .contains(roleQuery),
            )
            .toList();
        roles.sort((a, b) {
          final comparison = a.name.toLowerCase().compareTo(
            b.name.toLowerCase(),
          );
          return roleSort == 'name_desc' ? -comparison : comparison;
        });
        final members = data.members
            .where(
              (member) =>
                  '${member.fullName ?? ''} ${member.email ?? ''} ${member.roleName}'
                      .toLowerCase()
                      .contains(memberQuery),
            )
            .toList();
        members.sort((a, b) {
          final aName = (a.fullName ?? a.email ?? a.roleName).toLowerCase();
          final bName = (b.fullName ?? b.email ?? b.roleName).toLowerCase();
          final comparison = aName.compareTo(bName);
          return memberSort == 'name_desc' ? -comparison : comparison;
        });
        final rolePageCount = pageCountFor(roles.length);
        final memberPageCount = pageCountFor(members.length);
        if (rolePage >= rolePageCount) rolePage = rolePageCount - 1;
        if (memberPage >= memberPageCount) memberPage = memberPageCount - 1;
        final visibleRoles = pageItems(roles, rolePage);
        final visibleMembers = pageItems(members, memberPage);
        return RefreshIndicator(
          onRefresh: () => ref.refresh(
            accessControlOverviewProvider(workspace.businessId).future,
          ),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Staff and permissions',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      Text(
                        '${workspace.businessName} • ${data.members.length} member(s) • '
                        '${data.permissions.length} permissions',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (canCreateRoles || canCreateStaff)
                    Wrap(
                      spacing: 10,
                      children: [
                        if (canCreateRoles)
                          OutlinedButton.icon(
                            onPressed: () => _openRole(context, ref),
                            icon: const Icon(Icons.add_moderator_outlined),
                            label: const Text('New role'),
                          ),
                        if (canCreateStaff)
                          Wrap(
                            spacing: 8,
                            children: [
                              FilledButton.icon(
                                onPressed: () => _openCreateUser(context, ref),
                                icon: const Icon(Icons.key_outlined),
                                label: const Text('Create login'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _openInvite(context, ref),
                                icon: const Icon(Icons.mail_outline_rounded),
                                label: const Text('Invite by code'),
                              ),
                            ],
                          ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 24),
              _SectionTitle(title: 'Roles', count: data.roles.length),
              const SizedBox(height: 10),
              DataListControls(
                query: roleQuery,
                onSearchChanged: (value) => setState(() {
                  roleQuery = value.trim().toLowerCase();
                  rolePage = 0;
                }),
                searchLabel: 'Search roles or descriptions',
                sortValue: roleSort,
                sortOptions: const [
                  DataListSortOption('name', 'Name A–Z'),
                  DataListSortOption('name_desc', 'Name Z–A'),
                ],
                onSortChanged: (value) => setState(() {
                  roleSort = value;
                  rolePage = 0;
                }),
                page: rolePage,
                pageCount: rolePageCount,
                totalCount: roles.length,
                onPageChanged: (value) => setState(() => rolePage = value),
                selectedCount: selectedRoles.length,
                allSelected:
                    visibleRoles.isNotEmpty &&
                    visibleRoles.every(
                      (role) => selectedRoles.contains(role.id),
                    ),
                onSelectAll: visibleRoles.isEmpty
                    ? null
                    : (value) => setState(() {
                        if (value ?? false) {
                          selectedRoles.addAll(
                            visibleRoles.map((role) => role.id),
                          );
                        } else {
                          selectedRoles.removeAll(
                            visibleRoles.map((role) => role.id),
                          );
                        }
                      }),
                onClearSelection: () => setState(selectedRoles.clear),
                bulkActions: [
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(
                          text: roles
                              .where((role) => selectedRoles.contains(role.id))
                              .map((role) => role.name)
                              .join('\n'),
                        ),
                      );
                      setState(selectedRoles.clear);
                    },
                    icon: const Icon(Icons.copy_all_rounded),
                    label: const Text('Copy roles'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final role in visibleRoles) ...[
                AppPanel(
                  onTap: role.isSystem || !canUpdateRoles
                      ? null
                      : () => _openRole(context, ref, role),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Checkbox(
                            value: selectedRoles.contains(role.id),
                            onChanged: (value) => setState(() {
                              if (value ?? false) {
                                selectedRoles.add(role.id);
                              } else {
                                selectedRoles.remove(role.id);
                              }
                            }),
                          ),
                          CircleAvatar(
                            child: Icon(
                              role.isSystem
                                  ? Icons.verified_user_outlined
                                  : Icons.security_outlined,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  role.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                Text(
                                  role.description ?? 'Custom business role',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          StatusBadge(
                            label: '${role.permissionCodes.length} permissions',
                            tone: role.isSystem
                                ? StatusTone.info
                                : StatusTone.neutral,
                          ),
                        ],
                      ),
                      if (!role.isSystem &&
                          (canUpdateRoles || canDeleteRoles)) ...[
                        const Divider(height: 20),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (canUpdateRoles)
                              OutlinedButton.icon(
                                onPressed: () => _openRole(context, ref, role),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Edit role'),
                              ),
                            if (canDeleteRoles)
                              TextButton.icon(
                                onPressed: () =>
                                    _deleteRole(context, ref, role),
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Delete role'),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 16),
              _SectionTitle(title: 'Members', count: data.members.length),
              const SizedBox(height: 10),
              DataListControls(
                query: memberQuery,
                onSearchChanged: (value) => setState(() {
                  memberQuery = value.trim().toLowerCase();
                  memberPage = 0;
                }),
                searchLabel: 'Search members, email, or role',
                sortValue: memberSort,
                sortOptions: const [
                  DataListSortOption('name', 'Name A–Z'),
                  DataListSortOption('name_desc', 'Name Z–A'),
                ],
                onSortChanged: (value) => setState(() {
                  memberSort = value;
                  memberPage = 0;
                }),
                page: memberPage,
                pageCount: memberPageCount,
                totalCount: members.length,
                onPageChanged: (value) => setState(() => memberPage = value),
                selectedCount: selectedMembers.length,
                allSelected:
                    visibleMembers.isNotEmpty &&
                    visibleMembers.every(
                      (member) => selectedMembers.contains(member.id),
                    ),
                onSelectAll: visibleMembers.isEmpty
                    ? null
                    : (value) => setState(() {
                        if (value ?? false) {
                          selectedMembers.addAll(
                            visibleMembers.map((member) => member.id),
                          );
                        } else {
                          selectedMembers.removeAll(
                            visibleMembers.map((member) => member.id),
                          );
                        }
                      }),
                onClearSelection: () => setState(selectedMembers.clear),
                bulkActions: [
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(
                          text: members
                              .where(
                                (member) => selectedMembers.contains(member.id),
                              )
                              .map(
                                (member) =>
                                    '${member.email ?? member.fullName ?? 'Member'}\t${member.roleName}',
                              )
                              .join('\n'),
                        ),
                      );
                      setState(selectedMembers.clear);
                    },
                    icon: const Icon(Icons.copy_all_rounded),
                    label: const Text('Copy members'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final member in visibleMembers) ...[
                AppPanel(
                  onTap:
                      member.userId == currentUserId ||
                          !canUpdateStaff ||
                          !canManageMember(member)
                      ? null
                      : () => _openMember(context, ref, member),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Checkbox(
                            value: selectedMembers.contains(member.id),
                            onChanged: (value) => setState(() {
                              if (value ?? false) {
                                selectedMembers.add(member.id);
                              } else {
                                selectedMembers.remove(member.id);
                              }
                            }),
                          ),
                          const CircleAvatar(child: Icon(Icons.person_outline)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  member.fullName?.trim().isNotEmpty == true
                                      ? member.fullName!
                                      : member.email ?? 'Business member',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                Text(
                                  '${member.roleName} • '
                                  '${member.hasAllBranchAccess ? 'All branches' : '${member.branchIds.length} assigned'}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          StatusBadge(
                            label: member.status,
                            tone: member.status == 'active'
                                ? StatusTone.success
                                : StatusTone.warning,
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _viewMember(context, member),
                            icon: const Icon(Icons.visibility_outlined),
                            label: const Text('View'),
                          ),
                          if (member.userId != currentUserId &&
                              canUpdateStaff &&
                              canManageMember(member))
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _openMember(context, ref, member),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Edit access'),
                            ),
                          if (member.userId != currentUserId &&
                              member.status != 'active' &&
                              canUpdateStaff &&
                              canManageMember(member))
                            TextButton.icon(
                              onPressed: () =>
                                  _reactivateMember(context, ref, member),
                              icon: const Icon(Icons.restart_alt_rounded),
                              label: const Text('Reactivate'),
                            ),
                          if (member.userId != currentUserId &&
                              canDeleteStaff &&
                              canManageMember(member))
                            TextButton.icon(
                              onPressed: () =>
                                  _revokeMember(context, ref, member),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Remove access'),
                            ),
                          if (member.userId != currentUserId &&
                              canDeleteStaff &&
                              canManageMember(member))
                            TextButton.icon(
                              onPressed: () =>
                                  _deleteStaffLogin(context, ref, member),
                              icon: const Icon(Icons.delete_forever_outlined),
                              label: const Text('Delete login'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (data.invitations.isNotEmpty) ...[
                const SizedBox(height: 16),
                _SectionTitle(
                  title: 'Invitations',
                  count: data.invitations.length,
                ),
                const SizedBox(height: 10),
                for (final invitation in data.invitations) ...[
                  AppPanel(
                    child: Row(
                      children: [
                        const Icon(Icons.mail_outline_rounded),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(invitation.email),
                              Text(
                                invitation.roleName,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        StatusBadge(
                          label: invitation.status,
                          tone: invitation.status == 'pending'
                              ? StatusTone.warning
                              : StatusTone.neutral,
                        ),
                        if (invitation.status == 'pending' && canDeleteStaff)
                          TextButton.icon(
                            onPressed: () => _revoke(context, ref, invitation),
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text('Revoke'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});
  final String title;
  final int count;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(width: 8),
      StatusBadge(label: count.toString()),
    ],
  );
}

class _CreatedStaffLogin {
  const _CreatedStaffLogin({
    required this.credentials,
    required this.password,
  });

  final StaffUserCredentials credentials;
  final String password;
}

class _CreateStaffUserDialog extends ConsumerStatefulWidget {
  const _CreateStaffUserDialog({required this.workspace, required this.roles});

  final BusinessWorkspace workspace;
  final List<RoleSummary> roles;

  @override
  ConsumerState<_CreateStaffUserDialog> createState() =>
      _CreateStaffUserDialogState();
}

class _CreateStaffUserDialogState
    extends ConsumerState<_CreateStaffUserDialog> {
  final _email = TextEditingController();
  final _fullName = TextEditingController();
  final _password = TextEditingController();
  late String _roleId;
  bool _allBranches = true;
  final Set<String> _branches = {};
  bool _saving = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _roleId = widget.roles.first.id;
  }

  @override
  void dispose() {
    _email.dispose();
    _fullName.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final email = _email.text.trim().toLowerCase();
    final password = _password.text;
    if (!_isValidEmail(email)) {
      return _showError(context, 'Enter a valid email address.');
    }
    if (password.length < 8 || password.length > 128) {
      return _showError(context, 'Password must be between 8 and 128 characters.');
    }
    if (!_allBranches && _branches.isEmpty) {
      return _showError(context, 'Select at least one branch.');
    }
    setState(() => _saving = true);
    try {
      final credentials = await ref.read(tenantRepositoryProvider).createStaffUser(
        businessId: widget.workspace.businessId,
        email: email,
        password: password,
        fullName: _fullName.text.trim(),
        roleId: _roleId,
        allBranches: _allBranches,
        branchIds: _branches.toList(),
      );
      if (mounted) {
        Navigator.pop(
          context,
          _CreatedStaffLogin(credentials: credentials, password: password),
        );
      }
    } catch (error) {
      if (mounted) _showError(context, error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create staff login'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Create a Supabase account immediately without sending an invitation. '
              'The password is shown once after creation.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _fullName,
              enabled: !_saving,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Full name'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _email,
              enabled: !_saving,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Login email'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _password,
              enabled: !_saving,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Temporary password',
                helperText: 'Minimum 8 characters. Share it securely, then ask the user to change it.',
                suffixIcon: IconButton(
                  onPressed: () => setState(
                    () => _obscurePassword = !_obscurePassword,
                  ),
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _roleId,
              decoration: const InputDecoration(labelText: 'Role'),
              items: widget.roles
                  .map(
                    (role) => DropdownMenuItem(
                      value: role.id,
                      child: Text(role.name),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _roleId = value!),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _allBranches,
              title: const Text('Access all branches'),
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _allBranches = value),
            ),
            if (!_allBranches)
              for (final branch in widget.workspace.branches)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _branches.contains(branch.id),
                  title: Text(branch.name),
                  subtitle: Text(branch.code),
                  onChanged: _saving
                      ? null
                      : (checked) => setState(() {
                          checked == true
                              ? _branches.add(branch.id)
                              : _branches.remove(branch.id);
                        }),
                ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Creating…' : 'Create login'),
      ),
    ],
  );
}

class _RoleDialog extends ConsumerStatefulWidget {
  const _RoleDialog({
    required this.businessId,
    required this.permissions,
    this.role,
  });
  final String businessId;
  final List<PermissionSummary> permissions;
  final RoleSummary? role;
  @override
  ConsumerState<_RoleDialog> createState() => _RoleDialogState();
}

class _RoleDialogState extends ConsumerState<_RoleDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final Set<String> _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.role?.name);
    _description = TextEditingController(text: widget.role?.description);
    _selected = {...?widget.role?.permissionCodes};
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) {
      return _showError(context, 'Enter a role name.');
    }
    setState(() => _saving = true);
    try {
      final repository = ref.read(tenantRepositoryProvider);
      if (widget.role == null) {
        await repository.createRole(
          businessId: widget.businessId,
          name: _name.text,
          description: _description.text,
          permissionCodes: _selected.toList(),
        );
      } else {
        await repository.updateRole(
          roleId: widget.role!.id,
          name: _name.text,
          description: _description.text,
          permissionCodes: _selected.toList(),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (error) {
      if (mounted) _showError(context, error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<PermissionSummary>>{};
    for (final permission in widget.permissions) {
      grouped.putIfAbsent(permission.category, () => []).add(permission);
    }
    return AlertDialog(
      title: Text(
        widget.role == null ? 'Create custom role' : 'Edit custom role',
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Role name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 16),
              for (final group in grouped.entries) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    group.key,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                for (final permission in group.value)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _selected.contains(permission.code),
                    title: Text(permission.description),
                    subtitle: Text(permission.code),
                    onChanged: (checked) => setState(() {
                      checked == true
                          ? _selected.add(permission.code)
                          : _selected.remove(permission.code);
                    }),
                  ),
                const Divider(),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save role'),
        ),
      ],
    );
  }
}

class _InviteDialog extends ConsumerStatefulWidget {
  const _InviteDialog({required this.workspace, required this.roles});
  final BusinessWorkspace workspace;
  final List<RoleSummary> roles;
  @override
  ConsumerState<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends ConsumerState<_InviteDialog> {
  final _email = TextEditingController();
  late String _roleId;
  bool _allBranches = true;
  final Set<String> _branches = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _roleId = widget.roles.first.id;
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final email = _email.text.trim().toLowerCase();
    if (!_isValidEmail(email)) {
      return _showError(
        context,
        'Enter a valid email such as staff@example.com.',
      );
    }
    if (!_allBranches && _branches.isEmpty) {
      return _showError(context, 'Select at least one branch.');
    }
    setState(() => _saving = true);
    try {
      final result = await ref
          .read(tenantRepositoryProvider)
          .createStaffInvitation(
            businessId: widget.workspace.businessId,
            email: email,
            roleId: _roleId,
            allBranches: _allBranches,
            branchIds: _branches.toList(),
          );
      if (mounted) Navigator.pop(context, result);
    } on PostgrestException catch (error) {
      if (mounted) _showError(context, error.message);
    } catch (error) {
      if (mounted) _showError(context, 'Could not add staff user: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Invite staff member'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This creates a one-time invitation. The recipient must sign up '
              'with this same email address and then enter the invitation code.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _email,
              enabled: !_saving,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Work email'),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _roleId,
              decoration: const InputDecoration(labelText: 'Role'),
              items: widget.roles
                  .map(
                    (role) => DropdownMenuItem(
                      value: role.id,
                      child: Text(role.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _roleId = value!),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _allBranches,
              title: const Text('Access all branches'),
              onChanged: (value) => setState(() => _allBranches = value),
            ),
            if (!_allBranches)
              for (final branch in widget.workspace.branches)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _branches.contains(branch.id),
                  title: Text(branch.name),
                  subtitle: Text(branch.code),
                  onChanged: (checked) => setState(() {
                    checked == true
                        ? _branches.add(branch.id)
                        : _branches.remove(branch.id);
                  }),
                ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Creating…' : 'Create invitation'),
      ),
    ],
  );
}

class _MemberDialog extends ConsumerStatefulWidget {
  const _MemberDialog({
    required this.businessId,
    required this.member,
    required this.roles,
    required this.branches,
  });
  final String businessId;
  final MemberSummary member;
  final List<RoleSummary> roles;
  final List<BusinessBranch> branches;
  @override
  ConsumerState<_MemberDialog> createState() => _MemberDialogState();
}

class _MemberDetailsDialog extends StatelessWidget {
  const _MemberDetailsDialog({required this.member, required this.branches});

  final MemberSummary member;
  final List<BusinessBranch> branches;

  @override
  Widget build(BuildContext context) {
    final assignedBranches = member.hasAllBranchAccess
        ? 'All branches'
        : branches
              .where((branch) => member.branchIds.contains(branch.id))
              .map((branch) => branch.name)
              .join(', ');
    return AlertDialog(
      title: const Text('User details'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow(
              label: 'Name',
              value: member.fullName?.trim().isNotEmpty == true
                  ? member.fullName!
                  : 'Not set',
            ),
            _DetailRow(label: 'Email', value: member.email ?? 'Not available'),
            _DetailRow(label: 'Role', value: member.roleName),
            _DetailRow(label: 'Status', value: member.status),
            _DetailRow(label: 'Branch access', value: assignedBranches),
            _DetailRow(label: 'User ID', value: member.userId),
            _DetailRow(label: 'Membership ID', value: member.id),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}

class _MemberDialogState extends ConsumerState<_MemberDialog> {
  late final TextEditingController _email;
  late final TextEditingController _fullName;
  final _password = TextEditingController();
  late String _roleId;
  late String _status;
  late bool _allBranches;
  late final Set<String> _branches;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.member.email ?? '');
    _fullName = TextEditingController(text: widget.member.fullName ?? '');
    _roleId = widget.roles
        .firstWhere((role) => role.name == widget.member.roleName)
        .id;
    _status = widget.member.status;
    _allBranches = widget.member.hasAllBranchAccess;
    _branches = {...widget.member.branchIds};
  }

  @override
  void dispose() {
    _email.dispose();
    _fullName.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_allBranches && _branches.isEmpty) {
      return _showError(context, 'Select at least one branch.');
    }
    setState(() => _saving = true);
    try {
      await ref.read(tenantRepositoryProvider).updateStaffUser(
        businessId: widget.businessId,
        userId: widget.member.userId,
        email: _email.text.trim().isEmpty
            ? null
            : _email.text.trim().toLowerCase(),
        fullName: _fullName.text.trim(),
        password: _password.text.trim().isEmpty ? null : _password.text,
        roleId: _roleId,
        status: _status,
        allBranches: _allBranches,
        branchIds: _branches.toList(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) _showError(context, error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Manage ${widget.member.email ?? 'member'}'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _fullName,
              enabled: !_saving,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Full name'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _email,
              enabled: !_saving,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Login email'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _password,
              enabled: !_saving,
              obscureText: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'New password (optional)',
                helperText: 'Leave empty to keep the current password.',
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _roleId,
              decoration: const InputDecoration(labelText: 'Role'),
              items: widget.roles
                  .map(
                    (role) => DropdownMenuItem(
                      value: role.id,
                      child: Text(role.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _roleId = value!),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
                DropdownMenuItem(value: 'revoked', child: Text('Revoked')),
              ],
              onChanged: (value) => setState(() => _status = value!),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _allBranches,
              title: const Text('Access all branches'),
              onChanged: (value) => setState(() => _allBranches = value),
            ),
            if (!_allBranches)
              for (final branch in widget.branches)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _branches.contains(branch.id),
                  title: Text(branch.name),
                  onChanged: (checked) => setState(() {
                    checked == true
                        ? _branches.add(branch.id)
                        : _branches.remove(branch.id);
                  }),
                ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save user'),
      ),
    ],
  );
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

bool _isValidEmail(String value) => RegExp(
  r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$",
).hasMatch(value);
