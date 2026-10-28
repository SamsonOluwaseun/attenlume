# Attenlume

Be present. Bring ideas to light.

Attenlume (a-TEN-loom) by Samlytics Data Services is an offline-first conference capture app for Android, iOS and Windows. It records sessions, links your slide photos to the moment they were shown and bookmarks key points, so you can listen instead of typing notes. No account, network or AI model is needed for the core app.

**Status:** early test builds for Android and Windows. Recording, photos, bookmarks, review, trimming and export work; tested on an Android tablet, Android emulators and Windows. See `docs/PROGRESS.md`.

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

Hands-on Windows preview: `powershell -File tool\build_windows_preview.ps1` runs analysis and tests, builds a release, copies it to `..\attenlume-release\windows\Attenlume-<version>-<commit>\` with a portable ZIP, and points the desktop shortcut "Attenlume (preview)" at it. App data lives in `%LOCALAPPDATA%\Samlytics\Attenlume` (ADR-028).

End-to-end check of the real app with the real microphone and camera: `flutter test integration_test/app_capture_journey_test.dart -d windows` (or `-d <android device>`).

Design tokens: edit `design/tokens.json`, then run `dart run tool/gen_tokens.dart` to regenerate `lib/app/theme/tokens.dart`. A test fails if you forget.

Database schema: after changing tables and bumping `schemaVersion`, run `dart run drift_dev make-migrations` and add a migration test (see `test/data/local_database/migration_test.dart`).

## Export format

A conference, a day or chosen activities export as a folder or ZIP with `conference.json`, one folder per activity (audio, photos, `activity.json`, `notes.md`, `bookmarks.csv`, cut ranges) and `checksums.sha256` (P1-21, ADR-040). On Android and iOS a ZIP can be shared straight from the app. The README, `timeline.csv` and `analysis_prompt.md` for AI tools come with P1-22. The full layout is in `docs/BUILD_GUIDE.md` section 5.10.

## Caveats

- Most device checks are still to do. See the device matrix in `docs/TEST_PLAN.md`.
- iOS cannot be built or signed without a Mac (`docs/RELEASE_PLAN.md`).
- On Windows the system AAC encoder's minimum is 96 kbps, so all quality profiles record at about 43 MB per hour there (ADR-002).

## Building the Windows installer

`powershell -File tool\build_windows_installer.ps1` builds the release app and compiles `tool\windows_installer\attenlume.iss` with Inno Setup 6 (`winget install JRSoftware.InnoSetup`) into `attenlume-windows-setup.exe`. The installer is per user and unsigned until a code-signing certificate is in place; an automated release pipeline is task P1-28.

## Docs

- [`AGENTS.md`](AGENTS.md): rules for coding agents
- [`docs/BUILD_GUIDE.md`](docs/BUILD_GUIDE.md): full specification
- [`docs/DESIGN_GUIDE.md`](docs/DESIGN_GUIDE.md): brand, screens and tokens
- [`docs/PRODUCT_SPEC.md`](docs/PRODUCT_SPEC.md): user journeys, stories, edge cases and acceptance detail
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md): modules, recording lifecycle, storage, export, dependency versions
- [`docs/PLATFORM_FEASIBILITY.md`](docs/PLATFORM_FEASIBILITY.md): OS capabilities, sources and the spike results matrix
- [`docs/PRIVACY_AND_SAFETY.md`](docs/PRIVACY_AND_SAFETY.md): consent, stored data, retention, sharing and permissions
- [`docs/TEST_PLAN.md`](docs/TEST_PLAN.md): automated and manual tests, acceptance tests, device matrix and results
- [`docs/RELEASE_PLAN.md`](docs/RELEASE_PLAN.md): milestones, versioning, distribution and signing
- [`docs/DECISIONS.md`](docs/DECISIONS.md): architecture decision records
- [`docs/PROGRESS.md`](docs/PROGRESS.md): dated log of work done
- [`docs/HANDOVER.md`](docs/HANDOVER.md): where the last agent stopped

## Licences

Third-party licences are listed in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md), generated by `dart run tool/licence_audit.dart` (re-run it after any `pubspec.lock` change; a test fails if it is stale). Montserrat is under the SIL Open Font License 1.1 (`assets/fonts/OFL.txt`). The Attenlume name, logos and icon are not open source.

Attenlume's own code is under the [MIT licence](LICENSE), Copyright (c) 2026 Samlytics Data Services (ADR-007). The licence does not cover the brand assets.
