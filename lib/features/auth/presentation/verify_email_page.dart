import 'package:flexpos/features/auth/data/auth_repository.dart';
import 'package:flexpos/features/auth/presentation/widgets/auth_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VerifyEmailPage extends ConsumerStatefulWidget {
  const VerifyEmailPage({required this.email, super.key});
  final String email;
  @override
  ConsumerState<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends ConsumerState<VerifyEmailPage> {
  bool _sending = false;

  Future<void> _resend() async {
    if (widget.email.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(authRepositoryProvider).resendVerification(widget.email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification email sent again.')),
        );
      }
    } on AuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.mark_email_unread_outlined,
          size: 58,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 18),
        Text(
          'Verify your email',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 10),
        Text(
          widget.email.isEmpty
              ? 'Open the verification link sent to your inbox.'
              : 'We sent a verification link to ${widget.email}.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.tonal(
          onPressed: _sending || widget.email.isEmpty ? null : _resend,
          child: Text(_sending ? 'Sending…' : 'Resend email'),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => context.go('/login'),
          child: const Text('Back to sign in'),
        ),
      ],
    ),
  );
}
