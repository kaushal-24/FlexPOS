# Payment gateway adapters

FlexPOS keeps payment credentials and webhook verification on the server. The
Flutter client sends only the tender and the optional provider code; it never
receives a gateway secret.

## Implemented adapter

FlexPOS-2 now has a complete Razorpay Standard Checkout adapter. The
`razorpay-order` Edge Function creates a server-side Razorpay order with the
sale amount and tenant notes. The web client opens Razorpay Checkout with only
the public test key. The `razorpay-verify` Edge Function verifies the checkout
signature, re-reads the order and payment from Razorpay, and calls the
service-only `record_provider_payment_verification` RPC. The RPC performs the
final tenant, amount, currency, provider, and idempotency checks.

`supabase/functions/payment-webhook` remains the asynchronous reconciliation
adapter. It verifies Razorpay's raw webhook body with HMAC-SHA256 and accepts
all Razorpay payment methods returned by Standard Checkout (not only UPI).

The adapter requires the Razorpay payment entity to carry a
`notes.flexpos_payment_id` (or `notes.payment_id`) UUID. The order function
adds that note when it creates the provider order. Both
verification paths reject events that cannot be linked to a specific FlexPOS
payment.

## FlexPOS-2 setup

These steps are operator configuration, not source-controlled credentials:

1. Deploy `razorpay-order`, `razorpay-verify`, and `payment-webhook` to project
   `gpbsblokhpydtpgxpwrg`.
2. Add the Razorpay **test** credentials to the FlexPOS-2 Supabase Function
   secrets: `RAZORPAY_KEY_ID` (`rzp_test_...`) and `RAZORPAY_KEY_SECRET`.
3. Add `RAZORPAY_WEBHOOK_SECRET` when asynchronous webhook reconciliation is
   enabled, then configure the Razorpay webhook URL as
   `https://gpbsblokhpydtpgxpwrg.supabase.co/functions/v1/payment-webhook?provider=razorpay_upi`.
4. Subscribe to `payment.captured`, `payment.failed`, `payment.authorized`,
   `payment.pending`, and `order.paid` as required by the merchant checkout.
5. Send a signed test webhook and confirm a single row in
   `payment_verification_events`; replaying the same event must be idempotent.

Do not put the webhook secret, API key, or provider credentials in Flutter,
`config/dev.json`, migrations, or `integration_connections.config`.

The test checkout does not require a webhook to complete the immediate
signature verification, but the webhook remains recommended for delayed or
disputed payment reconciliation.

## Manual UPI QR mode (no webhook)

The POS checkout also supports a webhook-free manual UPI flow. It renders a
dynamic UPI QR for `kaushal.pithva@ptaxis`, including the sale amount and a
FlexPOS transaction reference. After the customer pays, the cashier selects
`Success` or `Failed`; the authenticated `confirm_upi_payment` RPC records the
result as a tenant-scoped, idempotent manual verification event. This mode does
not require `RAZORPAY_WEBHOOK_SECRET`, but the cashier must only choose
`Success` after confirming payment in the customer’s UPI app or bank record.
