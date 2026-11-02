import 'package:flexpos/app/app.dart';
import 'package:flexpos/app/config/app_config.dart';
import 'package:flexpos/core/providers/core_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows actionable setup guidance when configuration is missing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              appName: 'FlexPOS Test',
              supabaseUrl: '',
              supabasePublishableKey: '',
            ),
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
        child: const FlexPosApp(),
      ),
    );

    expect(find.text('Configuration required'), findsOneWidget);
    expect(
      find.text('flutter run --dart-define-from-file=config/dev.json'),
      findsOneWidget,
    );
  });
}
