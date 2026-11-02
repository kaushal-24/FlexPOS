# FlexPOS

FlexPOS is a production-oriented, multi-tenant point-of-sale and business
management application built with Flutter, Riverpod, GoRouter, PostgreSQL, and
Supabase. The current vertical slice supports secure business setup, catalog
and inventory operations, atomic POS checkout, and sales history.

## Implemented

- Material 3 responsive shell for mobile, tablet, desktop, and web
- Shared spacing, typography, radius, color, elevation, control-size, and motion
  tokens consumed by the light/dark themes and common components
- Restrained route and POS transitions with shared motion tokens and automatic
  reduced-motion support
- Responsive skeleton loading across data-heavy pages and detail dialogs, with
  accessible loading announcements and reduced-motion handling
- WCAG AA-checked core palettes, semantic status/loading labels, labeled icon
  controls, padded 48px touch targets, and verified 200% text scaling
- Light, dark, and system themes with persisted preference
- Email/password authentication, verification, and password recovery
- Multi-business onboarding and persisted workspace switching
- Branches, memberships, roles, permissions, invitations, and audit records
- Strict tenant RLS and permission-gated administration
- Products, variants, barcodes, prices, units, categories, brands, and tax rates
- Catalog tools for private product images, custom attributes, unit conversions,
  bundles/kits, CSV import/export, and permission-gated bulk edits
- Warehouses, stock balances, and immutable inventory movement records
- Permission-gated product creation and stock adjustment
- Searchable POS with horizontally scrollable category and Favorites tabs,
  manager-controlled favorite products, one-tap sale cards, and
  warehouse-aware stock enforcement
- Keyboard-wedge barcode scanning with exact-match add-to-cart, Enter handling,
  persistent scanner focus, and an F2 refocus shortcut
- Camera barcode/QR scanning from the POS search field on supported Android,
  iOS, macOS, and HTTPS web deployments, with manual scanning fallback
- HID/keyboard-wedge scanner setup over USB or Bluetooth, including F2 focus,
  Enter-suffix guidance, and exact-match safeguards
- Discoverable desktop POS shortcuts for help, held sales, cash/UPI/card/split
  tender selection, parking, drafts, checkout, and guarded cancellation
- Persistent held sales with park, resume, update, and discard controls;
  holding a cart never reserves or moves stock
- Persistent editable sales drafts with save, reopen, update, delete, and
  automatic cleanup after successful checkout
- Non-posting quotations with title and validity, exact price/tax snapshots,
  reopen/update/cancel controls, and conversion linkage after checkout
- Stock-reserving sales orders with requested delivery dates, exact item and
  total snapshots, reopen/update/cancel controls, and atomic fulfillment
- Confirmed current-sale cancellation that resets unsaved cart state while
  preserving the original held sale, draft, quotation, or order when opened
- Integer minor-unit calculations in Flutter and authoritative server totals
- Atomic, idempotent checkout with stable stock locking
- Cash settlement and explicit pending state for external payment methods
- Permission-gated order-history reconciliation for pending UPI, card, bank
  transfer, and wallet payments, backed by immutable verification events and a
  separate service-role-only provider intake contract
- Server-filtered order history with invoice search, payment/refund status,
  inclusive date ranges, totals, dates, and payment status
- Customer profiles with contact, tax, and credit-limit data
- Customer selection during POS checkout
- Refund-aware customer purchase history with invoice totals, item counts,
  payment status, net spend, and persisted receipt drill-down
- Supplier profiles, multi-line purchase orders, requisitions, approvals,
  supplier invoices, landed-cost allocation, supplier returns, payment
  tracking, and payable statements
- Partial/final goods receipts with idempotent stock updates and average cost
- Batch/lot and manufactured/expiry capture on non-serialized goods receipts,
  with an inventory-batch registry and immutable purchase movement ledger
- Expense entry with immutable, auditable reversal records
- Accounting workspace with tenant-scoped chart of accounts, balanced manual
  journal entries, cash/bank records, recurring expenses, approval events,
  private receipt attachments, explicit AR/AP/customer-receipt-to-GL posting,
  bank reconciliation, tax credit/debit notes, international VAT/sales-tax
  profiles, GST place-of-supply/CGST/SGST/IGST breakdowns, tax-invoice detail,
  GST summaries, and posted-entry financial statements with net profit
- Customer credit statements, credit-limit enforcement, and FIFO repayments
- Database-aggregated sales, tax, expense, profit, payment, and stock reports
- Permission-gated partial/full sale returns with stock restoration and
  immutable, idempotent cash refunds
- Atomic exchanges that link the original sale, return, and replacement sale;
  reconcile the exact cash difference; and update inventory in one transaction
- Immutable credit notes issued from atomic returns and redeemable as settled
  POS tender with partial-balance, expiry, customer, and concurrency controls
- Hashed bearer gift cards with permission-gated issuance, optional customer
  binding, expiry and balance lookup, immutable value ledger, and atomic POS
  redemption
- Wallet checkout and exact split tender across cash, UPI, card, bank transfer,
  wallet, and customer credit, with cash-change calculation
- Partial checkout with cash or an external tender paid now and the exact
  remainder posted to the selected customer's credit statement
- Permission-gated fixed and percentage order discounts with exact integer
  minor-unit totals and server-side authorization
- Customer-group wholesale pricing with product-level overrides and automatic
  POS price selection for the selected customer's group
- Customer-specific product pricing with direct overrides that take precedence
  over customer-group pricing in POS
- Coupon and promotion management with fixed/percentage discounts, minimum
  subtotals, usage limits, POS preview, and atomic redemption at checkout
- Permission-gated per-line POS price overrides with server-side catalog-price
  validation for non-overridden lines
- Per-line POS item notes with trimmed 240-character input, edit/clear controls,
  and persistence into authoritative sale-item records at checkout
- Persisted-data receipt preview with A4 and selectable 58 mm/80 mm PDF
  layouts, adaptive print layout, dedicated PDF save/download, system
  printing/sharing, order-history reprinting, and business-configured invoice
  prefix, tax ID, and footer
- Register creation, cashier shift opening/closing, blind cash counts, exact
  over/short reconciliation, cash in/out, X/Z reports, and POS sales linked to
  the selected open shift
- Tenant-scoped audit-log viewer with permission-gated search, refresh, actor,
  target, timestamp, and structured-detail display

The live `flexpos-2` database has 112 public tables with RLS enabled, no
anonymous data access to operational RPCs, authenticated
permission-checked operational RPCs, with critical foreign-key indexes present
for implemented transactional paths. Supabase advisors still report broader
index-usage opportunities that are not release blockers. The
61-case catalog/inventory/POS/register/exchange/payment, 17-case
accounting/reporting, 21-case sale-returns, 35-case credit-note, 8-case
sales-discount, 23-case held-cart, 23-case sales-draft, 27-case quotation,
40-case sales-order, 41-case gift-card transaction, and 44-case payment
verification suites pass; all test data is rolled back.

## Architecture

```text
lib/
  app/             Configuration, routing, and themes
  core/            Shared providers, utilities, and widgets
  features/
    accounting/     Expenses, customer credit, AR/AP GL bridge, tax,
                    repayments, reconciliation, and reports
    auth/           Supabase authentication
    tenants/        Businesses, branches, roles, and staff access
    catalog/        Product models, data access, and product management
    inventory/      Stock balances and adjustments
    pos/            Stock-aware cart and checkout
    orders/         Sales history, returns, exchanges, and reprinting
    receipts/       Receipt reconstruction, preview, PDF, print, and share
    registers/      Registers, shifts, drawer movements, and X/Z reports
    customers/      Customer master data and POS selection
    promotions/     Coupon and promotion management
    purchasing/     Suppliers, purchase orders, and goods receipts
    dashboard/      Tenant-aware operational overview
  shared/layout/    Responsive application shell
```

Business rules affecting stock, money, or authorization are enforced through
tenant-scoped constraints, RLS, and transaction-safe PostgreSQL functions.

## Supabase project

This repository targets only the new project:

- Name: `flexpos-2`
- Project ref: `gpbsblokhpydtpgxpwrg`
- URL: `https://gpbsblokhpydtpgxpwrg.supabase.co`
- Region: `ap-southeast-2` (Sydney)

The pre-existing `FlexPOS` project in `ap-south-1` is not used or modified.
Only a browser-safe publishable key belongs in the Flutter client. Never add a
service-role key or database password to this repository.

## Configuration

Copy the example and provide the publishable key:

```powershell
Copy-Item config/dev.example.json config/dev.json
```

```json
{
  "APP_NAME": "FlexPOS",
  "SUPABASE_URL": "https://gpbsblokhpydtpgxpwrg.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_your_key"
}
```

## Run and verify

```powershell
flutter pub get
flutter gen-l10n
flutter analyze
flutter test
flutter run --dart-define-from-file=config/dev.json
```

Build web:

```powershell
flutter build web --dart-define-from-file=config/dev.json
```

## Database migrations and tests

Migrations are in `supabase/migrations`. Backend pgTAP coverage includes:

- `supabase/tests/tenant_rls_test.sql`
- `supabase/tests/phase2_access_admin_test.sql`
- `supabase/tests/catalog_inventory_pos_test.sql`
- `supabase/tests/customers_purchasing_test.sql`
- `supabase/tests/accounting_reports_test.sql`
- `supabase/tests/sales_returns_test.sql`
- `supabase/tests/credit_notes_test.sql`
- `supabase/tests/sales_discounts_test.sql`
- `supabase/tests/held_pos_carts_test.sql`
- `supabase/tests/pos_drafts_test.sql`
- `supabase/tests/sales_quotations_test.sql`
- `supabase/tests/sales_orders_test.sql`
- `supabase/tests/gift_cards_test.sql`
- `supabase/tests/payment_verification_test.sql`

The suites cover onboarding, permissions, negative cross-tenant access,
operational defaults, product creation, idempotent stock adjustments,
negative-stock rejection, checkout, stock deduction, immutable ledgers, and
tenant isolation. Purchasing coverage adds partial receipts, over-receipt
rejection, receipt idempotency, and stock increases. The suites are
transactional and roll back their test data.

The discount suite verifies authorized fixed discounts, exact persisted
subtotal/tax/discount/grand-total values, and rejection when a staff role lacks
`sales.discount`.

`20261020110000_flexpos_sales_returns.sql` is live on `flexpos-2`. It adds
append-only return documents, refund records, atomic stock restoration,
settled-cash refund caps, idempotency, RLS, and return-aware net reporting.

`20261020203000_atomic_sale_exchanges.sql` is live only on `flexpos-2`. It adds
immutable exchange links and an authenticated, permission-checked transaction
that performs the return, replacement sale, inventory changes, and exact cash
difference atomically. The expanded 61-case catalog/inventory/POS/register
suite passes live and rolls back every fixture.

`20261022140000_mark_mixed_tender_partially_paid.sql` is live only on
`flexpos-2`. It classifies mixed tender with settled cash and an outstanding
balance as `partially_paid`; partial checkout records the remainder through the
existing customer-credit ledger and credit-limit enforcement.

`20261022150000_held_pos_carts.sql` and its branch-index follow-up are live
only on `flexpos-2`. They add RLS-protected persistent held carts plus
authenticated park/update/discard RPCs. Held carts do not reserve or move
inventory; checkout performs the current stock and price validation. The
23-case live suite passes and rolls back every fixture.

`20261022160000_pos_draft_sales.sql` is live only on `flexpos-2`. It adds
RLS-protected editable sales drafts plus authenticated save/update/delete RPCs.
Drafts do not create sales, reserve stock, or move inventory; checkout uses the
current products, prices, and stock. The 23-case live suite passes and rolls
back every fixture.

`20261022170000_sales_quotations.sql` is live only on `flexpos-2`. It adds
RLS-protected quotation headers and item snapshots plus authenticated,
permission-checked save/update, cancel, and conversion RPCs. Quotations never
reserve stock, move inventory, or create payments; checkout uses current
products, prices, and stock before linking the completed sale. The 27-case
live suite passes and rolls back every fixture.

`20261022180000_sales_orders.sql` is live only on `flexpos-2`. It adds
RLS-protected sales-order headers and item snapshots plus authenticated,
permission-checked save/update, cancel, and fulfillment RPCs. Open orders
reserve stock without creating inventory movements; edits replace the
reservation, cancellation releases it, and fulfillment atomically releases it
while completing and linking the authoritative sale. The 40-case live suite
passes and rolls back every fixture.

`20261023100000_gift_cards.sql` is live only on `flexpos-2`. It stores only
SHA-256 hashes of bearer card numbers, adds permission-gated issuance and
masked balance lookup, and records every issue/redemption in an immutable value
ledger. Redemption locks the card, enforces balance, currency, expiry, and
optional customer binding, and settles the payment and sale atomically. The
41-case live suite passes and rolls back every fixture.

`20261023110000_payment_verification.sql` is live only on `flexpos-2`. It adds
an immutable RLS-scoped verification-event history, a permission-gated manual
reconciliation RPC, and an idempotent service-role-only provider intake RPC.
Provider reports must match the recorded amount and currency before settlement;
sale paid/due totals refresh atomically. The 44-case live suite passes and rolls
back every fixture. Concrete gateway webhook/signature adapters remain open
until a provider and credentials are selected.

`20261022120000_credit_notes.sql` and its parameter-resolution and index
follow-ups are live only on `flexpos-2`. They add atomic credit-note issuance
from returns, immutable redemption ledgers, partial-balance enforcement,
expiry and customer binding, and settled POS redemption. The 35-case live
suite passes and rolls back every fixture.

The accounting migration is
`supabase/migrations/20261020093000_flexpos_accounting_reports.sql`. It and its
role-seed, privilege-hardening, and foreign-key-index follow-ups were applied
to project `gpbsblokhpydtpgxpwrg` on 2026-10-20. They add no anonymous data
access and must never be run against the old `ap-south-1` project.

`20261028095835_serialized_inventory_registry.sql` and its retry-safety
follow-ups are live only on `flexpos-2`. They add per-variant serial/IMEI modes,
globally unique identifiers, stock-bounded and idempotent bulk registration,
branch-scoped RLS, immutable registration events, and Inventory-screen
registration/history. POS allocation, returns, direct transfers, and loss-state
transitions now carry unit identifiers.

`20261028101536_purchase_receipt_serialized_inventory.sql` makes serialized
purchase receiving atomic: each tracked unit requires one valid identifier,
duplicates are rejected across the business, and registry events link the unit
to its goods receipt. Any identifier failure rolls back the receipt, stock
movement, balance change, and serial registration together.
`20261029072500_fix_completed_purchase_receipt_idempotency.sql` also ensures
that a retry of a fully received order returns its original receipt result
instead of being rejected merely because the order is already complete.

`20261029100000_pos_serialized_unit_allocation.sql` adds the sale-line link
table, while `20261029100500_complete_sale_serialized_units.sql` adds the POS
selection path. The checkout dialog requires one available unit per tracked
quantity; the transaction moves those units to `sold`, records immutable sale
events, links them to the sale line, and decrements stock together.
`20261029103000_serialized_sale_returns.sql` adds the return-unit link table
and a serial-aware return RPC overload. The Orders return dialog now shows the
sold serials/IMEIs as selectable chips; a successful cash return moves each
selected unit back to `in_stock`, records one immutable `returned` event, and
rejects duplicate or mismatched selections. The follow-up policy migration
allows only refund-authorized staff to inspect identifiers attached to sales in
their accessible branches.
`20261029110000_serialized_stock_loss.sql` now extends damage/wastage
recording with explicit serial/IMEI selection; selected units move to
`damaged` or `wastage`, receive immutable lifecycle events, and remain covered
by the same atomic stock-loss/idempotency guarantees.
`20261029120000_serialized_inventory_transfers.sql` adds direct inventory
transfers. The Inventory screen can transfer non-serialized quantities or exact
serial/IMEI units between accessible warehouses; the transaction locks both
balances, writes paired movement rows, updates the serialized registry, records
immutable transfer events, and safely returns the original result on an
idempotent retry.
`20261029130000_inventory_transfer_workflow.sql` adds staged transfer requests
with source-stock reservation, approval, dispatch, receipt, and cancellation.
The Inventory screen exposes request creation and status actions. Balances move
only when a dispatched request is received, while serialized units remain
reserved until receipt or cancellation. The follow-up result-reference fix is
`20261029130500_fix_inventory_transfer_workflow_result_refs.sql`.
`20261029140000_inventory_batches_and_expiry.sql` adds the RLS-protected
inventory-batch registry and immutable batch movement ledger. The follow-up
`20261029140500_purchase_receipt_batch_capture.sql` extends goods receiving so
non-serialized lines can capture batch number, lot number, manufacture date, and
expiry date. Each captured batch is linked to its receipt, updates quantity and
weighted average cost atomically, and records a purchase movement. Invalid or
past expiry metadata is rejected. `20261029150000_fefo_batch_sale_allocation.sql`
adds sale-side FEFO depletion: active, non-expired batches are consumed in
expiry order, while reserved, expired, recalled, and blocked quantities cannot
be silently sold as untracked stock. Batches without expiry dates use
creation-order FIFO selection.
`20261029160000_inventory_stocktakes.sql` adds warehouse-scoped physical
stocktake sessions. The Inventory screen can snapshot tracked SKUs and their
batches, capture counted quantities, and finalize atomic stocktake variances
with immutable inventory movements, batch movements, permission checks, and
idempotent audit records. The follow-up migrations fix count-parameter,
composite inventory-balance key, and warehouse-access handling.
`20261029170000_inventory_valuation_methods.sql` adds a business-scoped
valuation setting with weighted-average as the default, FIFO current batch
layers, and standard-cost valuation. Only users with `inventory.manage` can
change the method through the audited RPC; reports keep branch and permission
scoping, and legacy unbatched FIFO quantities use their stored average cost.
The follow-up `20261029170500_inventory_valuation_settings_indexes.sql` covers
the settings audit foreign key for predictable write performance.
`20261029180000_inventory_stock_alert_notifications.sql` adds durable,
branch-scoped low-stock notifications. Inventory managers can refresh the
notification inbox from the Reports screen, acknowledge active alerts, and
see alerts resolve automatically when available stock returns above its
configured threshold.
`20261029190000_customer_groups.sql` adds business-scoped customer groups and
customer membership with RLS-protected management. The Customers screen can
create groups, assign them while creating customers, reassign existing
customers, and display the active group.
`20261029200000_customer_group_pricing.sql` extends `product_prices` with
business-safe customer-group overrides. Products can set a global group price,
and POS applies the matching override for the selected customer with the
variant selling price as fallback.
`20261029230000_customer_specific_pricing.sql` adds business-safe direct
customer overrides. Products can set a global price for an individual customer;
POS applies it before the customer's group price, with the normal variant price
as the final fallback.
`20261029240000_coupons_promotions.sql` adds manager-controlled coupons,
business/branch scope, usage limits, redemption history, and an atomic
`complete_sale_with_coupon` checkout path. `20261029241000_coupon_preview.sql`
adds the POS preflight preview; checkout always validates the code again before
incrementing its redemption count.
`20261029250000_authorized_price_overrides.sql` adds the permission-gated
`complete_sale_with_price_overrides` path and validates unchanged lines against
the current customer, customer-group, or variant catalog price.
`20261029210000_loyalty_transactions.sql` adds an append-only, idempotent
customer loyalty ledger and a permission-checked RPC for earn, redeem, refund,
and adjustment postings. The Customers screen shows balances and transaction
history and lets authorized staff post a transaction.
The follow-up `20261029210500_fix_loyalty_rpc_parameter_ambiguity.sql` keeps the
RPC parameter names distinct from ledger columns for reliable Postgres binding.
The current POS unit-selection path is available for standard cash/electronic
sale completion and cash returns; credit-note, gift-card, and sales-order
fulfillment remain guarded until their corresponding unit-selection flows are
implemented.
Customer statements now support permission-controlled debit and credit
adjustments through `20261029220000_customer_credit_adjustments.sql`. The
operation is branch-scoped, idempotent, audit-written, and prevents credit
adjustments from exceeding the accessible outstanding balance.

`20261029310000_business_invoice_prefix.sql` is live only on `flexpos-2`. It
patches the authoritative `complete_sale` function so each new invoice uses
the business-configured invoice prefix, with `FP` as the fallback. Business
managers can edit the prefix, tax registration number, and receipt footer from
the Business receipt settings screen. The transparent FlexPOS logo is embedded
in the receipt PDF and preview; 58 mm and 80 mm layouts remain available for
print and PDF output.

`20261029320000_catalog_management_completion.sql` and
`20261029321000_catalog_policy_cleanup.sql` are live only on `flexpos-2`. They
add the tenant-scoped private product-image bucket and policies, product JSON
attributes, unit-conversion definitions, and bundle component definitions.
Catalog tools at `/catalog-management` provide signed image previews, CSV
import/export, bundle/unit editors, and bulk price/favorite updates.

`20261029330000_bundle_inventory_consumption.sql` is live only on `flexpos-2`.
It validates bundle components and atomically consumes non-serialized component
stock (including active-batch FEFO movements) when a bundle is sold.

`20261029331000_bundle_parent_guard.sql` is live only on `flexpos-2` and prevents
bundle parent SKUs from being configured as separately tracked inventory.

`20261029340000_receipt_templates_assets.sql` is live only on `flexpos-2` and
adds private business receipt assets plus classic/minimal/detailed template,
logo, and QR settings. Receipt PDFs render the configured logo and QR payload
for the selected 58 mm, 80 mm, or A4 format.

`20261029341000_platform_devices_cashier_pin.sql` is live only on `flexpos-2`.
It adds the server-enforced platform administrator overview, tenant device
registration/revocation, and salted, rate-limited cashier PIN verification.

`20261029350000_purchasing_lifecycle_completion.sql` and
`20261029351000_purchasing_policy_cleanup.sql` are live only on `flexpos-2`.
They add tenant-scoped purchase requisitions and approval decisions, supplier
invoices, idempotent invoice payments, payable balances, and landed-cost
allocation across purchase-order lines.

## Authentication notes

- Registration, login, logout, and password reset use Supabase Auth directly.
- Passwords and recovery tokens are never stored in application tables.
- Production redirect URLs must be added to Supabase Auth URL Configuration.
- Cashier PINs only unlock a checkout re-entry prompt; they are salted/hashed
  server-side, rate-limited, and never replace server authorization.

## Troubleshooting

If Windows reports that plugin builds require symlink support, enable Windows
Developer Mode, restart Android Studio, and rerun `flutter pub get`.

If the configuration screen appears, launch with
`--dart-define-from-file=config/dev.json`. Missing configuration intentionally
shows a safe error instead of connecting to an unintended project.

## Setup and release guides

- [Windows and Android Studio setup](docs/windows-android-studio-setup.md)
- [Android release signing](docs/android-release-signing.md)
- [Manual deployment runbook](docs/manual-deployment.md)
- [Feature inventory and dependency report](docs/feature-inventory-and-dependencies.md)

The locally generated APK uses the debug signing key unless a private
`android/key.properties` file is configured. Do not distribute a debug-signed
artifact.
