import 'package:flexpos/features/auth/data/auth_repository.dart';
import 'package:flexpos/features/auth/presentation/widgets/auth_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UpdatePasswordPage extends ConsumerStatefulWidget {
  const UpdatePasswordPage({super.key});
  @override
  ConsumerState<UpdatePasswordPage> createState() => _UpdatePasswordPageState();
}

class _UpdatePasswordPageState extends ConsumerState<UpdatePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _saving = false;
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(authRepositoryProvider).updatePassword(_password.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password updated securely.')),
        );
        context.go('/dashboard');
      }
    } on AuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthSurface(
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Choose a new password',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Use at least 10 characters and keep it unique to FlexPOS.',
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _password,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'New password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Show password' : 'Hide password',
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            validator: (value) => (value?.length ?? 0) < 10
                ? 'Use at least 10 characters.'
                : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _confirmation,
            obscureText: _obscure,
            decoration: const InputDecoration(
              labelText: 'Confirm new password',
              prefixIcon: Icon(Icons.verified_user_outlined),
            ),
            validator: (value) =>
                value != _password.text ? 'Passwords do not match.' : null,
            onFieldSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Updating…' : 'Update password'),
          ),
        ],
      ),
    ),
  );
}
