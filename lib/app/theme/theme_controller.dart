import 'package:flexpos/core/providers/core_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends Notifier<ThemeMode> {
  static const _preferenceKey = 'theme_mode';

  @override
  ThemeMode build() {
    final saved = ref
        .watch(sharedPreferencesProvider)
        .getString(_preferenceKey);
    return ThemeMode.values.where((mode) => mode.name == saved).firstOrNull ??
        ThemeMode.system;
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await ref
        .read(sharedPreferencesProvider)
        .setString(_preferenceKey, mode.name);
  }

  Future<void> cycle() async {
    final next = switch (state) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    await setMode(next);
  }
}
