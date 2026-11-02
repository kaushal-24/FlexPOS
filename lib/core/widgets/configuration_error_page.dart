import 'package:flexpos/app/theme/app_tokens.dart';
import 'package:flutter/material.dart';

class ConfigurationErrorPage extends StatelessWidget {
  const ConfigurationErrorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ExcludeSemantics(
                          child: Icon(
                            Icons.settings_suggest_outlined,
                            size: 52,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Semantics(
                          header: true,
                          child: Text(
                            'Configuration required',
                            style: Theme.of(context).textTheme.headlineMedium,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        const Text(
                          'Start FlexPOS with SUPABASE_URL and '
                          'SUPABASE_PUBLISHABLE_KEY supplied through '
                          '--dart-define or --dart-define-from-file.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        const SelectableText(
                          'flutter run --dart-define-from-file=config/dev.json',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
