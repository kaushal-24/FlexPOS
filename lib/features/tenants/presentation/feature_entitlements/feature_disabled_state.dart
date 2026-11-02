import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class FeatureDisabledState extends StatelessWidget {
  const FeatureDisabledState({
    required this.featureName,
    required this.canManage,
    super.key,
  });

  final String featureName;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.extension_off_outlined,
      title: '$featureName is disabled',
      message:
          'This module is not enabled for the selected business. '
          '${canManage ? 'You can enable it in Module settings.' : 'Ask a business administrator to enable it.'}',
      action: canManage
          ? FilledButton.icon(
              onPressed: () => context.go('/modules'),
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Open module settings'),
            )
          : null,
    );
  }
}
