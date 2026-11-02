import 'package:flexpos/app/theme/app_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('motion durations are restrained and ordered', () {
    expect(AppMotion.quick, lessThan(AppMotion.standard));
    expect(AppMotion.standard, lessThan(AppMotion.emphasized));
    expect(
      AppMotion.emphasized,
      lessThanOrEqualTo(const Duration(milliseconds: 250)),
    );
    expect(AppMotion.ambient, greaterThan(AppMotion.emphasized));
  });

  test('motion resolves to zero when reduced motion is requested', () {
    expect(
      AppMotion.resolveDuration(
        const MediaQueryData(disableAnimations: true),
        AppMotion.emphasized,
      ),
      Duration.zero,
    );
    expect(
      AppMotion.resolveDuration(
        const MediaQueryData(accessibleNavigation: true),
        AppMotion.standard,
      ),
      Duration.zero,
    );
    expect(
      AppMotion.resolveDuration(const MediaQueryData(), AppMotion.standard),
      AppMotion.standard,
    );
  });

  testWidgets('motion switcher applies the reduced-motion duration', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: AppMotionSwitcher(
            motionKey: ValueKey('content'),
            child: Text('Content'),
          ),
        ),
      ),
    );

    final switcher = tester.widget<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher),
    );
    expect(switcher.duration, Duration.zero);
    expect(switcher.reverseDuration, Duration.zero);
  });
}
