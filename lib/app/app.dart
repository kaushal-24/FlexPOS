import 'package:flexpos/app/router/app_router.dart';
import 'package:flexpos/app/theme/app_theme.dart';
import 'package:flexpos/app/theme/theme_controller.dart';
import 'package:flexpos/core/providers/core_providers.dart';
import 'package:flexpos/core/widgets/configuration_error_page.dart';
import 'package:flexpos/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FlexPosApp extends ConsumerWidget {
  const FlexPosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final themeMode = ref.watch(themeModeProvider);

    if (!config.isSupabaseConfigured) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: config.appName,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        home: const ConfigurationErrorPage(),
      );
    }

    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: config.appName,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
