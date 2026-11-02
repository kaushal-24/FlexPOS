import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/features/tenants/data/tenant_repository.dart';
import 'package:flexpos/features/tenants/domain/business_workspace.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BusinessOnboardingPage extends ConsumerStatefulWidget {
  const BusinessOnboardingPage({super.key});

  @override
  ConsumerState<BusinessOnboardingPage> createState() =>
      _BusinessOnboardingPageState();
}

class _BusinessOnboardingPageState
    extends ConsumerState<BusinessOnboardingPage> {
  final _formKey = GlobalKey<FormState>();
  final _businessName = TextEditingController();
  final _branchName = TextEditingController(text: 'Main Branch');
  final _branchCode = TextEditingController(text: 'MAIN');
  String _businessType = 'retail';
  String _currency = 'INR';
  String _timezone = 'Asia/Kolkata';
  String _country = 'IN';
  bool _isSubmitting = false;

  static const _businessTypes = {
    'retail': 'Retail store',
    'grocery': 'Supermarket or grocery',
    'restaurant': 'Restaurant, cafe, or bakery',
    'wholesale': 'Wholesale distributor',
    'fashion': 'Clothing and fashion',
    'electronics': 'Electronics and mobile',
    'hardware': 'Hardware and electrical',
    'auto_parts': 'Auto parts',
    'salon': 'Salon or beauty service',
    'service': 'Repair or service center',
    'pharmacy': 'Pharmacy',
    'warehouse': 'Warehouse',
    'manufacturing': 'Manufacturing or assembly',
    'other': 'Other business',
  };

  @override
  void dispose() {
    _businessName.dispose();
    _branchName.dispose();
    _branchCode.dispose();
    super.dispose();
  }

  Future<void> _createWorkspace() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final businessId = await ref
          .read(tenantRepositoryProvider)
          .createBusiness(
            CreateBusinessRequest(
              businessName: _businessName.text,
              businessType: _businessType,
              currencyCode: _currency,
              timezone: _timezone,
              branchName: _branchName.text,
              branchCode: _branchCode.text,
              countryCode: _country,
            ),
          );
      await ref.read(selectedBusinessIdProvider.notifier).select(businessId);
      ref.invalidate(workspacesProvider);
      if (mounted) context.go('/dashboard');
    } on PostgrestException catch (error) {
      if (mounted) _showError(error.message);
    } catch (_) {
      if (mounted) {
        _showError(
          'Unable to create the workspace. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to dashboard',
          onPressed: () => context.go('/dashboard'),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Create your workspace'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primary,
                          foregroundColor: Theme.of(context)
                              .colorScheme
                              .onPrimary,
                          child: const Text('1'),
                        ),
                        const Expanded(child: Divider()),
                        CircleAvatar(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: const Text('2'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Business and branch',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This creates a tenant, owner role, full permission set, '
                      'membership, and first branch in one database transaction.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    AppPanel(
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _businessName,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Business name',
                              prefixIcon: Icon(Icons.storefront_outlined),
                            ),
                            validator: (value) =>
                                (value?.trim().length ?? 0) < 2
                                ? 'Enter at least 2 characters.'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: _businessType,
                            decoration: const InputDecoration(
                              labelText: 'Business type',
                              prefixIcon: Icon(Icons.category_outlined),
                            ),
                            items: _businessTypes.entries
                                .map(
                                  (item) => DropdownMenuItem(
                                    value: item.key,
                                    child: Text(item.value),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setState(() => _businessType = value!),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _currency,
                                  decoration: const InputDecoration(
                                    labelText: 'Currency',
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'INR',
                                      child: Text('INR — Indian Rupee'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'USD',
                                      child: Text('USD — US Dollar'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'AED',
                                      child: Text('AED — UAE Dirham'),
                                    ),
                                  ],
                                  onChanged: (value) =>
                                      setState(() => _currency = value!),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _country,
                                  decoration: const InputDecoration(
                                    labelText: 'Country',
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'IN',
                                      child: Text('India'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'US',
                                      child: Text('United States'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'AE',
                                      child: Text('United Arab Emirates'),
                                    ),
                                  ],
                                  onChanged: (value) =>
                                      setState(() => _country = value!),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: _timezone,
                            decoration: const InputDecoration(
                              labelText: 'Timezone',
                              prefixIcon: Icon(Icons.schedule_outlined),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'Asia/Kolkata',
                                child: Text('Asia/Kolkata (IST)'),
                              ),
                              DropdownMenuItem(
                                value: 'UTC',
                                child: Text('UTC'),
                              ),
                              DropdownMenuItem(
                                value: 'Asia/Dubai',
                                child: Text('Asia/Dubai'),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => _timezone = value!),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 22),
                            child: Divider(),
                          ),
                          TextFormField(
                            controller: _branchName,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'First branch name',
                              prefixIcon: Icon(Icons.location_on_outlined),
                            ),
                            validator: (value) =>
                                (value?.trim().length ?? 0) < 2
                                ? 'Enter at least 2 characters.'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _branchCode,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Branch code',
                              helperText: 'Letters, numbers, and hyphens only.',
                              prefixIcon: Icon(Icons.tag_rounded),
                            ),
                            validator: (value) =>
                                RegExp(r'^[A-Za-z0-9-]{1,16}$')
                                    .hasMatch(value?.trim() ?? '')
                                ? null
                                : 'Enter a valid branch code.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _isSubmitting ? null : _createWorkspace,
                      icon: _isSubmitting
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Create secure workspace'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
