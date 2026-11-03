# FlexPOS Supabase backend architecture

This document describes the backend boundary for **FlexPOS** (`flexpos-2`,
`gpbsblokhpydtpgxpwrg`, Sydney `ap-southeast-2`). The older `FlexPOS`
`ap-south-1` project is not part of this system.

## Tenant and authorization boundary

Every tenant-owned table carries `business_id` and has RLS enabled. Positive
policies call the private membership/permission helpers; mutations that span
multiple tables use authenticated, idempotent RPCs. Flutter receives only the
publishable Supabase key. Service-role keys, database passwords, provider
credentials, and webhook secrets stay outside the client.

The Flutter client resolves CRUD capabilities from the role's scoped permission
codes (`<resource>.view` for reads and `<resource>.manage` for backwards-
compatible full writes, with narrower create/update/delete grants supported).
Unauthorized controls are hidden or disabled, while RLS remains the final
enforcement boundary. Master data uses tenant-safe delete/deactivation mutations where
history is referenced by sales or purchasing records; workflow domains use
audited status transitions instead of destructive deletes.

Inventory balances keep `reorder_point` and `safety_stock` per warehouse and
variant. Stock quantities are never writable through the Data API. The
`set_inventory_threshold` security-definer RPC validates the authenticated
tenant, branch access, active stock-tracked variant, and `inventory.manage`
permission before changing only `reorder_point`; the audit event then feeds
the existing low-stock notifications, dashboard KPIs, reports, and reorder
suggestions.

Custom role deletion is exposed through `delete_role`, which is restricted to
roles.manage holders, rejects system roles and roles still assigned to any
membership, and records an audit event. Posted journals, sales, and inventory
ledgers remain lifecycle-controlled/immutable rather than hard-deleted.

## Immutable business records

`invoice_documents` stores an immutable sale snapshot (sale, items, payments,
totals, selected template, and presentation data). It is created through
`record_invoice_document`, is unique per business/sale, and can be read only
with `sales.view`. Returns and credit notes remain separate immutable records.

## Loyalty and promotions

Promotion definitions/redemptions and the append-only loyalty ledger are
tenant-scoped. `business_loyalty_settings` controls earn and redemption rates.
Paid or partially-paid completed sales automatically earn points exactly once
using the sale operation id. `redeem_customer_loyalty_points` is authenticated,
permission-gated, balance-safe, and idempotent.

## Storage and assets

The private `business-assets`, `product-images`, and `expense-attachments`
buckets have authenticated tenant policies for read/write paths. The public
Data API never receives a service-role storage credential; the app uses signed
URLs for private product and business assets.

## Realtime and large-data reads

RLS-protected `sales`, `payments`, `inventory_stock_alert_notifications`,
`invoice_documents`, `hardware_devices`, `enterprise_records`, and
`integration_connections` are in `supabase_realtime`. The client may subscribe
to tenant-safe changes. `list_sales_keyset` and `list_products_keyset` provide
bounded `(created_at, id)` cursor reads (1–100 rows) without offset drift; both
invoke a narrow authorization wrapper and remain invoker functions so table RLS
continues to apply.

## Trusted integrations

The `integration-health` Edge Function requires a JWT, validates provider and
status values, rejects credential-shaped JSON keys, accepts only opaque
`vault://`, `secret://`, or `kms://` references, and forwards the caller's JWT
to the audited `upsert_integration_connection` RPC. Provider secrets and
webhook verification belong in Supabase secrets or an external vault, never in
Flutter or a public table. FlexPOS-2 also deploys the concrete
`razorpay-order` and `razorpay-verify` Standard Checkout functions plus the
`payment-webhook` asynchronous adapter. Checkout signatures and webhook
payloads are verified server-side before idempotent
`record_provider_payment_verification` intake; `RAZORPAY_KEY_ID`,
`RAZORPAY_KEY_SECRET`, and (for webhooks) `RAZORPAY_WEBHOOK_SECRET` remain
operator-configured Function secrets.

## Operational verification

The live project has migration records through `loyalty_sale_rules`. The
backend architecture pgTAP suite covers invoice immutability, RLS, gift-card
reads, policy consolidation, realtime publication, and keyset privileges; the
loyalty suite covers automatic earn, idempotent ledger behavior, configured
rates, safe redemption, and overdraft rejection. Supabase advisors are run
after DDL. Remaining notices are intentionally authorized authenticated
security-definer RPCs, non-blocking unused/unindexed opportunities, and
platform-level leaked-password protection; the Auth leaked-password toggle
must be enabled by an operator in the Supabase Auth dashboard.
