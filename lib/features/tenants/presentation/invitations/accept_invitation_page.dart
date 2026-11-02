import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/features/tenants/data/tenant_repository.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AcceptInvitationPage extends ConsumerStatefulWidget {
  const AcceptInvitationPage({super.key});
  @override
  ConsumerState<AcceptInvitationPage> createState() =>
      _AcceptInvitationPageState();
}

class _AcceptInvitationPageState extends ConsumerState<AcceptInvitationPage> {
  final _token = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    if (_token.text.trim().length < 20) {
      return _error('Enter the complete invitation code.');
    }
    setState(() => _submitting = true);
    try {
      final businessId = await ref
          .read(tenantRepositoryProvider)
          .acceptStaffInvitation(_token.text);
      await ref.read(selectedBusinessIdProvider.notifier).select(businessId);
      ref.invalidate(workspacesProvider);
      if (mounted) context.go('/dashboard');
    } on PostgrestException catch (error) {
      if (mounted) _error(error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _error(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Back to dashboard',
        onPressed: () => context.go('/dashboard'),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: const Text('Join a business'),
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.mark_email_read_outlined, size: 52),
                const SizedBox(height: 16),
                Text(
                  'Accept staff invitation',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sign in with the invited email address, then enter the one-time code shared by your business administrator.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: _token,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Invitation code',
                    prefixIcon: Icon(Icons.key_outlined),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _submitting ? null : _accept,
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: Text(_submitting ? 'Joining…' : 'Join business'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
