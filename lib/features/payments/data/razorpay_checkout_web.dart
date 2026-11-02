import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

export 'razorpay_checkout_stub.dart';
import 'razorpay_checkout_stub.dart';

JSAny? _readProperty(JSAny? object, String key) {
  if (object is! JSObject) return null;
  return object.getProperty(key.toJS);
}

String? _readString(JSAny? object, String key) {
  final value = _readProperty(object, key);
  if (value == null || !value.isA<JSString>()) return null;
  final text = (value as JSString).toDart.trim();
  return text.isEmpty ? null : text;
}

Future<RazorpayCheckoutResult> openRazorpayCheckout(
  RazorpayCheckoutRequest request,
) async {
  final constructor = globalContext['Razorpay'];
  if (constructor == null || !constructor.isA<JSFunction>()) {
    return const RazorpayCheckoutResult(
      status: 'unavailable',
      errorMessage: 'Razorpay Checkout did not load. Check your internet connection and restart the web app.',
    );
  }

  final completer = Completer<RazorpayCheckoutResult>();
  void complete(RazorpayCheckoutResult result) {
    if (!completer.isCompleted) completer.complete(result);
  }

  final prefill = <String, Object?>{};
  if (request.customerEmail != null &&
      request.customerEmail!.trim().isNotEmpty) {
    prefill['email'] = request.customerEmail!.trim();
  }

  final options =
      <String, Object?>{
            'key': request.keyId,
            'amount': request.amountPaise,
            'currency': request.currencyCode,
            'name': 'FlexPOS',
            'description': request.description,
            'order_id': request.orderId,
            if (prefill.isNotEmpty) 'prefill': prefill,
            'theme': {'color': '#5E9BFF'},
            'modal': {
              'ondismiss': (() {
                complete(const RazorpayCheckoutResult(status: 'cancelled'));
              }).toJS,
            },
            'handler': ((JSAny? response) {
              final paymentId = _readString(response, 'razorpay_payment_id');
              final orderId = _readString(response, 'razorpay_order_id');
              final signature = _readString(response, 'razorpay_signature');
              if (paymentId == null || orderId == null || signature == null) {
                complete(
                  const RazorpayCheckoutResult(
                    status: 'failed',
                    errorMessage:
                        'Razorpay returned an incomplete payment response.',
                  ),
                );
                return;
              }
              complete(
                RazorpayCheckoutResult(
                  status: 'success',
                  paymentId: paymentId,
                  orderId: orderId,
                  signature: signature,
                ),
              );
            }).toJS,
          }.jsify()!
          as JSObject;

  try {
    final instance = (constructor as JSFunction).callAsConstructor<JSObject>(
      options,
    );
    instance.callMethodVarArgs('on'.toJS, [
      'payment.failed'.toJS,
      ((JSAny? response) {
        final error = _readProperty(response, 'error');
        final description =
            _readString(error, 'description') ??
            _readString(response, 'description');
        complete(
          RazorpayCheckoutResult(
            status: 'failed',
            errorMessage:
                description ??
                _readString(error, 'reason') ??
                'Razorpay payment failed.',
          ),
        );
      }).toJS,
    ]);
    instance.callMethodVarArgs('open'.toJS);
  } catch (error) {
    complete(
      RazorpayCheckoutResult(
        status: 'failed',
        errorMessage: 'Could not open Razorpay Checkout: $error',
      ),
    );
  }

  return completer.future;
}
