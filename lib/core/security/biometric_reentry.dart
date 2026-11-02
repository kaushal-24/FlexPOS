import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';

/// Performs a local device-authentication step before the server-verified
/// cashier PIN re-entry. The PIN remains mandatory, so a device biometric
/// never replaces the tenant-scoped Supabase authorization check.
class BiometricReentry {
  BiometricReentry({LocalAuthentication? authentication})
    : _authentication = authentication ?? LocalAuthentication();

  final LocalAuthentication _authentication;

  Future<bool> isAvailable() async {
    try {
      return (await _authentication.getAvailableBiometrics()).isNotEmpty;
    } on MissingPluginException {
      return false;
    } on LocalAuthException {
      return false;
    }
  }

  Future<bool> authenticate() async {
    try {
      if (!await isAvailable()) return false;
      return await _authentication.authenticate(
        localizedReason:
            'Verify this device before re-entering the cashier PIN.',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on MissingPluginException {
      return false;
    } on LocalAuthException {
      return false;
    }
  }
}
