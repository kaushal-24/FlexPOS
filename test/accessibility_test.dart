import 'package:flexpos/app/theme/app_colors.dart';
import 'package:flexpos/app/theme/app_theme.dart';
import 'package:flexpos/app/theme/app_tokens.dart';
import 'package:flexpos/core/widgets/configuration_error_page.dart';
import 'package:flexpos/core/widgets/data_list_controls.dart';
import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/core/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('core light and dark text colors meet WCAG AA contrast', () {
    final pairs = <(Color, Color)>[
      (AppColors.lightText, AppColors.lightBackground),
      (AppColors.lightMutedText, AppColors.lightBackground),
      (AppColors.lightPrimary, AppColors.lightSurface),
      (AppColors.lightSecondary, AppColors.lightSurface),
      (AppColors.lightError, AppColors.lightSurface),
      (AppColors.darkText, AppColors.darkBackground),
      (AppColors.darkMutedText, AppColors.darkBackground),
      (AppColors.darkPrimary, AppColors.darkSurface),
      (AppColors.darkSecondary, AppColors.darkSurface),
      (AppColors.darkError, AppColors.darkSurface),
    ];

    for (final pair in pairs) {
      expect(_contrastRatio(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
    }
  });

  test('global interaction themes enforce padded 48px touch targets', () {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
      expect(
        theme.iconButtonTheme.style?.minimumSize?.resolve({}),
        const Size.square(AppSizes.minimumTouchTarget),
      );
    }
  });

  testWidgets('shared states remain usable at 200 percent text scale', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 560));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: EmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'No products are available',
            message:
                'Create a product or change the active filters to continue.',
            action: FilledButton(
              onPressed: null,
              child: Text('Create product'),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: ConfigurationErrorPage(),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('status badges expose one explicit semantic status label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: StatusBadge(label: 'Paid', tone: StatusTone.success),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Status: Paid'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('shared data-list controls expose labelled navigation actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: DataListControls(
            searchLabel: 'Search products',
            onSearchChanged: (_) {},
            sortOptions: const [DataListSortOption('name', 'Name')],
            sortValue: 'name',
            onSortChanged: (_) {},
            page: 0,
            pageCount: 2,
            onPageChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Search products'), findsOneWidget);
    expect(find.byTooltip('Previous page'), findsOneWidget);
    expect(find.byTooltip('Next page'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('shared data-list controls fit compact browser widths', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(208, 560));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: DataListControls(
              searchLabel: 'Search orders',
              onSearchChanged: _ignoreString,
              sortOptions: [
                DataListSortOption('newest', 'Newest first'),
                DataListSortOption('name', 'Name (A–Z)'),
              ],
              sortValue: 'newest',
              onSortChanged: _ignoreString,
              page: 0,
              pageCount: 1,
              onPageChanged: _ignoreInt,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Sort by'), findsOneWidget);
  });
}

void _ignoreString(String _) {}

void _ignoreInt(int _) {}

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
