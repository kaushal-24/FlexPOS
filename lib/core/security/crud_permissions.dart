import 'package:flexpos/features/tenants/domain/business_workspace.dart';

/// CRUD operations understood by the UI permission layer.
///
/// The database currently exposes domain permissions as `<domain>.view` and
/// `<domain>.manage`. A future role can opt into narrower permissions such as
/// `<domain>.create` without requiring a client migration; `manage` remains a
/// backwards-compatible grant for all write operations.
enum CrudAction { create, read, update, delete }

extension BusinessWorkspaceCrudPermissions on BusinessWorkspace {
  bool canCrud(String resource, CrudAction action) {
    final normalized = resource.trim().toLowerCase();
    if (normalized.isEmpty) return false;

    // CRM quotations intentionally use a narrower write permission than the
    // rest of CRM, while reads remain covered by crm.view.
    final aliases = <String>[
      if (action == CrudAction.read && normalized == 'promotions')
        'sales'
      else ...[
        if (action == CrudAction.read &&
            (normalized == 'crm.quotations' || normalized == 'quotations'))
          'crm',
        if (normalized == 'quotations') 'crm.quotations' else normalized,
      ],
    ];

    final suffix = switch (action) {
      CrudAction.create => 'create',
      CrudAction.read => 'view',
      CrudAction.update => 'update',
      CrudAction.delete => 'delete',
    };
    for (final alias in aliases) {
      if (permissionCodes.contains('$alias.$suffix')) return true;
      if (action == CrudAction.read && permissionCodes.contains('$alias.manage')) {
        return true;
      }
      if (action != CrudAction.read && permissionCodes.contains('$alias.manage')) {
        return true;
      }
    }
    return false;
  }

  bool canRead(String resource) => canCrud(resource, CrudAction.read);

  bool canCreate(String resource) => canCrud(resource, CrudAction.create);

  bool canUpdate(String resource) => canCrud(resource, CrudAction.update);

  bool canDelete(String resource) => canCrud(resource, CrudAction.delete);

  bool canManage(String resource) => canUpdate(resource) || canDelete(resource);
}

