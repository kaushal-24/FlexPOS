# FlexPOS manual deployment guide

This runbook deploys the current FlexPOS application manually. It is intentionally
pinned to one Supabase project:

- Project name: `flexpos-2`
- Project ref: `gpbsblokhpydtpgxpwrg`
- Region: `ap-southeast-2` (Sydney)
- URL: `https://gpbsblokhpydtpgxpwrg.supabase.co`

Do not link, migrate, configure, or deploy against the older `FlexPOS` project in
`ap-south-1`. Stop if any dashboard, CLI, or connection screen shows a different
project ref or region.

## 1. Release prerequisites

Use a clean copy of the intended source version and record the release owner,
application version, database migration range, and rollback owner. Before the
release:

1. Update `version` in `pubspec.yaml` to the approved version and build number.
2. Replace the placeholder Android ID `com.example.flexpos` with the permanent
   reverse-domain application ID before the first store release.
3. Configure the private Android upload key by following
   [Android release signing](android-release-signing.md).
4. Ensure Windows Developer Mode is enabled before attempting a Windows build.
5. Confirm the production hostname and the people authorized to access the
   Supabase dashboard, hosting provider, store account, and signing backup.
6. Schedule a maintenance window for any migration that can lock large tables or
   materially change a live workflow.

## 2. Create the local production configuration

Create an ignored production file from the browser-safe example:

```powershell
Copy-Item config\dev.example.json config\prod.json
```

Set only these values:

```json
{
  "APP_NAME": "FlexPOS",
  "SUPABASE_URL": "https://gpbsblokhpydtpgxpwrg.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_your_key"
}
```

`config/prod.json` is ignored by source control. A Supabase publishable key is
expected in the client application; a service-role/secret key, database password,
SMTP password, payment-provider secret, or signing password is not. Never place
privileged secrets in Dart defines, Flutter assets, Gradle files committed to the
repository, or a web bundle.

## 3. Verify the source release

From the repository root, run:

```powershell
flutter pub get
flutter gen-l10n
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
```

The release is blocked if formatting, analysis, or a test fails. Record the
command output with the release record. The current verified baseline is 111
Flutter tests, all passing. Analyzer exit code must be 0 with no errors
(info-level lint/deprecation notices may remain visible), and a new release
must meet or exceed the verified baseline unless a reviewed test change
explains the difference.

## 4. Prepare Supabase safely

### Identity and backup gate

Open the project dashboard and verify all four identity values at the top of this
guide. Check the project health before changing anything. Confirm the applicable
Supabase backup/PITR coverage and take an approved logical or platform backup
before a destructive or data-transforming migration. A Free Plan backup may not
be downloadable, so confirm recovery capability instead of assuming it exists.

Never run `supabase db reset` against a linked remote project. Never edit or
delete a previously deployed migration. Correct a deployed schema through a new,
forward-only migration.

### Migration gate

The repository currently contains 124 ordered SQL migrations under
`supabase/migrations`; the live project reports 118 tracked migration records.
The six-file drift is documented in `supabase/migrations/README.md`; do not
blindly replay bootstrap or renamed retry files against the live database.
Apply only committed, reviewed migrations and preserve their filename order.
When using the Supabase CLI, link explicitly and inspect the target before
pushing:

```powershell
supabase login
supabase link --project-ref gpbsblokhpydtpgxpwrg
supabase migration list --linked
supabase db push --linked --dry-run
supabase db push --linked
```

If the CLI displays a project other than `gpbsblokhpydtpgxpwrg`, answer no and
stop. Do not copy a concatenated migration history into the SQL Editor. Run the
corresponding pgTAP suites from `supabase/tests` in a transaction and confirm the
fixtures roll back.

After migration, use the Supabase Security and Performance Advisors and verify:

- RLS remains enabled on every exposed operational table.
- Policies still isolate businesses and branches as designed.
- Anonymous users have no operational table or privileged RPC access.
- Authenticated RPCs enforce permissions and tenant ownership.
- Foreign keys and common query paths retain suitable indexes.
- Data API exposure is limited to the intended schemas and objects.
- Receipt settings can save a private logo, template, and QR payload, and a
  reconstructed 58 mm/80 mm receipt renders the configured values.
- A business manager can register/revoke a device and set a cashier PIN; a
  configured PIN blocks checkout until the server accepts re-entry.
- A provisioned platform administrator can open `/platform-admin`; a regular
  member receives the restricted state.

### Authentication configuration

In **Authentication -> URL Configuration**:

1. Set **Site URL** to the exact HTTPS production origin.
2. Add exact production redirect URLs for the origin and password recovery path,
   including `https://YOUR_HOST/update-password`.
3. Add only the development/preview URLs that are actually used. Broad `**`
   wildcards are for local or preview environments, not the production origin.
4. Test registration, verification, reset-password, update-password, and logout
   using a new non-admin account.

The app sends the current origin for registration verification and resolves
`/update-password` for recovery. The hosting configuration must serve the Flutter
entry point for that path so the PKCE recovery session reaches the app.

For production email, configure a custom SMTP provider under Auth settings.
Supabase's default SMTP service is for evaluation, is restricted, and is not a
production delivery service. Configure SPF, DKIM, and DMARC with the provider,
disable link tracking when it rewrites Auth links, and review Auth rate limits.

Before public launch, also enable MFA on Supabase administrator accounts, review
SSL/network restrictions appropriate to the deployment, and verify email
confirmation, OTP expiry, CAPTCHA, and abuse controls.

Official references:

- [Supabase production checklist](https://supabase.com/docs/guides/deployment/going-into-prod)
- [Supabase Auth redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls)
- [Supabase custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp)
- [Supabase deployment maturity model](https://supabase.com/docs/guides/deployment/maturity-model)

## 5. Build and deploy the web application

Build the production bundle:

```powershell
flutter build web --release --no-pub `
  --dart-define-from-file=config/prod.json
```

Deploy the entire `build/web` directory to an HTTPS static host. Configure:

- the production hostname used in Supabase Auth URL Configuration;
- a fallback to `index.html` for `/update-password` and other app routes;
- no-cache or short-cache behavior for `index.html` and service-worker metadata;
- long immutable caching only for fingerprinted assets;
- correct content types, compression, and HTTPS redirect behavior.

Camera barcode/QR scanning in the POS requires a browser camera permission and
an HTTPS origin (localhost is also permitted by browsers). If the permission is
denied or the target has no camera, the existing keyboard-wedge/manual barcode
field remains available.

Do not upload `config/prod.json`; its public settings are compiled into the web
bundle. After deployment, test a hard refresh on every public/Auth route, then
complete the post-deployment checks below.

## 6. Build and distribute Android

Follow the signing guide, then build both store and direct-install artifacts:

```powershell
flutter build appbundle --release --no-pub `
  --dart-define-from-file=config/prod.json
flutter build apk --release --no-pub `
  --dart-define-from-file=config/prod.json
```

Expected outputs:

- `build/app/outputs/bundle/release/app-release.aab`
- `build/app/outputs/flutter-apk/app-release.apk`

Do not distribute when Gradle reports the debug-signing fallback. Verify the APK
certificate with `apksigner`, upload the AAB to an internal test track first, and
exercise a clean install and an upgrade from the previous production version.

## 7. Build and package Windows

After Developer Mode and the Visual Studio desktop toolchain are configured:

```powershell
flutter build windows --release --no-pub `
  --dart-define-from-file=config/prod.json
```

Package the complete `build/windows/x64/runner/Release` directory, including its
DLLs and `data` directory. Do not distribute only the executable. Sign the final
installer or package with the organization's code-signing certificate and test
on a clean supported Windows machine.

The Windows release is not yet verified in this workspace because Developer Mode
is disabled. It remains a release blocker for Windows distribution.

## 8. Post-deployment smoke test

Run these checks with least-privileged accounts in a dedicated test business:

1. Register, verify email, sign in, reset the password, and sign out.
2. Create or select a business; verify cross-business data is not visible.
3. As a business manager, open Business receipt settings and save an invoice
   prefix, tax registration number, and receipt footer.
4. Create a product, set a branch price, add stock, upload a product image,
   edit custom attributes, and verify the signed image preview.
5. Open Catalog tools, define a unit conversion, create a bundle with a
   non-serialized component, and confirm a bundle sale consumes component
   stock and writes its inventory movement.
6. Export the catalog CSV, import a validated row into a test business, and
   exercise the permission-gated bulk price/favorite editor.
7. Open a register shift and complete a cash sale.
8. Confirm the branded receipt preview/PDF and inventory movement; exercise
   both the 58 mm and 80 mm paper-size options before physical printer
   certification.
9. Focus POS with F2, scan a test barcode using a keyboard-wedge scanner, and
   confirm that exactly one matching product is added.
10. Complete one pending external-tender sale and reconcile it with authorized
   evidence; do not treat an unverified payment as settled.
11. Test a return/refund and confirm stock and reports update once.
12. Create and receive a purchase order.
13. Verify customer credit, repayment, expenses, X/Z reports, and dashboard totals.
14. Verify a cashier cannot perform owner/administrator actions.
15. Review Supabase Auth, Postgres, and API logs for unexpected errors without
    copying tokens or customer data into the release record.

## 9. Rollback and incident response

- **Web:** retain the prior immutable bundle and redeploy it if the application
  release fails. Re-test Auth redirect flows after rollback.
- **Android/Windows:** stop rollout and redistribute the last approved signed
  version. App-store version codes cannot be reused.
- **Database:** prefer a reviewed forward-fix migration. Do not delete migration
  history or manually reverse data without a tested recovery plan. For severe
  corruption, stop writes and use the verified backup/PITR process.
- **Credentials:** revoke and rotate any exposed privileged credential. A leaked
  publishable key alone is not an authorization bypass; RLS is still mandatory.
- **Payments:** leave uncertain external payments pending and reconcile from
  provider evidence. Never mark them settled merely to unblock a sale.

Record the failure, affected release/version, timestamps, operator actions, data
recovery decision, and final verification. Preserve logs with customer and secret
data redacted.
