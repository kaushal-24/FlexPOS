import 'package:flexpos/app/theme/app_colors.dart';
import 'package:flexpos/app/theme/app_tokens.dart';
import 'package:flutter/material.dart';

abstract final class AppTheme {
  static ThemeData light() => _build(
    brightness: Brightness.light,
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    primary: AppColors.lightPrimary,
    secondary: AppColors.lightSecondary,
    foreground: AppColors.lightText,
    muted: AppColors.lightMutedText,
    border: AppColors.lightBorder,
    error: AppColors.lightError,
  );

  static ThemeData dark() => _build(
    brightness: Brightness.dark,
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    primary: AppColors.darkPrimary,
    secondary: AppColors.darkSecondary,
    foreground: AppColors.darkText,
    muted: AppColors.darkMutedText,
    border: AppColors.darkBorder,
    error: AppColors.darkError,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color primary,
    required Color secondary,
    required Color foreground,
    required Color muted,
    required Color border,
    required Color error,
  }) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: brightness,
        ).copyWith(
          primary: primary,
          secondary: secondary,
          surface: surface,
          onSurface: foreground,
          error: error,
          outline: border,
          outlineVariant: border.withValues(alpha: 0.65),
        );

    final baseTextTheme = ThemeData(brightness: brightness).textTheme;
    final textTheme = baseTextTheme.copyWith(
      displaySmall: baseTextTheme.displaySmall?.copyWith(
        fontWeight: AppTypography.extraBold,
        color: foreground,
        letterSpacing: AppTypography.displayTracking,
      ),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        fontWeight: AppTypography.bold,
        color: foreground,
        letterSpacing: AppTypography.headingTracking,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontWeight: AppTypography.bold,
        color: foreground,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontWeight: AppTypography.semibold,
        color: foreground,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(color: foreground),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(color: foreground),
      bodySmall: baseTextTheme.bodySmall?.copyWith(color: muted),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontWeight: AppTypography.bold,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      dividerColor: border,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        centerTitle: false,
        elevation: AppElevation.flat,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: AppElevation.flat,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.xl),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          borderSide: BorderSide(color: primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(
            AppSizes.minimumTouchTarget,
            AppSizes.controlHeight,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          textStyle: const TextStyle(fontWeight: AppTypography.bold),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(
            AppSizes.minimumTouchTarget,
            AppSizes.controlHeight,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(AppSizes.minimumTouchTarget),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: primary.withValues(alpha: 0.14),
        elevation: AppElevation.flat,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: primary.withValues(alpha: 0.14),
        elevation: AppElevation.flat,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: AppElevation.overlay,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.xl),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        elevation: AppElevation.overlay,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.xl),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        elevation: AppElevation.overlay,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: AppElevation.low,
        focusElevation: AppElevation.overlay,
        hoverElevation: AppElevation.overlay,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: AppElevation.overlay,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
      ),
    );
  }
}
