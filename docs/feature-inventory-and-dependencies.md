# FlexPOS feature inventory and dependency report

Snapshot date: **2026-10-30**

This report describes the implemented source tree and its known release gaps. It
is not a claim that every item in `MASTER_DEVELOPMENT_CHECKLIST.md` is complete.
The only backend in scope is Supabase project `flexpos-2`
(`gpbsblokhpydtpgxpwrg`, Sydney `ap-southeast-2`). The older `FlexPOS` project in
`ap-south-1` is excluded.

## Implemented application inventory

| Domain | Implemented scope |
| --- | --- |
| Foundation | Flutter feature-first application, Riverpod state, GoRouter routes, Material 3 light/dark/system themes, localization foundation, responsive mobile/tablet/desktop shell, shared design/motion tokens, skeleton states, audited accessibility primitives, repository substitution contracts, stable server-page cursors, and shared searchable/sortable/paginated data-list controls with domain-safe bulk actions. |
| Authentication | Supabase email/password registration and sign-in, verification resend, password recovery/update, logout, PKCE sessions, and guarded routes. |
| Tenancy and access | Business onboarding/switching, branches, warehouses, memberships, staff invitations, branch access, custom roles, granular permissions, RLS, trusted RPC checks, audit events, server-enforced platform-admin overview, business device registration/revocation, and rate-limited cashier PIN verification. |
| Catalog | Products/services, categories, brands, units, variants, SKU, multiple stored barcodes, HSN/SAC, cost/MRP/selling prices, favorites, product creation/search, private product images with signed URLs, JSON custom attributes, unit-conversion definitions, bundle/kit components, CSV import/export, and permission-gated bulk edits. |
| Inventory | Tenant/branch/warehouse balances, opening stock, adjustments, immutable movements, negative-stock prevention, reserved/available quantities, reorder fields, sale/return/purchase movements, serial/IMEI, batches/expiry, FEFO allocation, transfers, stocktakes, valuation methods, stock alerts, dead-stock and ABC analysis. |
| POS | Product/SKU/barcode/category search, camera barcode/QR scanning on supported web and mobile/desktop Apple targets, keyboard-wedge scanning, favorites, cart quantities, custom service items, exact tax/totals, fixed/percentage order discounts, permission-gated fixed service charges, configurable cash rounding, coupons, authorized per-line price overrides, customer-specific/group pricing, customer selection, held carts, drafts, quotations, stock-reserving sales orders, keyboard shortcuts, and atomic idempotent checkout. |
| Payments | Cash, manual UPI QR for `kaushal.pithva@ptaxis`, Razorpay Standard Checkout (test/live key configured server-side), customer credit, credit notes, exact split tender, partial payment, cash change, pending external-tender states, checkout signature verification, and permission-gated reconciliation evidence. |
| Orders and after-sales | Server-filtered sales history, persisted receipt access, partial/full returns, cash refunds, atomic exchanges, immutable credit notes, payment status, and conversion links for quotations/orders. |
| Customers | Profiles, contact/tax/address fields, credit limits, purchase history, refund-aware spend, customer groups, group/direct pricing, customer statements, dues, FIFO repayments, and an idempotent loyalty ledger. |
| CRM | Tenant-scoped leads, opportunities, quotations, follow-ups, notes, reminders, pipeline views, list controls, completion actions, and salesperson attribution. |
| Purchasing | Supplier profiles, multi-line purchase orders, authoritative totals, partial/final goods receipts, idempotency, over-receipt prevention, stock increases, average-cost updates, requisitions and approvals, supplier invoices, landed-cost allocation, supplier returns, payment tracking, and payable statements. |
| Registers | Register creation, shift open/close, opening/closing cash, blind count, cash in/out with reasons, X/Z reports, over/short reconciliation, and POS shift linkage. |
| Accounting/reporting slice | Expense categories, idempotent expense entry, immutable reversal, customer ledger, gross/net sales, tax, expense, gross profit, settled-payment, daily-series, receivable, stock, retention, forecast, supplier, and register-performance reporting. |
| Receipts | Reconstruction from persisted sales, business-configured invoice prefix/tax ID/footer, classic/minimal/detailed template setting, private business logo assets, QR payload storage/rendering, transparent FlexPOS branding in PDF/preview, adaptive PDF generation, A4 and 58/80 mm output, preview, save/download, system print, and order-history reprint. |

Primary UI routes are `/dashboard`, `/pos`, `/products`, `/catalog-management`, `/inventory`,
`/orders`, `/customers`, `/purchases`, `/expenses`, `/reports`, `/registers`,
`/promotions`, `/access-control`, `/branches`, `/business-settings`, and
`/platform-admin`, plus
the Auth, onboarding, and invitation routes.

## Backend inventory

- 142 ordered SQL migration files under `supabase/migrations`; 137 migration
  records are present in the live project's migration history. The known
  bootstrap/renamed-history drift is documented in
  `supabase/migrations/README.md` and must not be replayed blindly.
- 22 pgTAP suites under `supabase/tests`, including invoice/keyset and
  automatic-loyalty coverage.
- 14 typed repositories behind a shared substitution contract, bounded keyset
  page readers for sales/products, and a deterministic 100,000-row local
  performance profile under `tool/performance_profile.dart`.
- PostgreSQL `NUMERIC` storage and integer minor-unit calculations in Flutter
  for implemented monetary paths.
- RLS, tenant ownership, permission checks, constraints, indexes, immutable
  ledgers, idempotency records, and transaction-safe RPCs for completed domains.
- Data API access through `supabase_flutter`; no Firebase or separate custom
  application server.
- The JWT-protected `integration-health` Edge Function validates integration
  status/configuration and forwards opaque provider references to the audited
  integration RPC. Provider-specific adapters and webhooks remain intentionally
  outside the client and require operator-owned secrets.

The current verified local baseline is 113/113 Flutter tests after the
engineering-quality and tax/discount coverage additions. Analyzer exit code is
0 with no errors (info-level lint/deprecation notices remain visible). A
successful Web release build and fresh Android release-mode APK are also
recorded. The existing APK uses the debug signing fallback unless a private
upload key is configured, so it is a validation artifact rather than a
distributable release.

## Direct Dart and Flutter dependencies

Versions below are the declared constraints in `pubspec.yaml`, not a promise that
future package resolution will select the same transitive graph.

| Dependency | Declared version | Purpose and external effect |
| --- | --- | --- |
| Flutter SDK | SDK | Cross-platform UI, rendering, platform integration, localization generation, and build tooling. |
| `flutter_localizations` | SDK | Flutter-provided localization delegates and locale data integration. |
| `cupertino_icons` | `^1.0.8` | Bundled Cupertino icon font; no network service. |
| `flutter_riverpod` | `^3.4.3` | Dependency injection and reactive application state; no network service. |
| `go_router` | `^18.1.0` | Declarative application routing and Auth guards; no network service. |
| `supabase_flutter` | `^2.18.3` | Supabase Auth session handling and HTTPS Data API/RPC access to `flexpos-2`. |
| `shared_preferences` | `^2.5.6` | Local non-sensitive preferences such as theme/workspace selection; it is not an encrypted offline transaction store. |
| `intl` | `^0.20.3` | Locale-aware dates, numbers, and currency display; no network service. |
| `pdf` | `^3.13.1` | In-process receipt/invoice PDF generation; no network service. |
| `printing` | `^5.15.1` | Platform print dialogs, preview, and PDF generation; behavior depends on installed OS print services. |
| `file_picker` | `^13.1.0` | User-granted file selection for receipt PDFs and catalog CSV/image import/export. |
| `mobile_scanner` | `^7.4.2` | Camera barcode/QR capture on Android, iOS, macOS, and supported web browsers; requires camera permission and a device/browser camera. |
| `qr_flutter` | `^4.1.0` | In-app UPI payment QR rendering; the payload contains the configured UPI address, amount, currency, and FlexPOS transaction reference. |
| `local_auth` | `^3.0.2` | Device biometric gate before cashier PIN re-entry on supported Android, iOS, macOS, and Windows targets; it never replaces server-side PIN verification. |
| `flutter_test` | SDK, dev only | Flutter unit/widget test framework; not shipped as an application service. |
| `flutter_lints` | `^6.0.0`, dev only | Static-analysis rules; not included as a runtime service. |

## Build and platform toolchains

| Target | Toolchain/status |
| --- | --- |
| Dart | SDK constraint `^3.13.5`. |
| Android | Android Gradle Plugin 9.1.0, Kotlin 2.4.0, Gradle 9.3.1, Java/JVM 17, Flutter-managed compile/min/target SDK values. Permanent application ID and private upload signing are release gates. |
| Web | Flutter web static bundle. Requires HTTPS hosting, Auth redirect configuration, and route fallback for recovery/deep links. |
| Windows | Flutter Windows runner plus Visual Studio C++ desktop toolchain. Release build remains unverified until Windows Developer Mode enables plugin symlinks. |
| iOS/macOS | Flutter targets exist, but release builds/signing are unverified because supported Apple hardware is required. |
| Linux | Flutter target exists; no production packaging or compatibility verification is recorded. |

## Required external systems

| System | Required? | Data/secret boundary |
| --- | --- | --- |
| Supabase Postgres, Auth, and Data API | Required | Client receives only the exact project URL and publishable key. RLS and trusted RPCs enforce authorization. Database passwords and service-role/secret keys must stay outside the client. |
| Production SMTP provider | Required for reliable public Auth email | SMTP credentials stay in Supabase Auth settings, not Flutter. Sender DNS should use SPF, DKIM, and DMARC. |
| Static web host | Required for web distribution | Receives the compiled `build/web` bundle. Must use HTTPS and serve the Flutter entry point for Auth/deep-link paths. |
| Google Play or equivalent Android channel | Required only for managed Android distribution | Receives the privately signed AAB. Upload key and Play app-signing identity stay outside source control. |
| Windows packaging/code-signing service | Required only for trusted Windows distribution | Receives the complete Release directory/installer. Code-signing keys stay outside source control. |
| OS printing and share services | Required for physical printing/sharing | Invoked through the `printing` plugin; printer drivers and compatibility are deployment responsibilities. |
| Payment gateways | Razorpay Standard Checkout plus webhook reconciliation integrated on FlexPOS-2 | `razorpay-order` creates tenant-linked orders, `razorpay-verify` verifies the checkout signature and re-reads Razorpay, and `payment-webhook` verifies raw-body HMAC signatures for asynchronous events. Test credentials and webhook secret are operator configuration; no provider secret belongs in Flutter. |

No Firebase dependency, custom application backend, analytics SDK, crash-reporting
SDK, SMS/WhatsApp provider, tax-service adapter, AI-provider adapter, or CI/CD
workflow is present.

## Configuration and secret matrix

| Value | Client/build input | Privileged secret | Storage location |
| --- | --- | --- | --- |
| `APP_NAME` | Yes | No | Ignored Dart-define JSON or build command. |
| `SUPABASE_URL` | Yes | No | Ignored Dart-define JSON; must equal the `flexpos-2` URL. |
| Supabase publishable key | Yes | No, but project-scoped | Ignored Dart-define JSON and compiled client; security still depends on RLS. |
| Service-role/secret key | Never | Yes | Trusted server/secret manager only; no current Flutter use. |
| Database password/access token | Never | Yes | Operator secret manager/CLI session only. |
| SMTP credentials | Never | Yes | Supabase Auth SMTP settings/approved secret store. |
| Android upload key/passwords | Build only | Yes | Private keystore and ignored `android/key.properties`; back up securely. |
| Payment/webhook secrets | Never | Yes | Supabase Function secrets `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, and (for asynchronous reconciliation) `RAZORPAY_WEBHOOK_SECRET`. |

## Materially incomplete areas

The master checklist remains the authoritative item-by-item backlog. The largest
open groups are:

- offline catalog/queue/synchronization and conflict recovery (intentionally
  excluded; FlexPOS requires authenticated online connectivity);
- physical camera runtime validation, native serial/SDK scanner adapters,
  thermal printer, cash drawer, label printer,
  scale, customer display, and physical device validation;
- full general ledger, accounts payable/receivable integration, statutory tax
  workflows, fiscal closing, and complete financial statements;
- advanced pricing beyond the implemented discounts, coupons, price overrides,
  customer pricing, service charges, and cash rounding;
- provider-specific CRM/tax adapters, statutory filing, and advanced
  report/export formats beyond the deployed tenant-safe workflows;
- restaurant, service/repair, wholesale, grocery, fashion, electronics,
  pharmacy, salon, manufacturing, and rental modules;
- provider-specific SaaS billing, subscription webhooks, and external provider
  adapters beyond the deployed Razorpay Standard Checkout/webhook boundary;
- complete large-data profiling/pagination coverage for every secondary report
  (sales and products have bounded keyset RPCs; other screens use capped,
  tenant-filtered queries);
- verified Windows, iOS, macOS, Linux packaging and production hardware testing.

## Current release blockers and cautions

1. The Android namespace/application ID is still `com.example.flexpos`.
2. A private Android upload keystore is not configured in this workspace; the
   current APK uses the documented debug-signing fallback.
3. The Windows release build is blocked until Developer Mode is enabled.
4. iOS/macOS builds have not been verified on Apple hardware.
5. Production hostname, Auth URL configuration, custom SMTP, hosting, store
   identities, and code-signing identities require operator-owned values.
6. Physical printers, scanners, and other hardware still require operator-side
   validation on the chosen native platform; the online registry, adapter
   boundaries, and diagnostics are implemented.
7. Razorpay Standard Checkout is deployed, but the merchant test gateway keys
   and optional webhook secret are operator configuration; recorded electronic
   tenders remain pending until the server-side checkout or webhook verifies
   them.
8. The application is a substantial working vertical slice, not the complete
   production product described by every open master-checklist item.

Use [the manual deployment guide](manual-deployment.md) for the release sequence
and `MASTER_DEVELOPMENT_CHECKLIST.md` for the live completion status.
