/// Provider identifiers understood by the server-side payment adapters.
///
/// Secrets and credentials are intentionally not represented here. They live
/// in Supabase Edge Function secrets and are never shipped to Flutter.
enum PaymentGatewayProvider {
  razorpayUpi('razorpay_upi');

  const PaymentGatewayProvider(this.code);

  final String code;
}

/// Returns the provider used for an electronic payment method when the
/// cashier has not supplied an explicit provider.
///
/// Cash, credit-note, gift-card, and customer-credit payments are internal
/// tenders and must not be sent through a gateway adapter. Razorpay remains
/// persisted as the existing UPI tender category, while its provider value
/// records the concrete Razorpay Checkout adapter.
String? providerCodeForPaymentMethod(String method) {
  final normalized = method.trim().toLowerCase();
  if (normalized == 'razorpay') return PaymentGatewayProvider.razorpayUpi.code;
  if (normalized == 'upi') return 'upi_manual';
  return null;
}

/// Maps a POS-facing tender to the server payment method understood by the
/// current database adapter. Razorpay checkout settles through the same UPI
/// payment record, while retaining the Razorpay provider code for auditing.
String backendPaymentMethodForPos(String method) {
  return method.trim().toLowerCase() == 'razorpay' ? 'upi' : method;
}
