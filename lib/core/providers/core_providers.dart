import 'package:flexpos/app/config/app_config.dart';
import 'package:flexpos/core/logging/app_logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final appConfigProvider = Provider<AppConfig>(
  (ref) => throw StateError('AppConfig must be provided at startup.'),
);

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw StateError('SharedPreferences must be provided at startup.'),
);

final appLoggerProvider = Provider<AppLogger>((ref) => AppLogger());
