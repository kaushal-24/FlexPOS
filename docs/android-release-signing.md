# Android release signing

FlexPOS supports an optional private upload keystore through
`android/key.properties`. Without that file, local release builds deliberately
fall back to the Android debug key and are **not suitable for distribution**.

## 1. Finalize the application identity

Before the first Play Console upload, replace `com.example.flexpos` in
`android/app/build.gradle.kts` with the permanent reverse-domain application ID.
Changing it later creates a different Android application.

## 2. Create the upload keystore

Keep the keystore outside the repository and any synchronized public folder.
From PowerShell, run the JDK 17 `keytool` command and choose strong, unique
passwords when prompted:

```powershell
keytool -genkeypair -v `
  -keystore C:\secure\flexpos-upload.jks `
  -alias flexpos-upload `
  -keyalg RSA -keysize 2048 -validity 10000
```

Back up the keystore and its passwords in an approved password manager. Losing
the upload key can block updates until the Play Console recovery process is
completed.

## 3. Configure Gradle locally

Copy `android/key.properties.example` to `android/key.properties`, then replace
all placeholders:

```properties
storePassword=YOUR_UPLOAD_KEYSTORE_PASSWORD
keyPassword=YOUR_UPLOAD_KEY_PASSWORD
keyAlias=flexpos-upload
storeFile=C:/secure/flexpos-upload.jks
```

`android/key.properties`, `*.jks`, and `*.keystore` are ignored by Git. Never
place passwords, a service-role key, or a Supabase secret in Dart code, Gradle,
the repository, an APK, or an AAB.

## 4. Build a signed release

Use the production configuration containing only the Supabase URL and
publishable key:

```powershell
flutter clean
flutter pub get
flutter build appbundle --release --dart-define-from-file=config/prod.json
flutter build apk --release --dart-define-from-file=config/prod.json
```

The Play Store artifact is
`build/app/outputs/bundle/release/app-release.aab`. The directly installable APK
is `build/app/outputs/flutter-apk/app-release.apk`.

## 5. Verify the signer

Use Android SDK Build Tools `apksigner` and confirm the certificate fingerprint
matches the upload key stored in the Play Console:

```powershell
apksigner verify --verbose --print-certs `
  build\app\outputs\flutter-apk\app-release.apk
```

Also install the release on a clean test device and verify login, checkout,
receipts, file saving, printing/sharing, and network error handling.

## 6. Play App Signing and rotation

Enable Play App Signing. Uploads are signed with the upload key; Google protects
the app-signing key used for distributed packages. If the upload key is exposed,
request an upload-key reset and rotate `android/key.properties` without changing
the application ID or Play app-signing identity.

## Release gate

Do not distribute a build when Gradle prints the debug-signing fallback warning.
A production release is ready only after signer verification, clean-device
testing, version review in `pubspec.yaml`, and secure backup of signing material.
