# PROMPT: Evolve FlexPOS to Surpass Zobaze POS

You are an expert Flutter + Supabase POS engineer. Your sole objective is to evolve this FlexPOS codebase into a product that is faster, cleaner and more powerful than Zobaze POS whilst preserving all of its existing correctness and security guarantees. 

Do not implement offline-first functionality. Focus purely on UX, speed, features and polish. 


## Project Context
This is FlexPOS, a multi-tenant POS and business management app. 

### Tech Stack
- Framework: Flutter (Dart ^3.13.5), Material 3
- State Management: flutter_riverpod ^3.4.3
- Routing: go_router ^18.1.0
- Backend: Supabase (Postgres + Auth + RLS), specifically project `flexpos-2` (gpbsblokhpydtpgxpwrg)
- Utils: intl, pdf, printing, shared_preferences
- Architecture: Feature based (`lib/features/*`) with `lib/core/`, `lib/app/` and `lib/shared/`

### Existing Strengths To Preserve
- Multi-tenant architecture with strict RLS on all tables.
- Permission gated actions (e.g `sales.create`, `sales.discount`) enforced on both the client and server.
- Integer minor-unit money math (do not switch to doubles for money). All totals are authoritative server side via RPCs.
- Atomic, idempotent checkout with stock locking and immutable ledgers (inventory movements, refunds, repayments).
- Robust features already implemented: Products/Variants, Inventory, POS, Customers, Suppliers/PO's, Goods Receipts, Returns, Discounts, Customer Credit (FIFO), Expenses, DB aggregated reports, Receipts (PDF/Print/Share), Theming, Auth flows.
- pgTAP test suites for all major flows that rollback test data.
- Only the publishable Supabase key in the client, NEVER a service role key. 


### Current Weaknesses To Fix
Look at `lib/features/pos/presentation/pos_page.dart` to understand the current register. Zobaze's advantage is purely speed of sale and simplicity for a cashier. Your mission is to outclass this. 


---


## Goal
Transform this app to feel like Zobaze POS but better. Prioritize the cashier experience first, as that's what drives daily usage. Every change must feel snappier, require fewer clicks and be more obvious to a non-technical shopkeeper. 


---


## Implementation Priorities

### 1) Re-Engineer The Register (Highest Priority)
This is the make or break difference between the two apps. Overhaul `lib/features/pos/` whilst keeping `completeSale` RPC contract intact unless absolutely necessary, and if changed, update all call sites and tests.

Requirements:
- **Split layout**: On >= 900 width have a product/catalog pane (left) and a persistent cart pane (right, ~380-420px). On mobile have a tab/swipe between "Products" and "Cart" with a cart summary bar (item count + total) that is always visible and can be tapped to checkout.
- **Categorization**: Add category tabs/chips above the product grid. Filter products by category with instant filtering. Also allow filtering by brand if present.
- **Speed access**: Add "Favorites" (star a product, persisted per user/business) and "Recent" (last sold products in this register/business) sections at the top of the catalog when not searching.
- **Smarter grid**: Increase touch targets, show product image placeholder if none exists, price, stock status (In stock / X left / Out of stock) and make out of stock un-tappable with feedback. Use a denser grid on desktop, larger cards on tablet.
- **Search**: Upgrade search to be instant, fuzzy to SKU/name/barcode and prioritize barcode matches. Keep existing `searchText` logic but improve it. 
- **Variant selection**: If a product has variants, tapping it must open a bottom sheet/modal to select variant (with price, stock and SKU) instead of auto-selecting the first variant. Do not clutter the grid with every variant.
- **Barcode**: Integrate camera based barcode scanning (e.g `mobile_scanner`). On scan, add the matched variant to cart or open variant selector if ambiguous. Also support hardware keyboard wedge scanners (focus an input and parse scans). Add a "Scan" FAB/button in the register. 


### 2) Checkout Flow & Payments (High Priority)
Improve the cart pane (`_CartPane`) drastically whilst keeping the calculation pipeline (`calculatePosTotals`) as the source of truth for line/subtotal/tax/discount/total. 

Requirements:
- **Cart UX**: Show product image, variant name, price per unit, line total, quantity stepper (+/-) with long press to edit quantity manually. Allow removing items. Clearing cart must have a confirmation. 
- **Hold/Park orders**: Implement "Hold Sale". Persist held carts per business/branch/register (create new tables via migration if needed e.g `pos_held_sales` with items as JSONB or normalized). Allow viewing "Held Sales" (list with time, customer, item count, total), resume (loads back into cart, removes from held), and delete. This is expected to be at feature parity with Zobaze.
- **Customer**: Make customer selection faster. Allow quick add customer from the cart (name + phone minimum) without leaving the register. Show outstanding credit balance if customer credit is selected and enforce limits with clear messaging (your existing checks are good, improve UI).
- **Discounts**: Keep permission check `sales.discount`. Improve the discount modal to be quicker (preset percentages e.g 5%,10%,15%, custom % or fixed amount). Show discount applied clearly on cart with ability to edit/remove in one tap.
- **Payments**: Keep existing methods, but add **split payment**. Allow paying with multiple methods (e.g Cash + UPI) until total is covered. Track amounts per method, validate sum == total, and send this breakdown to the checkout flow. Update the RPC or its payload to accept split payments if possible, otherwise add a new secure RPC that is idempotent and preserves atomicity. Do not break existing single payment method checkout.
- **Quick cash**: For cash payments add quick amount buttons (Exact Amount, +10, +50, +100, +500, Custom). Auto-focus amount input and show change due.
- **Checkout confirmation**: After `completeSale`, improve the success dialog. Always show invoice number, total, payment status and have prominent "View Receipt" and "New Sale" actions. Keep the receipt dialog flow intact.
- **Validation**: Prevent checkout with $0 total, insufficient stock (you already enforce, make errors clearer), and invalid split payments. 


### 3) Products, Inventory & Pricing (High Priority)
Leverage existing catalog models but improve workflows.

Requirements:
- **Product management UX**: Polish product/variant creation. Make it faster to add variants, barcodes (multiple), prices, tax, track inventory toggle. 
- **Barcode management**: Allow adding/removing barcodes from product screen and ensure search/scanner uses them.
- **Stock visibility**: In POS and product lists show warehouse aware stock. Add low stock indicators in catalog grid and a "Low stock" filter.
- **Units**: If the schema allows, improve unit handling in UI. Don't redesign the schema unless necessary, adapt to what exists.
- **Price lists**: Only add if trivial and doesn't overcomplicate. Do not do this at the cost of register speed.


### 4) Customers, Khata & Credit (High Priority)
Zobaze's "Khata" is extremely simple. Make this more approachable than it currently is.

Requirements:
- **Khata home**: Create a dedicated, simple Khata screen (list of customers with balance due/credit, last transaction date, search). One tap to view ledger.
- **Ledger UX**: Customer statement should be scannable (Date, Type (Sale/Payment/Adjustment), Amount, Balance). Make "Add Payment" (repayment) frictionless with amount presets and notes.
- **Credit enforcement**: Improve messaging in POS when credit limit is hit/exceeded (show limit, current balance, remaining). Keep server enforcement as source of truth.
- **Quick actions**: From POS and Khata allow collecting payment against outstanding credit with minimal inputs.


### 5) Dashboard, Reports & Business Overview (High Priority)
Replace or augment the dashboard to show actionable info at a glance (like Zobaze's home).

Requirements:
- **Today summary**: Cards for Today's Sales (amount + count), Cash collected, Outstanding Credit, Low Stock count. All derived from existing data sources where possible.
- **Recent sales**: Quick access to recent orders with ability to reprint/view receipt.
- **Shortcuts**: Big, tappable shortcuts to POS, Add Product, Khata, Reports.
- **Reports polish**: Improve the existing DB aggregated reports UI (Sales, Tax, Expenses, Profit, Payments, Stock). Make them filterable by date range (today/week/month/custom) and branch/warehouse where applicable. Prioritize readability and exportability where it already exists.
- **Expenses**: Make adding an expense faster from dashboard/expenses screen with common categories.


### 6) Staff, Roles & Settings Polish (Medium-High)
- **Role UI**: Simplify permission assignment with grouped toggles (Sales, Inventory, Purchases, Reports, Administration) whilst keeping granular permission codes intact. Do not remove any permission.
- **Register/Branch clarity**: Make switching business/branch/warehouse/register obvious and frictionless.
- **Receipts settings**: Expose receipt customization already supported by `receipts/` (store details) in an easy settings screen.
- **Thermal printing**: Improve `printing` integration for common thermal printers. Add printer selection, test print, and paper size (58mm/80mm). If possible add basic ESC/POS direct print support for Bluetooth printers without breaking existing PDF print/share flow. Make this opt-in and resilient. 


### 7) UI/UX, Performance & Polish
- **Design system**: Lean more into a clean, modern retail look. Use consistent spacing, elevation, larger buttons for cart actions, and clear hierarchy. Keep Material 3.
- **Responsiveness**: Flawless on phone (portrait), tablet, desktop and web. Test the responsive breakpoints used by POS.
- **Speed**: Avoid unnecessary rebuilds, paginate large lists, use efficient filtering. Keep provider usage idiomatic with Riverpod.
- **Empty states**: Improve all empty states with actionable CTAs.
- **Feedback**: Use snackbars, loading indicators and optimistic UI only where safe (never for money/stock mutations). 
- **Localization**: Respect `l10n.yaml` and existing `AppLocalizations`. Add strings for new features.
- **Theming**: Keep light/dark/system themes working.


---


## Technical Constraints & Rules
- **Money**: ALWAYS use integer minor units. Never use `double` for currency calculations. Use existing `money.dart` utilities.
- **Backend integrity**: Money and stock mutations must remain server authoritative. Prefer using existing RPCs (`completeSale` etc). If you must add new RPCs, write them as idempotent, transaction safe PostgreSQL functions with proper RLS and tenant scoping. Put migrations in `supabase/migrations/` with the existing timestamped naming convention.
- **Security**: Never add a service role key. Enforce permissions on client (hide/disable) and never rely on it alone. Maintain RLS. No anonymous access to sensitive data.
- **Architecture**: Follow the existing feature-first structure. Put models in `domain/`, repos/providers in `data/`, UI in `presentation/`. Reuse `core/widgets` (`AppPanel`, `EmptyState` etc).
- **State**: Use Riverpod. Invalidate relevant providers after mutations (`catalogSnapshotProvider`, `salesProvider`, etc) as done currently.
- **Routing**: Use existing `app_router.dart`. Add routes for new screens (Hold Sales, Khata, etc) in a consistent manner.
- **Config**: Keep the `--dart-define-from-file=config/dev.json` pattern. Don't hardcode Supabase credentials.
- **Tests**: Do not remove existing pgTAP tests. If you change DB functions, update/add pgTAP tests in `supabase/tests/`. For Flutter, add widget tests for critical POS flows (cart calculations, discounts, split payments) where reasonable. Ensure `flutter analyze` and `flutter test` pass.
- **No offline-first**: Ignore any offline caching/sync queue requirements. Assume online connectivity.
- **Migrations**: Only modify the `flexpos-2` project patterns. Never touch `ap-south-1` references.
- **Dependencies**: Only add dependencies if necessary and well maintained (e.g `mobile_scanner` for barcode). Check pubspec before adding.


---


## Implementation Plan
Execute in this order to avoid regressions:

1. **Audit**: Read `pos_page.dart`, `catalog_models.dart`, `pos_calculations.dart`, `catalog_repository.dart`, router, and relevant migrations to fully understand the checkout flow and data model.
2. **Register UX**: Redesign POS layout, categories, favorites/recent, variant selector, barcode scanning foundation.
3. **Cart & Checkout**: Hold/park orders, split payments, quick cash, improved validation and success flow.
4. **Khata & Customers**: New Khata screen + frictionless repayments + credit UX.
5. **Dashboard**: Actionable home with today's summary and shortcuts.
6. **Polish**: Printing, staff UI, reports, theming, performance passes.
7. **Verify**: Run `flutter gen-l10n`, `flutter analyze`, `flutter test`. Review migrations and pgTAP if changed.


---


## Success Criteria
- **Faster billing**: Adding a product + checkout should feel noticeably faster than current implementation. Fewer taps for common flows.
- **Zobaze parity + better**: Has hold orders, barcode scanning, split payments, quick cash, category navigation, favorites/recent, and a proper Khata. 
- **Polished**: The register looks cleaner and more modern than Zobaze without feeling cluttered.
- **Correct**: All money/stock still go through server enforcement. No regressions in existing tests. RLS untouched in a way that weakens security.
- **Production ready**: Handles edge cases gracefully, responsive, and doesn't introduce new bugs to existing features (returns, discounts, credit, reports).


## Final Instructions
- Be surgical but ambitious. Prioritize the register and checkout above everything else.
- Match the codebase style (naming, formatting, patterns). Don't refactor unrelated code.
- Explain major architectural decisions in code comments only if necessary, but prefer self-documenting code. 
- If a feature would require weakening security/correctness to implement, find a secure alternative or don't implement it.
- Your output should be a fully working implementation that makes this app feel like the superior version of Zobaze POS.

flutter run --dart-define-from-file=config/dev.json
flutter run --dart-define-from-file=config/dev.json

pithvakaushal24@gmail.com
FlexPOS2!K7vR4mQ9xT6nL3pZ8

<!-- Q8!vN4#tR2@kM7$zP5xL -->

flutter run -d chrome --web-port 0 --dart-define-from-file=config/dev.json
flutter run --dart-define-from-file=config/dev.json