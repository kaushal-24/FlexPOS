# Windows and Android Studio setup

## Required software

Install the following on Windows 11:

1. Git for Windows.
2. The stable Flutter SDK in a short writable path such as `C:\src\flutter`.
3. Android Studio with the Flutter and Dart plugins.
4. Android SDK Platform, Platform-Tools, Build-Tools, Command-line Tools, and an
   emulator image or physical-device driver.
5. JDK 17 (the Android Studio bundled JDK is supported).
6. Visual Studio 2022 Community or higher with **Desktop development with C++**,
   MSVC v143, CMake tools, and a current Windows 10/11 SDK.

Do not install Flutter inside `Program Files`, and do not commit machine-local
SDK paths or credentials.

## Enable plugin symlinks

Flutter desktop builds with plugins require Windows Developer Mode. Open
**Settings → System → For developers → Developer Mode**, enable it, then restart
the terminal and Android Studio. This is a system-wide security setting and must
be approved by the workstation owner.

## Validate the toolchains

Run:

```powershell
flutter channel stable
flutter upgrade
flutter config --enable-windows-desktop
flutter doctor -v
flutter doctor --android-licenses
```

Resolve every Windows, Visual Studio, Android, and license error reported by
`flutter doctor -v` before building.

## Configure FlexPOS

From the repository root:

```powershell
flutter pub get
Copy-Item config\dev.example.json config\dev.json
```

Edit `config/dev.json` so it contains only the `flexpos-2` URL
`https://gpbsblokhpydtpgxpwrg.supabase.co` and its active publishable key. Never
use a service-role/secret key and never point this checkout at the old
`ap-south-1` project.

Run the application:

```powershell
flutter run -d windows --dart-define-from-file=config/dev.json
flutter run -d android --dart-define-from-file=config/dev.json
```

## Local verification

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
flutter build web --release --no-pub
flutter build apk --release --no-pub
flutter build windows --release --no-pub
```

The Windows bundle is written to `build/windows/x64/runner/Release`. Copy the
entire `Release` directory when testing or packaging; the executable depends on
the adjacent DLLs and `data` directory.

## Common Windows failures

- **Plugin builds require symlink support:** enable Developer Mode and restart
  the terminal/IDE.
- **Visual Studio toolchain missing:** modify Visual Studio and install Desktop
  development with C++, MSVC, CMake, and Windows SDK components.
- **CMake cache/path errors after moving the checkout:** delete only the
  generated `build/windows` directory and rebuild.
- **Configuration screen appears:** pass the intended `--dart-define-from-file`
  file and verify it points to `flexpos-2`.
- **Android device unavailable:** run `flutter devices`, start an emulator, or
  enable USB debugging and authorize the workstation on the device.

For store-ready Android signing, follow
[`android-release-signing.md`](android-release-signing.md).
