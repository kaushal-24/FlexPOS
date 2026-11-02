import 'package:flexpos/features/auth/data/auth_repository.dart';
import 'package:flexpos/features/auth/presentation/widgets/auth_surface.dart';
import 'package:flexpos/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final response = await ref
          .read(authRepositoryProvider)
          .signUp(
            email: _emailController.text,
            password: _passwordController.text,
          );
      if (!mounted) return;
      if (response.session == null) {
        context.go(
          Uri(
            path: '/verify-email',
            queryParameters: {'email': _emailController.text.trim()},
          ).toString(),
        );
      }
    } on AuthException catch (error) {
      if (!mounted) return;
      _showError(error.message);
    } catch (_) {
      if (!mounted) return;
      _showError('Unable to create your account. Try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AuthSurface(
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.signUp,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Use your work email. Business setup starts after verification.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              TextFormField(
                controller: _emailController,
                autofillHints: const [AutofillHints.newUsername],
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.email,
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
                      ? null
                      : 'Enter a valid email address.';
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                autofillHints: const [AutofillHints.newPassword],
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.password,
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? 'Show passwords'
                        : 'Hide passwords',
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) => (value?.length ?? 0) < 10
                    ? 'Use at least 10 characters.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: l10n.confirmPassword,
                  prefixIcon: const Icon(Icons.verified_user_outlined),
                ),
                validator: (value) => value != _passwordController.text
                    ? 'Passwords do not match.'
                    : null,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.signUp),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(l10n.hasAccount),
                  TextButton(
                    onPressed: _isLoading ? null : () => context.go('/login'),
                    child: Text(l10n.signIn),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
