import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/core/widgets/data_page_skeleton.dart';
import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/features/tenants/data/tenant_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PlatformAdminPage extends ConsumerWidget {
  const PlatformAdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Map<String, dynamic>>(
      future: ref.read(tenantRepositoryProvider).fetchPlatformAdminOverview(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const DataPageSkeleton(
            sectionLabel: 'platform administration',
          );
        }
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.admin_panel_settings_outlined,
            title: 'Platform administration is restricted',
            message: 'Only an active platform administrator can view SaaS-wide operations.',
          );
        }
        final values = snapshot.data!;
        final cards = [
          ('Businesses', values['business_count'], Icons.business_outlined),
          ('Active members', values['member_count'], Icons.people_alt_outlined),
          ('Active devices', values['device_count'], Icons.devices_outlined),
          ('Auth users', values['user_count'], Icons.verified_user_outlined),
        ];
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
          children: [
            Text(
              'Platform administration',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'SaaS-wide health and tenant operations. Access is enforced by Supabase, not by the client UI.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final card in cards)
                  SizedBox(
                    width: 220,
                    child: AppPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            card.$3,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            card.$1,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${card.$2 ?? 0}',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            const AppPanel(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.security_outlined),
                title: Text('Role assignment is service-controlled'),
                subtitle: Text(
                  'Platform administrator membership is intentionally not self-service. Provision it through a protected operator workflow, then use this screen for verified overview access.',
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
