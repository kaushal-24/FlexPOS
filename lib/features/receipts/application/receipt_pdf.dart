import 'package:flexpos/features/receipts/domain/receipt_models.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const flexPosReceiptPageFormat = PdfPageFormat.roll80;
const flexPosReceipt58PageFormat = PdfPageFormat(
  58 * PdfPageFormat.mm,
  double.infinity,
  marginAll: 5 * PdfPageFormat.mm,
);

enum ReceiptPaperSize { mm58, mm80 }

extension ReceiptPaperSizeX on ReceiptPaperSize {
  PdfPageFormat get pageFormat => switch (this) {
    ReceiptPaperSize.mm58 => flexPosReceipt58PageFormat,
    ReceiptPaperSize.mm80 => PdfPageFormat.roll80,
  };

  String get label => switch (this) {
    ReceiptPaperSize.mm58 => '58 mm',
    ReceiptPaperSize.mm80 => '80 mm',
  };
}

Future<Uint8List> buildReceiptPdf(
  ReceiptDocument receipt, [
  PdfPageFormat pageFormat = flexPosReceiptPageFormat,
]) async {
  final document = pw.Document(
    title: receipt.invoiceNumber,
    author: 'FlexPOS',
    subject: 'Sales receipt',
  );
  final compact = pageFormat.width < PdfPageFormat.a5.width;
  final narrow = pageFormat.width <= flexPosReceipt58PageFormat.width;
  final minimal = receipt.receiptTemplate == 'minimal';
  final margin = compact ? 12.0 : 32.0;
  final baseStyle = pw.TextStyle(fontSize: compact ? 8 : 10);
  final smallStyle = pw.TextStyle(
    fontSize: compact ? 7 : 8,
    color: PdfColors.grey700,
  );
  final logo = receipt.logoBytes == null
      ? await _loadFlexPosLogo()
      : pw.MemoryImage(receipt.logoBytes!);

  final content = <pw.Widget>[
    pw.Center(
      child: pw.Column(
        children: [
          if (receipt.receiptShowLogo && logo != null) ...[
            pw.Image(
              logo,
              width: compact ? 86 : 132,
              height: compact ? 46 : 70,
              fit: pw.BoxFit.contain,
            ),
            pw.SizedBox(height: 4),
          ],
          pw.Text(
            receipt.businessName,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: compact ? 14 : 20,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            receipt.branchName,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          if (!minimal && receipt.branchAddress != null)
            pw.Text(
              receipt.branchAddress!,
              textAlign: pw.TextAlign.center,
              style: smallStyle,
            ),
          if (!minimal &&
              (receipt.branchPhone != null || receipt.branchEmail != null))
            pw.Text(
              [
                receipt.branchPhone,
                receipt.branchEmail,
              ].whereType<String>().join(' | '),
              textAlign: pw.TextAlign.center,
              style: smallStyle,
            ),
          if (!minimal && receipt.taxRegistrationNumber != null)
            pw.Text(
              'Tax ID: ${receipt.taxRegistrationNumber}',
              style: smallStyle,
            ),
        ],
      ),
    ),
    pw.SizedBox(height: 10),
    pw.Divider(),
    _labelValue('Invoice', receipt.invoiceNumber, bold: true),
    _labelValue(
      'Date',
      DateFormat('dd MMM yyyy, hh:mm a').format(receipt.completedAt),
    ),
    _labelValue('Status', _statusLabel(receipt.status)),
    if (!minimal && receipt.customerName != null)
      _labelValue('Customer', receipt.customerName!),
    if (!minimal && receipt.customerPhone != null)
      _labelValue('Customer phone', receipt.customerPhone!),
    if (!minimal && receipt.customerTaxNumber != null)
      _labelValue('Customer tax ID', receipt.customerTaxNumber!),
    pw.Divider(),
    _itemsTable(receipt, compact, narrow: narrow),
    pw.Divider(),
    _moneyRow('Subtotal', receipt, receipt.subtotalMinor),
    if (receipt.discountMinor > 0)
      _moneyRow('Discount', receipt, -receipt.discountMinor),
    if (receipt.taxMinor > 0) _moneyRow('Tax', receipt, receipt.taxMinor),
    if (receipt.serviceChargeMinor > 0)
      _moneyRow('Service charge', receipt, receipt.serviceChargeMinor),
    if (receipt.roundingMinor != 0)
      _moneyRow('Rounding', receipt, receipt.roundingMinor),
    pw.SizedBox(height: 3),
    _moneyRow(
      'TOTAL',
      receipt,
      receipt.grandTotalMinor,
      bold: true,
      fontSize: compact ? 11 : 14,
    ),
    _moneyRow('Paid', receipt, receipt.paidTotalMinor),
    if (receipt.dueTotalMinor > 0)
      _moneyRow('Due', receipt, receipt.dueTotalMinor, bold: true),
    pw.SizedBox(height: 8),
    pw.Text('Payments', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
    pw.SizedBox(height: 3),
    for (final payment in receipt.payments)
      _labelValue(
        '${payment.methodLabel} (${_statusLabel(payment.status)})',
        _money(receipt.currencyCode, payment.amountMinor),
      ),
    if (!minimal && receipt.notes != null) ...[
      pw.SizedBox(height: 8),
      pw.Text('Note: ${receipt.notes}', style: smallStyle),
    ],
    if (receipt.receiptShowQr && receipt.receiptQrPayload != null) ...[
      pw.SizedBox(height: 8),
      pw.Center(
        child: pw.BarcodeWidget(
          data: receipt.receiptQrPayload!,
          barcode: pw.Barcode.qrCode(),
          width: compact ? 84 : 112,
          height: compact ? 84 : 112,
          drawText: false,
        ),
      ),
      pw.SizedBox(height: 4),
    ],
    pw.SizedBox(height: 12),
    pw.Center(
      child: pw.Text(
        receipt.receiptFooter ?? 'Thank you for your business.',
        textAlign: pw.TextAlign.center,
        style: smallStyle,
      ),
    ),
    pw.SizedBox(height: 4),
    pw.Center(child: pw.Text('Generated by FlexPOS', style: smallStyle)),
  ];

  final pageMargin = pw.EdgeInsets.all(margin);
  final pageTheme = pw.ThemeData(defaultTextStyle: baseStyle);
  if (pageFormat.height == double.infinity) {
    document.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: pageMargin,
        theme: pageTheme,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: content,
        ),
      ),
    );
  } else {
    document.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: pageMargin,
        theme: pageTheme,
        build: (_) => content,
      ),
    );
  }

  return document.save();
}

Future<pw.MemoryImage?> _loadFlexPosLogo() async {
  try {
    final bytes = await rootBundle.load('assets/branding/flexpos_logo.png');
    return pw.MemoryImage(bytes.buffer.asUint8List());
  } catch (_) {
    // Keep receipt generation resilient if an embedding omits optional assets.
    return null;
  }
}

pw.Widget _itemsTable(
  ReceiptDocument receipt,
  bool compact, {
  required bool narrow,
}) {
  final headerStyle = pw.TextStyle(
    fontSize: compact ? 7 : 9,
    fontWeight: pw.FontWeight.bold,
  );
  final cellStyle = pw.TextStyle(fontSize: compact ? 7 : 9);
  pw.Widget cell(String text, {pw.TextAlign align = pw.TextAlign.left}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 2),
        child: pw.Text(text, textAlign: align, style: cellStyle),
      );

  if (narrow) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        for (final item in receipt.items) ...[
          pw.Text(
            item.productName,
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            [
              if (item.variantName != 'Default') item.variantName,
              item.sku,
              if (item.taxRate > 0) '${item.taxRate}% tax',
            ].join(' | '),
            style: cellStyle,
          ),
          pw.SizedBox(height: 2),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  '${item.quantityText} x ${_money(receipt.currencyCode, item.unitPriceMinor)}',
                  style: cellStyle,
                ),
              ),
              pw.Text(
                _money(receipt.currencyCode, item.lineTotalMinor),
                style: pw.TextStyle(
                  fontSize: 7,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.Divider(color: PdfColors.grey300, thickness: 0.5),
        ],
      ],
    );
  }

  return pw.Table(
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
    ),
    columnWidths: const {
      0: pw.FlexColumnWidth(3.5),
      1: pw.FlexColumnWidth(1),
      2: pw.FlexColumnWidth(1.5),
      3: pw.FlexColumnWidth(1.5),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.all(2),
            child: pw.Text('Item', style: headerStyle),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(2),
            child: pw.Text(
              'Qty',
              textAlign: pw.TextAlign.right,
              style: headerStyle,
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(2),
            child: pw.Text(
              'Price',
              textAlign: pw.TextAlign.right,
              style: headerStyle,
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(2),
            child: pw.Text(
              'Total',
              textAlign: pw.TextAlign.right,
              style: headerStyle,
            ),
          ),
        ],
      ),
      for (final item in receipt.items)
        pw.TableRow(
          children: [
            cell(
              [
                item.productName,
                if (item.variantName != 'Default') item.variantName,
                item.sku,
                if (item.taxRate > 0) '${item.taxRate}% tax',
              ].join('\n'),
            ),
            cell(item.quantityText, align: pw.TextAlign.right),
            cell(
              _money(receipt.currencyCode, item.unitPriceMinor),
              align: pw.TextAlign.right,
            ),
            cell(
              _money(receipt.currencyCode, item.lineTotalMinor),
              align: pw.TextAlign.right,
            ),
          ],
        ),
    ],
  );
}

pw.Widget _labelValue(String label, String value, {bool bold = false}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: pw.Text(label)),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null,
            ),
          ),
        ],
      ),
    );

pw.Widget _moneyRow(
  String label,
  ReceiptDocument receipt,
  int amountMinor, {
  bool bold = false,
  double? fontSize,
}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
  child: pw.Row(
    children: [
      pw.Expanded(
        child: pw.Text(
          label,
          style: pw.TextStyle(
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            fontSize: fontSize,
          ),
        ),
      ),
      pw.Text(
        _money(receipt.currencyCode, amountMinor),
        textAlign: pw.TextAlign.right,
        style: pw.TextStyle(
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontSize: fontSize,
        ),
      ),
    ],
  ),
);

String _money(String currencyCode, int minor) {
  final sign = minor < 0 ? '-' : '';
  return '$sign$currencyCode ${(minor.abs() / 100).toStringAsFixed(2)}';
}

String _statusLabel(String status) => status
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');
