# Testing and production verification

FlexPOS uses layered verification. The application remains online-only: a
successful production check must exercise the live Supabase project
`flexpos-2` (`gpbsblokhpydtpgxpwrg`) and must not introduce a disconnected
queue or local transaction cache.

## Local verification gate

The complete Windows release gate is scripted in
`tool/release_gate.ps1`. It validates production configuration, formatting,
analysis, tests, the performance profile, and Web/Android/Windows release
builds. See `docs/release-readiness.md` for signing and operator-owned gates.
Run it after stopping any other Flutter command that holds the SDK startup
lock:

```powershell
.\tool\release_gate.ps1
```

Run these commands from the project root and record their output with the
release artifact:

```powershell
flutter pub get
flutter gen-l10n
dart format --output=none --set-exit-if-changed lib test integration_test tool
flutter analyze --no-pub
flutter test --no-pub
dart run tool/performance_profile.dart
```

The development server port is intentionally not part of the gate. Use the
operator-selected port with:

```powershell
flutter run --dart-define-from-file=config/dev.json
```

The current source suite contains 113 test cases, including unit, widget,
accessibility, repository-contract, server-page, discount/tax, and performance
coverage. The latest analyzer run reports zero errors; existing info-level
lint/deprecation notices remain visible in the output.

## Flutter integration smoke tests

The live Supabase harness is in
`integration_test/production_smoke_test.dart`. It covers authenticated sign-in,
catalog/product loading, sales history, returnable-sale lookup, suppliers, and
purchase orders through the same repositories used by the app. Tests are
skipped when live credentials and a business fixture are not supplied, so a
local unit-test run never mutates a tenant accidentally. A return test also
requires `FLEXPOS_TEST_SALE_ID`.

Run it against FlexPOS-2 with an operator-owned test account:

```powershell
flutter test integration_test/production_smoke_test.dart -d windows `
  --dart-define=SUPABASE_URL=https://gpbsblokhpydtpgxpwrg.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-key> `
  --dart-define=FLEXPOS_TEST_EMAIL=<test-email> `
  --dart-define=FLEXPOS_TEST_PASSWORD=<test-password> `
  --dart-define=FLEXPOS_TEST_BUSINESS_ID=<business-uuid> `
  --dart-define=FLEXPOS_TEST_SALE_ID=<completed-sale-uuid> `
  --dart-define=FLEXPOS_TEST_SECOND_EMAIL=<second-test-email> `
  --dart-define=FLEXPOS_TEST_SECOND_PASSWORD=<second-test-password> `
  --dart-define=FLEXPOS_TEST_SECOND_BUSINESS_ID=<second-business-uuid>
```

Never commit those values. The live integration run is an environment gate;
the source harness is implemented independently of whether a test account is
currently available. Supplying the second account and business also runs the
explicit concurrent-session isolation case.

Latest local result (2026-10-30): `flutter test --no-pub` **113/113 passed**;
the focused discount/tax/promotion suite passed **5/5**; and the large-data
profile completed in **0.13 ms** for a 50-row page from 100,000 rows.

## Verification matrix

| Area | Automated coverage | Production check |
| --- | --- | --- |
| Authentication and permissions | Repository contract, configuration, access-control, and logger tests | Register/sign in, accept an invite, verify role restrictions, sign out, and repeat on a second browser session |
| Products and inventory | Catalog, inventory, server-page, performance tests, and live integration smoke test | Create a product with image/tax, scan/search it, receive stock, sell it, and confirm live stock/report changes |
| POS and billing | Exact tax, discount, rounding, payment, coupon, and POS total tests | Complete cash/card/UPI flows, including successful and failed UPI confirmation, then verify receipt and ledger records |
| Customers, purchasing, returns | Customer, purchasing, sales-order, refund, credit-note suites, and live integration smoke test | Create a purchase, sell, return, refund, and confirm customer balance and inventory movement |
| Supabase isolation | Live pgTAP suites with tenant, privilege, idempotency, and audit assertions | Repeat the critical flows with two businesses and confirm neither can read or mutate the other |
| Cashier re-entry | Server-verified PIN, rate limiting, and device biometric gate | Re-enter a configured cashier PIN; where a supported biometric is available, pass biometric verification first and confirm the server PIN is still required |
| Accessibility and release artifacts | Contrast, semantics, touch-target, text-scale, analyzer, and format gates | Check keyboard traversal, screen-reader order, 200% scaling, Android APK, and Web release |

## Live backend verification

Apply migrations only to `flexpos-2`, then run the corresponding pgTAP suite
with fixtures that roll back. Record the suite name, check count, migration
name, and timestamp. Never point these checks at the old `ap-south-1`
FlexPOS project.

## Remaining environment gates

Windows release verification requires Developer Mode for Flutter plugin
symlinks. iOS/macOS release verification requires supported Apple hardware and
signing. The source harness for auth/products/sales/returns/purchasing and
explicit concurrent-session isolation is implemented; run it with operator-
owned live fixtures before release. Physical scanner validation remains a
separate hardware evidence gate.
