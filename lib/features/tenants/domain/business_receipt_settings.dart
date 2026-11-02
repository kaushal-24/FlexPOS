class BusinessReceiptSettings {
  const BusinessReceiptSettings({
    required this.businessId,
    required this.businessName,
    required this.taxRegistrationNumber,
    required this.invoicePrefix,
    required this.receiptFooter,
    required this.receiptTemplate,
    required this.receiptLogoPath,
    required this.receiptQrPayload,
    required this.receiptShowLogo,
    required this.receiptShowQr,
  });

  factory BusinessReceiptSettings.fromJson(Map<String, dynamic> json) {
    return BusinessReceiptSettings(
      businessId: json['id'] as String,
      businessName: json['name'] as String,
      taxRegistrationNumber: _optionalText(json['tax_registration_number']),
      invoicePrefix: json['invoice_prefix'] as String,
      receiptFooter: _optionalText(json['receipt_footer']),
      receiptTemplate: json['receipt_template'] as String? ?? 'classic',
      receiptLogoPath: _optionalText(json['receipt_logo_path']),
      receiptQrPayload: _optionalText(json['receipt_qr_payload']),
      receiptShowLogo: json['receipt_show_logo'] as bool? ?? true,
      receiptShowQr: json['receipt_show_qr'] as bool? ?? false,
    );
  }

  final String businessId;
  final String businessName;
  final String? taxRegistrationNumber;
  final String invoicePrefix;
  final String? receiptFooter;
  final String receiptTemplate;
  final String? receiptLogoPath;
  final String? receiptQrPayload;
  final bool receiptShowLogo;
  final bool receiptShowQr;
}

String? _optionalText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
