import 'package:flexpos/core/utils/money.dart';
import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/core/security/crud_permissions.dart';
import 'package:flexpos/core/widgets/data_page_skeleton.dart';
import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/core/widgets/status_badge.dart';
import 'package:flexpos/core/widgets/data_list_controls.dart';
import 'package:flexpos/features/auth/data/auth_repository.dart';
import 'package:flexpos/features/registers/data/register_repository.dart';
import 'package:flexpos/features/registers/domain/register_models.dart';
import 'package:flexpos/features/tenants/domain/business_workspace.dart';
import 'package:flexpos/features/tenants/domain/feature_entitlement.dart';
import 'package:flexpos/features/tenants/presentation/feature_entitlements/feature_disabled_state.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class RegistersPage extends ConsumerWidget {
  const RegistersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    if (workspace == null) {
      return const EmptyState(
        icon: Icons.add_business_outlined,
        title: 'Select a business',
        message: 'A business workspace is required to manage registers.',
      );
    }
    if (!workspace.isFeatureEnabled(FeatureCodes.registers)) {
      return FeatureDisabledState(
        featureName: 'Registers and shifts',
        canManage: workspace.canManage('business'),
      );
    }
    final canOperate = workspace.canCreate('sales');
    final canCreate = workspace.canCreate('registers');
    final canUpdate = workspace.canUpdate('registers');
    final canDelete = workspace.canDelete('registers');
    final canManage = canUpdate || canDelete;
    if (!canOperate && !canManage && !canCreate) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Registers are restricted',
        message: 'Your role cannot operate or manage cashier registers.',
      );
    }

    final snapshot = ref.watch(registerOperationsProvider);
    return snapshot.when(
      loading: () => const DataPageSkeleton(sectionLabel: 'registers'),
      error: (error, _) => EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load registers',
        message: error.toString(),
        action: FilledButton.icon(
          onPressed: () => ref.invalidate(registerOperationsProvider),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      ),
      data: (data) => _RegistersContent(
        workspace: workspace,
        data: data,
        canOperate: canOperate,
        canManage: canManage,
        canCreate: canCreate,
        canUpdate: canUpdate,
        canDelete: canDelete,
        currentUserId: ref.read(supabaseClientProvider).auth.currentUser?.id,
      ),
    );
  }
}

class _RegistersContent extends ConsumerStatefulWidget {
  const _RegistersContent({
    required this.workspace,
    required this.data,
    required this.canOperate,
    required this.canManage,
    required this.canCreate,
    required this.canUpdate,
    required this.canDelete,
    required this.currentUserId,
  });

  final BusinessWorkspace workspace;
  final RegisterOperationsSnapshot data;
  final bool canOperate;
  final bool canManage;
  final bool canCreate;
  final bool canUpdate;
  final bool canDelete;
  final String? currentUserId;

  @override
  ConsumerState<_RegistersContent> createState() => _RegistersContentState();
}

class _RegistersContentState extends ConsumerState<_RegistersContent> {
  String _query = '';
  String _sort = 'name';
  int _page = 0;
  final Set<String> _selectedRegisterIds = {};

  BusinessWorkspace get workspace => widget.workspace;
  RegisterOperationsSnapshot get data => widget.data;
  bool get canOperate => widget.canOperate;
  bool get canManage => widget.canManage;
  bool get canCreate => widget.canCreate;
  bool get canUpdate => widget.canUpdate;
  bool get canDelete => widget.canDelete;
  String? get currentUserId => widget.currentUserId;

  String _branchName(String id) =>
      workspace.branches
          .where((branch) => branch.id == id)
          .map((branch) => branch.name)
          .firstOrNull ??
      'Accessible branch';

  @override
  Widget build(BuildContext context) {
    final filteredRegisters = data.registers
        .where(
          (register) => '${register.name} ${_branchName(register.branchId)}'
              .toLowerCase()
              .contains(_query),
        )
        .toList();
    filteredRegisters.sort((a, b) {
      final comparison = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return _sort == 'name_desc' ? -comparison : comparison;
    });
    final pageCount = pageCountFor(filteredRegisters.length);
    if (_page >= pageCount) _page = pageCount - 1;
    final visibleRegisters = pageItems(filteredRegisters, _page);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(registerOperationsProvider.future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Registers and shifts',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Open shifts, record drawer cash, and review X/Z reports.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (canCreate)
                FilledButton.icon(
                  onPressed: () => _createRegister(context, ref),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New register'),
                ),
            ],
          ),
          const SizedBox(height: 24),
          if (data.registers.isEmpty)
            EmptyState(
              icon: Icons.point_of_sale_outlined,
              title: 'No accessible registers',
              message: canCreate
                  ? 'Create a register for an accessible branch to start a cashier shift.'
                  : 'Ask a manager to create or assign a register for your branch.',
              action: canCreate
                  ? FilledButton.icon(
                      onPressed: () => _createRegister(context, ref),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Create register'),
                    )
                  : null,
            )
          else ...[
            Text(
              'Active registers',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            DataListControls(
              query: _query,
              onSearchChanged: (value) => setState(() {
                _query = value.trim().toLowerCase();
                _page = 0;
              }),
              searchLabel: 'Search registers or branches',
              sortValue: _sort,
              sortOptions: const [
                DataListSortOption('name', 'Name A–Z'),
                DataListSortOption('name_desc', 'Name Z–A'),
              ],
              onSortChanged: (value) => setState(() {
                _sort = value;
                _page = 0;
              }),
              page: _page,
              pageCount: pageCount,
              totalCount: filteredRegisters.length,
              onPageChanged: (value) => setState(() => _page = value),
              selectedCount: _selectedRegisterIds.length,
              allSelected:
                  visibleRegisters.isNotEmpty &&
                  visibleRegisters.every(
                    (register) => _selectedRegisterIds.contains(register.id),
                  ),
              onSelectAll: visibleRegisters.isEmpty
                  ? null
                  : (value) => setState(() {
                      if (value ?? false) {
                        _selectedRegisterIds.addAll(
                          visibleRegisters.map((register) => register.id),
                        );
                      } else {
                        _selectedRegisterIds.removeAll(
                          visibleRegisters.map((register) => register.id),
                        );
                      }
                    }),
              onClearSelection: () => setState(_selectedRegisterIds.clear),
              bulkActions: [
                FilledButton.tonalIcon(
                  onPressed: () => _copySelectedRegisters(filteredRegisters),
                  icon: const Icon(Icons.copy_all_rounded),
                  label: const Text('Copy registers'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1100
                    ? 3
                    : constraints.maxWidth >= 680
                    ? 2
                    : 1;
                final width =
                    (constraints.maxWidth - (columns - 1) * 12) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final register in visibleRegisters)
                      SizedBox(
                        width: width,
                        child: _RegisterCard(
                          register: register,
                          assignedStaffName: data.staff
                              .where(
                                (staff) =>
                                    staff.userId == register.assignedUserId,
                              )
                              .firstOrNull
                              ?.displayName,
                          branchName: _branchName(register.branchId),
                          shift: data.openShiftFor(register.id),
                          currencyCode: workspace.currencyCode,
                          canOpen: canOperate || canManage,
                          canClose:
                              canManage ||
                              data.openShiftFor(register.id)?.openedBy ==
                                  currentUserId,
                          onOpen: () => _openShift(context, ref, register),
                          onClose: (shift) => _closeShift(context, ref, shift),
                          onCashMovement: (shift, type) =>
                              _recordCashMovement(context, ref, shift, type),
                          onReport: (shift) => _showReport(context, ref, shift),
                          onEdit: () => _editRegister(context, ref, register),
                          onDelete: () =>
                              _deleteRegister(context, ref, register),
                          canUpdate: canUpdate,
                          canDelete: canDelete,
                          selected: _selectedRegisterIds.contains(register.id),
                          onSelected: (value) => setState(() {
                            if (value) {
                              _selectedRegisterIds.add(register.id);
                            } else {
                              _selectedRegisterIds.remove(register.id);
                            }
                          }),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
          if (data.closedShifts.isNotEmpty) ...[
            const SizedBox(height: 28),
            Text(
              'Recent closed shifts',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            AppPanel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < data.closedShifts.length; i++) ...[
                    _ClosedShiftTile(
                      shift: data.closedShifts[i],
                      branchName: _branchName(data.closedShifts[i].branchId),
                      currencyCode: workspace.currencyCode,
                      onReport: () =>
                          _showReport(context, ref, data.closedShifts[i]),
                    ),
                    if (i < data.closedShifts.length - 1)
                      const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _createRegister(BuildContext context, WidgetRef ref) async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateRegisterDialog(
        workspace: workspace,
        repository: ref.read(registerRepositoryProvider),
        staff: data.staff,
      ),
    );
    if (created == true) {
      ref.invalidate(registerOperationsProvider);
    }
  }

  Future<void> _editRegister(
    BuildContext context,
    WidgetRef ref,
    PosRegister register,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateRegisterDialog(
        workspace: workspace,
        repository: ref.read(registerRepositoryProvider),
        staff: data.staff,
        register: register,
      ),
    );
    if (saved == true) ref.invalidate(registerOperationsProvider);
  }

  Future<void> _deleteRegister(
    BuildContext context,
    WidgetRef ref,
    PosRegister register,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete register?'),
        content: Text(
          '“${register.name}” will be removed from active registers. Shift history is preserved.',
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
      await ref
          .read(registerRepositoryProvider)
          .deleteRegister(
            businessId: workspace.businessId,
            registerId: register.id,
          );
      ref.invalidate(registerOperationsProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete register: $error')),
        );
      }
    }
  }

  Future<void> _openShift(
    BuildContext context,
    WidgetRef ref,
    PosRegister register,
  ) async {
    final opened = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OpenShiftDialog(
        register: register,
        currencyCode: workspace.currencyCode,
        businessId: workspace.businessId,
        repository: ref.read(registerRepositoryProvider),
        staff: data.staff,
        currentUserId: currentUserId,
        canAssignStaff: canManage,
      ),
    );
    if (opened == true) {
      ref.invalidate(registerOperationsProvider);
    }
  }

  Future<void> _closeShift(
    BuildContext context,
    WidgetRef ref,
    RegisterShift shift,
  ) async {
    final result = await showDialog<RegisterCloseResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CloseShiftDialog(
        shift: shift,
        currencyCode: workspace.currencyCode,
        repository: ref.read(registerRepositoryProvider),
      ),
    );
    if (result == null || !context.mounted) return;
    ref.invalidate(registerOperationsProvider);
    final difference = result.differenceMinor;
    final differenceLabel = difference == 0
        ? 'balanced exactly'
        : difference > 0
        ? '${formatMoney(workspace.currencyCode, difference)} over'
        : '${formatMoney(workspace.currencyCode, difference.abs())} short';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Shift closed. Expected ${formatMoney(workspace.currencyCode, result.expectedCashMinor)}; $differenceLabel.',
        ),
      ),
    );
  }

  Future<void> _recordCashMovement(
    BuildContext context,
    WidgetRef ref,
    RegisterShift shift,
    String movementType,
  ) async {
    final recorded = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CashMovementDialog(
        shift: shift,
        movementType: movementType,
        currencyCode: workspace.currencyCode,
        repository: ref.read(registerRepositoryProvider),
      ),
    );
    if (recorded == true && context.mounted) {
      ref.invalidate(registerOperationsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            movementType == 'cash_in'
                ? 'Cash added to the drawer.'
                : 'Cash removed from the drawer.',
          ),
        ),
      );
    }
  }

  Future<void> _showReport(
    BuildContext context,
    WidgetRef ref,
    RegisterShift shift,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ShiftReportDialog(
        shiftId: shift.id,
        currencyCode: workspace.currencyCode,
        repository: ref.read(registerRepositoryProvider),
      ),
    );
  }

  Future<void> _copySelectedRegisters(List<PosRegister> registers) async {
    final selected = registers
        .where((register) => _selectedRegisterIds.contains(register.id))
        .toList(growable: false);
    if (selected.isEmpty) return;
    await Clipboard.setData(
      ClipboardData(
        text: selected
            .map((register) => '${register.name}\t${register.code}')
            .join('\n'),
      ),
    );
    if (!mounted) return;
    setState(_selectedRegisterIds.clear);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${selected.length} register${selected.length == 1 ? '' : 's'} copied.',
        ),
      ),
    );
  }
}

class _RegisterCard extends StatelessWidget {
  const _RegisterCard({
    required this.register,
    required this.assignedStaffName,
    required this.branchName,
    required this.shift,
    required this.currencyCode,
    required this.canOpen,
    required this.canClose,
    required this.onOpen,
    required this.onClose,
    required this.onCashMovement,
    required this.onReport,
    required this.onEdit,
    required this.onDelete,
    required this.canUpdate,
    required this.canDelete,
    required this.selected,
    required this.onSelected,
  });

  final PosRegister register;
  final String? assignedStaffName;
  final String branchName;
  final RegisterShift? shift;
  final String currencyCode;
  final bool canOpen;
  final bool canClose;
  final VoidCallback onOpen;
  final ValueChanged<RegisterShift> onClose;
  final void Function(RegisterShift shift, String movementType) onCashMovement;
  final ValueChanged<RegisterShift> onReport;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool canUpdate;
  final bool canDelete;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) => AppPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            CircleAvatar(
              child: Icon(
                shift == null
                    ? Icons.point_of_sale_outlined
                    : Icons.lock_open_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    register.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${register.code} · $branchName',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (assignedStaffName != null)
                    Text(
                      'Assigned to $assignedStaffName',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
            Checkbox(
              value: selected,
              onChanged: (value) => onSelected(value ?? false),
            ),
            if (canUpdate || canDelete)
              PopupMenuButton<String>(
                tooltip: 'Register actions',
                onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
                itemBuilder: (_) => [
                  if (canUpdate)
                    const PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit register'),
                      ),
                    ),
                  if (canDelete)
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline_rounded),
                        title: Text('Delete register'),
                      ),
                    ),
                ],
              ),
            StatusBadge(
              label: shift == null ? 'Closed' : 'Open',
              tone: shift == null ? StatusTone.neutral : StatusTone.success,
            ),
          ],
        ),
        if (shift != null) ...[
          const SizedBox(height: 14),
          Text(
            'Opened ${DateFormat.yMMMd().add_jm().format(shift!.openedAt)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Opening cash: ${formatMoney(currencyCode, shift!.openingCashMinor)}',
          ),
        ],
        const SizedBox(height: 16),
        if (shift == null && canOpen)
          FilledButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.lock_open_rounded),
            label: const Text('Open shift'),
          )
        else if (shift != null && canClose)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => onCashMovement(shift!, 'cash_in'),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Cash in'),
              ),
              OutlinedButton.icon(
                onPressed: () => onCashMovement(shift!, 'cash_out'),
                icon: const Icon(Icons.remove_rounded),
                label: const Text('Cash out'),
              ),
              OutlinedButton.icon(
                onPressed: () => onReport(shift!),
                icon: const Icon(Icons.summarize_outlined),
                label: const Text('X report'),
              ),
              FilledButton.icon(
                onPressed: () => onClose(shift!),
                icon: const Icon(Icons.lock_outline_rounded),
                label: const Text('Count and close'),
              ),
            ],
          )
        else
          Text(
            shift == null ? 'You cannot operate this register.' : 'Only the opening cashier or a register manager can close this shift.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    ),
  );
}

class _ClosedShiftTile extends StatelessWidget {
  const _ClosedShiftTile({
    required this.shift,
    required this.branchName,
    required this.currencyCode,
    required this.onReport,
  });

  final RegisterShift shift;
  final String branchName;
  final String currencyCode;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final difference = shift.differenceMinor ?? 0;
    final color = difference == 0
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.error;
    return ListTile(
      onTap: onReport,
      leading: const CircleAvatar(child: Icon(Icons.history_rounded)),
      title: Text('${shift.registerName} · $branchName'),
      subtitle: Text(
        '${DateFormat.yMMMd().add_jm().format(shift.openedAt)} → '
        '${shift.closedAt == null ? 'Closed' : DateFormat.yMMMd().add_jm().format(shift.closedAt!)}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatMoney(currencyCode, shift.closingCashMinor ?? 0),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                difference == 0
                    ? 'Balanced'
                    : difference > 0
                    ? '${formatMoney(currencyCode, difference)} over'
                    : '${formatMoney(currencyCode, difference.abs())} short',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(width: 8),
          const Tooltip(
            message: 'View Z report',
            child: Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _CreateRegisterDialog extends StatefulWidget {
  const _CreateRegisterDialog({
    required this.workspace,
    required this.repository,
    required this.staff,
    this.register,
  });

  final BusinessWorkspace workspace;
  final RegisterRepository repository;
  final List<RegisterStaff> staff;
  final PosRegister? register;

  @override
  State<_CreateRegisterDialog> createState() => _CreateRegisterDialogState();
}

class _CreateRegisterDialogState extends State<_CreateRegisterDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
  String? _branchId;
  String _assignedUserId = '';
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _branchId =
        widget.register?.branchId ?? widget.workspace.branches.firstOrNull?.id;
    _name.text = widget.register?.name ?? '';
    _code.text = widget.register?.code ?? '';
    final assignedUserId = widget.register?.assignedUserId;
    _assignedUserId =
        widget.staff.any((staff) => staff.userId == assignedUserId)
        ? assignedUserId!
        : '';
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _branchId == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final register = widget.register;
      if (register == null) {
        await widget.repository.createRegister(
          businessId: widget.workspace.businessId,
          branchId: _branchId!,
          name: _name.text,
          code: _code.text,
          assignedUserId: _assignedUserId.isEmpty ? null : _assignedUserId,
        );
      } else {
        await widget.repository.updateRegister(
          businessId: widget.workspace.businessId,
          registerId: register.id,
          branchId: _branchId!,
          name: _name.text,
          code: _code.text,
          assignedUserId: _assignedUserId.isEmpty ? null : _assignedUserId,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.register == null ? 'Create register' : 'Edit register'),
    content: SizedBox(
      width: 480,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _branchId,
              decoration: const InputDecoration(labelText: 'Branch'),
              items: widget.workspace.branches
                  .map(
                    (branch) => DropdownMenuItem(
                      value: branch.id,
                      child: Text(branch.name),
                    ),
                  )
                  .toList(),
              onChanged: _submitting
                  ? null
                  : (value) => setState(() => _branchId = value),
            ),
            const SizedBox(height: 14),
            DropdownMenu<String>(
              initialSelection: _assignedUserId,
              enableFilter: true,
              enableSearch: true,
              requestFocusOnTap: true,
              expandedInsets: EdgeInsets.zero,
              label: const Text('Assigned staff (optional)'),
              hintText: 'Search staff by name or email',
              leadingIcon: const Icon(Icons.person_search_outlined),
              dropdownMenuEntries: [
                const DropdownMenuEntry<String>(
                  value: '',
                  label: 'Unassigned — any authorized cashier',
                ),
                ...widget.staff.map(
                  (staff) => DropdownMenuEntry<String>(
                    value: staff.userId,
                    label: '${staff.displayName} • ${staff.email}',
                  ),
                ),
              ],
              onSelected: _submitting
                  ? null
                  : (value) => setState(() => _assignedUserId = value ?? ''),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _name,
              enabled: !_submitting,
              decoration: const InputDecoration(labelText: 'Register name'),
              validator: (value) => (value?.trim().length ?? 0) < 2
                  ? 'Enter at least two characters.'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _code,
              enabled: !_submitting,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
                LengthLimitingTextInputFormatter(30),
              ],
              decoration: const InputDecoration(
                labelText: 'Code',
                hintText: 'FRONT-1',
              ),
              validator: (value) =>
                  !RegExp(r'^[A-Za-z0-9-]{1,30}$').hasMatch(value?.trim() ?? '')
                  ? 'Use letters, numbers, and hyphens only.'
                  : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        onPressed: _submitting ? null : _submit,
        icon: _submitting
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                widget.register == null
                    ? Icons.add_rounded
                    : Icons.save_outlined,
              ),
        label: Text(widget.register == null ? 'Create' : 'Save changes'),
      ),
    ],
  );
}

class _OpenShiftDialog extends StatefulWidget {
  const _OpenShiftDialog({
    required this.register,
    required this.currencyCode,
    required this.businessId,
    required this.repository,
    required this.staff,
    required this.currentUserId,
    required this.canAssignStaff,
  });

  final PosRegister register;
  final String currencyCode;
  final String businessId;
  final RegisterRepository repository;
  final List<RegisterStaff> staff;
  final String? currentUserId;
  final bool canAssignStaff;

  @override
  State<_OpenShiftDialog> createState() => _OpenShiftDialogState();
}

class _OpenShiftDialogState extends State<_OpenShiftDialog> {
  final _formKey = GlobalKey<FormState>();
  final _openingCash = TextEditingController(text: '0.00');
  final _notes = TextEditingController();
  late String _openedByUserId;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final assigned = widget.register.assignedUserId;
    final current = widget.currentUserId;
    _openedByUserId = widget.staff.any((staff) => staff.userId == assigned)
        ? assigned!
        : (widget.staff.any((staff) => staff.userId == current)
              ? current!
              : (widget.staff.firstOrNull?.userId ?? current ?? ''));
  }

  @override
  void dispose() {
    _openingCash.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_openedByUserId.isEmpty) {
      setState(
        () => _error = 'No active staff member is available for this shift.',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.repository.openShift(
        businessId: widget.businessId,
        registerId: widget.register.id,
        openingCashMinor: parseMoneyToMinor(_openingCash.text)!,
        openedByUserId: _openedByUserId,
        notes: _notes.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Open ${widget.register.name}'),
    content: SizedBox(
      width: 480,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownMenu<String>(
              initialSelection: _openedByUserId,
              enabled: widget.canAssignStaff && widget.staff.isNotEmpty,
              enableFilter: true,
              enableSearch: true,
              requestFocusOnTap: true,
              expandedInsets: EdgeInsets.zero,
              label: const Text('Open shift for'),
              hintText: 'Search staff by name or email',
              leadingIcon: const Icon(Icons.person_outline_rounded),
              dropdownMenuEntries: widget.staff
                  .map(
                    (staff) => DropdownMenuEntry<String>(
                      value: staff.userId,
                      label: '${staff.displayName} • ${staff.email}',
                    ),
                  )
                  .toList(growable: false),
              onSelected: widget.canAssignStaff
                  ? (value) => setState(
                      () => _openedByUserId = value ?? _openedByUserId,
                    )
                  : null,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.canAssignStaff
                    ? 'A shift records the opening float and all cash activity for one staff member.'
                    : 'This shift will open for your signed-in staff account.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _openingCash,
              enabled: !_submitting,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Opening cash (${widget.currencyCode})',
              ),
              validator: (value) => parseMoneyToMinor(value ?? '') == null
                  ? 'Enter a non-negative amount with up to two decimals.'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _notes,
              enabled: !_submitting,
              maxLength: 500,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Opening note (optional)',
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        onPressed: _submitting ? null : _submit,
        icon: _submitting
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.lock_open_rounded),
        label: const Text('Open shift'),
      ),
    ],
  );
}

class _CloseShiftDialog extends StatefulWidget {
  const _CloseShiftDialog({
    required this.shift,
    required this.currencyCode,
    required this.repository,
  });

  final RegisterShift shift;
  final String currencyCode;
  final RegisterRepository repository;

  @override
  State<_CloseShiftDialog> createState() => _CloseShiftDialogState();
}

class _CloseShiftDialogState extends State<_CloseShiftDialog> {
  final _formKey = GlobalKey<FormState>();
  final _closingCash = TextEditingController();
  final _notes = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _closingCash.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await widget.repository.closeShift(
        shiftId: widget.shift.id,
        closingCashMinor: parseMoneyToMinor(_closingCash.text)!,
        notes: _notes.text,
      );
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Close ${widget.shift.registerName}'),
    content: SizedBox(
      width: 500,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Count physical cash without an expected-cash hint. FlexPOS reconciles opening cash, cash sales, refunds, and drawer movements after you close.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _closingCash,
              autofocus: true,
              enabled: !_submitting,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Counted closing cash (${widget.currencyCode})',
              ),
              validator: (value) => parseMoneyToMinor(value ?? '') == null
                  ? 'Enter a non-negative amount with up to two decimals.'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _notes,
              enabled: !_submitting,
              maxLength: 500,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Closing note (optional)',
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        onPressed: _submitting ? null : _submit,
        icon: _submitting
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.lock_outline_rounded),
        label: const Text('Close and reconcile'),
      ),
    ],
  );
}

class _CashMovementDialog extends StatefulWidget {
  const _CashMovementDialog({
    required this.shift,
    required this.movementType,
    required this.currencyCode,
    required this.repository,
  });

  final RegisterShift shift;
  final String movementType;
  final String currencyCode;
  final RegisterRepository repository;

  @override
  State<_CashMovementDialog> createState() => _CashMovementDialogState();
}

class _CashMovementDialogState extends State<_CashMovementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  bool _submitting = false;
  String? _error;

  bool get _isCashIn => widget.movementType == 'cash_in';

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.repository.recordCashMovement(
        shiftId: widget.shift.id,
        movementType: widget.movementType,
        amountMinor: parseMoneyToMinor(_amount.text)!,
        reason: _reason.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_isCashIn ? 'Record cash in' : 'Record cash out'),
    content: SizedBox(
      width: 480,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${widget.shift.registerName} · ${widget.shift.registerCode}'),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amount,
              autofocus: true,
              enabled: !_submitting,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount (${widget.currencyCode})',
              ),
              validator: (value) {
                final amount = parseMoneyToMinor(value ?? '');
                return amount == null || amount <= 0
                    ? 'Enter an amount greater than zero.'
                    : null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _reason,
              enabled: !_submitting,
              maxLength: 250,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'Petty cash, float top-up, bank drop…',
              ),
              validator: (value) => (value?.trim().length ?? 0) < 3
                  ? 'Enter at least three characters.'
                  : null,
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        onPressed: _submitting ? null : _submit,
        icon: _submitting
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(_isCashIn ? Icons.add_rounded : Icons.remove_rounded),
        label: Text(_isCashIn ? 'Add cash' : 'Remove cash'),
      ),
    ],
  );
}

class _ShiftReportDialog extends StatefulWidget {
  const _ShiftReportDialog({
    required this.shiftId,
    required this.currencyCode,
    required this.repository,
  });

  final String shiftId;
  final String currencyCode;
  final RegisterRepository repository;

  @override
  State<_ShiftReportDialog> createState() => _ShiftReportDialogState();
}

class _ShiftReportDialogState extends State<_ShiftReportDialog> {
  late Future<RegisterShiftReport> _report;

  @override
  void initState() {
    super.initState();
    _report = widget.repository.fetchShiftReport(widget.shiftId);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Shift report'),
    content: SizedBox(
      width: 560,
      child: FutureBuilder<RegisterShiftReport>(
        future: _report,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 260,
              child: DataListSkeleton(
                sectionLabel: 'shift report',
                itemCount: 2,
                padding: EdgeInsets.zero,
              ),
            );
          }
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load report',
              message: snapshot.error.toString(),
              action: FilledButton.icon(
                onPressed: () => setState(() {
                  _report = widget.repository.fetchShiftReport(widget.shiftId);
                }),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            );
          }
          final report = snapshot.requireData;
          final difference = report.differenceMinor;
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    StatusBadge(
                      label: '${report.reportType} report',
                      tone: report.reportType == 'X'
                          ? StatusTone.warning
                          : StatusTone.success,
                    ),
                    const Spacer(),
                    Text('${report.registerName} · ${report.registerCode}'),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Opened ${DateFormat.yMMMd().add_jm().format(report.openedAt)}'
                  '${report.closedAt == null ? '' : ' · Closed ${DateFormat.yMMMd().add_jm().format(report.closedAt!)}'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Divider(height: 28),
                _ReportAmountRow(
                  label: 'Sales (${report.saleCount})',
                  amountMinor: report.totalSalesMinor,
                  currencyCode: widget.currencyCode,
                ),
                _ReportAmountRow(
                  label: 'Refunds',
                  amountMinor: -report.totalRefundsMinor,
                  currencyCode: widget.currencyCode,
                ),
                if (report.paymentBreakdown.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Net payments',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  for (final payment in report.paymentBreakdown)
                    _ReportAmountRow(
                      label: payment.method.replaceAll('_', ' '),
                      amountMinor: payment.amountMinor,
                      currencyCode: widget.currencyCode,
                    ),
                ],
                const Divider(height: 28),
                _ReportAmountRow(
                  label: 'Opening cash',
                  amountMinor: report.openingCashMinor,
                  currencyCode: widget.currencyCode,
                ),
                _ReportAmountRow(
                  label: 'Cash sales',
                  amountMinor: report.cashSalesMinor,
                  currencyCode: widget.currencyCode,
                ),
                _ReportAmountRow(
                  label: 'Cash refunds',
                  amountMinor: -report.cashRefundsMinor,
                  currencyCode: widget.currencyCode,
                ),
                _ReportAmountRow(
                  label: 'Cash in',
                  amountMinor: report.cashInMinor,
                  currencyCode: widget.currencyCode,
                ),
                _ReportAmountRow(
                  label: 'Cash out',
                  amountMinor: -report.cashOutMinor,
                  currencyCode: widget.currencyCode,
                ),
                const Divider(height: 28),
                _ReportAmountRow(
                  label: 'Expected cash',
                  amountMinor: report.expectedCashMinor,
                  currencyCode: widget.currencyCode,
                  emphasized: true,
                ),
                if (report.closingCashMinor != null)
                  _ReportAmountRow(
                    label: 'Counted cash',
                    amountMinor: report.closingCashMinor!,
                    currencyCode: widget.currencyCode,
                  ),
                if (difference != null)
                  _ReportAmountRow(
                    label: difference == 0
                        ? 'Difference'
                        : difference > 0
                        ? 'Over'
                        : 'Short',
                    amountMinor: difference,
                    currencyCode: widget.currencyCode,
                    emphasized: true,
                  ),
              ],
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
  );
}

class _ReportAmountRow extends StatelessWidget {
  const _ReportAmountRow({
    required this.label,
    required this.amountMinor,
    required this.currencyCode,
    this.emphasized = false,
  });

  final String label;
  final int amountMinor;
  final String currencyCode;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          formatMoney(currencyCode, amountMinor),
          style: emphasized ? Theme.of(context).textTheme.titleMedium : null,
        ),
      ],
    ),
  );
}
