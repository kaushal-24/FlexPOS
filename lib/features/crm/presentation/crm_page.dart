import 'package:flexpos/app/theme/app_tokens.dart';
import 'package:flexpos/core/security/crud_permissions.dart';
import 'package:flexpos/core/utils/money.dart';
import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/core/widgets/data_page_skeleton.dart';
import 'package:flexpos/core/widgets/data_list_controls.dart';
import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/features/crm/data/crm_repository.dart';
import 'package:flexpos/features/crm/domain/crm_models.dart';
import 'package:flexpos/features/auth/data/auth_repository.dart';
import 'package:flexpos/features/tenants/domain/business_workspace.dart';
import 'package:flexpos/features/tenants/domain/feature_entitlement.dart';
import 'package:flexpos/features/tenants/presentation/feature_entitlements/feature_disabled_state.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class CrmPage extends ConsumerStatefulWidget {
  const CrmPage({super.key});

  @override
  ConsumerState<CrmPage> createState() => _CrmPageState();
}

class _CrmPageState extends ConsumerState<CrmPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _leadQuery = '';
  String _opportunityQuery = '';
  String _leadSort = 'newest';
  String _opportunitySort = 'newest';
  int _leadPage = 0;
  int _opportunityPage = 0;
  final Set<String> _selectedLeadIds = {};
  final Set<String> _selectedOpportunityIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    if (workspace == null) {
      return const EmptyState(
        icon: Icons.add_business_outlined,
        title: 'Select a business',
        message: 'A workspace is required to view CRM.',
      );
    }
    if (!workspace.isFeatureEnabled(FeatureCodes.crm)) {
      return FeatureDisabledState(
        featureName: 'Customer Relationship Management',
        canManage: workspace.canManage('business'),
      );
    }
    if (!workspace.canRead('crm')) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'CRM is restricted',
        message: 'Your role does not include permission to view CRM.',
      );
    }

    final canCreate = workspace.canCreate('crm');

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _createLead(
                context,
                workspace,
                ref.read(crmRepositoryProvider),
                ref,
              ),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('New lead'),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.sm),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            labelPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            tabs: [
              Tab(text: 'Leads', icon: Icon(Icons.person_outline_rounded)),
              Tab(text: 'Opportunities', icon: Icon(Icons.trending_up_rounded)),
              Tab(text: 'Quotations', icon: Icon(Icons.description_outlined)),
              Tab(text: 'Follow-ups', icon: Icon(Icons.schedule_outlined)),
              Tab(text: 'Customer notes', icon: Icon(Icons.note_outlined)),
              Tab(text: 'Reminders', icon: Icon(Icons.notifications_outlined)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _LeadsTab(
                  query: _leadQuery,
                  onQueryChanged: (v) => setState(() => _leadQuery = v),
                  sort: _leadSort,
                  onSortChanged: (v) => setState(() {
                    _leadSort = v;
                    _leadPage = 0;
                  }),
                  page: _leadPage,
                  onPageChanged: (v) => setState(() => _leadPage = v),
                  selectedIds: _selectedLeadIds,
                  onSelectionChanged: (ids) => setState(() {
                    _selectedLeadIds
                      ..clear()
                      ..addAll(ids);
                  }),
                ),
                _OpportunitiesTab(
                  query: _opportunityQuery,
                  onQueryChanged: (v) => setState(() => _opportunityQuery = v),
                  sort: _opportunitySort,
                  onSortChanged: (v) => setState(() {
                    _opportunitySort = v;
                    _opportunityPage = 0;
                  }),
                  page: _opportunityPage,
                  onPageChanged: (v) => setState(() => _opportunityPage = v),
                  selectedIds: _selectedOpportunityIds,
                  onSelectionChanged: (ids) => setState(() {
                    _selectedOpportunityIds
                      ..clear()
                      ..addAll(ids);
                  }),
                ),
                _QuotationsTab(),
                _FollowUpsTab(),
                _CustomerNotesTab(),
                _RemindersTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LeadsTab extends ConsumerWidget {
  const _LeadsTab({
    required this.query,
    required this.onQueryChanged,
    required this.sort,
    required this.onSortChanged,
    required this.page,
    required this.onPageChanged,
    required this.selectedIds,
    required this.onSelectionChanged,
  });

  final String query;
  final ValueChanged<String> onQueryChanged;
  final String sort;
  final ValueChanged<String> onSortChanged;
  final int page;
  final ValueChanged<int> onPageChanged;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onSelectionChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(crmLeadsProvider);
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    final canCreate = workspace?.canCreate('crm') ?? false;
    final canUpdate = workspace?.canUpdate('crm') ?? false;
    final canDelete = workspace?.canDelete('crm') ?? false;
    return leads.when(
      loading: () => const DataPageSkeleton(sectionLabel: 'crm leads'),
      error: (error, _) => EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load leads',
        message: error.toString(),
      ),
      data: (items) {
        final filtered = items
            .where(
              (lead) => lead.title.toLowerCase().contains(query.toLowerCase()),
            )
            .toList();
        filtered.sort(
          (a, b) => switch (sort) {
            'value_desc' => (b.estimatedValueMinor ?? 0).compareTo(
              a.estimatedValueMinor ?? 0,
            ),
            'oldest' => a.createdAt.compareTo(b.createdAt),
            _ => b.createdAt.compareTo(a.createdAt),
          },
        );
        final pageCount = pageCountFor(filtered.length);
        final boundedPage = page >= pageCount ? pageCount - 1 : page;
        final visible = pageItems(filtered, boundedPage);
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 100),
          children: [
            Text('Leads', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 6),
            Text(
              '${items.length} lead${items.length == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            DataListControls(
              query: query,
              onSearchChanged: onQueryChanged,
              searchLabel: 'Search leads by title',
              sortValue: sort,
              sortOptions: const [
                DataListSortOption('newest', 'Newest first'),
                DataListSortOption('oldest', 'Oldest first'),
                DataListSortOption('value_desc', 'Estimated value (high–low)'),
              ],
              onSortChanged: onSortChanged,
              page: boundedPage,
              pageCount: pageCount,
              totalCount: filtered.length,
              onPageChanged: onPageChanged,
              selectedCount: selectedIds.length,
              allSelected:
                  visible.isNotEmpty &&
                  visible.every((lead) => selectedIds.contains(lead.id)),
              onSelectAll: visible.isEmpty
                  ? null
                  : (selected) {
                      final ids = {...selectedIds};
                      if (selected ?? false) {
                        ids.addAll(visible.map((lead) => lead.id));
                      } else {
                        ids.removeAll(visible.map((lead) => lead.id));
                      }
                      onSelectionChanged(ids);
                    },
              onClearSelection: () => onSelectionChanged({}),
              bulkActions: [
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final selected = items
                        .where((lead) => selectedIds.contains(lead.id))
                        .map((lead) => '${lead.title}\t${lead.status}')
                        .join('\n');
                    await Clipboard.setData(ClipboardData(text: selected));
                    onSelectionChanged({});
                  },
                  icon: const Icon(Icons.copy_all_rounded),
                  label: const Text('Copy selected'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (visible.isEmpty)
              EmptyState(
                icon: query.isEmpty
                    ? Icons.person_outline_rounded
                    : Icons.search_off_outlined,
                title: query.isEmpty ? 'No leads yet' : 'No matching leads',
                message: query.isEmpty
                    ? 'Create a lead to start tracking potential sales.'
                    : 'Try a different search.',
                action: canCreate
                    ? FilledButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Create lead'),
                      )
                    : null,
              )
            else
              for (final lead in visible) ...[
                AppPanel(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: selectedIds.contains(lead.id),
                        onChanged: (selected) {
                          final ids = {...selectedIds};
                          if (selected ?? false) {
                            ids.add(lead.id);
                          } else {
                            ids.remove(lead.id);
                          }
                          onSelectionChanged(ids);
                        },
                      ),
                      CircleAvatar(
                        child: Text(lead.title.characters.first.toUpperCase()),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lead.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 3),
                            if (lead.source != null)
                              Text(
                                lead.source!,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              children: [
                                _Chip(label: lead.status.toUpperCase()),
                                if (lead.estimatedValueMinor != null)
                                  _Chip(
                                    label: formatMoney(
                                      workspace?.currencyCode ?? 'USD',
                                      lead.estimatedValueMinor!,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (lead.expectedCloseAt != null)
                            Text(
                              DateFormat.yMMMd().format(lead.expectedCloseAt!),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          if (canUpdate || canDelete)
                            PopupMenuButton<String>(
                              tooltip: 'Lead actions',
                              onSelected: (action) {
                                if (action == 'edit' && workspace != null) {
                                  _editLead(context, workspace, ref, lead);
                                } else if (action == 'archive' &&
                                    workspace != null) {
                                  _archiveLead(context, workspace, ref, lead);
                                }
                              },
                              itemBuilder: (_) => [
                                if (canUpdate)
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit lead'),
                                  ),
                                if (canDelete)
                                  const PopupMenuItem(
                                    value: 'archive',
                                    child: Text('Archive lead'),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
          ],
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _OpportunitiesTab extends ConsumerWidget {
  const _OpportunitiesTab({
    required this.query,
    required this.onQueryChanged,
    required this.sort,
    required this.onSortChanged,
    required this.page,
    required this.onPageChanged,
    required this.selectedIds,
    required this.onSelectionChanged,
  });

  final String query;
  final ValueChanged<String> onQueryChanged;
  final String sort;
  final ValueChanged<String> onSortChanged;
  final int page;
  final ValueChanged<int> onPageChanged;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onSelectionChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opportunities = ref.watch(crmOpportunitiesProvider);
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    final canUpdate = workspace?.canUpdate('crm') ?? false;
    final canDelete = workspace?.canDelete('crm') ?? false;
    return opportunities.when(
      loading: () => const DataPageSkeleton(sectionLabel: 'crm opportunities'),
      error: (error, _) => EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load opportunities',
        message: error.toString(),
      ),
      data: (items) {
        final filtered = items
            .where((o) => o.title.toLowerCase().contains(query.toLowerCase()))
            .toList();
        filtered.sort(
          (a, b) => switch (sort) {
            'value_desc' => b.valueMinor.compareTo(a.valueMinor),
            'probability_desc' => b.probability.compareTo(a.probability),
            'oldest' => a.createdAt.compareTo(b.createdAt),
            _ => b.createdAt.compareTo(a.createdAt),
          },
        );
        final pageCount = pageCountFor(filtered.length);
        final boundedPage = page >= pageCount ? pageCount - 1 : page;
        final visible = pageItems(filtered, boundedPage);
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 100),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Opportunities',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                if (workspace != null && workspace.canCreate('crm'))
                  FilledButton.icon(
                    onPressed: () => _createOpportunity(
                      context,
                      workspace,
                      ref.read(crmRepositoryProvider),
                      ref,
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New opportunity'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${items.length} opportunity${items.length == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            DataListControls(
              query: query,
              onSearchChanged: onQueryChanged,
              searchLabel: 'Search opportunities by title',
              sortValue: sort,
              sortOptions: const [
                DataListSortOption('newest', 'Newest first'),
                DataListSortOption('oldest', 'Oldest first'),
                DataListSortOption('value_desc', 'Value (high–low)'),
                DataListSortOption(
                  'probability_desc',
                  'Probability (high–low)',
                ),
              ],
              onSortChanged: onSortChanged,
              page: boundedPage,
              pageCount: pageCount,
              totalCount: filtered.length,
              onPageChanged: onPageChanged,
              selectedCount: selectedIds.length,
              allSelected:
                  visible.isNotEmpty &&
                  visible.every((item) => selectedIds.contains(item.id)),
              onSelectAll: visible.isEmpty
                  ? null
                  : (selected) {
                      final ids = {...selectedIds};
                      if (selected ?? false) {
                        ids.addAll(visible.map((item) => item.id));
                      } else {
                        ids.removeAll(visible.map((item) => item.id));
                      }
                      onSelectionChanged(ids);
                    },
              onClearSelection: () => onSelectionChanged({}),
              bulkActions: [
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final selected = items
                        .where((item) => selectedIds.contains(item.id))
                        .map((item) => '${item.title}\t${item.stage}')
                        .join('\n');
                    await Clipboard.setData(ClipboardData(text: selected));
                    onSelectionChanged({});
                  },
                  icon: const Icon(Icons.copy_all_rounded),
                  label: const Text('Copy selected'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (visible.isEmpty)
              EmptyState(
                icon: query.isEmpty
                    ? Icons.trending_up_rounded
                    : Icons.search_off_outlined,
                title: query.isEmpty
                    ? 'No opportunities yet'
                    : 'No matching opportunities',
                message: query.isEmpty
                    ? 'Convert a qualified lead or create an opportunity directly.'
                    : 'Try a different search.',
              )
            else
              for (final opportunity in visible) ...[
                AppPanel(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: selectedIds.contains(opportunity.id),
                        onChanged: (selected) {
                          final ids = {...selectedIds};
                          if (selected ?? false) {
                            ids.add(opportunity.id);
                          } else {
                            ids.remove(opportunity.id);
                          }
                          onSelectionChanged(ids);
                        },
                      ),
                      CircleAvatar(
                        child: Text(
                          opportunity.title.characters.first.toUpperCase(),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              opportunity.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${opportunity.stage.replaceAll('_', ' ')} · ${opportunity.probability}%',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              formatMoney(
                                workspace?.currencyCode ?? 'USD',
                                opportunity.valueMinor,
                              ),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (opportunity.expectedCloseAt != null)
                            Text(
                              DateFormat.yMMMd().format(
                                opportunity.expectedCloseAt!,
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          if (canUpdate || canDelete)
                            PopupMenuButton<String>(
                              tooltip: 'Opportunity actions',
                              onSelected: (action) {
                                if (workspace == null) return;
                                if (action == 'edit') {
                                  _editOpportunity(
                                    context,
                                    workspace,
                                    ref,
                                    opportunity,
                                  );
                                } else {
                                  _archiveOpportunity(
                                    context,
                                    workspace,
                                    ref,
                                    opportunity,
                                  );
                                }
                              },
                              itemBuilder: (_) => [
                                if (canUpdate)
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit opportunity'),
                                  ),
                                if (canDelete)
                                  const PopupMenuItem(
                                    value: 'archive',
                                    child: Text('Archive opportunity'),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
          ],
        );
      },
    );
  }
}

class _QuotationsTab extends ConsumerWidget {
  const _QuotationsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    final quotations = ref.watch(crmQuotationsProvider);
    final canUpdate = workspace?.canUpdate('quotations') ?? false;
    final canDelete = workspace?.canDelete('quotations') ?? false;
    return quotations.when(
      loading: () => const DataPageSkeleton(sectionLabel: 'crm quotations'),
      error: (error, _) => EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load quotations',
        message: error.toString(),
      ),
      data: (items) {
        var query = '';
        var sort = 'newest';
        var page = 0;
        final selected = <String>{};
        return StatefulBuilder(
          builder: (context, setState) {
            final filtered = items
                .where(
                  (item) =>
                      '${item.quotationNumber} ${item.title} ${item.status}'
                          .toLowerCase()
                          .contains(query),
                )
                .toList();
            filtered.sort(
              (a, b) => sort == 'oldest'
                  ? a.createdAt.compareTo(b.createdAt)
                  : b.createdAt.compareTo(a.createdAt),
            );
            final pageCount = pageCountFor(filtered.length);
            if (page >= pageCount) page = pageCount - 1;
            final visible = pageItems(filtered, page);
            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 100),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Quotations',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    if (workspace != null && workspace.canCreate('quotations'))
                      FilledButton.icon(
                        onPressed: () => _createQuotation(
                          context,
                          workspace,
                          ref.read(crmRepositoryProvider),
                          ref,
                        ),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('New quotation'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${items.length} quotation${items.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                DataListControls(
                  query: query,
                  onSearchChanged: (value) => setState(() {
                    query = value.trim().toLowerCase();
                    page = 0;
                  }),
                  searchLabel: 'Search quotation number, title, or status',
                  sortValue: sort,
                  sortOptions: const [
                    DataListSortOption('newest', 'Newest first'),
                    DataListSortOption('oldest', 'Oldest first'),
                  ],
                  onSortChanged: (value) => setState(() {
                    sort = value;
                    page = 0;
                  }),
                  page: page,
                  pageCount: pageCount,
                  totalCount: filtered.length,
                  onPageChanged: (value) => setState(() => page = value),
                  selectedCount: selected.length,
                  allSelected:
                      visible.isNotEmpty &&
                      visible.every((item) => selected.contains(item.id)),
                  onSelectAll: visible.isEmpty
                      ? null
                      : (value) => setState(() {
                          if (value ?? false) {
                            selected.addAll(visible.map((item) => item.id));
                          } else {
                            selected.removeAll(visible.map((item) => item.id));
                          }
                        }),
                  onClearSelection: () => setState(selected.clear),
                  bulkActions: [
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(
                            text: items
                                .where((item) => selected.contains(item.id))
                                .map(
                                  (item) =>
                                      '${item.quotationNumber}\t${item.status}',
                                )
                                .join('\n'),
                          ),
                        );
                        setState(selected.clear);
                      },
                      icon: const Icon(Icons.copy_all_rounded),
                      label: const Text('Copy quotations'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  EmptyState(
                    icon: Icons.description_outlined,
                    title: 'No quotations yet',
                    message: 'Create a quotation from an opportunity or lead.',
                  )
                else
                  for (final quotation in visible) ...[
                    AppPanel(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: selected.contains(quotation.id),
                            onChanged: (value) => setState(() {
                              if (value ?? false) {
                                selected.add(quotation.id);
                              } else {
                                selected.remove(quotation.id);
                              }
                            }),
                          ),
                          CircleAvatar(
                            child: Text(
                              quotation.quotationNumber.characters.first
                                  .toUpperCase(),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  quotation.quotationNumber,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  quotation.title,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${quotation.status.toUpperCase()} · '
                                  '${formatMoney(workspace?.currencyCode ?? 'USD', quotation.grandTotalMinor)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (quotation.validUntil != null)
                                Text(
                                  DateFormat.yMMMd().format(
                                    quotation.validUntil!,
                                  ),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              if (canUpdate || canDelete)
                                PopupMenuButton<String>(
                                  tooltip: 'Quotation actions',
                                  onSelected: (action) {
                                    if (workspace == null) return;
                                    if (action == 'edit') {
                                      _editQuotation(
                                        context,
                                        workspace,
                                        ref,
                                        quotation,
                                      );
                                    } else {
                                      _archiveQuotation(
                                        context,
                                        workspace,
                                        ref,
                                        quotation,
                                      );
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    if (canUpdate)
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Edit quotation'),
                                      ),
                                    if (canDelete)
                                      const PopupMenuItem(
                                        value: 'archive',
                                        child: Text('Archive quotation'),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
              ],
            );
          },
        );
      },
    );
  }
}

class _FollowUpsTab extends ConsumerWidget {
  const _FollowUpsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final followUps = ref.watch(crmFollowUpsProvider);
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    return followUps.when(
      loading: () => const DataListSkeleton(sectionLabel: 'crm follow-ups'),
      error: (error, _) => EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load follow-ups',
        message: error.toString(),
      ),
      data: (items) {
        final pending = items
            .where((f) => !f.isCompleted)
            .toList(growable: false);
        final overdue = pending
            .where((f) => f.isOverdue)
            .toList(growable: false);
        var query = '';
        var sort = 'due_soon';
        var page = 0;
        final selected = <String>{};
        return StatefulBuilder(
          builder: (context, setState) {
            final filtered = pending
                .where(
                  (item) => '${item.title} ${item.type} ${item.notes ?? ''}'
                      .toLowerCase()
                      .contains(query),
                )
                .toList();
            filtered.sort(
              (a, b) => sort == 'newest'
                  ? b.dueAt.compareTo(a.dueAt)
                  : a.dueAt.compareTo(b.dueAt),
            );
            final pageCount = pageCountFor(filtered.length);
            if (page >= pageCount) page = pageCount - 1;
            final visible = pageItems(filtered, page);
            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 100),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Follow-ups',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    if (workspace != null && workspace.canCreate('crm'))
                      FilledButton.icon(
                        onPressed: () => _createFollowUp(
                          context,
                          workspace,
                          ref.read(crmRepositoryProvider),
                          ref,
                        ),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('New follow-up'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${pending.length} pending ${pending.length == 1 ? 'follow-up' : 'follow-ups'}',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (overdue.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  AppPanel(
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${overdue.length} overdue follow-up${overdue.length == 1 ? '' : 's'} due today or earlier.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                DataListControls(
                  query: query,
                  onSearchChanged: (value) => setState(() {
                    query = value.trim().toLowerCase();
                    page = 0;
                  }),
                  searchLabel: 'Search follow-ups, type, or notes',
                  sortValue: sort,
                  sortOptions: const [
                    DataListSortOption('due_soon', 'Due soonest'),
                    DataListSortOption('newest', 'Due latest'),
                  ],
                  onSortChanged: (value) => setState(() {
                    sort = value;
                    page = 0;
                  }),
                  page: page,
                  pageCount: pageCount,
                  totalCount: filtered.length,
                  onPageChanged: (value) => setState(() => page = value),
                  selectedCount: selected.length,
                  allSelected:
                      visible.isNotEmpty &&
                      visible.every((item) => selected.contains(item.id)),
                  onSelectAll: visible.isEmpty
                      ? null
                      : (value) => setState(() {
                          if (value ?? false) {
                            selected.addAll(visible.map((item) => item.id));
                          } else {
                            selected.removeAll(visible.map((item) => item.id));
                          }
                        }),
                  onClearSelection: () => setState(selected.clear),
                  bulkActions: [
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(
                            text: items
                                .where((item) => selected.contains(item.id))
                                .map((item) => '${item.title}\t${item.type}')
                                .join('\n'),
                          ),
                        );
                        setState(selected.clear);
                      },
                      icon: const Icon(Icons.copy_all_rounded),
                      label: const Text('Copy follow-ups'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  const EmptyState(
                    icon: Icons.schedule_outlined,
                    title: 'No follow-ups scheduled',
                    message: 'Schedule calls, emails, or meetings for your leads and opportunities.',
                  )
                else
                  for (final followUp in visible) ...[
                    AppPanel(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: selected.contains(followUp.id),
                              onChanged: (value) => setState(() {
                                if (value ?? false) {
                                  selected.add(followUp.id);
                                } else {
                                  selected.remove(followUp.id);
                                }
                              }),
                            ),
                            CircleAvatar(
                              child: Text(
                                followUp.title.characters.first.toUpperCase(),
                              ),
                            ),
                          ],
                        ),
                        title: Text(followUp.title),
                        subtitle: Text(
                          '${DateFormat.yMMMd().add_jm().format(followUp.dueAt)} · ${followUp.type.toUpperCase()}',
                        ),
                        trailing: Wrap(
                          spacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (followUp.isOverdue)
                              Text(
                                'Overdue',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            if (workspace != null &&
                                workspace.canUpdate('crm')) ...[
                              IconButton(
                                tooltip: 'Edit follow-up',
                                onPressed: () => _editFollowUp(
                                  context,
                                  workspace,
                                  ref,
                                  followUp,
                                ),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Complete follow-up',
                                onPressed: () async {
                                  await ref
                                      .read(crmRepositoryProvider)
                                      .completeFollowUp(
                                        id: followUp.id,
                                        businessId: workspace.businessId,
                                      );
                                  ref.invalidate(crmFollowUpsProvider);
                                },
                                icon: const Icon(Icons.check_circle_outline),
                              ),
                            ],
                            if (workspace != null && workspace.canDelete('crm'))
                              IconButton(
                                tooltip: 'Delete follow-up',
                                onPressed: () => _deleteFollowUp(
                                  context,
                                  workspace,
                                  ref,
                                  followUp,
                                ),
                                icon: const Icon(Icons.delete_outline),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
              ],
            );
          },
        );
      },
    );
  }
}

class _CustomerNotesTab extends ConsumerStatefulWidget {
  const _CustomerNotesTab();

  @override
  ConsumerState<_CustomerNotesTab> createState() => _CustomerNotesTabState();
}

class _CustomerNotesTabState extends ConsumerState<_CustomerNotesTab> {
  String _customerId = '';
  String _query = '';
  String _sort = 'newest';
  int _page = 0;
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    final notes = _customerId.isNotEmpty
        ? ref.watch(crmCustomerNotesProvider(_customerId))
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _customerId = v.trim()),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    labelText: 'Customer ID (to view notes)',
                  ),
                ),
              ),
              if (_customerId.isNotEmpty &&
                  workspace != null &&
                  workspace.canCreate('crm')) ...[
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () => _createCustomerNote(
                    context,
                    workspace,
                    ref.read(crmRepositoryProvider),
                    _customerId,
                    ref,
                  ),
                  icon: const Icon(Icons.add_comment_outlined),
                  label: const Text('Add note'),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: _customerId.isEmpty
              ? const EmptyState(
                  icon: Icons.note_outlined,
                  title: 'Customer notes',
                  message: 'Enter a customer ID to view their notes.',
                )
              : notes!.when(
                  loading: () =>
                      const DataListSkeleton(sectionLabel: 'customer notes'),
                  error: (error, _) => EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Could not load notes',
                    message: error.toString(),
                  ),
                  data: (items) {
                    final filtered = items
                        .where(
                          (item) => item.note.toLowerCase().contains(_query),
                        )
                        .toList();
                    filtered.sort(
                      (a, b) => _sort == 'oldest'
                          ? a.createdAt.compareTo(b.createdAt)
                          : b.createdAt.compareTo(a.createdAt),
                    );
                    final pageCount = pageCountFor(filtered.length);
                    if (_page >= pageCount) _page = pageCount - 1;
                    final visible = pageItems(filtered, _page);
                    if (items.isEmpty) {
                      return const EmptyState(
                        icon: Icons.note_outlined,
                        title: 'No notes',
                        message: 'Notes added for this customer appear here.',
                      );
                    }
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
                      children: [
                        DataListControls(
                          query: _query,
                          onSearchChanged: (value) => setState(() {
                            _query = value.trim().toLowerCase();
                            _page = 0;
                          }),
                          searchLabel: 'Search note text',
                          sortValue: _sort,
                          sortOptions: const [
                            DataListSortOption('newest', 'Newest first'),
                            DataListSortOption('oldest', 'Oldest first'),
                          ],
                          onSortChanged: (value) => setState(() {
                            _sort = value;
                            _page = 0;
                          }),
                          page: _page,
                          pageCount: pageCount,
                          totalCount: filtered.length,
                          onPageChanged: (value) =>
                              setState(() => _page = value),
                          selectedCount: _selected.length,
                          allSelected:
                              visible.isNotEmpty &&
                              visible.every(
                                (item) => _selected.contains(item.id),
                              ),
                          onSelectAll: visible.isEmpty
                              ? null
                              : (value) => setState(() {
                                  if (value ?? false) {
                                    _selected.addAll(
                                      visible.map((item) => item.id),
                                    );
                                  } else {
                                    _selected.removeAll(
                                      visible.map((item) => item.id),
                                    );
                                  }
                                }),
                          onClearSelection: () => setState(_selected.clear),
                          bulkActions: [
                            FilledButton.tonalIcon(
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text: items
                                        .where(
                                          (item) => _selected.contains(item.id),
                                        )
                                        .map((item) => item.note)
                                        .join('\n'),
                                  ),
                                );
                                setState(_selected.clear);
                              },
                              icon: const Icon(Icons.copy_all_rounded),
                              label: const Text('Copy notes'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        for (final note in visible) ...[
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Checkbox(
                                  value: _selected.contains(note.id),
                                  onChanged: (value) => setState(() {
                                    if (value ?? false) {
                                      _selected.add(note.id);
                                    } else {
                                      _selected.remove(note.id);
                                    }
                                  }),
                                ),
                                CircleAvatar(
                                  child: Text(
                                    note.note.characters.first.toUpperCase(),
                                  ),
                                ),
                              ],
                            ),
                            title: Text(note.note),
                            subtitle: Text(
                              '${note.isPrivate ? 'Private' : 'Shared'} · '
                              '${DateFormat.yMMMd().add_jm().format(note.createdAt)}',
                            ),
                            trailing: Wrap(
                              spacing: 2,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Icon(
                                  note.isPrivate
                                      ? Icons.lock_outline_rounded
                                      : Icons.notes_outlined,
                                  size: 18,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                                if (workspace != null &&
                                    workspace.canUpdate('crm'))
                                  IconButton(
                                    tooltip: 'Edit note',
                                    onPressed: () => _editCustomerNote(
                                      context,
                                      workspace,
                                      ref,
                                      _customerId,
                                      note,
                                    ),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                if (workspace != null &&
                                    workspace.canDelete('crm'))
                                  IconButton(
                                    tooltip: 'Delete note',
                                    onPressed: () => _deleteCustomerNote(
                                      context,
                                      workspace,
                                      ref,
                                      _customerId,
                                      note,
                                    ),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                        ],
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _RemindersTab extends ConsumerWidget {
  const _RemindersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminders = ref.watch(crmRemindersProvider);
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    return reminders.when(
      loading: () => const DataListSkeleton(sectionLabel: 'crm reminders'),
      error: (error, _) => EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load reminders',
        message: error.toString(),
      ),
      data: (items) {
        final pending = items
            .where((r) => !r.isCompleted)
            .toList(growable: false);
        var query = '';
        var sort = 'due_soon';
        var page = 0;
        final selected = <String>{};
        return StatefulBuilder(
          builder: (context, setState) {
            final filtered = pending
                .where(
                  (item) =>
                      '${item.title} ${item.description ?? ''} ${item.relatedTable ?? ''}'
                          .toLowerCase()
                          .contains(query),
                )
                .toList();
            filtered.sort(
              (a, b) => sort == 'newest'
                  ? b.dueAt.compareTo(a.dueAt)
                  : a.dueAt.compareTo(b.dueAt),
            );
            final pageCount = pageCountFor(filtered.length);
            if (page >= pageCount) page = pageCount - 1;
            final visible = pageItems(filtered, page);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child:
                        workspace != null &&
                            workspace.permissionCodes.contains(
                              CrmPermissionCodes.manage,
                            )
                        ? FilledButton.icon(
                            onPressed: () => _createReminder(
                              context,
                              workspace,
                              ref.read(crmRepositoryProvider),
                              ref,
                            ),
                            icon: const Icon(Icons.add_alert_outlined),
                            label: const Text('New reminder'),
                          )
                        : null,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: DataListControls(
                    query: query,
                    onSearchChanged: (value) => setState(() {
                      query = value.trim().toLowerCase();
                      page = 0;
                    }),
                    searchLabel: 'Search reminders or related records',
                    sortValue: sort,
                    sortOptions: const [
                      DataListSortOption('due_soon', 'Due soonest'),
                      DataListSortOption('newest', 'Due latest'),
                    ],
                    onSortChanged: (value) => setState(() {
                      sort = value;
                      page = 0;
                    }),
                    page: page,
                    pageCount: pageCount,
                    totalCount: filtered.length,
                    onPageChanged: (value) => setState(() => page = value),
                    selectedCount: selected.length,
                    allSelected:
                        visible.isNotEmpty &&
                        visible.every((item) => selected.contains(item.id)),
                    onSelectAll: visible.isEmpty
                        ? null
                        : (value) => setState(() {
                            if (value ?? false) {
                              selected.addAll(visible.map((item) => item.id));
                            } else {
                              selected.removeAll(
                                visible.map((item) => item.id),
                              );
                            }
                          }),
                    onClearSelection: () => setState(selected.clear),
                    bulkActions: [
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(
                              text: items
                                  .where((item) => selected.contains(item.id))
                                  .map((item) => '${item.title}\t${item.dueAt}')
                                  .join('\n'),
                            ),
                          );
                          setState(selected.clear);
                        },
                        icon: const Icon(Icons.copy_all_rounded),
                        label: const Text('Copy reminders'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: visible.isEmpty
                      ? const EmptyState(
                          icon: Icons.notifications_outlined,
                          title: 'No reminders',
                          message:
                              'Set reminders for follow-ups, calls, and tasks.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(24, 12, 24, 100),
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final reminder = visible[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Checkbox(
                                    value: selected.contains(reminder.id),
                                    onChanged: (value) => setState(() {
                                      if (value ?? false) {
                                        selected.add(reminder.id);
                                      } else {
                                        selected.remove(reminder.id);
                                      }
                                    }),
                                  ),
                                  CircleAvatar(
                                    child: Text(
                                      reminder.title.characters.first
                                          .toUpperCase(),
                                    ),
                                  ),
                                ],
                              ),
                              title: Text(reminder.title),
                              subtitle: Text(
                                '${DateFormat.yMMMd().add_jm().format(reminder.dueAt)} '
                                '${reminder.isOverdue ? '· Overdue' : ''}',
                              ),
                              trailing: Wrap(
                                spacing: 2,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (reminder.isOverdue)
                                    Text(
                                      'Overdue',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  if (workspace != null &&
                                      workspace.canUpdate('crm')) ...[
                                    IconButton(
                                      tooltip: 'Edit reminder',
                                      onPressed: () => _editReminder(
                                        context,
                                        workspace,
                                        ref,
                                        reminder,
                                      ),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    IconButton(
                                      tooltip: 'Complete reminder',
                                      onPressed: () async {
                                        await ref
                                            .read(crmRepositoryProvider)
                                            .completeReminder(
                                              id: reminder.id,
                                              businessId: workspace.businessId,
                                            );
                                        ref.invalidate(crmRemindersProvider);
                                      },
                                      icon: const Icon(
                                        Icons.check_circle_outline,
                                      ),
                                    ),
                                  ],
                                  if (workspace != null &&
                                      workspace.canDelete('crm'))
                                    IconButton(
                                      tooltip: 'Delete reminder',
                                      onPressed: () => _deleteReminder(
                                        context,
                                        workspace,
                                        ref,
                                        reminder,
                                      ),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

Future<void> _createLead(
  BuildContext context,
  BusinessWorkspace workspace,
  CrmRepository repository,
  WidgetRef ref,
) async {
  final created = await showDialog<bool>(
    context: context,
    builder: (_) => _LeadDialog(
      workspace: workspace,
      repository: repository,
      salespersonId: ref.read(authRepositoryProvider).currentUser?.id,
    ),
  );
  if (created == true && context.mounted) {
    ref.invalidate(crmLeadsProvider);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Lead created.')));
  }
}

Future<void> _editLead(
  BuildContext context,
  BusinessWorkspace workspace,
  WidgetRef ref,
  CrmLead lead,
) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _LeadDialog(
      workspace: workspace,
      repository: ref.read(crmRepositoryProvider),
      salespersonId: ref.read(authRepositoryProvider).currentUser?.id,
      existing: lead,
    ),
  );
  if (saved == true) {
    ref.invalidate(crmLeadsProvider);
  }
}

Future<void> _archiveLead(
  BuildContext context,
  BusinessWorkspace workspace,
  WidgetRef ref,
  CrmLead lead,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Archive lead?'),
      content: Text(
        'Archive “${lead.title}”? Historical activity is retained.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Archive'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await ref
      .read(crmRepositoryProvider)
      .archiveLead(id: lead.id, businessId: workspace.businessId);
  ref.invalidate(crmLeadsProvider);
}

Future<void> _createOpportunity(
  BuildContext context,
  BusinessWorkspace workspace,
  CrmRepository repository,
  WidgetRef ref,
) async {
  final created = await showDialog<bool>(
    context: context,
    builder: (_) => _OpportunityDialog(
      workspace: workspace,
      repository: repository,
      salespersonId: ref.read(authRepositoryProvider).currentUser?.id,
    ),
  );
  if (created == true && context.mounted) {
    ref.invalidate(crmOpportunitiesProvider);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Opportunity created.')));
  }
}

Future<void> _editOpportunity(
  BuildContext context,
  BusinessWorkspace workspace,
  WidgetRef ref,
  CrmOpportunity opportunity,
) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _OpportunityDialog(
      workspace: workspace,
      repository: ref.read(crmRepositoryProvider),
      salespersonId: ref.read(authRepositoryProvider).currentUser?.id,
      existing: opportunity,
    ),
  );
  if (saved == true) ref.invalidate(crmOpportunitiesProvider);
}

Future<void> _archiveOpportunity(
  BuildContext context,
  BusinessWorkspace workspace,
  WidgetRef ref,
  CrmOpportunity opportunity,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Archive opportunity?'),
      content: Text(
        'Archive “${opportunity.title}”? Historical activity is retained.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Archive'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await ref
      .read(crmRepositoryProvider)
      .archiveOpportunity(id: opportunity.id, businessId: workspace.businessId);
  ref.invalidate(crmOpportunitiesProvider);
}

Future<void> _createQuotation(
  BuildContext context,
  BusinessWorkspace workspace,
  CrmRepository repository,
  WidgetRef ref,
) async {
  final created = await showDialog<bool>(
    context: context,
    builder: (_) => _QuotationDialog(
      workspace: workspace,
      repository: repository,
      salespersonId: ref.read(authRepositoryProvider).currentUser?.id,
    ),
  );
  if (created == true && context.mounted) {
    ref.invalidate(crmQuotationsProvider);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Quotation created.')));
  }
}

Future<void> _editQuotation(
  BuildContext context,
  BusinessWorkspace workspace,
  WidgetRef ref,
  CrmQuotation quotation,
) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _QuotationDialog(
      workspace: workspace,
      repository: ref.read(crmRepositoryProvider),
      salespersonId: ref.read(authRepositoryProvider).currentUser?.id,
      existing: quotation,
    ),
  );
  if (saved == true) ref.invalidate(crmQuotationsProvider);
}

Future<void> _archiveQuotation(
  BuildContext context,
  BusinessWorkspace workspace,
  WidgetRef ref,
  CrmQuotation quotation,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Archive quotation?'),
      content: Text(
        'Archive ${quotation.quotationNumber}? Historical activity is retained.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Archive'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await ref
      .read(crmRepositoryProvider)
      .archiveQuotation(id: quotation.id, businessId: workspace.businessId);
  ref.invalidate(crmQuotationsProvider);
}

Future<void> _createFollowUp(
  BuildContext context,
  BusinessWorkspace workspace,
  CrmRepository repository,
  WidgetRef ref,
) async {
  final created = await showDialog<bool>(
    context: context,
    builder: (_) => _FollowUpDialog(
      workspace: workspace,
      repository: repository,
      salespersonId: ref.read(authRepositoryProvider).currentUser?.id,
    ),
  );
  if (created == true && context.mounted) {
    ref.invalidate(crmFollowUpsProvider);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Follow-up scheduled.')));
  }
}

Future<void> _editFollowUp(
  BuildContext context,
  BusinessWorkspace workspace,
  WidgetRef ref,
  CrmFollowUp followUp,
) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _FollowUpDialog(
      workspace: workspace,
      repository: ref.read(crmRepositoryProvider),
      existing: followUp,
    ),
  );
  if (saved == true) ref.invalidate(crmFollowUpsProvider);
}

Future<void> _deleteFollowUp(
  BuildContext context,
  BusinessWorkspace workspace,
  WidgetRef ref,
  CrmFollowUp followUp,
) async {
  if (!await _confirmCrmDelete(
    context,
    'Delete follow-up?',
    'Delete “${followUp.title}”? This cannot be undone.',
  )) {
    return;
  }
  await ref
      .read(crmRepositoryProvider)
      .deleteFollowUp(id: followUp.id, businessId: workspace.businessId);
  ref.invalidate(crmFollowUpsProvider);
}

Future<void> _createCustomerNote(
  BuildContext context,
  BusinessWorkspace workspace,
  CrmRepository repository,
  String customerId,
  WidgetRef ref,
) async {
  final created = await showDialog<bool>(
    context: context,
    builder: (_) => _CustomerNoteDialog(
      workspace: workspace,
      repository: repository,
      customerId: customerId,
      salespersonId: ref.read(authRepositoryProvider).currentUser?.id,
    ),
  );
  if (created == true && context.mounted) {
    ref.invalidate(crmCustomerNotesProvider(customerId));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Customer note added.')));
  }
}

Future<void> _editCustomerNote(
  BuildContext context,
  BusinessWorkspace workspace,
  WidgetRef ref,
  String customerId,
  CrmCustomerNote note,
) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _CustomerNoteDialog(
      workspace: workspace,
      repository: ref.read(crmRepositoryProvider),
      customerId: customerId,
      existing: note,
    ),
  );
  if (saved == true) {
    ref.invalidate(crmCustomerNotesProvider(customerId));
  }
}

Future<void> _deleteCustomerNote(
  BuildContext context,
  BusinessWorkspace workspace,
  WidgetRef ref,
  String customerId,
  CrmCustomerNote note,
) async {
  if (!await _confirmCrmDelete(
    context,
    'Delete customer note?',
    'Delete this note? This cannot be undone.',
  )) {
    return;
  }
  await ref
      .read(crmRepositoryProvider)
      .deleteCustomerNote(id: note.id, businessId: workspace.businessId);
  ref.invalidate(crmCustomerNotesProvider(customerId));
}

Future<void> _createReminder(
  BuildContext context,
  BusinessWorkspace workspace,
  CrmRepository repository,
  WidgetRef ref,
) async {
  final created = await showDialog<bool>(
    context: context,
    builder: (_) => _ReminderDialog(
      workspace: workspace,
      repository: repository,
      salespersonId: ref.read(authRepositoryProvider).currentUser?.id,
    ),
  );
  if (created == true && context.mounted) {
    ref.invalidate(crmRemindersProvider);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Reminder created.')));
  }
}

Future<void> _editReminder(
  BuildContext context,
  BusinessWorkspace workspace,
  WidgetRef ref,
  CrmReminder reminder,
) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _ReminderDialog(
      workspace: workspace,
      repository: ref.read(crmRepositoryProvider),
      existing: reminder,
    ),
  );
  if (saved == true) ref.invalidate(crmRemindersProvider);
}

Future<void> _deleteReminder(
  BuildContext context,
  BusinessWorkspace workspace,
  WidgetRef ref,
  CrmReminder reminder,
) async {
  if (!await _confirmCrmDelete(
    context,
    'Delete reminder?',
    'Delete “${reminder.title}”? This cannot be undone.',
  )) {
    return;
  }
  await ref
      .read(crmRepositoryProvider)
      .deleteReminder(id: reminder.id, businessId: workspace.businessId);
  ref.invalidate(crmRemindersProvider);
}

Future<bool> _confirmCrmDelete(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
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
    ) ??
    false;

class _LeadDialog extends StatefulWidget {
  const _LeadDialog({
    required this.workspace,
    required this.repository,
    this.salespersonId,
    this.existing,
  });

  final BusinessWorkspace workspace;
  final CrmRepository repository;
  final String? salespersonId;
  final CrmLead? existing;

  @override
  State<_LeadDialog> createState() => _LeadDialogState();
}

class _LeadDialogState extends State<_LeadDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _source = TextEditingController();
  final _status = TextEditingController(text: 'new');
  final _notes = TextEditingController();
  final _estimatedValue = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final lead = widget.existing;
    if (lead != null) {
      _title.text = lead.title;
      _source.text = lead.source ?? '';
      _status.text = lead.status;
      _notes.text = lead.notes ?? '';
      _estimatedValue.text = lead.estimatedValueMinor == null
          ? ''
          : (lead.estimatedValueMinor! / 100).toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _source.dispose();
    _status.dispose();
    _notes.dispose();
    _estimatedValue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Create lead' : 'Edit lead'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _title,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _source,
                  decoration: const InputDecoration(
                    labelText: 'Source (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _status.text,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'new', child: Text('New')),
                    DropdownMenuItem(
                      value: 'contacted',
                      child: Text('Contacted'),
                    ),
                    DropdownMenuItem(
                      value: 'qualified',
                      child: Text('Qualified'),
                    ),
                    DropdownMenuItem(
                      value: 'unqualified',
                      child: Text('Unqualified'),
                    ),
                    DropdownMenuItem(
                      value: 'converted',
                      child: Text('Converted'),
                    ),
                    DropdownMenuItem(value: 'lost', child: Text('Lost')),
                  ],
                  onChanged: (v) => _status.text = v ?? 'new',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _estimatedValue,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Estimated value (optional)',
                    prefixText: '\$',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                  maxLines: 2,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
              : Text(widget.existing == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.existing == null) {
        await widget.repository.createLead(
          businessId: widget.workspace.businessId,
          title: _title.text,
          source: _source.text,
          status: _status.text,
          salespersonId: widget.salespersonId,
          estimatedValueMinor: parseMoneyToMinor(_estimatedValue.text),
          notes: _notes.text,
        );
      } else {
        await widget.repository.updateLead(
          id: widget.existing!.id,
          businessId: widget.workspace.businessId,
          title: _title.text,
          source: _source.text,
          status: _status.text,
          salespersonId: widget.salespersonId,
          estimatedValueMinor: parseMoneyToMinor(_estimatedValue.text),
          notes: _notes.text,
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

class _OpportunityDialog extends StatefulWidget {
  const _OpportunityDialog({
    required this.workspace,
    required this.repository,
    this.salespersonId,
    this.existing,
  });
  final BusinessWorkspace workspace;
  final CrmRepository repository;
  final String? salespersonId;
  final CrmOpportunity? existing;

  @override
  State<_OpportunityDialog> createState() => _OpportunityDialogState();
}

class _OpportunityDialogState extends State<_OpportunityDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _value = TextEditingController();
  final _probability = TextEditingController(text: '50');
  final _notes = TextEditingController();
  String _stage = 'prospecting';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final opportunity = widget.existing;
    if (opportunity != null) {
      _title.text = opportunity.title;
      _stage = opportunity.stage;
      _value.text = (opportunity.valueMinor / 100).toStringAsFixed(2);
      _probability.text = opportunity.probability.toString();
      _notes.text = opportunity.notes ?? '';
    }
  }

  @override
  void dispose() {
    for (final controller in [_title, _value, _probability, _notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.existing == null ? 'Create opportunity' : 'Edit opportunity',
    ),
    content: SizedBox(
      width: 520,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _title,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _stage,
                decoration: const InputDecoration(labelText: 'Pipeline stage'),
                items: const [
                  DropdownMenuItem(
                    value: 'prospecting',
                    child: Text('Prospecting'),
                  ),
                  DropdownMenuItem(
                    value: 'qualification',
                    child: Text('Qualification'),
                  ),
                  DropdownMenuItem(value: 'proposal', child: Text('Proposal')),
                  DropdownMenuItem(
                    value: 'negotiation',
                    child: Text('Negotiation'),
                  ),
                  DropdownMenuItem(
                    value: 'closed_won',
                    child: Text('Closed won'),
                  ),
                  DropdownMenuItem(
                    value: 'closed_lost',
                    child: Text('Closed lost'),
                  ),
                ],
                onChanged: (value) => setState(() => _stage = value ?? _stage),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _value,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Value',
                  prefixText: '\$',
                ),
                validator: (value) =>
                    value == null || parseMoneyToMinor(value) == null
                    ? 'Enter a valid amount'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _probability,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Probability (0–100%)',
                ),
                validator: (value) {
                  final parsed = int.tryParse(value ?? '');
                  return parsed == null || parsed < 0 || parsed > 100
                      ? 'Enter 0–100'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
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
            : Text(widget.existing == null ? 'Create' : 'Save'),
      ),
    ],
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.existing == null) {
        await widget.repository.createOpportunity(
          businessId: widget.workspace.businessId,
          title: _title.text,
          stage: _stage,
          probability: int.parse(_probability.text),
          valueMinor: parseMoneyToMinor(_value.text) ?? 0,
          notes: _notes.text,
          salespersonId: widget.salespersonId,
        );
      } else {
        await widget.repository.updateOpportunity(
          id: widget.existing!.id,
          businessId: widget.workspace.businessId,
          title: _title.text,
          stage: _stage,
          probability: int.parse(_probability.text),
          valueMinor: parseMoneyToMinor(_value.text) ?? 0,
          notes: _notes.text,
          salespersonId: widget.salespersonId,
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

class _QuotationDialog extends StatefulWidget {
  const _QuotationDialog({
    required this.workspace,
    required this.repository,
    this.salespersonId,
    this.existing,
  });
  final BusinessWorkspace workspace;
  final CrmRepository repository;
  final String? salespersonId;
  final CrmQuotation? existing;

  @override
  State<_QuotationDialog> createState() => _QuotationDialogState();
}

class _QuotationDialogState extends State<_QuotationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _number = TextEditingController();
  final _title = TextEditingController();
  final _subtotal = TextEditingController();
  final _tax = TextEditingController(text: '0');
  final _discount = TextEditingController(text: '0');
  final _notes = TextEditingController();
  String _status = 'draft';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final quotation = widget.existing;
    if (quotation != null) {
      _number.text = quotation.quotationNumber;
      _title.text = quotation.title;
      _status = quotation.status;
      _subtotal.text = (quotation.subtotalMinor / 100).toStringAsFixed(2);
      _tax.text = (quotation.taxMinor / 100).toStringAsFixed(2);
      _discount.text = (quotation.discountMinor / 100).toStringAsFixed(2);
      _notes.text = quotation.notes ?? '';
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _number,
      _title,
      _subtotal,
      _tax,
      _discount,
      _notes,
    ])
      controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.existing == null ? 'Create quotation' : 'Edit quotation',
    ),
    content: SizedBox(
      width: 540,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _number,
                decoration: const InputDecoration(
                  labelText: 'Quotation number',
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'draft', child: Text('Draft')),
                  DropdownMenuItem(value: 'sent', child: Text('Sent')),
                  DropdownMenuItem(value: 'accepted', child: Text('Accepted')),
                  DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                ],
                onChanged: (value) =>
                    setState(() => _status = value ?? _status),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _subtotal,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Subtotal'),
                      validator: _moneyValidator,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _tax,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Tax'),
                      validator: _moneyValidator,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _discount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Discount'),
                      validator: _moneyValidator,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
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
            : Text(widget.existing == null ? 'Create' : 'Save'),
      ),
    ],
  );

  String? _moneyValidator(String? value) =>
      parseMoneyToMinor(value ?? '') == null ? 'Enter a valid amount' : null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final subtotal = parseMoneyToMinor(_subtotal.text) ?? 0;
    final tax = parseMoneyToMinor(_tax.text) ?? 0;
    final discount = parseMoneyToMinor(_discount.text) ?? 0;
    if (subtotal + tax < discount) {
      setState(() => _error = 'Discount cannot exceed subtotal plus tax.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.existing == null) {
        await widget.repository.createQuotation(
          businessId: widget.workspace.businessId,
          quotationNumber: _number.text,
          title: _title.text,
          status: _status,
          subtotalMinor: subtotal,
          taxMinor: tax,
          discountMinor: discount,
          grandTotalMinor: subtotal + tax - discount,
          notes: _notes.text,
          salespersonId: widget.salespersonId,
        );
      } else {
        await widget.repository.updateQuotation(
          id: widget.existing!.id,
          businessId: widget.workspace.businessId,
          quotationNumber: _number.text,
          title: _title.text,
          status: _status,
          subtotalMinor: subtotal,
          taxMinor: tax,
          discountMinor: discount,
          grandTotalMinor: subtotal + tax - discount,
          notes: _notes.text,
          salespersonId: widget.salespersonId,
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

class _FollowUpDialog extends StatefulWidget {
  const _FollowUpDialog({
    required this.workspace,
    required this.repository,
    this.salespersonId,
    this.existing,
  });
  final BusinessWorkspace workspace;
  final CrmRepository repository;
  final String? salespersonId;
  final CrmFollowUp? existing;

  @override
  State<_FollowUpDialog> createState() => _FollowUpDialogState();
}

class _FollowUpDialogState extends State<_FollowUpDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _notes = TextEditingController();
  String _type = 'call';
  DateTime _dueAt = DateTime.now().add(const Duration(days: 1));
  bool _saving = false;
  String? _error;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _title.text = existing.title;
      _notes.text = existing.notes ?? '';
      _type = existing.type;
      _dueAt = existing.dueAt;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_editing ? 'Edit follow-up' : 'Schedule follow-up'),
    content: SizedBox(
      width: 500,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                DropdownMenuItem(value: 'call', child: Text('Call')),
                DropdownMenuItem(value: 'email', child: Text('Email')),
                DropdownMenuItem(value: 'meeting', child: Text('Meeting')),
                DropdownMenuItem(value: 'visit', child: Text('Visit')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (value) => setState(() => _type = value ?? _type),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(DateFormat.yMMMd().format(_dueAt)),
              subtitle: const Text('Due date'),
              trailing: TextButton(
                onPressed: _pickDate,
                child: const Text('Change'),
              ),
            ),
            TextFormField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
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
            : Text(_editing ? 'Save changes' : 'Schedule'),
      ),
    ],
  );

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: _dueAt,
    );
    if (date != null && mounted)
      setState(() => _dueAt = DateTime(date.year, date.month, date.day, 9));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final existing = widget.existing;
      if (existing == null) {
        await widget.repository.createFollowUp(
          businessId: widget.workspace.businessId,
          title: _title.text,
          type: _type,
          dueAt: _dueAt,
          notes: _notes.text,
          salespersonId: widget.salespersonId,
        );
      } else {
        await widget.repository.updateFollowUp(
          id: existing.id,
          businessId: widget.workspace.businessId,
          title: _title.text,
          type: _type,
          dueAt: _dueAt,
          notes: _notes.text,
          salespersonId: existing.salespersonId,
          leadId: existing.leadId,
          opportunityId: existing.opportunityId,
          quotationId: existing.quotationId,
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

class _CustomerNoteDialog extends StatefulWidget {
  const _CustomerNoteDialog({
    required this.workspace,
    required this.repository,
    required this.customerId,
    this.salespersonId,
    this.existing,
  });
  final BusinessWorkspace workspace;
  final CrmRepository repository;
  final String customerId;
  final String? salespersonId;
  final CrmCustomerNote? existing;

  @override
  State<_CustomerNoteDialog> createState() => _CustomerNoteDialogState();
}

class _CustomerNoteDialogState extends State<_CustomerNoteDialog> {
  final _formKey = GlobalKey<FormState>();
  final _note = TextEditingController();
  bool _private = true;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _note.text = existing.note;
      _private = existing.isPrivate;
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_editing ? 'Edit customer note' : 'Add customer note'),
    content: SizedBox(
      width: 500,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _note,
              autofocus: true,
              maxLines: 5,
              maxLength: 4000,
              decoration: const InputDecoration(labelText: 'Note'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Required' : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _private,
              title: const Text('Private note'),
              subtitle: const Text(
                'Only the author, assignee, or CRM managers can see it.',
              ),
              onChanged: (value) => setState(() => _private = value),
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
            : Text(_editing ? 'Save changes' : 'Save note'),
      ),
    ],
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final existing = widget.existing;
      if (existing == null) {
        await widget.repository.createCustomerNote(
          businessId: widget.workspace.businessId,
          customerId: widget.customerId,
          note: _note.text,
          isPrivate: _private,
          salespersonId: widget.salespersonId,
        );
      } else {
        await widget.repository.updateCustomerNote(
          id: existing.id,
          businessId: widget.workspace.businessId,
          note: _note.text,
          isPrivate: _private,
          salespersonId: existing.salespersonId,
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

class _ReminderDialog extends StatefulWidget {
  const _ReminderDialog({
    required this.workspace,
    required this.repository,
    this.salespersonId,
    this.existing,
  });
  final BusinessWorkspace workspace;
  final CrmRepository repository;
  final String? salespersonId;
  final CrmReminder? existing;

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  DateTime _dueAt = DateTime.now().add(const Duration(days: 1));
  bool _saving = false;
  String? _error;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _title.text = existing.title;
      _description.text = existing.description ?? '';
      _dueAt = existing.dueAt;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_editing ? 'Edit reminder' : 'Create reminder'),
    content: SizedBox(
      width: 500,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(DateFormat.yMMMd().format(_dueAt)),
              subtitle: const Text('Due date'),
              trailing: TextButton(
                onPressed: _pickDate,
                child: const Text('Change'),
              ),
            ),
            TextFormField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
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
            : Text(_editing ? 'Save changes' : 'Create'),
      ),
    ],
  );

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: _dueAt,
    );
    if (date != null && mounted)
      setState(() => _dueAt = DateTime(date.year, date.month, date.day, 9));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final existing = widget.existing;
      if (existing == null) {
        await widget.repository.createReminder(
          businessId: widget.workspace.businessId,
          title: _title.text,
          description: _description.text,
          dueAt: _dueAt,
          salespersonId: widget.salespersonId,
        );
      } else {
        await widget.repository.updateReminder(
          id: existing.id,
          businessId: widget.workspace.businessId,
          title: _title.text,
          description: _description.text,
          dueAt: _dueAt,
          salespersonId: existing.salespersonId,
          relatedTable: existing.relatedTable,
          relatedId: existing.relatedId,
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
