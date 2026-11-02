import 'package:flexpos/app/app.dart';
import 'package:flexpos/app/config/app_config.dart';
import 'package:flexpos/core/providers/core_providers.dart';
import 'package:flexpos/features/splash/presentation/startup_splash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AppConfig.fromEnvironment();
  final preferences = await SharedPreferences.getInstance();

  if (config.isSupabaseConfigured) {
    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabasePublishableKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: const StartupGate(child: FlexPosApp()),
    ),
  );
}
