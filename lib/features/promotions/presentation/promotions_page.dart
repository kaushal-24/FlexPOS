import 'package:flexpos/core/utils/money.dart';
import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/core/security/crud_permissions.dart';
import 'package:flexpos/core/widgets/data_page_skeleton.dart';
import 'package:flexpos/core/widgets/data_list_controls.dart';
import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/features/promotions/data/promotion_repository.dart';
import 'package:flexpos/features/promotions/domain/promotion_models.dart';
import 'package:flexpos/features/tenants/domain/business_workspace.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PromotionsPage extends ConsumerStatefulWidget {
  const PromotionsPage({super.key});

  @override
  ConsumerState<PromotionsPage> createState() => _PromotionsPageState();
}

class _PromotionsPageState extends ConsumerState<PromotionsPage> {
  String _query = '';
  String _sort = 'newest';
  int _page = 0;
  final Set<String> _selectedPromotionIds = {};

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    if (workspace == null) {
      return const EmptyState(
        icon: Icons.local_offer_outlined,
        title: 'Select a business',
        message: 'A business workspace is required to manage promotions.',
      );
    }
    if (!workspace.canRead('promotions')) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Promotions are restricted',
        message: 'Your role does not include permission to view promotions.',
      );
    }
    final canCreate = workspace.canCreate('promotions');
    final canUpdate = workspace.canUpdate('promotions');
    final canDelete = workspace.canDelete('promotions');
    final canManage = canUpdate;
    final promotions = ref.watch(promotionsProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _showCreatePromotion(context, ref, workspace),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New coupon'),
            )
          : null,
      body: promotions.when(
        loading: () => const DataPageSkeleton(sectionLabel: 'promotions'),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load promotions',
          message: error.toString(),
          action: FilledButton.icon(
            onPressed: () => ref.invalidate(promotionsProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ),
        data: (items) {
          final filtered = items
              .where(
                (promotion) =>
                    '${promotion.name} ${promotion.code} ${promotion.discountLabel}'
                        .toLowerCase()
                        .contains(_query),
              )
              .toList();
          filtered.sort(
            (a, b) => switch (_sort) {
              'name_asc' => a.name.toLowerCase().compareTo(
                b.name.toLowerCase(),
              ),
              'redemptions_desc' => b.redeemedCount.compareTo(a.redeemedCount),
              'active_first' => (b.isActive ? 1 : 0).compareTo(
                a.isActive ? 1 : 0,
              ),
              _ => b.createdAt.compareTo(a.createdAt),
            },
          );
          final pageCount = pageCountFor(filtered.length);
          if (_page >= pageCount) _page = pageCount - 1;
          final visible = pageItems(filtered, _page);
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 96),
            children: [
              Text(
                'Coupons and promotions',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Create controlled discounts that are validated and redeemed atomically at checkout.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              DataListControls(
                query: _query,
                onSearchChanged: (value) => setState(() {
                  _query = value.trim().toLowerCase();
                  _page = 0;
                }),
                searchLabel: 'Search promotion name or code',
                sortValue: _sort,
                sortOptions: const [
                  DataListSortOption('newest', 'Newest first'),
                  DataListSortOption('name_asc', 'Name (A–Z)'),
                  DataListSortOption('active_first', 'Active first'),
                  DataListSortOption('redemptions_desc', 'Most redeemed'),
                ],
                onSortChanged: (value) => setState(() {
                  _sort = value;
                  _page = 0;
                }),
                page: _page,
                pageCount: pageCount,
                totalCount: filtered.length,
                onPageChanged: (value) => setState(() => _page = value),
                selectedCount: _selectedPromotionIds.length,
                allSelected:
                    visible.isNotEmpty &&
                    visible.every(
                      (promotion) =>
                          _selectedPromotionIds.contains(promotion.id),
                    ),
                onSelectAll: visible.isEmpty
                    ? null
                    : (selected) => setState(() {
                        if (selected ?? false) {
                          _selectedPromotionIds.addAll(
                            visible.map((promotion) => promotion.id),
                          );
                        } else {
                          _selectedPromotionIds.removeAll(
                            visible.map((promotion) => promotion.id),
                          );
                        }
                      }),
                onClearSelection: () =>
                    setState(() => _selectedPromotionIds.clear()),
                bulkActions: [
                  FilledButton.tonalIcon(
                    onPressed: canManage
                        ? () => _bulkSetActive(
                            workspace,
                            items
                                .where(
                                  (promotion) => _selectedPromotionIds.contains(
                                    promotion.id,
                                  ),
                                )
                                .toList(growable: false),
                            true,
                          )
                        : null,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Activate selected'),
                  ),
                  OutlinedButton.icon(
                    onPressed: canManage
                        ? () => _bulkSetActive(
                            workspace,
                            items
                                .where(
                                  (promotion) => _selectedPromotionIds.contains(
                                    promotion.id,
                                  ),
                                )
                                .toList(growable: false),
                            false,
                          )
                        : null,
                    icon: const Icon(Icons.pause_rounded),
                    label: const Text('Pause selected'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (visible.isEmpty)
                const EmptyState(
                  icon: Icons.local_offer_outlined,
                  title: 'No coupons yet',
                  message: 'Create a coupon to offer a fixed or percentage discount.',
                )
              else
                for (final promotion in visible) ...[
                  AppPanel(
                    child: Row(
                      children: [
                        Checkbox(
                          value: _selectedPromotionIds.contains(promotion.id),
                          onChanged: (selected) => setState(() {
                            if (selected ?? false) {
                              _selectedPromotionIds.add(promotion.id);
                            } else {
                              _selectedPromotionIds.remove(promotion.id);
                            }
                          }),
                        ),
                        Expanded(
                          child: _PromotionCard(
                            promotion: promotion,
                            currencyCode: workspace.currencyCode,
                            canManage: canUpdate,
                            canDelete: canDelete,
                            onToggle: () async {
                              try {
                                await ref
                                    .read(promotionRepositoryProvider)
                                    .setPromotionActive(
                                      businessId: workspace.businessId,
                                      promotionId: promotion.id,
                                      isActive: !promotion.isActive,
                                    );
                                ref.invalidate(promotionsProvider);
                              } catch (error) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(error.toString())),
                                  );
                                }
                              }
                            },
                            onDelete: () => _deletePromotion(
                              context,
                              ref,
                              workspace,
                              promotion,
                            ),
                            onEdit: () => _editPromotion(
                              context,
                              ref,
                              workspace,
                              promotion,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _bulkSetActive(
    BusinessWorkspace workspace,
    List<Promotion> promotions,
    bool isActive,
  ) async {
    if (promotions.isEmpty) return;
    final repository = ref.read(promotionRepositoryProvider);
    for (final promotion in promotions) {
      await repository.setPromotionActive(
        businessId: workspace.businessId,
        promotionId: promotion.id,
        isActive: isActive,
      );
    }
    if (!mounted) return;
    setState(() => _selectedPromotionIds.clear());
    ref.invalidate(promotionsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${promotions.length} promotion${promotions.length == 1 ? '' : 's'} updated.',
        ),
      ),
    );
  }

  Future<void> _showCreatePromotion(
    BuildContext context,
    WidgetRef ref,
    BusinessWorkspace workspace,
  ) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CreatePromotionDialog(
        businessId: workspace.businessId,
        currencyCode: workspace.currencyCode,
        repository: ref.read(promotionRepositoryProvider),
      ),
    );
    if (created == true) {
      ref.invalidate(promotionsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Coupon created.')));
      }
    }
  }

  Future<void> _deletePromotion(
    BuildContext context,
    WidgetRef ref,
    BusinessWorkspace workspace,
    Promotion promotion,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete promotion?'),
        content: Text(
          '“${promotion.name}” will be permanently removed. Use Pause instead if it has already been redeemed.',
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
          .read(promotionRepositoryProvider)
          .deletePromotion(
            businessId: workspace.businessId,
            promotionId: promotion.id,
          );
      ref.invalidate(promotionsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Promotion deleted.')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete promotion: $error')),
        );
      }
    }
  }

  Future<void> _editPromotion(
    BuildContext context,
    WidgetRef ref,
    BusinessWorkspace workspace,
    Promotion promotion,
  ) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _CreatePromotionDialog(
        businessId: workspace.businessId,
        currencyCode: workspace.currencyCode,
        repository: ref.read(promotionRepositoryProvider),
        existing: promotion,
      ),
    );
    if (updated == true) ref.invalidate(promotionsProvider);
  }
}

class _PromotionCard extends StatelessWidget {
  const _PromotionCard({
    required this.promotion,
    required this.currencyCode,
    required this.canManage,
    required this.canDelete,
    required this.onToggle,
    required this.onDelete,
    required this.onEdit,
  });

  final Promotion promotion;
  final String currencyCode;
  final bool canManage;
  final bool canDelete;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => AppPanel(
    child: Row(
      children: [
        CircleAvatar(
          child: Icon(
            promotion.isActive
                ? Icons.local_offer_rounded
                : Icons.pause_rounded,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                promotion.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 3),
              Text(
                '${promotion.code} · ${promotion.discountLabel}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 3),
              Text(
                'Used ${promotion.redeemedCount}${promotion.usageLimit == null ? '' : ' / ${promotion.usageLimit}'} · Minimum ${formatMoney(currencyCode, promotion.minimumSubtotalMinor)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (canManage)
          Wrap(
            spacing: 2,
            children: [
              IconButton(
                tooltip: 'Edit promotion',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              Switch(value: promotion.isActive, onChanged: (_) => onToggle()),
            ],
          ),
        if (canDelete)
          IconButton(
            tooltip: 'Delete promotion',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
      ],
    ),
  );
}

class _CreatePromotionDialog extends StatefulWidget {
  const _CreatePromotionDialog({
    required this.businessId,
    required this.currencyCode,
    required this.repository,
    this.existing,
  });

  final String businessId;
  final String currencyCode;
  final PromotionRepository repository;
  final Promotion? existing;

  @override
  State<_CreatePromotionDialog> createState() => _CreatePromotionDialogState();
}

class _CreatePromotionDialogState extends State<_CreatePromotionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _value = TextEditingController();
  final _minimum = TextEditingController(text: '0.00');
  final _usageLimit = TextEditingController();
  String _type = 'percentage';
  bool _saving = false;
  String? _error;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _name.text = existing.name;
      _code.text = existing.code;
      _type = existing.discountType;
      _value.text = existing.discountValue.toString();
      _minimum.text = (existing.minimumSubtotalMinor / 100).toStringAsFixed(2);
      _usageLimit.text = existing.usageLimit?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _value.dispose();
    _minimum.dispose();
    _usageLimit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_editing ? 'Edit coupon' : 'Create coupon'),
    content: SizedBox(
      width: 460,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Promotion name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a name.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Coupon code'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a code.'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Discount type'),
                items: const [
                  DropdownMenuItem(
                    value: 'percentage',
                    child: Text('Percentage'),
                  ),
                  DropdownMenuItem(value: 'fixed', child: Text('Fixed amount')),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _type = value ?? _type),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _value,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: _type == 'percentage'
                      ? 'Discount percentage'
                      : 'Discount amount',
                  prefixText: _type == 'fixed'
                      ? '${widget.currencyCode} '
                      : null,
                  suffixText: _type == 'percentage' ? '%' : null,
                ),
                validator: (value) {
                  final parsed = double.tryParse(value?.trim() ?? '');
                  if (parsed == null ||
                      parsed <= 0 ||
                      (_type == 'percentage' && parsed > 100)) {
                    return 'Enter a valid discount.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _minimum,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Minimum subtotal',
                  prefixText: '${widget.currencyCode} ',
                ),
                validator: (value) =>
                    parseMoneyToMinor(value?.trim() ?? '') == null &&
                        value?.trim().isNotEmpty == true
                    ? 'Enter a valid amount.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _usageLimit,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Usage limit (optional)',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  final parsed = int.tryParse(value.trim());
                  return parsed == null || parsed <= 0
                      ? 'Enter a positive whole number.'
                      : null;
                },
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
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(_editing ? 'Save changes' : 'Create coupon'),
      ),
    ],
  );

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final value = double.parse(_value.text.trim());
    final minimum = parseMoneyToMinor(_minimum.text.trim()) ?? 0;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final existing = widget.existing;
      final usageLimit = _usageLimit.text.trim().isEmpty
          ? null
          : int.parse(_usageLimit.text.trim());
      if (existing == null) {
        await widget.repository.createPromotion(
          businessId: widget.businessId,
          code: _code.text,
          name: _name.text,
          discountType: _type,
          discountValue: value,
          minimumSubtotalMinor: minimum,
          usageLimit: usageLimit,
        );
      } else {
        await widget.repository.updatePromotion(
          businessId: widget.businessId,
          promotionId: existing.id,
          code: _code.text,
          name: _name.text,
          discountType: _type,
          discountValue: value,
          minimumSubtotalMinor: minimum,
          usageLimit: usageLimit,
          startsAt: existing.startsAt,
          endsAt: existing.endsAt,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
