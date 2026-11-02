class AppConfig {
  const AppConfig({
    required this.appName,
    required this.supabaseUrl,
    required this.supabasePublishableKey,
  });

  factory AppConfig.fromEnvironment() {
    return const AppConfig(
      appName: String.fromEnvironment('APP_NAME', defaultValue: 'FlexPOS'),
      supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
      supabasePublishableKey: String.fromEnvironment(
        'SUPABASE_PUBLISHABLE_KEY',
      ),
    );
  }

  final String appName;
  final String supabaseUrl;
  final String supabasePublishableKey;

  bool get isSupabaseConfigured =>
      Uri.tryParse(supabaseUrl)?.hasScheme == true &&
      supabasePublishableKey.startsWith('sb_publishable_');
}
