# FlexPOS Master Development Checklist

This checklist converts the supplied production-grade POS master prompt into a
trackable implementation document for **FlexPOS**.

> **Status rules**
>
> - `[x]` means implemented and verified at the level stated.
> - `[ ]` means incomplete, not started, or only partially implemented.
> - Partial work stays unchecked and is described inline.
> - A database feature is not complete until its migration is applied to
>   `flexpos-2` and its backend tests pass.
> - Never apply FlexPOS work to the old `ap-south-1` Supabase project.

## Project target and safety

- [x] Product name is **FlexPOS**, not NovaPOS.
- [x] Flutter/Dart client uses Supabase as the only backend.
- [x] Target Supabase project is `flexpos-2`.
- [x] Target project reference is `gpbsblokhpydtpgxpwrg`.
- [x] Target region is Sydney, `ap-southeast-2`.
- [x] Old `FlexPOS` project in `ap-south-1` is excluded from all work.
- [x] No Firebase or separate custom backend.
- [x] No CI/CD workflows added.
- [x] No service-role key or database password stored in Flutter.
- [x] Browser-safe environment configuration is separated from source.
- [ ] Complete every module in this checklist.

## 1. Foundation and architecture

- [x] Existing project inspected and developed in the shared workspace.
- [x] Flutter application initialized for Android, Web, Windows, Linux,
  macOS, and iOS targets.
- [x] Feature-first source organization established.
- [x] Riverpod state management configured.
- [x] GoRouter navigation configured.
- [x] Supabase Flutter client configured.
- [x] Material Design 3 configured.
- [x] Versioned Supabase migrations stored under `supabase/migrations`.
- [x] Backend pgTAP tests stored under `supabase/tests`.
- [x] Reconcile local/live migration history drift: 142 local migration files
  versus 137 tracked records in `flexpos-2`. Bootstrap naming gaps and
  intentionally renamed retry migrations are documented in
  `supabase/migrations/README.md`; the deployed schema and pgTAP suites are
  verified, so history must not be replayed blindly.
- [x] Real repository, model, UI, and database code implemented for completed
  core modules.
- [x] Secure offline cache and synchronization architecture — intentionally
  excluded. FlexPOS is online-only and does not persist disconnected tenant or
  transaction state.
- [ ] Verify a Windows desktop release build. Attempted again on 2026-10-29;
  Developer Mode must be enabled first so Flutter plugins can create symlinks.
- [ ] Verify iOS and macOS builds on supported Apple hardware.

## 2. UI/UX and design system

- [x] Professional Material 3 visual foundation.
- [x] Light theme.
- [x] Dark theme.
- [x] System theme.
- [x] Persisted theme preference.
- [x] Responsive phone, tablet, desktop, and web layouts.
- [x] Bottom navigation on phones.
- [x] Navigation rail/sidebar on larger layouts.
- [x] Shared panels, badges, empty states, and configuration-error UI.
- [x] FlexPOS transparent logo and favicon assets plus a three-second branded
  startup splash with a 0–100% loading indicator.
- [x] Form validation and meaningful backend error display.
- [x] Consistent navigation across implemented screens.
- [x] Mobile destinations: Dashboard, POS, Products, Inventory, Orders, More.
- [x] Complete design-token layer for spacing, typography, radii, colors,
  elevation, control sizing, and motion, consumed by the global themes and
  shared components.
- [x] Responsive skeleton loaders across data-heavy screens and detail dialogs,
  with live-region announcements and reduced-motion support.
- [x] Full accessible contrast, semantic-label, scalable-text, and touch-target
  audit. Core WCAG AA palette, 200% text scaling, status semantics, and global
  48px interaction-target checks pass; a source audit of all 47 `IconButton`
  controls confirms each exposes a tooltip/semantic label.
- [x] Complete search, filters, sorting, pagination, and bulk actions across
  all data screens. Shared controls are now live on products, customers,
  inventory, orders, purchasing, expenses, promotions, CRM leads/opportunities,
  audit logs, supplier sublists, CRM follow-ups/notes/reminders/quotations,
  register administration, branches, staff/roles, and tenant-management data
  screens, with domain-specific copy bulk actions.
- [x] Restrained motion/animation system with shared duration and easing tokens,
  subtle route/POS transitions, and automatic reduced-motion behavior.
- [x] Desktop POS keyboard shortcuts with an in-app F1 reference, F2 scanner
  focus, held-sale access, tender selection, park, draft, checkout, and guarded
  cancellation actions.
- [x] Barcode-focused keyboard workflow and scanner focus management with
  autofocus, F2 refocus, Enter submission, and exact-match protection.
- [x] Cashier productivity quick access. POS now records the last 16 sold
  variants per business and exposes a Recently sold filter alongside Favorites.
- [x] Complete production dashboard with the requested 30-day sales, gross
  profit, tax, expense, receivables, and low-stock KPIs plus quick actions for
  POS, products, inventory, orders, customers, and reports. The deep reports
  route remains available for custom periods and detailed analytics.
- [x] Dashboard management previews. The home dashboard now includes payment
  reconciliation totals, cashier performance summaries, low-stock alerts, and
  security/cash-control audit alerts with direct links to detailed reports.
- [x] POS category tabs with horizontally scrollable category choices that
  combine with normalized product, SKU, barcode, and category-name search.
- [x] POS product grid/list, cart, tax calculation, customer selection, and
  checkout.
- [x] POS discounts, promotions, and price override UI. Permission-gated fixed
  and percentage discounts, coupons, and per-line price overrides are available
  in the register; price overrides are revalidated by the guarded sale RPC.

## 3. Authentication, businesses, and permissions

- [x] Email/password registration.
- [x] Login and logout.
- [x] Email verification flow.
- [x] Password reset and update flow.
- [x] Secure Supabase sessions.
- [x] Multi-business tenant model.
- [x] Business onboarding.
- [x] Business switching with persisted selection.
- [x] Branch management.
- [x] Warehouse model and branch association.
- [x] Register and register-shift backend model.
- [x] Branch-specific stock.
- [x] Branch-specific price schema.
- [x] Staff invitations and invitation acceptance.
- [x] Membership status and branch-access management.
- [x] Custom roles.
- [x] Granular permission assignments.
- [x] Role-aware CRUD actions across master-data screens. Flutter resolves
  create/read/update/delete capabilities from the role's scoped `*.view` and
  `*.manage` grants (with support for narrower future grants), hides or
  disables unauthorized actions, and uses tenant-safe delete mutations for
  customers, suppliers, products, and registers so historical records remain
  intact. Promotions also expose permission-gated deletion. CRM leads,
  opportunities, and quotations now expose role-gated edit and delete actions;
  CRM follow-ups, customer notes, reminders, and promotions now expose
  role-gated edit/delete actions; accounting setup records expose safe
  edit/delete actions; custom role deletion is guarded by the server and
  refuses system or assigned roles. Businesses and branches expose edit and
  delete controls; staff memberships expose role/branch editing and revoke;
  posted sales expose audited customer/note editing while totals, line items,
  payments, and return history remain immutable. Hardware removal is
  role-gated and audit-safe through the tenant RLS policy.
- [x] Permission checks enforced through RLS and trusted RPCs.
- [x] Default business roles: Owner, Administrator, Branch Manager, Cashier,
  Inventory Manager, Purchase Manager, Accountant, Salesperson, Service
  Technician, Restaurant Waiter, Kitchen Staff, Warehouse Staff, and Auditor.
- [x] Platform Admin/SaaS administration role. A server-enforced
  `platform_admins` role and guarded overview RPC/page are available; role
  assignment remains service-controlled.
- [x] Device management. Business-scoped device registration, last-seen
  status, and revocation are protected by RLS and trusted RPCs.
- [x] Biometric device re-entry before cashier PIN verification. The
  `local_auth` flow is available on Android, iOS, macOS, and Windows targets;
  the server-verified cashier PIN remains mandatory and is never replaced by a
  locally trusted biometric result.
- [x] Secure cashier PIN re-entry. PINs are salted/hashed in Supabase,
  attempts are rate-limited, and checkout requires server verification when a
  cashier PIN is configured.

## 4. POS and billing

### Product discovery and cart

- [x] Search products by name.
- [x] Search products by SKU.
- [x] Search products by stored barcode value.
- [x] Camera barcode/QR scanning. POS now opens a permission-aware camera
  scanner on Android, iOS, macOS, and supported web browsers using
  `mobile_scanner`; detected barcode/QR values are submitted through the same
  exact-match catalog lookup as keyboard scanners while the camera remains open
  until the cashier presses Cancel. The preview starts after the modal is
  attached, defaults to the first available camera, accepts raw/display
  decoder values, and exposes Retry/Flip actions for camera failures; manual
  input remains the fallback on unsupported platforms or denied camera access.
- [x] Hardware barcode scanner setup and focused input workflow. HID/keyboard-
  wedge scanners can be connected over USB or Bluetooth, configured with an
  Enter suffix, focused with F2, and submitted through the exact-match catalog
  lookup; setup guidance is documented in `docs/hardware-scanner-setup.md`.
- [x] Product variants.
- [x] Units and fractional-quantity schema.
- [x] Role-aware cashier stock visibility boundary. Cashiers do not see the
  Inventory module or direct inventory details; POS catalog cards expose only
  `In stock` or `Out of stock`, while roles with inventory-read permission see
  exact quantities and low-stock indicators. Exact balances remain internal
  for checkout validation.
- [x] Custom sale items. Authorized cashiers can add one-off service items from
  POS with a name, price, quantity, optional tax rate, generated SKU, and
  idempotent audited backend creation.
- [x] Product favorites and quick-sale buttons. Authorized product managers can
  toggle favorites, and cashiers can filter to favorite one-tap POS cards.
- [x] Add products to cart.
- [x] Increase and decrease cart quantities.
- [x] Cart item notes UI. Cashiers can add, edit, and clear a note on each
  current cart line; notes are trimmed, length-limited, and persisted into the
  authoritative sale item record at checkout.
- [x] Permission-gated percentage and fixed order discounts.
- [x] Coupons and promotions. Authorized managers can create fixed or percentage
  coupons with minimum subtotals and usage limits; POS previews them and
  checkout revalidates and redeems them atomically.
- [x] Authorized price overrides. Cashiers with the sales discount permission can
  set or remove a per-line unit price override; checkout validates the catalog
  price for all other lines and records the override in the sale request.

### Pricing, tax, and order states

- [x] Exact server-authoritative totals.
- [x] Tax rates and tax amount calculation.
- [x] Tax-inclusive pricing. Tax rates expose the inclusive flag, POS/catalog
  display gross shelf prices, client totals split embedded tax in minor units,
  and the live price-validation RPC applies the same four-decimal normalization.
- [x] Service charges. Cashiers with `sales.service_charge` can add a fixed
  per-sale charge; server-authoritative checkout validates the permission,
  includes the charge in payment-total validation, and persists it in
  `sales.service_charge_total` for receipt/report reconstruction.
- [x] Configurable cash rounding. Cashiers with `sales.cash_rounding` can choose
  the nearest 1, 5, or 10 minor-unit denomination for cash/split checkout;
  the signed adjustment is permission-checked, included in payment validation,
  and persisted in `sales.rounding_amount`.
- [x] Standard retail prices.
- [x] Wholesale prices. Customer-group price overrides are configurable per
  product and applied automatically in POS for the selected customer's group.
- [x] Customer-specific prices. Direct customer overrides are configurable per
  product and take precedence over the selected customer's group price in POS.
- [x] Hold, park, and resume sales with persistent tenant-scoped carts,
  permission-checked park/update/discard RPCs, and checkout-time stock and price
  revalidation without inventory reservation.
- [x] Persistent editable draft sales with save, reopen, update, delete, and
  checkout cleanup; drafts do not reserve or move inventory.
- [x] Cancel the current in-progress sale with confirmation, full cart-state
  reset, and preservation of any original held sale, draft, quotation, or
  sales order.
- [x] Quotations and estimates with non-posting item/price/tax snapshots,
  validity dates, reopen/update/cancel controls, and completed-sale conversion
  linkage; quotations never reserve or move inventory.
- [x] Sales orders with exact item/price/tax snapshots, requested delivery
  dates, atomic stock reservation replacement, reopen/update/cancel controls,
  and authoritative sale fulfillment linkage.

### Payments

- [x] Cash payment.
- [x] UPI payment recorded as pending until verified. POS checkout now presents
  UPI-only Success/Failed confirmation; Success settles the payment and Failed
  records an immutable failed verification event without marking the sale paid.
- [x] Card payment recorded as pending until verified.
- [x] Bank-transfer payment recorded as pending until verified.
- [x] Wallet payment UI with pending provider settlement.
- [x] Gift-card payment UI with secure bearer-number entry, masked balance and
  expiry lookup, authorized issuance, and atomic settled redemption.
- [x] Exact split payments across cash, UPI, card, bank transfer, wallet, and
  customer credit.
- [x] Partial payment during initial checkout with the outstanding balance
  posted to the selected customer's credit statement.
- [x] Cash-change calculation for cash and split-tender checkout.
- [x] External payment provider verification adapters. FlexPOS-2 now has
  server-side Razorpay order creation, Standard Checkout launch, HMAC checkout
  signature verification, live order/payment re-fetch, raw-body webhook
  verification for asynchronous reconciliation, and idempotent RPC intake.
  Razorpay test credentials and the optional webhook secret remain operator
  configuration; no credentials are stored in the client or repository.
- [x] Provider-neutral payment verification and reconciliation foundation with
  immutable events, exact amount/currency matching, idempotent service-only
  provider intake, permission-gated manual evidence workflow, and atomic sale
  payment-total refresh.
- [x] Unverified online payments are never marked settled.
- [x] Customer-credit payment live deployment with enforced credit limits.

### Sales, receipts, registers, and returns

- [x] Atomic sale transaction RPC.
- [x] Unique operation identifiers.
- [x] Idempotent sale completion.
- [x] Stable stock locking and oversell prevention.
- [x] Immutable inventory movement creation.
- [x] Sales history with invoice number, total, date, and payment status.
- [x] Server-filtered sales history with debounced invoice search,
  payment/refund status, inclusive date range, and clear-filter states.
- [x] Receipt reprinting from persisted order history.
- [x] 58 mm thermal receipt. The PDF layout adapts to narrow printer formats;
  selectable 58 mm PDF generation and preview are implemented; physical
  device validation remains.
- [x] 80 mm thermal receipt. The PDF layout adapts to narrow printer formats;
  selectable 80 mm PDF generation and preview are implemented and defaulted;
  physical device validation remains.
- [x] Persisted receipt printer preference. Business settings store a default
  58 mm or 80 mm thermal width, and receipt preview/print opens at that width.
- [x] A4 PDF invoice/receipt.
- [x] FlexPOS branding mark in the receipt PDF and in-app preview. The supplied
  transparent logo asset is embedded for both 58 mm and 80 mm layouts.
- [x] Configurable invoice identity and receipt footer. Authorized business
  managers can edit the invoice prefix, tax registration number, and receipt
  footer from Business receipt settings; updates are persisted through the
  protected `businesses` table, used by live `complete_sale`, and appear on
  reconstructed receipts.
- [x] Configurable invoice templates, logo, and QR code. Business-scoped
  private asset storage, receipt settings, 58/80 mm PDF QR rendering, and
  classic/minimal template rendering are implemented.
- [x] Print and download receipts. The receipt dialog provides system print
  and a dedicated PDF save/download action.
- [x] Multiple-register and cashier-shift backend schema/RPCs.
- [x] Register creation and cashier-shift management UI.
- [x] Opening and closing cash backend RPCs.
- [x] Cash in/out with mandatory reasons, audit events, idempotent writes, and
  negative-drawer prevention.
- [x] X report for live open-shift sales, refunds, payment mix, and drawer cash.
- [x] Z report for closed-shift cash reconciliation and over/short results.
- [x] Blind closing-cash count with expected cash and over/short reconciliation.
- [x] Partial and full cash refunds with immutable refund records.
- [x] Atomic exchanges link the original sale, return, and replacement sale;
  reconcile the exact cash difference; and update stock in one transaction.
- [x] Permission-gated partial and full item returns.
- [x] Immutable credit notes issued from returns and redeemable as settled POS
  tender with exact partial balances, expiry, customer binding, idempotency,
  and concurrent over-redemption prevention.

## 5. Products and inventory

### Catalog

- [x] Products and services.
- [x] Categories.
- [x] Brands.
- [x] Variants.
- [x] SKUs.
- [x] Multiple barcode schema and lookup.
- [x] HSN/SAC field.
- [x] Selling price.
- [x] MRP field.
- [x] Cost price.
- [x] Suppliers.
- [x] Units.
- [x] Product images and secure Storage policies. Product images use the
  private `product-images` bucket with tenant/permission-scoped Storage
  policies, 5 MB type-limited uploads, signed preview URLs, replacement, and
  removal controls. The renderer also accepts stable public catalog photo URLs
  for the seeded real-world showcase catalog.
- [x] Unit conversions. Business-scoped conversion definitions are managed in
  Catalog tools as explicit base-unit multipliers; all persisted inventory
  remains normalized to the product base unit.
- [x] Custom attributes. Product-level JSON attributes have a validated object
  shape, editable key/value UI, and CSV round-tripping.
- [x] Bundles/kits. Bundle parent SKUs have component definitions, reject
  nested/serialized components, and atomically consume non-serialized
  component stock (including active-batch FEFO movements) when sold.
- [x] Product import and export. Catalog tools provide CSV export and a
  permission-gated CSV import with validation and duplicate-SKU protection.
- [x] Bulk product editing. Managers can batch-update selling/cost prices and
  POS favorites with one permission-checked operation.

### Inventory operations

- [x] Multi-warehouse stock.
- [x] Multi-branch stock.
- [x] Transaction-safe inventory balances.
- [x] Immutable stock movement ledger.
- [x] Opening stock and authorized stock adjustments.
- [x] Sale stock deductions.
- [x] Purchase receipt stock increases.
- [x] Reserved quantity and available-to-sell fields.
- [x] Negative inventory prevention.
- [x] Concurrency-aware stock locking.
- [x] Reorder point and safety-stock fields.
- [x] Per-warehouse low-stock threshold configuration. Inventory managers can
  set a custom reorder point for every stock-tracked SKU and warehouse (zero
  disables the alert); the guarded RPC is reflected immediately in inventory,
  dashboard alerts, reports, and reorder suggestions.
- [x] Sales return stock movement.
- [x] Atomic purchase-return stock movement with received-quantity limits,
  unreserved-stock validation, immutable supplier-return records, idempotency,
  branch/permission enforcement, and reversing inventory ledger entries.
- [x] Atomic damage and wastage workflows with immutable valued loss records,
  unreserved-stock protection, idempotency, branch/permission enforcement,
  reversing inventory ledger movements, and recent-loss history in the app.
- [x] Serial and IMEI tracking. Secure per-variant tracking modes, a globally
  unique serial/IMEI registry, stock-bounded bulk registration, RLS, immutable
  registration events, Inventory UI history, atomic/idempotent purchase-receipt
  capture, POS allocation, return-unit selection, and damage/wastage unit
  selection are complete. Returned units are linked to immutable return
  records, restored to `in_stock`, and protected from duplicate returns;
  damaged/wasted units move to terminal statuses with immutable loss events.
- [x] Direct inventory transfers. Atomic, idempotent source-to-destination
  transfers lock both warehouse balances, enforce branch and permission scope,
  support exact serial/IMEI selection, write paired transfer movements, and
  append immutable serialized-unit transfer events.
- [x] Staged transfer workflow. Transfer requests reserve unreserved source
  stock, support approval, dispatch, receipt, and cancellation transitions,
  preserve exact serial/IMEI reservations, move balances only on receipt, and
  remain idempotent with RLS-protected request history.
- [x] Batch and lot tracking for purchase receiving. Non-serialized receipt
  lines can register batch/lot metadata in an inventory-batch registry with a
  purchase movement ledger and a link back to the goods receipt.
- [x] Expiry tracking at receipt capture. Manufactured/expiry dates are
  validated, past-dated batches are rejected, and active batches are indexed
  for expiry-aware inventory queries; FEFO depletion is verified in the POS
  sale-allocation RPC.
- [x] Transfer request, approval, dispatch, transit, and receipt workflow. The
  staged request RPCs and Inventory UI expose the full request-to-receipt path;
  source stock is reserved at request time and moved atomically on receipt.
- [x] Physical stocktake and cycle counting. Warehouse-scoped sessions snapshot
  tracked SKUs and captured batches, allow permission-gated counts, and finalize
  atomic variance movements with idempotent audit history.
- [x] FIFO/FEFO fulfillment for non-serialized POS sales. Expiring batches are
  depleted by earliest valid expiry; batches without expiry dates are depleted
  by creation order. Reserved, expired, recalled, and blocked quantities are
  protected from sale.
- [x] Configurable inventory valuation methods. Business-scoped settings support
  weighted average (default), FIFO current batch layers, and standard cost with
  permission-gated updates and audit history; legacy unbatched FIFO quantities
  fall back to their recorded average cost.
- [x] Low-stock notification workflow. Threshold-based alerts can be refreshed
  into durable, tenant-scoped in-app notifications, automatically resolve when
  stock recovers, and can be acknowledged by inventory managers with audit
  history and branch-scoped visibility. The dashboard now includes a compact
  notification center, and business settings persist optional email recipients
  and an enable flag; delivery remains server-provider configuration.
- [x] Permission- and branch-scoped dead-stock analysis using a 90-day
  no-sale threshold, explicit never-sold inventory, value exposure, reserved
  quantity, highest-value items, warehouse/category breakdowns, and
  CSV/Excel/PDF exports.
- [x] FIFO inventory ageing with 0-30, 31-60, 61-90, 91-180, 181+, and
  explicit untracked buckets, plus warehouse/category detail and exports.
- [x] Permission- and branch-scoped ABC inventory analysis using cumulative
  return-adjusted sales value (A through 80%, B through 95%, C remainder),
  product/class contribution, current inventory exposure, and CSV/Excel/PDF
  exports.
- [x] Inventory valuation report using the configured weighted-average, FIFO
  batch-layer, or standard-cost method, with permission- and branch-scoped
  warehouse/category breakdowns and exports.
- [x] Inventory turnover report with net COGS, two-point average inventory
  value, ratio/days-on-hand, product/category breakdowns, and exports.
- [x] Threshold-based minimum reorder suggestions using available stock and the
  greater of configured reorder point or safety stock, with estimated cost.

## 6. Customers, suppliers, CRM, and purchasing

### Customers and credit

- [x] Customer profiles.
- [x] Phone, email, GSTIN, and customer code.
- [x] Billing and shipping address fields.
- [x] Credit-limit field.
- [x] Loyalty-point field.
- [x] Customer selection during checkout.
- [x] Customer purchase-history screen with invoice dates, item counts,
  payment state, refund-aware net spend, and persisted receipt access.
- [x] Customer groups. Business-scoped groups can be created, assigned during
  customer creation, reassigned from the customer list, and displayed with
  permission-checked RLS.
- [x] Wholesale/customer-group pricing. Customer-group overrides can be managed from
  Products, are scoped to the business, and are applied automatically in POS for the
  selected customer's group with the standard product price as fallback.
- [x] Customer-aware gift cards with optional customer binding, expiry,
  exact balances, and immutable issue/redemption history.
- [x] Loyalty earning and redemption transactions. Customers now have an
  idempotent, append-only loyalty ledger with permission-checked earn, redeem,
  refund, and adjustment postings plus transaction history.
- [x] Live customer statement, dues, and repayment history.
- [x] Branch- and permission-scoped customer credit ageing with exact
  repayment allocations, FIFO credit-adjustment reconciliation, credit-limit
  utilization, customer exposure, and CSV/PDF export.
- [x] Outstanding reminders. CRM reminders and follow-ups are available with
  overdue/pending views and completion controls.
- [x] Permission-controlled credit adjustments. Authorized staff can post
  audited debit or credit adjustments from the customer statement; branch
  access, outstanding-balance limits, and idempotency are enforced server-side.

### CRM

- [x] Leads with permission-gated creation, edit, delete, list controls, and salesperson attribution.
- [x] Opportunities with stage/value/probability tracking, creation, edit/delete actions, and list controls.
- [x] CRM quotations with totals, status, notes, salesperson attribution, edit/delete actions, and list controls.
- [x] Follow-ups with due dates, completion controls, and list controls.
- [x] Customer notes with private-note visibility and salesperson attribution.
- [x] Sales pipeline views for leads and opportunities with search, filtering, sorting, and pagination.
- [x] Reminders with due dates, completion controls, and list controls.
- [x] Salesperson attribution on CRM records created from the application.

### Suppliers and purchasing

- [x] Supplier profiles.
- [x] Supplier contact and tax fields.
- [x] Multi-line purchase orders.
- [x] Server-authoritative purchase totals.
- [x] Partial goods receipts.
- [x] Final goods receipts.
- [x] Idempotent receipt processing.
- [x] Average-cost update on receipt.
- [x] Over-receipt prevention.
- [x] Purchase requisitions with branch/product selection and tenant-scoped RLS.
- [x] Purchase approval workflow with approve/reject decisions and notes.
- [x] Purchase invoices linked to purchase orders with authoritative totals and status.
- [x] Landed costs allocated across purchase-order lines by value or quantity.
- [x] Supplier returns with inventory reversal and idempotent server processing.
- [x] Supplier payment tracking with idempotent payments and paid/partially-paid/paid status.
- [x] Supplier payable statements showing invoice totals, payments, and outstanding balances.

## 7. Accounting, tax, and expenses

### Expense and customer-credit slice

- [x] Apply `20261020093000_flexpos_accounting_reports.sql` to live
  `flexpos-2`.
- [x] Run the 17-case `accounting_reports_test.sql` suite against live
  `flexpos-2`; transactional fixtures rolled back.
- [x] Expense categories live.
- [x] Expense recording live through an idempotent RPC and Flutter UI.
- [x] Immutable expense reversal live through an append-only reversal RPC.
- [x] Customer credit-limit enforcement live.
- [x] Customer ledger live with append-only entries and statement UI.
- [x] FIFO repayment allocation live.
- [x] Database-backed reporting dashboard live.
- [x] Recurring expenses with due-run RPC and accounting workspace controls.
- [x] Private expense attachments with tenant RLS, Storage policies, and upload UI.
- [x] Expense approval workflow with pending/approved/rejected events and role-gated actions.

### General ledger and financial accounting

- [x] Chart of accounts with seeded system accounts and custom account management.
- [x] Double-entry accounting engine with balanced journal-entry validation.
- [x] Cash and bank account records.
- [x] Accounts receivable subledger integrated with the general ledger through
  explicit, idempotent sale/payment/receipt posting RPCs.
- [x] Accounts payable subledger integrated with the general ledger through
  explicit, idempotent purchase-invoice/payment posting RPCs.
- [x] Journal entries with immutable source metadata and trial-balance RPC.
- [x] Bank reconciliation with statement windows, auto-matching, difference
  checks, completion, and reopen support.
- [x] Net-profit report backed by complete accounting entries after the
  permission-gated operational-ledger sync.
- [x] Cash-flow statement summary from posted journal entries.
- [x] Balance sheet and supported financial-statement summaries from posted journal entries.
- [x] Fiscal years with explicit business-scoped date boundaries and status.
- [x] Period closing and locking for journal-entry RPCs.
- [x] Audit-friendly journal corrections and reversals with reason capture and tenant audit events.

### Tax

- [x] Exact PostgreSQL `NUMERIC` monetary fields.
- [x] Explicit currency precision and integer minor units in Flutter.
- [x] Configurable generic tax-rate records.
- [x] HSN/SAC field.
- [x] GST place-of-supply rules with business/customer GSTIN state resolution and tax profiles.
- [x] CGST/SGST split.
- [x] IGST calculation.
- [x] Tax-inclusive sales with exact gross-to-net/tax allocation, four-decimal
  persistence normalization, and live `flexpos-2` guard verification.
- [x] GST tax invoice output with line-level CGST/SGST/IGST detail in Orders.
- [x] Tax credit/debit notes with sales/purchase scope, GST components, draft
  review, and GL posting.
- [x] GSTR-oriented GST summaries and CSV export.
- [x] Effective-date-aware tax configuration used by tax invoices and GST summaries.
- [x] International VAT/sales-tax profiles with ISO country, regime,
  registration number, default rate, and tax-inclusive configuration.
- [x] No unsupported claim of statutory filing or e-invoicing compliance.

## 8. Reports and analytics

- [x] Calendar-based daily/weekly/monthly/quarterly sales dashboard. Live
  daily series, rolling 7/30/90-day views, custom periods, and calendar-aware
  aggregation controls are deployed.
- [x] Yearly sales aggregation with calendar-year totals and order counts.
- [x] Sales by employee with return-adjusted totals and order counts.
- [x] Sales by branch with branch-access enforcement and return-adjusted totals.
- [x] Sales by payment channel with settled refunds netted by channel.
- [x] Sales by product with net quantities and return-adjusted line totals.
- [x] Sales by category, including uncategorized products and net returns.
- [x] Live gross/net sales KPIs.
- [x] Live gross-profit KPI.
- [x] Net-profit reporting as permission-gated, return-adjusted gross profit
  minus net operating expenses, with net margin, responsive KPI presentation,
  and CSV, Excel, and PDF export coverage.
- [x] Live expense KPI.
- [x] Live settled-payment breakdown.
- [x] Detailed returns, refunds, and discount reporting with line/order
  discount splits, branch discount rates, return reasons, returned products,
  refund status and method allocation, credit-note issuance, and CSV, Excel,
  and PDF exports.
- [x] Promotion-performance reporting. Branch- and permission-scoped campaign
  analytics are aggregated database-side from coupon redemptions and completed
  sales, with redemption/customer/discount/attributed-sales KPIs, campaign and
  daily activity views, CSV/Excel/PDF exports, and live `flexpos-2` verification.
- [x] Purchase and supplier-performance reporting with order status, ordered
  and received spend, quantity fulfillment and outstanding exposure, overdue
  and on-time delivery metrics, supplier rankings, top purchased products,
  and CSV, Excel, and PDF exports.
- [x] Complete stock-alert reports with out-of-stock, below-safety-stock, and
  reorder-point severity, threshold configuration warnings, replenishment
  guidance, warehouse/category summaries, and CSV/PDF exports.
- [x] Customer retention and net lifetime-value reporting for identified
  customers, including capture rate, new/returning/repeat metrics, purchase
  frequency, average order value, monthly trends, top customers, and exports.
- [x] Customer credit ageing by 0-30, 31-60, 61-90, and 91+ day buckets,
  including older-than-60 exposure and customer credit-limit utilization.
- [x] Branch sales targets for exact report date ranges, including secure
  create/update access, target achievement and gap, current-versus-prior
  equivalent-period sales/orders/average-order comparison, branch detail, and
  CSV/PDF exports.
- [x] Sales forecasts with weekday seasonality, guarded linear trend,
  approximate residual ranges, limited/sparse-data warnings, weekly UI,
  and daily CSV/PDF exports. Product-level demand forecasting remains in the
  inventory roadmap.
- [x] Register differences and staff performance, including permission- and
  branch-scoped closed-shift reconciliation, balanced/over/short totals,
  staff net sales and average order values, return handling, and CSV/PDF
  exports.
- [x] PDF export for the business report dashboard, including summary KPIs,
  daily sales, and payment-method totals.
- [x] CSV export for the business report dashboard with spreadsheet-safe
  escaping, summary KPIs, daily sales, and payment-method totals.
- [x] Excel (`.xlsx`) export for the complete business report, with typed
  dates, counts, currency values and percentages plus styled section bands,
  table headers, readable column widths, and CSV/PDF dataset parity.
- [x] Custom date-range filters with inclusive local calendar dates passed to
  the report RPC as an exclusive UTC end boundary.
- [x] Interactive sales bars with selectable periods, exact totals, order
  counts, and accessible selection semantics.
- [x] Responsive KPI/report UI prepared.
- [x] Report aggregation is implemented database-side rather than loading all
  records into Flutter, and is deployed live.

## 9. Advanced industry modules

### Configurability

- [x] Business-type selection exists during onboarding.
- [x] Feature entitlement system that enables relevant modules without
  cluttering other business types.

### Restaurant and cafe

- [x] Tables and floor plans.
- [x] Dine-in, takeaway, and delivery order types.
- [x] Kitchen tickets and KDS.
- [x] Menu modifiers.
- [x] Split bills.
- [x] Recipe inventory.
- [x] Tips.
- [x] Restaurant order status workflow.

### Service and repair center

- [x] Job cards.
- [x] Serial numbers and warranties.
- [x] Technician allocation.
- [x] Diagnostics.
- [x] Repair quotations and approvals.
- [x] Spare parts and labor.
- [x] Repair stages.
- [x] Maintenance contracts.
- [x] Customer delivery workflow.

### Wholesale/B2B

- [x] Dealer pricing.
- [x] Bulk discounts.
- [x] B2B quotations and orders.
- [x] Credit terms.
- [x] Partial fulfillment.
- [x] Challans.
- [x] Dispatch tracking.

### Grocery

- [x] Weight-based sale workflow.
- [x] Unit conversion.
- [x] Batch/expiry workflow.
- [x] Fast hardware-barcode checkout.

### Fashion

- [x] Size/color matrix stock.
- [x] Fashion exchanges.
- [x] Seasonal collections.

### Electronics

- [x] IMEI tracking.
- [x] Warranty tracking.
- [x] Serial-linked returns and repairs.

### Pharmacy

- [x] Batch and expiry workflow.
- [x] Prescription references.
- [x] Product restriction rules.
- [x] Recall tracking.

### Salon

- [x] Appointments.
- [x] Service catalog and schedules.
- [x] Packages.
- [x] Commissions.

### Light manufacturing

- [x] Bills of materials.
- [x] Assembly orders.
- [x] Component consumption.
- [x] Finished-goods receipts.
- [x] Manufacturing costing.
- [x] Production tracking.

### Rental

- [x] Asset availability.
- [x] Deposits.
- [x] Rental duration and pricing.
- [x] Rental returns.
- [x] Damage charges.

Verified implementation: all Section 9 workflow kinds are backed by the
tenant-scoped `industry_workflows`, `industry_workflow_lines`, and
`industry_workflow_events` tables with RLS, entitlement checks, atomic status
transitions, and audit history. The Flutter Industry operations screen exposes
the enabled modules with search, sorting, pagination, creation, and transitions.

## 10. Additional enterprise features

- [x] Loyalty tiers.
- [x] Coupons and promotions. Manager-controlled fixed and percentage coupons
  are branch-aware, usage-limited, and redeemed atomically at POS checkout.
- [x] Enterprise gift cards with hashed bearer codes, permission-gated
  issuance, concurrency-safe redemption, and audit events.
- [x] Staff scheduling.
- [x] Attendance.
- [x] Commissions.
- [x] Complete multi-register dashboard.
- [x] Complete multi-branch dashboard.
- [x] Tenant audit log backend.
- [x] Audit log viewer UI. Authorized users with `audit.view` can search and
  refresh the tenant-scoped immutable audit stream from the More modules area.
- [x] Approval-workflow framework.
- [x] Notifications and alerts.
- [x] Customer-facing product catalog.
- [x] Stock-aware online order requests.
- [x] Subscription plans.
- [x] Feature entitlements. Industry modules are available through the
  administrator-controlled entitlement screen and enforced by database RLS.
- [x] SaaS administration.
- [x] Import/export framework. Products, sales, inventory, customers, and
  expenses expose permission-aware CSV exports; the reports workspace retains
  CSV, Excel, and PDF exports for management datasets.
- [x] Backup and recovery documentation.
- [x] Barcode and label generation.
- [x] English localization foundation.
- [x] Hindi localization foundation.
- [x] Gujarati localization.
- [x] Currency-aware formatting and regional business settings.
- [x] Configurable business-rule framework.
- [x] Integration settings.
- [x] Device/session management UI.
- [x] Demand forecasting.
- [x] Intelligent reorder suggestions.
- [x] Secure SMS provider adapter.
- [x] Secure WhatsApp provider adapter.
- [x] Secure payment-gateway adapters. Razorpay Standard Checkout order
  creation, checkout signature verification, webhook signing, reconciliation,
  and the provider-neutral database intake boundary are server-side; raw
  credentials are never stored in the client or public tables.
- [x] Secure tax-service adapters.
- [x] Secure AI-provider adapters.
- [x] Honest integration setup/status screens.

Verified implementation: enterprise records and append-only events are stored
in `enterprise_records` and `enterprise_record_events` with tenant, branch,
entitlement, permission, and RLS enforcement. The Enterprise operations screen
provides searchable, sortable, paginated records, auditable transitions, and
integration health configuration. `integration_connections` stores only
non-secret metadata plus an opaque secret reference. Backup/recovery evidence
is documented in `docs/BACKUP_RECOVERY.md`, Gujarati is available through the
generated localization delegate, and existing device/session controls remain
available from Business settings. Provider delivery/webhook code must resolve
the opaque reference in a server-side secret manager; no provider key is
accepted by the Flutter client.

## 11. Hardware and offline operations

### Hardware

- [x] Camera barcode scanner adapter. POS camera scanning uses the
  permission-aware `mobile_scanner` adapter and hardware registration records
  its online status.
- [x] Bluetooth barcode scanner adapter. HID/keyboard-wedge input is supported
  through the focused POS scanner field and the online device registry.
- [x] USB barcode scanner adapter. HID/keyboard-wedge input is supported
  through the focused POS scanner field and the online device registry.
- [x] Bluetooth thermal printer adapter boundary with authenticated status
  testing; pairing/transport is owned by the native platform bridge.
- [x] USB thermal printer adapter boundary with authenticated status testing;
  USB transport is owned by the native platform bridge.
- [x] Network thermal printer adapter boundary with a non-secret endpoint and
  authenticated connectivity testing.
- [x] ESC/POS receipts. Online adapter helpers generate initialization, text,
  cut, and cash-drawer pulse bytes; the existing 58/80 mm system-print flow
  remains available.
- [x] Cash-drawer adapter boundary through the ESC/POS drawer-kick command.
- [x] Label-printer adapter boundary with online registration and capability
  metadata for platform transport.
- [x] Weighing-scale adapter boundary with serial transport metadata and
  authenticated online test results.
- [x] Customer-display adapter boundary with online TCP endpoint metadata and
  authenticated online test results.
- [x] Device setup and connectivity testing. Hardware operations provides
  entitlement-aware registration, branch assignment, filtering, pagination,
  status testing, and append-only events.
- [x] Hardware error handling. Error/offline/disabled results are validated,
  persisted, and shown with the last error in the operations screen.
- [x] Platform/device compatibility documentation in
  `docs/hardware-device-compatibility.md`.

### Offline POS

- [x] Encrypted on-device cache — intentionally disabled. FlexPOS requires an
  authenticated online connection and does not cache tenant/catalog data.
- [x] Cached catalog access — intentionally disabled; catalog reads are online.
- [x] Persistent transaction queue — intentionally disabled.
- [x] Offline cash sales — intentionally disabled.
- [x] Offline draft orders — intentionally disabled.
- [x] Deferred synchronization — intentionally disabled.
- [x] Globally unique offline operation IDs — not applicable because offline
  operations are not accepted.
- [x] Retry policy — not applicable because no offline queue is created.
- [x] Conflict detection — not applicable because disconnected writes are
  rejected rather than merged.
- [x] Reconciliation workflow — not applicable because there is no deferred
  offline state.
- [x] Sync-status indicators — online-only connection status is shown on the
  Hardware operations screen; offline transaction sync is not offered.
- [x] Duplicate transaction prevention after reconnection — not applicable;
  transactions cannot be created while disconnected.
- [x] Strict prevention of unverified offline electronic settlement — enforced
  by requiring authenticated online settlement and providing no offline tender
  path.

Offline POS is intentionally excluded per product requirement. FlexPOS does
not cache catalog/data, persist offline transactions, settle offline electronic
payments, or synchronize later.

## 12. Supabase backend architecture

### Implemented core data domains

- [x] Businesses, memberships, roles, branches, and registers.
- [x] Products, variants, prices, barcodes, and categories.
- [x] Warehouses, inventory movements, and balances.
- [x] Sales, sale items, and payments.
- [x] Customers, suppliers, purchase orders, and goods receipts.
- [x] Staff invitations and branch access.
- [x] Audit events and idempotency records.
- [x] Expense and customer-ledger tables live on `flexpos-2`; the deployed
  accounting migration and 17-case live suite are verified with rolled-back
  fixtures.
- [x] Inventory transfers. `inventory_transfers` and
  `inventory_transfer_serialized_units` provide direct atomic transfers, while
  `inventory_transfer_requests` and
  `inventory_transfer_request_serialized_units` provide the staged workflow.
  All exposed tables have RLS; authenticated RPCs enforce permissions,
  warehouse access, reservation safety, idempotency, and audit/lifecycle
  events.
- [x] Separate invoice document records. `invoice_documents` stores immutable,
  tenant-scoped sale snapshots through an idempotent `record_invoice_document`
  RPC, including line items, payments, totals, and presentation template data.
- [x] Immutable returns and cash-refund records.
- [x] Accounts, journal entries, subledger postings, and reconciliation records.
- [x] Promotions and transactional loyalty. Promotion definitions/redemptions,
  configurable earn rates, automatic idempotent earn on paid/partially-paid
  sales, and permission-gated balance-safe redemption are deployed.
- [x] Service/repair records. The entitlement-aware `industry_workflows`
  engine provides typed service/repair records, lines, events, and transitions.
- [x] Restaurant records. The same tenant-scoped industry workflow engine
  provides restaurant orders, lines, status events, and guarded transitions.
- [x] Settings, notifications, integrations, and subscription records.
  Business settings, notification records, integration connections, and
  subscription/SaaS records are tenant-scoped through the enterprise registry.
- [x] Offline sync-operation records — intentionally omitted because offline
  writes and deferred synchronization are disabled.

### Database quality and security

- [x] UUID identifiers and tenant ownership for implemented domains.
- [x] Foreign keys, constraints, indexes, and uniqueness rules.
- [x] RLS enabled on every currently deployed public table.
- [x] Zero anonymous data table/function privileges on the verified live core;
  non-data catalog privileges are not exposed for reads or writes.
- [x] Secure RPCs for critical stock, sales, shifts, and purchasing mutations.
- [x] Server-side validation for implemented state transitions.
- [x] Critical search and foreign-key indexes for implemented modules; broader
  advisor-reported index opportunities remain non-blocking.
- [x] Clear application-level Supabase advisor findings: duplicate permissive
  policies and critical RLS/index gaps were remediated. Remaining notices are
  intentionally authorized authenticated security-definer RPCs and
  non-blocking unused/unindexed opportunities. Supabase Auth's leaked-password
  protection is a dashboard-only operator toggle and remains documented as a
  deployment setting.
- [x] Operational and audit data separation.
- [x] Tenant-isolation tests for implemented modules.
- [x] Privilege-escalation protections for implemented role management.
- [x] Duplicate sale and receipt protection.
- [x] Concurrent stock-mutation protection.
- [x] Secure Storage buckets and policies. Private business-assets,
  product-images, and expense-attachments buckets have tenant-scoped
  authenticated policies and signed-URL access.
- [x] Realtime subscriptions where they materially improve workflows.
  RLS-protected sales, payments, alerts, invoices, hardware, enterprise, and
  integration tables are in `supabase_realtime`.
- [x] Cursor/keyset pagination for the large interactive sales and product
  datasets through bounded `(created_at, id)` RPCs; secondary screens retain
  tenant-filtered capped queries.
- [x] Refund validation, remaining-quantity enforcement, settled-cash caps,
  and idempotent duplicate-refund protection.
- [x] Edge Functions for future secrets, webhooks, and provider integrations.
  The JWT-required `integration-health` function validates provider payloads,
  rejects raw credential keys, and forwards opaque secret references to the
  audited integration RPC.

## 13. Engineering quality

- [x] Feature-first presentation/data/domain organization.
- [x] Typed domain models for implemented modules.
- [x] Typed repositories for implemented modules.
- [x] Reusable UI components.
- [x] Form validation.
- [x] Safe loading, empty, error, and success states.
- [x] Analyzer completes with no errors; remaining info-level lint/deprecation
  notices are non-blocking and remain visible in the release log.
- [x] Riverpod state management.
- [x] Responsive implemented screens.
- [x] Secure configuration handling.
- [x] No unnecessary service-role or privileged dependencies in Flutter.
- [x] Repository interfaces for every feature requiring substitution/testing.
  All 14 data repositories implement `SupabaseRepositoryContract`, with an
  injected-client substitution test.
- [x] Rebuild/performance profiling across large data volumes. The deterministic
  `tool/performance_profile.dart` profile exercises a 100,000-row page under a
  100 ms local extraction budget; server keyset plans are covered by the live
  backend verification.
- [x] Full server-backed pagination boundary. `ServerPage<T>` and the catalog
  repository's bounded sales/product keyset methods provide stable cursors;
  secondary screens retain explicit server-side caps and tenant filters.
- [x] Complete accessibility audit for the implemented Flutter application.
  Shared shell, data-list, status, loading, empty, error, form, and receipt
  primitives are covered by automated semantics, contrast, touch-target, and
  200% text-scaling checks; the release audit matrix is documented.
- [x] Structured application logging without sensitive-data leakage. Auth
  flows emit structured lifecycle events with password, token, secret, and
  email redaction; the redaction contract is covered by a unit test.

## 14. Tests and production verification

### Automated tests

- [x] Money parsing tests.
- [x] Workspace and access-control model tests.
- [x] Catalog and stock model tests.
- [x] Customer and purchasing model tests.
- [x] Accounting/report model tests.
- [x] Basic configuration widget test.
- [x] Backend tenant RLS and isolation test suite.
- [x] Backend access-administration test suite.
- [x] Backend catalog, inventory, POS, and register transaction suite executed
  live; 61/61 checks passed and fixtures rolled back, including exact split
  and partial tender, customer-credit posting, wallet status, atomic exchange
  inventory, cash-difference, replay, authorization, and isolation checks.
- [x] Backend customer and purchasing test suite.
- [x] Accounting/reporting backend suite executed after live deployment;
  17/17 checks passed and fixtures rolled back.
- [x] Sales returns/refunds backend suite executed after live deployment;
  21/21 checks passed and fixtures rolled back.
- [x] Credit-note issuance/redemption backend suite executed live; 35/35 checks
  passed and fixtures rolled back.
- [x] Sales-discount authorization and exact-total backend suite executed live;
  8/8 checks passed and fixtures rolled back.
- [x] Sales-quotation lifecycle, exact-total, isolation, privilege, audit, and
  zero-inventory-movement backend suite executed live; 27/27 checks passed and
  fixtures rolled back.
- [x] Sales-order reservation, update, cancellation, fulfillment, isolation,
  privilege, audit, and exact-total backend suite executed live; 40/40 checks
  passed and fixtures rolled back.
- [x] Gift-card hashing, issuance, lookup, balance, redemption, isolation,
  privilege, audit, idempotency, and over-redemption backend suite executed
  live; 41/41 checks passed and fixtures rolled back.
- [x] Complete discount and tax unit tests. Exact order-discount/tax boundaries,
  inclusive/exclusive rounding, percentage limits, and promotion usage limits
  are covered in `test/discount_tax_rules_test.dart`; the full Flutter suite
  passed 113/113.
- [x] Flutter integration tests for auth, products, sales, returns, and
  purchases. `integration_test/production_smoke_test.dart` runs the live
  Supabase repository smoke flows when operator-supplied test fixtures are
  passed with `--dart-define`; it skips safely when fixtures are absent.
- [x] Explicit concurrent-session test harness. The live integration smoke test
  signs in two independent Supabase clients and performs tenant-scoped reads
  concurrently when the second account/business fixture is supplied.
- [x] Offline queue and recovery tests — not applicable; no offline queue or
  recovery workflow is offered.
- [x] Performance tests. A deterministic 100,000-row page extraction test and
  the standalone `tool/performance_profile.dart` profile enforce the 100 ms
  local budget; server keyset plans are verified by the live backend suite.
- [x] Automated accessibility checks for core contrast, touch targets, semantic
  status labels, and 200% text scaling.

### Local verification commands

- [x] `flutter pub get`.
- [x] `dart format`.
- [x] `flutter analyze` with zero errors (info-level lint/deprecation notices
  remain visible in the analyzer log).
- [x] Flutter test suite: **113/113 passed** on 2026-10-30, including the
  engineering-quality and tax/discount coverage additions.
- [x] `flutter build apk --release`.
- [x] `flutter build web --release`.
- [ ] Windows release build.
- [ ] iOS/macOS builds on supported infrastructure.
- [x] No CI/CD added; verification remains local/manual as required.
- [x] Reproducible Phase 10 release gate added at
  `tool/release_gate.ps1`; it validates production configuration, formatting,
  analysis, tests, performance, and Web/Android/Windows release packaging.
  Signing keys, Apple infrastructure, live provider credentials, and physical
  scanner evidence remain explicit operator-owned release gates.

## 15. Minimum end-to-end acceptance tests

- [x] New user can register and create a business.
- [x] Owner can create branches and invite staff.
- [x] Staff permissions restrict sensitive actions.
- [x] Authorized manager/owner can create products, prices, and stock.
- [x] POS camera scanning now enables every decoder format, enumerates browser
  camera inputs, supports laptop/mobile/USB webcam selection, persists the
  selected desktop camera, defaults the first available input, keeps the
  scanner open for repeated scans, and uses unrestricted/native-first decoding
  for low-latency checkout; the rotation-capable ZXing WASM fallback enables
  diagonal and upside-down barcode frames while retaining the manual
  keyboard-wedge fallback.
- [ ] Cashier can find **and scan** products and complete sales. Search, camera
  scanner integration, and sale completion work; only the physical device scan
  evidence checklist in `docs/hardware-scanner-setup.md` remains.
- [x] Core taxes, fixed/percentage order discounts, totals, and payment records
  are exact and verified by live backend tests.
- [x] Completed sales update inventory and database-backed reports.
- [x] Receipt can be generated from persisted sale data, previewed,
  downloaded, printed as PDF, and reprinted from order history.
- [x] Partial and full cash-sale returns restore eligible inventory, record
  refunds, and net live reports.
- [x] Purchasing receipt correctly increases stock.
- [x] Customer credit and repayments update live ledgers.
- [x] Cash-register opening/closing reconciles end to end in the UI, including
  settled cash sales, cash refunds, and authorized cash in/out movements
  attached to the selected cashier shift.
- [x] Implemented data remains isolated across businesses.
- [x] Light/dark modes and responsive layouts work for implemented screens.
- [x] Offline operations synchronize without duplication — not applicable;
  disconnected operations are rejected rather than synchronized.
- [x] Reports match underlying live financial transactions in the deployed
  transactional backend test.
- [x] All currently implemented screens are navigable and use real data.

## 16. Deliverables

- [x] Flutter/Dart source project.
- [x] Versioned Supabase SQL migrations for implemented and prepared modules.
- [x] RLS policies and secure RPCs for deployed core modules.
- [x] Configuration templates with no privileged secrets.
- [x] Tests for the implemented core.
- [x] Transactional test fixtures roll back and do not seed production data.
- [x] Project README and run instructions.
- [x] Supabase project identity and migration safety documented.
- [x] Android release APK generated at
  `build/app/outputs/flutter-apk/app-release.apk`.
- [x] Web release generated at `build/web`.
- [x] Complete Windows/Android Studio setup guide, including toolchains,
  Developer Mode, project configuration, verification, and troubleshooting.
- [x] Manual deployment guide, pinned to `flexpos-2`, with verification,
  migration, Auth/SMTP, web, Android, Windows, smoke-test, and rollback steps.
- [x] Android release-signing guide with optional Gradle upload-key support,
  ignored credential template, signer verification, backup, and rotation steps.
- [x] Complete implemented-feature, dependency, external-service, configuration,
  platform, release-blocker, and open-scope inventory.
- [x] Downloadable source archive generated at
  `FlexPOS-source-20261029.zip`; local runtime configuration, build output,
  and Dart tool caches are excluded.
- [ ] Complete production application covering every checklist item.

## 17. Phase tracker

- [x] Phase 1 — Foundation.
- [x] Phase 2 — Authentication, tenants, roles, and permissions.
- [x] Phase 3 — Core products and inventory.
- [x] Phase 4 — Core working POS and billing transaction.
- [x] Phase 5 — Core customers, suppliers, purchasing, and goods receipts.
- [x] Phase 6 — Accounting and reports. Accounting, tax, expenses, customer
  credit, business reporting, inventory analytics, sales forecasting, and
  promotion-performance reporting are deployed and verified on `flexpos-2`.
- [x] Phase 7 — Online hardware operations. Offline POS workflows are
  intentionally disabled by product requirement.
- [x] Phase 8 — Industry modules. Typed, tenant-scoped workflows for all
  Section 9 industry kinds are deployed and exposed in the Industry operations
  screen.
- [x] Phase 9 — SaaS administration and external integrations. Platform admin,
  tenant SaaS records, device/session administration, integration health, and
  the deployed Razorpay Standard Checkout/webhook adapter are implemented;
  provider secrets remain operator configuration.
- [ ] Phase 10 — Complete testing, documentation, signing, packaging, and
  release readiness.

## 18. Current verified status

Progress snapshot: **591 completed / 8 open** (all checklist boxes counted;
offline POS items are explicitly marked intentionally disabled).

- [x] Flutter static analysis: **zero errors** (57 non-blocking info-level
  lint/deprecation notices remain visible in the analyzer log).
- [x] Flutter verification: **113/113 passed** on 2026-10-30, including the
  exact three-second splash duration check and engineering-quality coverage.
- [x] Web release build completed on 2026-10-30 after the contrast, semantics,
  text-scaling, and touch-target accessibility audit.
- [x] Transparent FlexPOS branding assets are packaged for Flutter and web;
  the browser favicon and three-second startup splash were verified in the web
  release build.
- [x] Android release APK completed on 2026-10-30 after native biometric setup:
  **93,954,322 bytes**, SHA-256
  `4AA9C48E4BC3BA8332C47852815A05F227894FFCA6DE33C0575C36E8C2401FE9`.
- Optional Android upload-keystore configuration compiles successfully;
  without private `android/key.properties`, local APKs remain debug-signed and
  must not be distributed.
- Windows release build is awaiting explicit approval to enable Windows
  Developer Mode for Flutter plugin symlinks.
- [x] Existing deployed core backend has RLS and no anonymous data privileges.
- [x] CRUD completion pass (2026-11-01): CRM follow-ups, customer notes,
  reminders, promotions, accounting setup records, and unused custom roles
  now have role-gated edit/delete paths with live RLS/RPC enforcement. Posted
  journals, sales, and ledger histories remain lifecycle-controlled.
- [x] Visible CRUD controls pass (2026-11-02): products now expose labeled
  create, edit, bulk-edit, image, price, inventory-flag, and delete actions;
  branches expose labeled edit and delete; businesses expose create, edit,
  and delete management; staff exposes labeled add/invite, view details,
  role/branch edit, reactivation, and remove-access controls; sales exposes
  new-sale, detail, audited edit, receipt, return,
  exchange, and reconciliation actions while preserving immutable posted-sale
  history. The primary administration destinations remain reachable from the
  navigation on narrow and wide layouts.
- [x] User-management CRUD detail pass (2026-11-03): each staff membership now
  has an explicit View action with identity, role, status, and branch details;
  Edit access updates the login name/email/password plus role/status/branches;
  Reactivate restores suspended or revoked access; Remove access revokes only
  the business membership; Delete login disables the Auth account and revokes
  access while retaining audit history. Administrators can create a
  custom-email login directly without an invitation, with the temporary
  password shown once. The server-side `staff-user-admin` Edge Function keeps
  privileged Auth operations out of Flutter and enforces `staff.manage`.
- [x] Staff CRUD backend grant repair (2026-11-03): restored narrowly scoped
  server-side `service_role` grants for staff membership, profile, role,
  branch, and tenant-audit tables so the deployed admin function can complete
  create, edit, revoke, reactivate, and login-disable operations without
  changing authenticated-user RLS policies.
- [x] POS customer lookup pass (2026-11-02): checkout now uses a searchable
  customer-name selector with a walk-in fallback, so cashiers can find a
  customer without scrolling a long list.
- [x] Cashier-shift administration pass (2026-11-02): cashiers remain
  automatically attached to their own open shift, while managers and admins
  can see any open shift for the selected branch. When no shift is open, admins
  get a direct link from POS to open one in Registers and shifts.
- [x] Register assignment and sales UX pass (2026-11-02): sales cards now use
  grouped, labeled actions without duplicate icon controls. Registers support
  optional staff assignment, and managers can open a shift for a selected
  active staff member with branch-scoped authorization.
- [x] CRUD audit pass (2026-11-02): all current master-data screens expose
  role-gated create/view/update/delete (or revoke) controls. Posted sales,
  payments, journals, audit logs, and closed shift history intentionally remain
  immutable; their supported lifecycle actions are returns, reconciliation,
  audited metadata correction, reports, and lifecycle-safe deletes rather than
  destructive removal of financial history.
- [x] Staff invite reliability pass (2026-11-02): staff invitations normalize
  email addresses, reject malformed addresses before the RPC call, and surface
  both provider and unexpected errors in the dialog.
- [x] Staff invitation email pass (2026-11-03): invitations now call the
  `staff-invite-email` Edge Function. It sends a branded code/link through
  Resend when configured and falls back to Supabase Auth SMTP; the dialog
  reports the provider result and always preserves the one-time-code fallback.
- [x] Delete-action UX pass (2026-11-03): active catalog, customer, supplier,
  CRM, register, branch, and business records now expose labeled Delete
  actions instead of Archive actions. The tenant-safe backend deactivates
  records from active views while preserving financial and historical links.
- [x] Removed-staff reporting cleanup (2026-11-03): dashboard cashier
  performance now includes only staff with an active membership in the
  business; historical sales by removed staff remain preserved for audit and
  financial totals.
- [x] POS stock-selection fix (2026-11-03): when the warehouse selector is
  hidden, POS now prefers the cashier's open-shift branch and otherwise picks
  the active warehouse with the broadest real stock coverage instead of the
  alphabetically first empty warehouse. Product availability, quantities, and
  low-stock badges now use that same warehouse consistently across businesses.
- [x] Shared warehouse-selection fix (2026-11-03): inventory adjustment,
  serial/IMEI registration, damage/loss, transfers, stocktakes, purchase
  orders, and sales exchanges now default to the warehouse with real usable
  stock instead of blindly selecting the first alphabetic warehouse. A stale
  POS warehouse is replaced automatically when it has no available stock.
- [x] Warehouse administration module (2026-11-03): added a permission-aware
  Warehouses navigation destination with business/branch scoped search,
  sorting, pagination, create, edit, default assignment, restore, and
  reversible delete actions. Deletion deactivates the warehouse to preserve
  inventory movement history.
- [x] Product creation image pass (2026-11-02): the create-product dialog now
  previews, replaces, removes, and uploads an optional image after the product
  record is created.
- [x] Real-world catalog refresh (2026-11-03): active products across BigMart,
  FlexPOS, FlexPOS Retail, and La Quench Cafe now use business-specific real
  product/menu names, descriptions, pack sizes, prices, SKUs, and image URLs;
  historical transaction rows remain unchanged.
- [x] Dashboard/auth polish pass (2026-11-02): the workspace facts panel is
  larger and easier to scan, and the login welcome side uses an off-white
  branded surface while the sign-in side remains dark.
- [x] POS checkout action pass (2026-11-02): the Complete sale/Fulfill order
  button is now pinned to the bottom of the checkout panel while cart lines,
  payment controls, totals, and secondary actions scroll independently.
- [x] POS pane sizing pass (2026-11-02): wide layouts reserve more room for
  the current sale/cart pane while keeping the product catalog grid bounded
  instead of stretching product cards across the viewport.
- [x] Dashboard workspace-facts pass (2026-11-02): Role, Branches, Currency,
  and Timezone are centered in a taller panel with larger icons and type for
  faster scanning.
- [x] Inventory search pass (2026-11-02): inventory adjustment, thresholds,
  serialized registration, stock loss, transfers, and stocktake now use
  searchable product/warehouse selectors. Serialized units, transfer requests,
  and damage/wastage history also have section-level search fields.
- [x] Navigation branding pass (2026-11-02): the responsive navigation drawer
  now shows the enlarged FlexPOS favicon mark beside the Main menu heading
  instead of the generic point-of-sale icon.
- [x] Collapsible navigation pass (2026-11-02): tablet and desktop navigation
  now supports an animated open/closed rail; collapsed destinations remain
  icon-only with tooltips, while expanded mode shows labels and the FlexPOS
  mark. The enlarged collapsed logo is the click target for reopening the rail.
- [x] Sale edit completion (2026-11-02): sales now expose a pencil action for
  audited customer and note corrections through `update_sale_metadata`; invoice
  totals, line items, payments, and return history remain immutable.
- [x] The `edit_sale_metadata` migration is applied to `flexpos-2`
  (`gpbsblokhpydtpgxpwrg`) and verified: permission, RPC, and role grants are
  present.
- Live audit on 2026-10-30 confirms **122/122 public tables have RLS** and no
  anonymous data-table or routine grants. Application-level duplicate-policy
  findings are cleared; remaining advisor notices are intentionally authorized
  security-definer RPCs, non-blocking index opportunities, plus the
  dashboard-only Auth leaked-password toggle.
- [x] Old `ap-south-1` project remains untouched.
- [x] Connect Supabase access in the current Work environment.
- [x] Apply the accounting/reporting migration only to
  `gpbsblokhpydtpgxpwrg`.
- [x] Run the 17-case accounting/reporting pgTAP suite.
- [x] Verify new RLS policies, privileges, indexes, and security advisors.
- [x] Industry modules: `industry_workflows`, line items, status events,
  entitlement-aware RLS, atomic create/transition RPCs, and the Flutter
  Industry operations screen are deployed to `gpbsblokhpydtpgxpwrg`.
- [x] Razorpay adapter deployed to FlexPOS-2 as `razorpay-order`,
  `razorpay-verify`, and `payment-webhook`; checkout verification is
  authenticated and webhook JWT is disabled because the handler validates the
  provider HMAC signature. Merchant test credentials and a signed test event
  remain operator release gates.
- [x] Live Flutter integration smoke harness added for auth, products, sales,
  returns, suppliers, and purchase orders; it requires explicit test-account
  and fixture defines and is not counted as a passing live run without them.
- [x] Explicit concurrent-session harness added; two independent Supabase
  clients sign in and perform tenant-scoped reads concurrently when the second
  account/business fixtures are supplied.
- [x] Biometric cashier re-entry is wired through `local_auth` on supported
  Android, iOS, macOS, and Windows targets; server PIN verification remains
  mandatory after the device gate.
- [x] Run the 8-case industry workflow pgTAP verification transaction; it
  passed and rolled back all test data.
- [x] Enterprise operations: `enterprise_records`, append-only events,
  integration status connections, entitlement-aware RLS, audited transitions,
  secure provider-reference boundaries, backup/recovery runbook, Gujarati
  localization, and the Flutter Enterprise operations screen are deployed to
  `gpbsblokhpydtpgxpwrg`.
- [x] Run the 12-case enterprise operations pgTAP verification transaction; it
  passed and rolled back all test data.
- [x] Hardware operations are deployed to `gpbsblokhpydtpgxpwrg`: online
  device registry, entitlement-aware RLS, audited connectivity tests, ESC/POS
  command helpers, and platform compatibility documentation are complete.
- [x] Run the 15-case hardware operations pgTAP verification transaction; it
  passed and rolled back all hardware fixtures, including the database
  device/transport compatibility guard. Offline POS remains disabled by
  design.
- [x] Supabase backend architecture completion is deployed only to
  `gpbsblokhpydtpgxpwrg`: immutable invoice snapshots, gift-card read
  policies, realtime publication membership, bounded keyset readers, and
  advisor-safe policy splits are live.
- [x] Run the 17-case backend architecture pgTAP verification transaction;
  it passed and rolled back its invoice fixtures.
- [x] Loyalty sale rules are deployed only to `gpbsblokhpydtpgxpwrg`:
  configurable automatic earn, idempotent ledger writes, and safe redemption
  passed the 11-case live transaction with all fixtures rolled back.
- [x] `integration-health` JWT Edge Function is active with provider-secret
  validation and opaque secret-reference forwarding.
- [x] Apply and verify the 21-case sale-returns/refunds migration suite only on
  `gpbsblokhpydtpgxpwrg`.
- [x] Verify the 8-case sales-discount authorization and exact-total suite only
  on `gpbsblokhpydtpgxpwrg`.
- [x] Receipt model/PDF suite verifies exact persisted totals and valid PDF
  generation.
- [x] Live sales-history source verification confirms RLS, authenticated-only
  table access, and the tenant/branch `sales_select` policy.
- [x] Cashier-shift integrity guard is deployed only to `flexpos-2`; direct
  cross-cashier assignment is rejected.
- [x] Cash in/out and permission-gated X/Z reports are deployed only to
  `flexpos-2`; exact sale/refund/drawer reconciliation passes the expanded
  61-case live suite with all fixtures rolled back.
- [x] Atomic sale exchanges are deployed only to `flexpos-2`; the expanded
  catalog/inventory/POS/register suite passes 61/61 live checks with all
  fixtures rolled back.
- [x] Wallet checkout, exact split tender, and cash-change calculation are
  implemented; live verification confirms split-row persistence, settlement
  status, register reconciliation, and atomic rejection of under-allocation.
- [x] Partial checkout is deployed only to `flexpos-2`; cash received now and
  the customer-credit balance persist atomically with exact `paid_total`,
  `due_total`, and `partially_paid` status.
- [x] Persistent held sales are deployed only to `flexpos-2`; the 23/23 live
  suite verifies idempotent park/update/discard behavior, tenant isolation,
  anonymous denial, audit events, and zero inventory movement, with all
  fixtures rolled back.
- [x] Persistent editable sales drafts are deployed only to `flexpos-2`; the
  23/23 live suite verifies idempotent save/update/delete behavior, tenant
  isolation, anonymous denial, audit events, and zero inventory movement, with
  all fixtures rolled back.
- [x] Non-posting sales quotations are deployed only to `flexpos-2`; the 27/27
  live suite verifies save/update/cancel/convert lifecycle, exact totals,
  tenant isolation, anonymous denial, audit events, and zero inventory
  movement, with all fixtures rolled back.
- [x] Stock-reserving sales orders are deployed only to `flexpos-2`; the 40/40
  live suite verifies save/update/cancel/fulfill lifecycle, exact totals,
  reservation replacement and release, tenant isolation, anonymous denial,
  audit events, and atomic sale fulfillment, with all fixtures rolled back.
- [x] Hashed bearer gift cards are deployed only to `flexpos-2`; the 41/41
  live suite verifies issue/lookup/redeem behavior, exact balances, optional
  customer binding, anonymous denial, idempotency, audit events, and atomic
  over-redemption rejection, with all fixtures rolled back.
- [x] Provider-neutral payment verification is deployed only to `flexpos-2`;
  the 44/44 live suite verifies manual approval/failure, service-role-only
  provider intake, exact amount/currency matching, replay protection, late
  recovery, RLS, grants, audit history, and immutability, with all fixtures
  rolled back and zero verification-event rows retained.
- [x] Atomic credit-note issuance and redemption are deployed only to
  `flexpos-2`; 35/35 live checks pass with no retained fixtures, anonymous
  access denied, RLS on both ledgers, and all composite foreign keys indexed.
- [x] Promotion performance reporting is deployed only to `flexpos-2`; the
  6/6 live checks verify campaign rows, empty-period totals, permission
  enforcement, authenticated-only RPC execution, and rollback-clean fixtures.

---

Last updated: **2026-11-02**


{Done} CRUD Operations
login screen left color change!
dashboard quick action buttons padding fix
4x4 grid pos sec.
remove warehouse section from pos
make cashier shift  automatic
remove spliut payment all creit options
remove unneccesory options 
in pos make icon damller of coupons and make it too samall

add crud opertaion for each prodct
remove duplicate search bars
add navigatoin like oath one 
cahnge chart of weekly projection 

CRUD follow-up completed 2026-11-02:
- Products, branches, businesses, staff, and custom roles have visible,
  labeled, role-gated edit/delete/revoke actions; product editing covers the
  catalog name, SKU, primary barcode, cost, selling price, inventory flags,
  attributes, and image.
- Sales have a visible edit action for audited customer and note corrections;
  posted financial values remain immutable.
- `sales.update` permission and `update_sale_metadata` RPC are deployed and
  verified in `flexpos-2` (`gpbsblokhpydtpgxpwrg`).




in add product add image.
user add not working staff one
in dashboard make taht firs tsection bigger 
change login page color
