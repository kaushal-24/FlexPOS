import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/core/widgets/data_page_skeleton.dart';
import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/features/tenants/data/tenant_repository.dart';
import 'package:flexpos/features/tenants/domain/business_receipt_settings.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flexpos/core/security/crud_permissions.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BusinessSettingsPage extends ConsumerWidget {
  const BusinessSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    if (workspace == null) {
      return const EmptyState(
        icon: Icons.add_business_outlined,
        title: 'Select a business',
        message:
            'A business workspace is required to configure receipt settings.',
      );
    }
    if (!workspace.canManage('business')) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Business settings are restricted',
        message: 'Your role cannot change invoice or receipt settings.',
      );
    }

    final settings = ref.watch(
      businessReceiptSettingsProvider(workspace.businessId),
    );
    return settings.when(
      loading: () => const DataPageSkeleton(sectionLabel: 'business settings'),
      error: (error, _) => EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load business settings',
        message: error.toString(),
        action: FilledButton.icon(
          onPressed: () => ref.invalidate(
            businessReceiptSettingsProvider(workspace.businessId),
          ),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      ),
      data: (settings) => _BusinessSettingsForm(
        settings: settings,
        onSaved: () {
          ref.invalidate(businessReceiptSettingsProvider(workspace.businessId));
        },
      ),
    );
  }
}

class _BusinessSettingsForm extends StatefulWidget {
  const _BusinessSettingsForm({required this.settings, required this.onSaved});

  final BusinessReceiptSettings settings;
  final VoidCallback onSaved;

  @override
  State<_BusinessSettingsForm> createState() => _BusinessSettingsFormState();
}

class _BusinessSettingsFormState extends State<_BusinessSettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _taxController;
  late final TextEditingController _prefixController;
  late final TextEditingController _footerController;
  late final TextEditingController _qrController;
  late final TextEditingController _stockAlertRecipientsController;
  late String _template;
  late String _paperWidth;
  late bool _showLogo;
  late bool _showQr;
  late bool _stockAlertEmailEnabled;
  final _pinController = TextEditingController();
  bool _uploadingLogo = false;
  bool _saving = false;
  bool _savingPin = false;
  bool _registeringDevice = false;

  @override
  void initState() {
    super.initState();
    _taxController = TextEditingController(
      text: widget.settings.taxRegistrationNumber ?? '',
    );
    _prefixController = TextEditingController(
      text: widget.settings.invoicePrefix,
    );
    _footerController = TextEditingController(
      text: widget.settings.receiptFooter ?? '',
    );
    _qrController = TextEditingController(
      text: widget.settings.receiptQrPayload ?? '',
    );
    _stockAlertRecipientsController = TextEditingController(
      text: widget.settings.stockAlertEmailRecipients ?? '',
    );
    _template = widget.settings.receiptTemplate;
    _paperWidth = widget.settings.receiptPaperWidth;
    _showLogo = widget.settings.receiptShowLogo;
    _showQr = widget.settings.receiptShowQr;
    _stockAlertEmailEnabled = widget.settings.stockAlertEmailEnabled;
  }

  @override
  void dispose() {
    _taxController.dispose();
    _prefixController.dispose();
    _footerController.dispose();
    _qrController.dispose();
    _stockAlertRecipientsController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ProviderScope.containerOf(context, listen: false)
          .read(tenantRepositoryProvider)
          .updateBusinessReceiptSettings(
            businessId: widget.settings.businessId,
            taxRegistrationNumber: _taxController.text,
            invoicePrefix: _prefixController.text,
            receiptFooter: _footerController.text,
            receiptTemplate: _template,
            receiptQrPayload: _qrController.text,
            receiptShowLogo: _showLogo,
            receiptShowQr: _showQr,
            receiptPaperWidth: _paperWidth,
            stockAlertEmailEnabled: _stockAlertEmailEnabled,
            stockAlertEmailRecipients: _stockAlertRecipientsController.text,
          );
      if (!mounted) return;
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business receipt settings saved.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save business settings: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showStockAlertEmailSetup() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.mark_email_read_outlined),
        title: const Text('Email delivery setup'),
        content: const Text(
          'Recipients and the notification toggle are saved here. To deliver '
          'emails, configure a server-side provider (for example Resend) with '
          'RESEND_API_KEY and STOCK_ALERT_FROM_EMAIL, then deploy the '
          'stock-alert-email Supabase Edge Function. No provider secret is '
          'stored in the Flutter app.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
        children: [
          Text(
            'Business settings',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Configure the business identity printed on invoices and receipts.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 22),
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.settings.businessName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _prefixController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 12,
                  decoration: const InputDecoration(
                    labelText: 'Invoice prefix',
                    helperText: 'Uppercase letters, numbers, and hyphens only.',
                  ),
                  validator: (value) {
                    final prefix = value?.trim().toUpperCase() ?? '';
                    if (!RegExp(r'^[A-Z0-9-]{1,12}$').hasMatch(prefix)) {
                      return 'Use 1–12 uppercase letters, numbers, or hyphens.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _showStockAlertEmailSetup,
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Configure email delivery'),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _taxController,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Tax registration number',
                    helperText: 'Optional; printed on the receipt header.',
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _footerController,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Receipt footer',
                    helperText: 'Optional message printed below the totals.',
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _template,
                  decoration: const InputDecoration(
                    labelText: 'Invoice template',
                    helperText:
                        'Choose the information density used in receipts.',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'classic', child: Text('Classic')),
                    DropdownMenuItem(value: 'minimal', child: Text('Minimal')),
                    DropdownMenuItem(
                      value: 'detailed',
                      child: Text('Detailed'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _template = value);
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _paperWidth,
                  decoration: const InputDecoration(
                    labelText: 'Default receipt width',
                    helperText:
                        'Used when opening a receipt for printing or PDF.',
                  ),
                  items: const [
                    DropdownMenuItem(value: '58', child: Text('58 mm thermal')),
                    DropdownMenuItem(value: '80', child: Text('80 mm thermal')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _paperWidth = value);
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show logo on receipts'),
                  value: _showLogo,
                  onChanged: (value) => setState(() => _showLogo = value),
                ),
                const Divider(height: 28),
                Text(
                  'Low-stock email notifications',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Optional alerts are sent by the configured server-side email provider.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable email notifications'),
                  value: _stockAlertEmailEnabled,
                  onChanged: (value) =>
                      setState(() => _stockAlertEmailEnabled = value),
                ),
                TextFormField(
                  controller: _stockAlertRecipientsController,
                  maxLength: 2000,
                  maxLines: 2,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Notification recipients',
                    hintText: 'owner@example.com, manager@example.com',
                    helperText: 'Comma-separated email addresses.',
                  ),
                  validator: (value) {
                    if (!_stockAlertEmailEnabled ||
                        (value?.trim().isEmpty ?? true)) {
                      return null;
                    }
                    final addresses = value!
                        .split(',')
                        .map((item) => item.trim())
                        .where((item) => item.isNotEmpty);
                    final emailPattern = RegExp(
                      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                    );
                    if (addresses.any((item) => !emailPattern.hasMatch(item))) {
                      return 'Use valid comma-separated email addresses.';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: _qrController,
                  maxLength: 2048,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Receipt QR payload',
                    helperText:
                        'Optional URL or payment payload encoded as a QR code.',
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show QR code on receipts'),
                  value: _showQr,
                  onChanged: (value) => setState(() => _showQr = value),
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _uploadingLogo ? null : _uploadLogo,
                        icon: _uploadingLogo
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.upload_file_outlined),
                        label: Text(
                          widget.settings.receiptLogoPath == null
                              ? 'Upload logo'
                              : 'Replace logo',
                        ),
                      ),
                    ),
                    if (widget.settings.receiptLogoPath != null) ...[
                      const SizedBox(width: 10),
                      IconButton(
                        tooltip: 'Remove logo',
                        onPressed: _uploadingLogo ? null : _removeLogo,
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Saving…' : 'Save settings'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppPanel(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.check_circle_outline_rounded),
              title: const Text('Receipt presentation'),
              subtitle: const Text(
                'Templates, tenant logos, and QR payloads are stored securely '
                'per business and applied to reconstructed receipts.',
              ),
            ),
          ),
          const SizedBox(height: 14),
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cashier security',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Require a secure PIN re-entry before completing a sale on this account.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 12,
                  decoration: const InputDecoration(
                    labelText: 'Cashier PIN (6–12 digits)',
                    prefixIcon: Icon(Icons.pin_outlined),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: _savingPin ? null : _savePin,
                    icon: _savingPin
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_reset_outlined),
                    label: const Text('Set or replace PIN'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppPanel(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: ProviderScope.containerOf(context, listen: false)
                  .read(tenantRepositoryProvider)
                  .fetchBusinessDevices(widget.settings.businessId),
              builder: (context, snapshot) {
                final devices = snapshot.data ?? const <Map<String, dynamic>>[];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Registered devices',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _registeringDevice
                              ? null
                              : _registerDevice,
                          icon: _registeringDevice
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.devices_other_outlined),
                          label: const Text('Register this device'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const LinearProgressIndicator()
                    else if (devices.isEmpty)
                      const Text('No devices have been registered yet.')
                    else
                      for (final device in devices)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            device['status'] == 'active'
                                ? Icons.devices_outlined
                                : Icons.block_outlined,
                          ),
                          title: Text(
                            device['device_name'] as String? ?? 'Device',
                          ),
                          subtitle: Text(
                            '${device['platform'] ?? 'unknown'} · ${device['status'] ?? 'unknown'}',
                          ),
                          trailing: device['status'] == 'active'
                              ? IconButton(
                                  tooltip: 'Revoke device',
                                  onPressed: () =>
                                      _revokeDevice(device['id'] as String),
                                  icon: const Icon(Icons.remove_circle_outline),
                                )
                              : null,
                        ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _savePin() async {
    final pin = _pinController.text.trim();
    if (!RegExp(r'^\d{6,12}$').hasMatch(pin)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cashier PIN must contain 6 to 12 digits.'),
        ),
      );
      return;
    }
    setState(() => _savingPin = true);
    try {
      await ProviderScope.containerOf(context, listen: false)
          .read(tenantRepositoryProvider)
          .setCashierPin(businessId: widget.settings.businessId, pin: pin);
      _pinController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cashier PIN saved securely.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save cashier PIN: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingPin = false);
    }
  }

  Future<void> _registerDevice() async {
    setState(() => _registeringDevice = true);
    try {
      final repository = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(tenantRepositoryProvider);
      await repository.registerBusinessDevice(
        businessId: widget.settings.businessId,
        deviceKey:
            '${DateTime.now().microsecondsSinceEpoch}-${widget.settings.businessId}',
        deviceName: 'Current browser',
        platform: 'web',
      );
      if (mounted) setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This device is registered.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not register device: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _registeringDevice = false);
    }
  }

  Future<void> _revokeDevice(String id) async {
    try {
      await ProviderScope.containerOf(
        context,
        listen: false,
      ).read(tenantRepositoryProvider).revokeBusinessDevice(id);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not revoke device: $error')),
        );
      }
    }
  }

  Future<void> _uploadLogo() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;
    final extension = file.name.split('.').last.toLowerCase();
    final contentType = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      _ => 'image/png',
    };
    setState(() => _uploadingLogo = true);
    try {
      await ProviderScope.containerOf(context, listen: false)
          .read(tenantRepositoryProvider)
          .uploadBusinessReceiptLogo(
            businessId: widget.settings.businessId,
            bytes: await file.readAsBytes(),
            extension: extension == 'jpeg' ? 'jpg' : extension,
            contentType: contentType,
          );
      widget.onSaved();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not upload logo: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _removeLogo() async {
    setState(() => _uploadingLogo = true);
    try {
      await ProviderScope.containerOf(context, listen: false)
          .read(tenantRepositoryProvider)
          .removeBusinessReceiptLogo(widget.settings.businessId);
      widget.onSaved();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove logo: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }
}
