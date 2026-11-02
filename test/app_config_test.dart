import 'package:flexpos/app/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig', () {
    test('accepts a valid Supabase URL and publishable key', () {
      const config = AppConfig(
        appName: 'Test',
        supabaseUrl: 'https://project.supabase.co',
        supabasePublishableKey: 'sb_publishable_example',
      );

      expect(config.isSupabaseConfigured, isTrue);
    });

    test('rejects missing or privileged-looking credentials', () {
      const missing = AppConfig(
        appName: 'Test',
        supabaseUrl: '',
        supabasePublishableKey: '',
      );
      const secretKey = AppConfig(
        appName: 'Test',
        supabaseUrl: 'https://project.supabase.co',
        supabasePublishableKey: 'sb_secret_must_not_be_in_client',
      );

      expect(missing.isSupabaseConfigured, isFalse);
      expect(secretKey.isSupabaseConfigured, isFalse);
    });
  });
}
