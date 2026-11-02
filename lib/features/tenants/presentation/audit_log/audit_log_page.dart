import 'dart:convert';

import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/core/security/crud_permissions.dart';
import 'package:flexpos/core/widgets/data_page_skeleton.dart';
import 'package:flexpos/core/widgets/data_list_controls.dart';
import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/features/tenants/domain/tenant_audit_log.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class AuditLogPage extends ConsumerStatefulWidget {
  const AuditLogPage({super.key});

  @override
  ConsumerState<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends ConsumerState<AuditLogPage> {
  String _query = '';
  String _sort = 'newest';
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    if (workspace == null) {
      return const EmptyState(
        icon: Icons.add_business_outlined,
        title: 'Select a business',
        message: 'A business workspace is required to view audit activity.',
      );
    }
    if (!workspace.canRead('audit')) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Audit access is restricted',
        message: 'Your role does not include permission to view audit logs.',
      );
    }
    final logs = ref.watch(auditLogsProvider(workspace.businessId));
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: logs.when(
        loading: () => const DataPageSkeleton(sectionLabel: 'audit log'),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load audit log',
          message: error.toString(),
          action: FilledButton.icon(
            onPressed: () =>
                ref.invalidate(auditLogsProvider(workspace.businessId)),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ),
        data: (items) => _buildContent(context, workspace.businessId, items),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    String businessId,
    List<TenantAuditLog> items,
  ) {
    final query = _query.trim().toLowerCase();
    final filtered =
        (query.isEmpty
              ? items
              : items
                    .where(
                      (item) =>
                          item.action.toLowerCase().contains(query) ||
                          item.targetType.toLowerCase().contains(query) ||
                          (item.targetId?.toLowerCase().contains(query) ??
                              false) ||
                          jsonEncode(item.details)
                              .toLowerCase()
                              .contains(query),
                    )
                    .toList())
          ..sort(
            (a, b) => switch (_sort) {
              'oldest' => a.createdAt.compareTo(b.createdAt),
              'action' => a.action.compareTo(b.action),
              _ => b.createdAt.compareTo(a.createdAt),
            },
          );
    final pageCount = pageCountFor(filtered.length);
    if (_page >= pageCount) _page = pageCount - 1;
    final visible = pageItems(filtered, _page);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(auditLogsProvider(businessId));
        await ref.read(auditLogsProvider(businessId).future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 96),
        children: [
          Text('Audit log', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(
            'Immutable business activity visible to authorized auditors.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          DataListControls(
            query: _query,
            onSearchChanged: (value) => setState(() {
              _query = value;
              _page = 0;
            }),
            searchLabel: 'Search action, target, or details',
            sortValue: _sort,
            sortOptions: const [
              DataListSortOption('newest', 'Newest first'),
              DataListSortOption('oldest', 'Oldest first'),
              DataListSortOption('action', 'Action (A–Z)'),
            ],
            onSortChanged: (value) => setState(() {
              _sort = value;
              _page = 0;
            }),
            page: _page,
            pageCount: pageCount,
            totalCount: filtered.length,
            onPageChanged: (value) => setState(() => _page = value),
          ),
          const SizedBox(height: 18),
          if (filtered.isEmpty)
            EmptyState(
              icon: Icons.history_toggle_off_rounded,
              title: query.isEmpty ? 'No audit activity yet' : 'No matches',
              message: query.isEmpty
                  ? 'Security and operational events will appear here.'
                  : 'Try a different search term.',
            )
          else
            for (final item in visible) ...[
              _AuditLogCard(item: item),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _AuditLogCard extends StatelessWidget {
  const _AuditLogCard({required this.item});

  final TenantAuditLog item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actor = item.actorUserId == null
        ? 'System'
        : 'User ${item.actorUserId!.substring(0, 8)}';
    final target = item.targetId == null
        ? item.targetType
        : '${item.targetType} · ${item.targetId}';
    return AppPanel(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.secondaryContainer,
          foregroundColor: theme.colorScheme.onSecondaryContainer,
          child: const Icon(Icons.history_rounded),
        ),
        title: Text(item.action),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(target),
            Text(
              '$actor · ${DateFormat.yMMMd().add_jm().format(item.createdAt.toLocal())}',
              style: theme.textTheme.bodySmall,
            ),
            if (item.details.isNotEmpty)
              Text(
                jsonEncode(item.details),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}
