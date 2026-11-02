import 'package:flexpos/features/splash/presentation/startup_splash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('startup splash reveals the app after exactly three seconds', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: StartupGate(child: Text('Ready'))),
    );

    expect(find.text('Loading 0%'), findsOneWidget);
    expect(find.text('Ready'), findsNothing);

    await tester.pump(const Duration(milliseconds: 2999));
    expect(find.textContaining('Loading'), findsOneWidget);
    expect(find.text('Ready'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('Ready'), findsOneWidget);
  });
}
