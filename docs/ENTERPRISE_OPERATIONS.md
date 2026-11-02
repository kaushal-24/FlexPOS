# Enterprise operations

The Enterprise operations module provides tenant-scoped records for loyalty, staffing, attendance, commissions, register and branch dashboards, approvals, notifications, customer catalog publication, online order requests, subscriptions, SaaS administration, imports/exports, backups, labels, Gujarati translation work, business rules, forecasts, reorder suggestions, and integration status.

Every record is protected by Supabase RLS, business membership, branch access, the `enterprise_operations` entitlement, and the `enterprise.view` / `enterprise.manage` permissions. Status changes append an immutable event and a tenant audit entry.

## Integrations

`integration_connections` stores provider code, non-secret configuration, health status, and an opaque `secret_ref`. It intentionally does not store API keys, signing secrets, or access tokens. Delivery adapters and webhook handlers must resolve the reference in a server-side secret manager before making outbound calls.

Supported provider boundaries are SMS, WhatsApp, payment gateway, tax service, and AI. The UI exposes honest configuration and health states (`not_configured`, `configured`, `verifying`, `verified`, `disabled`, and `error`) so unconfigured adapters are visible instead of silently failing.

The payment-gateway boundary has a concrete FlexPOS-2 Razorpay adapter. The
`razorpay-order` and `razorpay-verify` Edge Functions create and verify
Standard Checkout payments, while `payment-webhook` resolves
`RAZORPAY_WEBHOOK_SECRET`, checks the provider signature on the raw body, and
records asynchronous settlement through the idempotent provider-verification
RPC. The gateway account and all secrets remain operator configuration.
