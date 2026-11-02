// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'FlexPOS';

  @override
  String get signIn => 'Sign in';

  @override
  String get signUp => 'Create account';

  @override
  String get email => 'Email address';

  @override
  String get password => 'Password';

  @override
  String get confirmPassword => 'Confirm password';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get sendResetLink => 'Send reset link';

  @override
  String get signOut => 'Sign out';

  @override
  String get dashboard => 'Dashboard';

  @override
  String get pos => 'POS';

  @override
  String get products => 'Products';

  @override
  String get inventory => 'Inventory';

  @override
  String get customers => 'Customers';

  @override
  String get more => 'More';

  @override
  String get welcomeBack => 'Welcome back';

  @override
  String get noAccount => 'New to FlexPOS?';

  @override
  String get hasAccount => 'Already have an account?';

  @override
  String get resetInstructions =>
      'Enter your email and we will send a secure reset link.';

  @override
  String get checkInbox => 'Check your inbox to continue.';

  @override
  String get foundationReady => 'Secure foundation ready';

  @override
  String get configurationRequired => 'Configuration required';

  @override
  String get tryAgain => 'Try again';
}
