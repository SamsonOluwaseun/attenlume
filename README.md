# Attenlume

Be present. Bring ideas to light.

Attenlume (a-TEN-loom) by Samlytics Data Services is an offline-first conference capture app for Android, iOS and Windows. It records sessions, links your slide photos to the moment they were shown and bookmarks key points, so you can listen instead of typing notes. No account, network or AI model is needed for the core app.

**Status:** early test builds for Android and Windows. Recording, photos, bookmarks, review, trimming and export work; tested on an Android tablet, Android emulators and Windows.

**New to Attenlume?** Read the quick guide: [PDF](docs/user-guide/Attenlume-Quick-Guide.pdf) or [PowerPoint](docs/user-guide/Attenlume-Quick-Guide.pptx). The same guide is in the app: tap **New here? Read the quick guide** on the first screen.

## Try it on Android

**[Download Attenlume for Android (APK)](https://github.com/SamsonOluwaseun/attenlume/releases/latest/download/attenlume-android.apk)**

This is an early test build, so expect rough edges and export anything important.

1. Open the link above on your Android phone or tablet. Chrome downloads the file.
2. Tap the download when it finishes. If Android says installs from this source are not allowed, tap **Settings**, turn on **Allow from this source**, then go back.
3. Tap **Install**. Google Play Protect may warn that the app is unknown because it is not from the Play Store. Tap **More details**, then **Install anyway**.
4. Open Attenlume and allow the microphone when it asks.

To update, download the latest APK and install it over the old one. Your conferences and recordings are kept. Every release, with its SHA-256 checksum, is on the [Releases page](https://github.com/SamsonOluwaseun/attenlume/releases).

## Try it on Windows

**[Download Attenlume for Windows (installer)](https://github.com/SamsonOluwaseun/attenlume/releases/latest/download/attenlume-windows-setup.exe)**

For Windows 10 (version 1809 or later) and Windows 11, 64-bit. No administrator rights are needed.

1. Open the link above. Your browser downloads `attenlume-windows-setup.exe`. If the browser warns that the file is not commonly downloaded, choose **Keep**.
2. Run the file. Test builds are not signed yet, so Windows may show **Windows protected your PC**. Click **More info**, then **Run anyway**.
3. Follow the installer. It adds Attenlume to the Start menu, and to the desktop if you tick the box.
4. Open Attenlume. The first time you record or take a photo, Windows may ask for microphone or camera access. If recording does not start, open **Settings > Privacy & security > Microphone** and turn on **Let desktop apps access your microphone**.

To update, run the newest installer; it replaces the old version and keeps your recordings. To remove Attenlume, use **Settings > Apps > Installed apps**. Your recordings, photos and notes stay in `%LOCALAPPDATA%\Samlytics\Attenlume` until you delete that folder.

## Develop

Requires Flutter 3.47.8 stable (Dart 3.13.7). Android builds need JDK 17 and the Android SDK. iOS builds need a Mac.

```powershell
flutter pub get
dart run build_runner build     # Drift code generation
flutter analyze
flutter test
flutter run -d windows
```

- Windows installer: `powershell -File tool\build_windows_installer.ps1` builds the app and an installer with Inno Setup 6 (`winget install JRSoftware.InnoSetup`).
- End-to-end check with the real microphone and camera: `flutter test integration_test/app_capture_journey_test.dart -d windows` (or `-d <android device>`).
- Design tokens: edit `design/tokens.json`, then run `dart run tool/gen_tokens.dart`. A test fails if you forget.
- Third-party notices: run `dart run tool/licence_audit.dart` after any `pubspec.lock` change. A test fails if they are stale.

App data lives in `%LOCALAPPDATA%\Samlytics\Attenlume` on Windows and in the app's private storage on Android.

## Export format

A conference, a day or chosen activities export as a folder or ZIP with `conference.json`, one folder per activity (audio, photos, `activity.json`, `notes.md`, `bookmarks.csv`, cut ranges) and `checksums.sha256`. On Android and iOS a ZIP can be shared straight from the app. A summary README, a timeline and a prompt for AI tools are coming next.

## Known limits

- These are early test builds. Most real-device checks are still to do.
- There is no iPhone version yet; it needs a Mac to build and sign.
- On Windows the system's audio encoder records at 96 kbps or more, so every quality setting uses about 43 MB per hour.
- Test builds are not signed yet, so Android and Windows warn before installing.

## Docs

- [Quick guide (PDF)](docs/user-guide/Attenlume-Quick-Guide.pdf): how to set up, record, review and export
- [Quick guide (PowerPoint)](docs/user-guide/Attenlume-Quick-Guide.pptx): the same guide as slides
- [Releases](https://github.com/SamsonOluwaseun/attenlume/releases): every version, with SHA-256 checksums
- [Third-party notices](THIRD_PARTY_NOTICES.md): licences of the packages Attenlume uses

## Licences

Attenlume's own code is under the [MIT licence](LICENSE), Copyright (c) 2026 Samlytics Data Services. The licence does not cover the Attenlume name, logos and icon. Montserrat is under the SIL Open Font License 1.1 (`assets/fonts/OFL.txt`). Third-party licences are in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).