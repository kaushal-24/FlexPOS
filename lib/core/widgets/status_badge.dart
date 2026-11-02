import 'package:flexpos/app/theme/app_colors.dart';
import 'package:flexpos/app/theme/app_tokens.dart';
import 'package:flutter/material.dart';

enum StatusTone { success, warning, danger, info, neutral }

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    required this.label,
    this.tone = StatusTone.neutral,
    super.key,
  });

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = switch (tone) {
      StatusTone.success =>
        dark ? AppColors.darkSuccess : AppColors.lightSuccess,
      StatusTone.warning =>
        dark ? AppColors.darkWarning : AppColors.lightWarning,
      StatusTone.danger => dark ? AppColors.darkError : AppColors.lightError,
      StatusTone.info => dark ? AppColors.darkInfo : AppColors.lightInfo,
      StatusTone.neutral => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return Semantics(
      label: 'Status: $label',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: color, fontWeight: AppTypography.bold),
            ),
          ),
        ),
      ),
    );
  }
}
