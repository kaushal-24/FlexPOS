import 'package:flexpos/core/logging/app_logger.dart';
import 'package:flexpos/core/providers/core_providers.dart';
import 'package:flexpos/core/data/repository_contract.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(appLoggerProvider),
  ),
);

final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges,
);

class AuthRepository implements SupabaseRepositoryContract {
  AuthRepository(this._client, [AppLogger? logger])
    : _logger = logger ?? AppLogger();

  final SupabaseClient _client;
  final AppLogger _logger;

  @override
  SupabaseClient get client => _client;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;
  Session? get currentSession => _client.auth.currentSession;
  User? get currentUser => _client.auth.currentUser;

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    _logger.info('auth.sign_in.started', fields: {'email': email.trim()});
    return _client.auth
        .signInWithPassword(email: email.trim(), password: password)
        .then((response) {
          _logger.info(
            'auth.sign_in.succeeded',
            fields: {'has_session': response.session != null},
          );
          return response;
        })
        .catchError((Object error) {
          _logger.error('auth.sign_in.failed', exception: error);
          throw error;
        });
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) {
    _logger.info('auth.sign_up.started', fields: {'email': email.trim()});
    return _client.auth
        .signUp(
          email: email.trim(),
          password: password,
          emailRedirectTo: Uri.base.origin,
        )
        .then((response) {
          _logger.info(
            'auth.sign_up.succeeded',
            fields: {'has_session': response.session != null},
          );
          return response;
        })
        .catchError((Object error) {
          _logger.error('auth.sign_up.failed', exception: error);
          throw error;
        });
  }

  Future<void> sendPasswordReset(String email) {
    _logger.info(
      'auth.password_reset.started',
      fields: {'email': email.trim()},
    );
    return _client.auth
        .resetPasswordForEmail(
          email.trim(),
          redirectTo: Uri.base.resolve('/update-password').toString(),
        )
        .then((_) => _logger.info('auth.password_reset.succeeded'))
        .catchError((Object error) {
          _logger.error('auth.password_reset.failed', exception: error);
          throw error;
        });
  }

  Future<void> resendVerification(String email) {
    _logger.info(
      'auth.verification_resend.started',
      fields: {'email': email.trim()},
    );
    return _client.auth
        .resend(
          type: OtpType.signup,
          email: email.trim(),
          emailRedirectTo: Uri.base.origin,
        )
        .then((_) => _logger.info('auth.verification_resend.succeeded'))
        .catchError((Object error) {
          _logger.error('auth.verification_resend.failed', exception: error);
          throw error;
        });
  }

  Future<UserResponse> updatePassword(String password) {
    _logger.info('auth.password_update.started');
    return _client.auth
        .updateUser(UserAttributes(password: password))
        .then((response) {
          _logger.info('auth.password_update.succeeded');
          return response;
        })
        .catchError((Object error) {
          _logger.error('auth.password_update.failed', exception: error);
          throw error;
        });
  }

  Future<void> signOut() {
    _logger.info('auth.sign_out.started');
    return _client.auth
        .signOut()
        .then((_) => _logger.info('auth.sign_out.succeeded'))
        .catchError((Object error) {
          _logger.error('auth.sign_out.failed', exception: error);
          throw error;
        });
  }
}
