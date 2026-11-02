class RazorpayCheckoutRequest {
  const RazorpayCheckoutRequest({
    required this.keyId,
    required this.orderId,
    required this.amountPaise,
    required this.currencyCode,
    required this.description,
    required this.customerEmail,
  });

  final String keyId;
  final String orderId;
  final int amountPaise;
  final String currencyCode;
  final String description;
  final String? customerEmail;
}

class RazorpayCheckoutResult {
  const RazorpayCheckoutResult({
    required this.status,
    this.paymentId,
    this.orderId,
    this.signature,
    this.errorMessage,
  });

  final String status;
  final String? paymentId;
  final String? orderId;
  final String? signature;
  final String? errorMessage;

  bool get isSuccess =>
      status == 'success' &&
      paymentId != null &&
      orderId != null &&
      signature != null;
}

Future<RazorpayCheckoutResult> openRazorpayCheckout(
  RazorpayCheckoutRequest request,
) async {
  return const RazorpayCheckoutResult(
    status: 'unavailable',
    errorMessage: 'Razorpay checkout is available on the web build only.',
  );
}
