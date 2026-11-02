import 'package:flexpos/app/theme/theme_controller.dart';
import 'package:flexpos/core/providers/core_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('theme selection cycles and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    expect(container.read(themeModeProvider), ThemeMode.system);

    await container.read(themeModeProvider.notifier).cycle();

    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(preferences.getString('theme_mode'), 'light');
  });
}
