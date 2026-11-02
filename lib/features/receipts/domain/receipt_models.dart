import 'dart:typed_data';

class ReceiptDocument {
  const ReceiptDocument({
    required this.saleId,
    required this.businessName,
    required this.branchName,
    required this.invoiceNumber,
    required this.completedAt,
    required this.currencyCode,
    required this.status,
    required this.paymentStatus,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.taxMinor,
    required this.serviceChargeMinor,
    required this.roundingMinor,
    required this.grandTotalMinor,
    required this.paidTotalMinor,
    required this.dueTotalMinor,
    required this.items,
    required this.payments,
    this.taxRegistrationNumber,
    this.receiptFooter,
    this.branchPhone,
    this.branchEmail,
    this.branchAddress,
    this.customerName,
    this.customerPhone,
    this.customerTaxNumber,
    this.notes,
    this.receiptTemplate = 'classic',
    this.receiptQrPayload,
    this.receiptShowLogo = true,
    this.receiptShowQr = false,
    this.receiptPaperWidth = '80',
    this.logoBytes,
  });

  factory ReceiptDocument.fromRows({
    required Map<String, dynamic> sale,
    required Map<String, dynamic> business,
    required Map<String, dynamic> branch,
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> payments,
    Map<String, dynamic>? customer,
    Uint8List? logoBytes,
  }) {
    return ReceiptDocument(
      saleId: sale['id'] as String,
      businessName: business['name'] as String,
      taxRegistrationNumber: _optionalText(business['tax_registration_number']),
      receiptFooter: _optionalText(business['receipt_footer']),
      branchName: branch['name'] as String,
      branchPhone: _optionalText(branch['phone']),
      branchEmail: _optionalText(branch['email']),
      branchAddress: _joinAddress(branch),
      invoiceNumber: sale['invoice_number'] as String,
      completedAt: DateTime.parse(sale['completed_at'] as String).toLocal(),
      currencyCode: sale['currency_code'] as String,
      status: sale['status'] as String,
      paymentStatus: sale['payment_status'] as String,
      customerName: _optionalText(customer?['name']),
      customerPhone: _optionalText(customer?['phone']),
      customerTaxNumber: _optionalText(customer?['gstin']),
      subtotalMinor: _minorUnits(sale['subtotal']),
      discountMinor: _minorUnits(sale['discount_total']),
      taxMinor: _minorUnits(sale['tax_total']),
      serviceChargeMinor: _minorUnits(sale['service_charge_total']),
      roundingMinor: _minorUnits(sale['rounding_amount']),
      grandTotalMinor: _minorUnits(sale['grand_total']),
      paidTotalMinor: _minorUnits(sale['paid_total']),
      dueTotalMinor: _minorUnits(sale['due_total']),
      notes: _optionalText(sale['notes']),
      receiptTemplate: business['receipt_template'] as String? ?? 'classic',
      receiptQrPayload: _optionalText(business['receipt_qr_payload']),
      receiptShowLogo: business['receipt_show_logo'] as bool? ?? true,
      receiptShowQr: business['receipt_show_qr'] as bool? ?? false,
      receiptPaperWidth: business['receipt_paper_width'] as String? ?? '80',
      logoBytes: logoBytes,
      items: items.map(ReceiptLine.fromJson).toList(growable: false),
      payments: payments.map(ReceiptPayment.fromJson).toList(growable: false),
    );
  }

  final String saleId;
  final String businessName;
  final String? taxRegistrationNumber;
  final String? receiptFooter;
  final String branchName;
  final String? branchPhone;
  final String? branchEmail;
  final String? branchAddress;
  final String invoiceNumber;
  final DateTime completedAt;
  final String currencyCode;
  final String status;
  final String paymentStatus;
  final String? customerName;
  final String? customerPhone;
  final String? customerTaxNumber;
  final int subtotalMinor;
  final int discountMinor;
  final int taxMinor;
  final int serviceChargeMinor;
  final int roundingMinor;
  final int grandTotalMinor;
  final int paidTotalMinor;
  final int dueTotalMinor;
  final String? notes;
  final String receiptTemplate;
  final String? receiptQrPayload;
  final bool receiptShowLogo;
  final bool receiptShowQr;
  final String receiptPaperWidth;
  final Uint8List? logoBytes;
  final List<ReceiptLine> items;
  final List<ReceiptPayment> payments;

  String get fileName {
    final safeInvoice = invoiceNumber.replaceAll(
      RegExp(r'[^A-Za-z0-9_-]'),
      '_',
    );
    return 'FlexPOS-$safeInvoice.pdf';
  }
}

class ReceiptLine {
  const ReceiptLine({
    required this.productName,
    required this.variantName,
    required this.sku,
    required this.quantity,
    required this.unitPriceMinor,
    required this.discountMinor,
    required this.taxRate,
    required this.taxMinor,
    required this.lineTotalMinor,
    this.note,
  });

  factory ReceiptLine.fromJson(Map<String, dynamic> json) => ReceiptLine(
    productName: json['product_name'] as String,
    variantName: json['variant_name'] as String,
    sku: json['sku'] as String,
    quantity: _decimal(json['quantity']),
    unitPriceMinor: _minorUnits(json['unit_price']),
    discountMinor: _minorUnits(json['discount_amount']),
    taxRate: _decimal(json['tax_rate']),
    taxMinor: _minorUnits(json['tax_amount']),
    lineTotalMinor: _minorUnits(json['line_total']),
    note: _optionalText(json['note']),
  );

  final String productName;
  final String variantName;
  final String sku;
  final double quantity;
  final int unitPriceMinor;
  final int discountMinor;
  final double taxRate;
  final int taxMinor;
  final int lineTotalMinor;
  final String? note;

  String get quantityText => quantity == quantity.truncateToDouble()
      ? quantity.toInt().toString()
      : quantity.toStringAsFixed(6).replaceFirst(RegExp(r'0+$'), '');
}

class ReceiptPayment {
  const ReceiptPayment({
    required this.method,
    required this.status,
    required this.amountMinor,
    this.reference,
    this.provider,
  });

  factory ReceiptPayment.fromJson(Map<String, dynamic> json) => ReceiptPayment(
    method: json['payment_method'] as String,
    status: json['status'] as String,
    amountMinor: _minorUnits(json['amount']),
    reference: _optionalText(json['reference']),
    provider: _optionalText(json['provider']),
  );

  final String method;
  final String status;
  final int amountMinor;
  final String? reference;
  final String? provider;

  String get methodLabel => provider == 'razorpay_upi'
      ? 'Razorpay'
      : method
            .split('_')
            .where((part) => part.isNotEmpty)
            .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
            .join(' ');
}

String? _optionalText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

String? _joinAddress(Map<String, dynamic> branch) {
  final parts = [
    branch['address_line_1'],
    branch['address_line_2'],
    branch['city'],
    branch['state_region'],
    branch['postal_code'],
    branch['country_code'],
  ].map(_optionalText).whereType<String>().toList(growable: false);
  return parts.isEmpty ? null : parts.join(', ');
}

int _minorUnits(Object? value) {
  final amount = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
  return (amount * 100).round();
}

double _decimal(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;
