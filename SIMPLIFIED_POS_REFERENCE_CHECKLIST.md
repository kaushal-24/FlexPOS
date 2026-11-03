# FlexPOS Simplified POS Reference Checklist

Status: **Planning only — no implementation requested yet**  
Created: **2026-11-01**  
Scope: Simplify FlexPOS UI/UX and functionality after the owner chooses what to keep or remove.

This checklist is intentionally undecided. Every item should be marked **Keep**,
**Remove**, or **Review later** before implementation begins.

## Reference repositories

- [ ] Review NexoPOS core patterns: products, categories, units, taxes, customers,
  POS sales, orders, payments, receipts, refunds, registers, inventory,
  procurement, stock history, low-stock workflows, reports, customer groups,
  rewards, coupons, roles, permissions, activity tracking, barcode support,
  media, dashboard widgets, and modular extensions.
- [ ] Review NexoPOS modular patterns separately from the core: restaurants,
  multi-store, service appointments, rentals, workforce, printing, PIN login,
  QR menu, raw materials, racks, hotel booking, commissions, and SaaS.
- [ ] Review `pos-app` patterns: product/category CRUD, cart, real-time totals,
  payment selection, fixed/percentage discounts, customer tracking, stock
  validation, search/filter controls, sales statistics, revenue reports,
  inventory overview, low-stock alerts, responsive layouts, and a compact admin
  panel.
- [ ] Review [Store-POS](https://github.com/tngoman/Store-POS) patterns: a
  focused till screen, barcode/search entry, category chips, product photos,
  cart quantity controls, hold/resume sales, cash payment flow, printable
  receipts, catalog and inventory screens, sales filters, staff permission
  flags, store/receipt settings, and a simple register-focused layout. Treat
  its Electron/Express/SQLite and LAN/standalone operating modes as reference
  material only; FlexPOS remains Supabase-backed and online-only.
- [ ] Decide which ideas are only UI/UX inspiration and which are appropriate for
  FlexPOS business rules.
- [ ] Review license obligations before copying code or assets: NexoPOS is GPL-3.0
  and `pos-app` is MIT. Review Store-POS authorship and licensing terms before
  copying any source code or assets.

## Owner decision legend

For each item below, choose one:

- [ ] **Keep** — part of the simplified FlexPOS product.
- [ ] **Remove** — hide/remove from the product plan.
- [ ] **Review later** — keep out of the first simplified release.

## 1. Product direction and scope

- [ ] Define the primary customer: small retail shop, café, restaurant, service
  business, or another focused segment.
- [ ] Define the smallest complete workflow: sign in → choose business → open
  POS → find product → take payment → print/download receipt.
- [ ] Define the secondary workflow: products → stock → customers → sales history
  → basic reports.
- [ ] Keep the application online-only; do not add offline queues or sync.
- [ ] Remove features that do not support the chosen primary workflow.
- [ ] Limit the first navigation to the smallest useful set of screens.

## 2. Simplified navigation and shell

- [ ] Keep a compact sidebar or bottom navigation with only essential routes.
- [ ] Keep: Dashboard.
- [ ] Keep: POS.
- [ ] Keep: Products.
- [ ] Keep: Inventory.
- [ ] Keep: Orders/Sales.
- [ ] Keep: Customers.
- [ ] Keep: Purchases/Suppliers.
- [ ] Keep: Reports.
- [ ] Keep: Settings.
- [ ] Review: CRM as a separate top-level route.
- [ ] Review: Accounting as a separate top-level route.
- [ ] Review: Promotions as a separate top-level route.
- [ ] Review: Registers as a separate top-level route.
- [ ] Review: Platform Admin/SaaS route.
- [ ] Remove or hide unfinished/rarely used navigation entries.
- [ ] Use one consistent page header, one primary action, and one filter row.
- [ ] Keep responsive layouts for phone, tablet, and desktop.
- [ ] Replace overly dense cards with clear tables/lists where appropriate.
- [ ] Remove duplicated “quick action” and “operational foundation” summaries.
- [ ] Keep visible loading, empty, error, permission, and success states.
- [ ] Keep keyboard shortcuts only where they speed up checkout.

## 3. Login, onboarding, business, and permissions

- [ ] Keep email/password sign-in.
- [ ] Keep account creation and email verification.
- [ ] Keep password reset and password update.
- [ ] Keep logout and guarded routes.
- [ ] Keep business onboarding.
- [ ] Keep business switching only if the owner needs multiple businesses.
- [ ] Keep branch selection only if the business has multiple locations.
- [ ] Keep warehouse selection only if inventory is warehouse-specific.
- [ ] Keep staff invitations.
- [ ] Keep simple roles: Owner/Admin, Manager, Cashier, and optional Accountant.
- [ ] Keep permission-gated CRUD and server-side authorization.
- [ ] Review custom role builder.
- [ ] Review granular permission matrix.
- [ ] Review platform-admin/SaaS administration.
- [ ] Review business device registration and revocation.
- [ ] Keep secure cashier PIN re-entry only if cashiers share a register.
- [ ] Keep audit log for security and money-changing actions.
- [ ] Remove unused tenant/business setup steps from the normal cashier flow.

## 4. Dashboard

- [ ] Keep today’s sales total.
- [ ] Keep transaction count.
- [ ] Keep low-stock count.
- [ ] Keep outstanding customer dues only if credit sales are retained.
- [ ] Keep a simple sales trend (today/week/month).
- [ ] Keep “Open POS” as the primary quick action.
- [ ] Keep “New product” as a secondary quick action.
- [ ] Keep “Adjust stock” as a secondary quick action.
- [ ] Review forecasts and projections.
- [ ] Review retention, ABC, dead-stock, and advanced KPI tiles.
- [ ] Remove decorative status cards that do not lead to an action.
- [ ] Remove duplicate operational-foundation progress panels.

## 5. POS and checkout

- [ ] Keep product search by name, SKU, and barcode.
- [ ] Keep camera barcode scanning where the device supports it.
- [ ] Keep USB/Bluetooth keyboard-wedge scanner input.
- [ ] Keep category filters.
- [ ] Keep favorites only if they improve checkout speed.
- [ ] Keep product images in the product grid and cart where useful.
- [ ] Keep add-to-cart, quantity changes, remove line, and line notes.
- [ ] Keep customer selection, including walk-in customer.
- [ ] Keep exact tax and total calculation.
- [ ] Keep cash checkout and change calculation.
- [ ] Keep UPI QR checkout with fixed amount and Success/Failed confirmation.
- [ ] Keep Razorpay Checkout only if a real gateway is required.
- [ ] Keep customer credit only if the business sells on credit.
- [ ] Keep credit-note payment only if returns create credit notes.
- [ ] Review split payment.
- [ ] Review partial payment.
- [ ] Review coupons.
- [ ] Review service charges.
- [ ] Review cash rounding.
- [ ] Review authorized price overrides.
- [ ] Review held carts.
- [ ] Review drafts.
- [ ] Review quotations.
- [ ] Review stock-reserving sales orders.
- [ ] Remove payment methods the owner does not use.
- [ ] Remove gift cards if not required.
- [ ] Remove wallet/card/bank-transfer options if not required.
- [ ] Keep a single obvious “Complete sale” action.
- [ ] Keep a clear payment confirmation state before finalizing a sale.
- [ ] Keep sale idempotency and duplicate-submit protection.
- [ ] Keep receipt preview after successful checkout.

## 6. Products and catalog

- [ ] Keep product/service create, view, edit, delete, and restore workflow.
- [ ] Keep product name, SKU, selling price, cost, tax, and active status.
- [ ] Keep one or more product images with visible thumbnails.
- [ ] Keep categories.
- [ ] Keep brands only if the business uses brands.
- [ ] Keep units.
- [ ] Keep product variants only if size/color/model options are needed.
- [ ] Keep multiple barcodes only if variants require them.
- [ ] Keep HSN/SAC only if required for local tax invoices.
- [ ] Keep configurable low-stock threshold per product/warehouse.
- [ ] Keep customer/group pricing only if needed.
- [ ] Review bundles/kits.
- [ ] Review unit conversions.
- [ ] Review bulk price editing.
- [ ] Review CSV import/export.
- [ ] Remove unused custom attributes.
- [ ] Remove catalog fields that are never shown or used at checkout.
- [ ] Use one simple product form instead of several overlapping dialogs.
- [ ] Use a clear product list with search, status, category, and stock columns.

## 7. Inventory

- [ ] Keep stock by warehouse.
- [ ] Keep stock adjustment with reason.
- [ ] Keep opening stock setup.
- [ ] Keep purchase receiving.
- [ ] Keep sales/return stock movement history.
- [ ] Keep low-stock alerts.
- [ ] Keep stock transfer only for multi-warehouse businesses.
- [ ] Review stocktakes.
- [ ] Review reservations.
- [ ] Review batches and expiry.
- [ ] Review FEFO allocation.
- [ ] Review serial/IMEI tracking.
- [ ] Review inventory valuation methods.
- [ ] Review dead-stock and ABC analysis.
- [ ] Remove inventory modes that do not match the chosen industry.
- [ ] Make stock quantity and threshold status understandable at a glance.

## 8. Orders, returns, and receipts

- [ ] Keep searchable sales/order history.
- [ ] Keep order detail with items, totals, payment, cashier, and timestamp.
- [ ] Keep full and partial returns where required.
- [ ] Keep refund workflow appropriate to the payment method.
- [ ] Keep exchange workflow only if the business needs exchanges.
- [ ] Keep receipt reprint/download.
- [ ] Keep small thermal receipt output (58/80 mm).
- [ ] Keep configurable invoice prefix, tax ID, footer, logo, and QR payload.
- [ ] Review A4 invoice output.
- [ ] Review multiple receipt templates.
- [ ] Remove unused order states and duplicated receipt actions.

## 9. Customers and CRM

- [ ] Keep customer create, view, edit, delete, and search.
- [ ] Keep phone/email/address fields only when operationally useful.
- [ ] Keep purchase history.
- [ ] Keep customer balance/dues only if credit sales remain.
- [ ] Keep customer groups only if group pricing is used.
- [ ] Review loyalty ledger and rewards.
- [ ] Review CRM leads.
- [ ] Review CRM opportunities.
- [ ] Review CRM quotations.
- [ ] Review follow-ups, notes, and reminders.
- [ ] Remove CRM features if FlexPOS is primarily a checkout/inventory product.
- [ ] Keep supplier profiles and supplier search.

## 10. Purchasing and suppliers

- [ ] Keep supplier create, edit, delete, and search.
- [ ] Keep purchase order only if formal ordering is needed.
- [ ] Keep goods receiving and stock increase.
- [ ] Keep supplier invoice tracking only if payables are used.
- [ ] Keep supplier payment status only if payables are used.
- [ ] Review purchase requisitions and approvals.
- [ ] Review landed costs.
- [ ] Review supplier returns.
- [ ] Remove procurement workflows that are too complex for the target business.

## 11. Accounting, tax, and expenses

- [ ] Keep tax rates and inclusive/exclusive tax handling.
- [ ] Keep expense categories.
- [ ] Keep simple expense entry with attachment if needed.
- [ ] Keep customer credit/repayment records only if credit sales remain.
- [ ] Keep daily sales, tax, expenses, and profit summaries.
- [ ] Review full chart of accounts.
- [ ] Review fiscal-year management.
- [ ] Review journal entries.
- [ ] Review bank reconciliation.
- [ ] Review tax adjustment notes.
- [ ] Review recurring expenses.
- [ ] Review statutory filing workflows.
- [ ] Remove accounting screens that are not needed by the owner or accountant.
- [ ] Keep immutable history and reversal actions for posted financial records.

## 12. Reports and analytics

- [ ] Keep sales by day/week/month.
- [ ] Keep top products.
- [ ] Keep payment totals.
- [ ] Keep tax summary.
- [ ] Keep stock and low-stock report.
- [ ] Keep customer dues report if credit is enabled.
- [ ] Keep supplier payable report if purchasing invoices are enabled.
- [ ] Review profit forecast.
- [ ] Review retention analysis.
- [ ] Review ABC/dead-stock analysis.
- [ ] Review register-performance analysis.
- [ ] Review export formats.
- [ ] Remove reports that cannot be understood or acted on by the target user.
- [ ] Use consistent date range, business, branch, warehouse, and export controls.

## 13. Promotions and loyalty

- [ ] Keep fixed and percentage discounts if needed.
- [ ] Keep coupon codes only if actively used.
- [ ] Review scheduled promotions.
- [ ] Review customer-group promotions.
- [ ] Review loyalty points and rewards.
- [ ] Remove promotions/loyalty if they add complexity without business value.

## 14. Industry-specific modules

- [ ] Decide the primary industry before keeping any specialized workflow.
- [ ] Review restaurant tables, modifiers, kitchen routing, and kitchen display.
- [ ] Review grocery/scale barcode and weighted products.
- [ ] Review pharmacy batches, expiry, and regulated fields.
- [ ] Review fashion variants and size/color matrix.
- [ ] Review electronics serial/IMEI tracking.
- [ ] Review salon/service appointments and staff scheduling.
- [ ] Review repair/service jobs.
- [ ] Review manufacturing recipes/raw materials.
- [ ] Review hotel/rental reservations.
- [ ] Remove all industry modules not used by the chosen target business.
- [ ] Keep industry modules modular so the core POS stays simple.

## 15. Hardware and printing

- [ ] Keep camera barcode scanner.
- [ ] Keep USB/Bluetooth HID scanner.
- [ ] Keep small receipt printer output.
- [ ] Review cash drawer integration.
- [ ] Review label printer integration.
- [ ] Review weighing-scale integration.
- [ ] Review customer display.
- [ ] Remove hardware setup screens for devices the business will not use.
- [ ] Keep clear hardware diagnostics only for enabled devices.

## 16. Backend, security, and data rules

- [ ] Keep Supabase Auth and tenant isolation.
- [ ] Keep RLS on every tenant-owned table.
- [ ] Keep role-aware CRUD checks in the client and database/RPC layer.
- [ ] Keep audit events for sales, refunds, stock adjustments, permissions, and
  settings changes.
- [ ] Keep immutable posted sales, journals, ledgers, and stock movement history.
- [ ] Keep idempotency for sale, payment, purchase, and stock operations.
- [ ] Keep no secrets in Flutter or client configuration.
- [ ] Keep online-only behavior; no offline transaction queue.
- [ ] Remove backend tables and APIs for features marked Remove after approval.

## 17. UI/UX simplification pass

- [ ] Define a compact color, typography, spacing, and icon system.
- [ ] Use one primary button style and one destructive action style.
- [ ] Make touch targets at least 44 px where practical.
- [ ] Remove nested scroll views that cause overflow.
- [ ] Make tables responsive with mobile card fallback.
- [ ] Keep product images large enough to identify products quickly.
- [ ] Keep concise labels; remove repeated helper text.
- [ ] Make all dropdowns, dialogs, and bottom sheets fit short screens.
- [ ] Use inline validation before submit.
- [ ] Use consistent confirmation dialogs for destructive actions.
- [ ] Use consistent snackbars/toasts for success and failure.
- [ ] Keep skeleton loading and useful empty states.
- [ ] Keep keyboard and camera scanner focus behavior obvious.
- [ ] Test light mode and dark mode.
- [ ] Test narrow phone, tablet, desktop, and browser zoom.
- [ ] Test keyboard navigation and text scaling.
- [ ] Remove decorative content that does not help a cashier or owner act.

## 18. Testing and approval gates before implementation

- [ ] Owner marks every item Keep, Remove, or Review later.
- [ ] Confirm the final navigation map.
- [ ] Confirm the final payment methods.
- [ ] Confirm whether CRM is included.
- [ ] Confirm whether accounting is basic or advanced.
- [ ] Confirm the primary industry and any required module.
- [ ] Confirm receipt format: thermal only, A4 only, or both.
- [ ] Confirm camera scanner and physical scanner targets.
- [ ] Confirm which roles are needed.
- [ ] Confirm which reports are required for daily operations.
- [ ] Confirm which data must remain immutable.
- [ ] Approve a simplified wireframe before code changes.
- [ ] Approve a feature-removal list before deleting or hiding anything.
- [ ] After approval, update the main development checklist with the accepted
  scope; do not implement from this planning file until decisions are recorded.

## Current FlexPOS reference scope

The current implementation already contains substantially more than a minimal
POS, including multi-tenant permissions, catalog and inventory controls, POS
checkout, UPI/Razorpay flows, customers, CRM, purchasing, accounting, reports,
promotions, receipts, hardware adapters, industry workflows, and enterprise
administration. This file is a decision checklist for simplifying that scope;
it does not claim that every item above should remain.

