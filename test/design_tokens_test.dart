import 'package:flexpos/app/theme/app_theme.dart';
import 'package:flexpos/app/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('spacing, radius, and elevation token scales are ordered', () {
    expect(const [
      AppSpacing.xxs,
      AppSpacing.xs,
      AppSpacing.sm,
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.xl,
      AppSpacing.xxl,
      AppSpacing.section,
    ], orderedEquals(const [4, 8, 12, 16, 20, 24, 32, 40]));
    expect(const [
      AppRadii.xs,
      AppRadii.sm,
      AppRadii.md,
      AppRadii.lg,
      AppRadii.xl,
      AppRadii.xxl,
    ], orderedEquals(const [4, 8, 12, 14, 18, 22]));
    expect(const [
      AppElevation.flat,
      AppElevation.low,
      AppElevation.overlay,
      AppElevation.high,
    ], orderedEquals(const [0, 1, 3, 6]));
  });

  test('global themes consume shared shape, elevation, and type tokens', () {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      final cardShape = theme.cardTheme.shape! as RoundedRectangleBorder;
      final cardRadius = cardShape.borderRadius as BorderRadius;
      expect(cardRadius.topLeft.x, AppRadii.xl);
      expect(theme.cardTheme.elevation, AppElevation.flat);
      expect(theme.dialogTheme.elevation, AppElevation.overlay);
      expect(theme.textTheme.titleLarge?.fontWeight, AppTypography.bold);
      expect(
        theme.filledButtonTheme.style?.minimumSize?.resolve({}),
        const Size(AppSizes.minimumTouchTarget, AppSizes.controlHeight),
      );
    }
  });
}
