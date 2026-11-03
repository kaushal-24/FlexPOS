# FlexPOS release readiness

This document is the Phase 10 release handoff for the online-only FlexPOS
application. It is intentionally scoped to the `flexpos-2` Supabase project
(`gpbsblokhpydtpgxpwrg`). Never run release verification against the old
`ap-south-1` FlexPOS project.

## Automated release gate

From the project root, create `config/prod.json` from
`config/prod.example.json`. It may contain only the public Supabase URL and
publishable key. Then run:

```powershell
.\tool\release_gate.ps1
```

Use `-SkipBuilds` when only static analysis, tests, and the performance profile
are needed. Use `-SkipLiveIntegration` only to omit the reminder for the
operator-supplied live Supabase smoke fixtures; it does not disable any local
test.

The gate runs:

- dependency resolution and generated localization;
- formatting with `--set-exit-if-changed`;
- static analysis;
- the Flutter unit/widget/accessibility suite;
- the deterministic performance profile;
- Web, Android APK, Android App Bundle, and Windows release builds.

## Signing and artifact checks

Android distribution requires `android/key.properties` and a private upload
keystore. Without it, Gradle deliberately falls back to the debug key. Follow
[`android-release-signing.md`](android-release-signing.md), then verify the
certificate with `apksigner` before uploading an AAB or distributing an APK.

Windows distribution requires a clean `build/windows/x64/runner/Release`
directory, installation testing on a clean Windows machine, and an
organization-owned code-signing certificate if trusted distribution is needed.

iOS and macOS distribution requires Apple hardware, Xcode, provisioning
profiles, and Apple signing identities. Those builds cannot be certified from
this Windows environment.

## Live and hardware gates

Run `integration_test/production_smoke_test.dart` with disposable,
operator-owned FlexPOS-2 test accounts and fixtures as described in
[`TESTING_AND_PRODUCTION_VERIFICATION.md`](TESTING_AND_PRODUCTION_VERIFICATION.md).
The concurrent-session case requires the second account/business defines.

Physical USB/Bluetooth scanner validation is recorded separately in
[`hardware-scanner-setup.md`](hardware-scanner-setup.md). The application-side
keyboard-wedge and camera workflows are implemented and tested, but a release
must still include evidence from each real scanner model and target device.

## Release acceptance

Before distribution, verify on the target device/browser:

1. Register/sign in, switch business, and confirm role-gated navigation.
2. Search and camera-scan a known product, complete an online sale, and verify
   one inventory decrement and one persisted receipt.
3. Exercise cash, UPI success/failure confirmation, and Razorpay test mode.
4. Print a thermal receipt, download the PDF, and reprint it from sales history.
5. Confirm low-stock highlighting, returns, purchasing receipt, and reports.
6. Confirm no offline queue is created when the network is unavailable.
7. Record build hashes, signer fingerprints, test timestamps, and the physical
   scanner evidence with the release package.

## Current blockers

The following cannot be truthfully completed by source changes alone:

- a Windows build while another Flutter debug process holds the SDK startup
  lock;
- iOS/macOS signing and builds without supported Apple hardware and identities;
- physical scanner evidence without the actual scanner and target device;
- production payment-provider credentials and signed provider events.

Stop the running debug session before invoking the Windows build, and keep all
private credentials outside source control.
