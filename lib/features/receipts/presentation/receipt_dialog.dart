import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flexpos/core/utils/money.dart';
import 'package:flexpos/core/widgets/data_page_skeleton.dart';
import 'package:flexpos/features/receipts/application/receipt_pdf.dart';
import 'package:flexpos/features/receipts/data/receipt_repository.dart';
import 'package:flexpos/features/receipts/domain/receipt_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

Future<void> showReceiptDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String businessId,
  required String saleId,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ReceiptDialog(
    repository: ref.read(receiptRepositoryProvider),
    businessId: businessId,
    saleId: saleId,
  ),
);

class _ReceiptDialog extends StatefulWidget {
  const _ReceiptDialog({
    required this.repository,
    required this.businessId,
    required this.saleId,
  });

  final ReceiptRepository repository;
  final String businessId;
  final String saleId;

  @override
  State<_ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<_ReceiptDialog> {
  late Future<ReceiptDocument> _receipt;
  bool _working = false;
  ReceiptPaperSize _paperSize = ReceiptPaperSize.mm80;
  bool _paperSizeInitialized = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _receipt = widget.repository
        .fetchReceipt(businessId: widget.businessId, saleId: widget.saleId)
        .then((receipt) {
          if (mounted && !_paperSizeInitialized) {
            _paperSizeInitialized = true;
            _paperSize = receipt.receiptPaperWidth == '58'
                ? ReceiptPaperSize.mm58
                : ReceiptPaperSize.mm80;
          }
          return receipt;
        });
  }

  Future<void> _print(ReceiptDocument receipt) async {
    setState(() => _working = true);
    try {
      await Printing.layoutPdf(
        name: receipt.fileName,
        format: _paperSize.pageFormat,
        dynamicLayout: false,
        onLayout: (_) => buildReceiptPdf(receipt, _paperSize.pageFormat),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not print: $error')));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _share(ReceiptDocument receipt) async {
    setState(() => _working = true);
    try {
      final bytes = await buildReceiptPdf(receipt, _paperSize.pageFormat);
      await Printing.sharePdf(bytes: bytes, filename: receipt.fileName);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not share: $error')));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _download(ReceiptDocument receipt) async {
    setState(() => _working = true);
    try {
      final bytes = await buildReceiptPdf(receipt, _paperSize.pageFormat);
      final destination = await FilePicker.saveFile(
        dialogTitle: 'Save receipt PDF',
        fileName: receipt.fileName,
        bytes: bytes,
        mimeType: 'application/pdf',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (mounted && destination != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Receipt PDF saved.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save PDF: $error')));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: math.min(screen.width - 32, 520),
        height: math.min(screen.height - 32, 780),
        child: FutureBuilder<ReceiptDocument>(
          future: _receipt,
          builder: (context, snapshot) {
            final receipt = snapshot.data;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long_rounded),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          receipt == null
                              ? 'Receipt'
                              : 'Receipt ${receipt.invoiceNumber}',
                          style: Theme.of(context).textTheme.titleLarge,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: _working
                            ? null
                            : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: switch (snapshot.connectionState) {
                    ConnectionState.waiting ||
                    ConnectionState.active => const DataListSkeleton(
                      sectionLabel: 'receipt',
                      itemCount: 4,
                    ),
                    _ when snapshot.hasError => _ReceiptError(
                      error: snapshot.error.toString(),
                      retry: () => setState(_load),
                    ),
                    _ => _ReceiptPreview(
                      receipt: receipt!,
                      paperSize: _paperSize,
                    ),
                  },
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SegmentedButton<ReceiptPaperSize>(
                        segments: const [
                          ButtonSegment(
                            value: ReceiptPaperSize.mm58,
                            label: Text('58 mm'),
                          ),
                          ButtonSegment(
                            value: ReceiptPaperSize.mm80,
                            label: Text('80 mm'),
                          ),
                        ],
                        selected: {_paperSize},
                        showSelectedIcon: false,
                        onSelectionChanged: _working
                            ? null
                            : (selection) =>
                                  setState(() => _paperSize = selection.single),
                      ),
                      TextButton(
                        onPressed: _working
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                      OutlinedButton.icon(
                        onPressed: receipt == null || _working
                            ? null
                            : () => _download(receipt),
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Download PDF'),
                      ),
                      OutlinedButton.icon(
                        onPressed: receipt == null || _working
                            ? null
                            : () => _share(receipt),
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('Share PDF'),
                      ),
                      FilledButton.icon(
                        onPressed: receipt == null || _working
                            ? null
                            : () => _print(receipt),
                        icon: _working
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.print_outlined),
                        label: const Text('Print'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ReceiptError extends StatelessWidget {
  const _ReceiptError({required this.error, required this.retry});

  final String error;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 42,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          const Text('Could not load this receipt'),
          const SizedBox(height: 6),
          Text(error, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

class _ReceiptPreview extends StatelessWidget {
  const _ReceiptPreview({required this.receipt, required this.paperSize});

  final ReceiptDocument receipt;
  final ReceiptPaperSize paperSize;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: paperSize == ReceiptPaperSize.mm58 ? 300 : 360,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (receipt.receiptShowLogo)
                receipt.logoBytes == null
                    ? Image.asset(
                        'assets/branding/flexpos_logo.png',
                        width: paperSize == ReceiptPaperSize.mm58 ? 86 : 132,
                        height: paperSize == ReceiptPaperSize.mm58 ? 46 : 70,
                        fit: BoxFit.contain,
                      )
                    : Image.memory(
                        receipt.logoBytes!,
                        width: paperSize == ReceiptPaperSize.mm58 ? 86 : 132,
                        height: paperSize == ReceiptPaperSize.mm58 ? 46 : 70,
                        fit: BoxFit.contain,
                      ),
              const SizedBox(height: 4),
              Text(
                receipt.businessName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                receipt.branchName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (receipt.branchAddress != null)
                Text(
                  receipt.branchAddress!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted),
                ),
              if (receipt.branchPhone != null || receipt.branchEmail != null)
                Text(
                  [
                    receipt.branchPhone,
                    receipt.branchEmail,
                  ].whereType<String>().join(' · '),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted),
                ),
              if (receipt.taxRegistrationNumber != null)
                Text(
                  'Tax ID: ${receipt.taxRegistrationNumber}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted),
                ),
              const SizedBox(height: 16),
              const Divider(),
              _PreviewRow(label: 'Invoice', value: receipt.invoiceNumber),
              _PreviewRow(
                label: 'Date',
                value: DateFormat.yMMMd().add_jm().format(receipt.completedAt),
              ),
              _PreviewRow(label: 'Status', value: _label(receipt.status)),
              if (receipt.customerName != null)
                _PreviewRow(label: 'Customer', value: receipt.customerName!),
              if (receipt.customerPhone != null)
                _PreviewRow(
                  label: 'Customer phone',
                  value: receipt.customerPhone!,
                ),
              const Divider(),
              for (final item in receipt.items) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.productName,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              [
                                if (item.variantName != 'Default')
                                  item.variantName,
                                item.sku,
                                '${item.quantityText} × ${formatMoney(receipt.currencyCode, item.unitPriceMinor)}',
                                if (item.taxRate > 0) '${item.taxRate}% tax',
                              ].join(' · '),
                              style: TextStyle(color: muted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        formatMoney(receipt.currencyCode, item.lineTotalMinor),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
              ],
              const SizedBox(height: 8),
              _PreviewMoney(
                label: 'Subtotal',
                currencyCode: receipt.currencyCode,
                amountMinor: receipt.subtotalMinor,
              ),
              if (receipt.discountMinor > 0)
                _PreviewMoney(
                  label: 'Discount',
                  currencyCode: receipt.currencyCode,
                  amountMinor: -receipt.discountMinor,
                ),
              if (receipt.taxMinor > 0)
                _PreviewMoney(
                  label: 'Tax',
                  currencyCode: receipt.currencyCode,
                  amountMinor: receipt.taxMinor,
                ),
              if (receipt.serviceChargeMinor > 0)
                _PreviewMoney(
                  label: 'Service charge',
                  currencyCode: receipt.currencyCode,
                  amountMinor: receipt.serviceChargeMinor,
                ),
              if (receipt.roundingMinor != 0)
                _PreviewMoney(
                  label: 'Rounding',
                  currencyCode: receipt.currencyCode,
                  amountMinor: receipt.roundingMinor,
                ),
              const SizedBox(height: 6),
              _PreviewMoney(
                label: 'Total',
                currencyCode: receipt.currencyCode,
                amountMinor: receipt.grandTotalMinor,
                prominent: true,
              ),
              _PreviewMoney(
                label: 'Paid',
                currencyCode: receipt.currencyCode,
                amountMinor: receipt.paidTotalMinor,
              ),
              if (receipt.dueTotalMinor > 0)
                _PreviewMoney(
                  label: 'Due',
                  currencyCode: receipt.currencyCode,
                  amountMinor: receipt.dueTotalMinor,
                  prominent: true,
                ),
              const SizedBox(height: 14),
              Text('Payments', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              for (final payment in receipt.payments)
                _PreviewRow(
                  label: '${payment.methodLabel} (${_label(payment.status)})',
                  value: formatMoney(receipt.currencyCode, payment.amountMinor),
                ),
              if (receipt.notes != null) ...[
                const SizedBox(height: 12),
                Text('Note: ${receipt.notes}', style: TextStyle(color: muted)),
              ],
              if (receipt.receiptShowQr &&
                  receipt.receiptQrPayload != null) ...[
                const SizedBox(height: 12),
                Icon(
                  Icons.qr_code_2_rounded,
                  size: paperSize == ReceiptPaperSize.mm58 ? 64 : 84,
                ),
                Text(
                  receipt.receiptQrPayload!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, fontSize: 10),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                receipt.receiptFooter ?? 'Thank you for your business.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 4),
              Text(
                'Generated by FlexPOS',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Flexible(child: Text(value, textAlign: TextAlign.right)),
      ],
    ),
  );
}

class _PreviewMoney extends StatelessWidget {
  const _PreviewMoney({
    required this.label,
    required this.currencyCode,
    required this.amountMinor,
    this.prominent = false,
  });

  final String label;
  final String currencyCode;
  final int amountMinor;
  final bool prominent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: prominent ? Theme.of(context).textTheme.titleMedium : null,
          ),
        ),
        Text(
          formatMoney(currencyCode, amountMinor),
          style: prominent ? Theme.of(context).textTheme.titleMedium : null,
        ),
      ],
    ),
  );
}

String _label(String value) => value
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');
