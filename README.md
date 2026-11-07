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

The opening page now has a **Settings gear**, so no conference is needed to
reach Settings. The camera offers a labelled **Zoom slider** when the active
camera/driver reports a usable range; capture remains available without zoom.

## Optional transcription and support

The 0.1.8 test build adds an off-by-default after-recording transcription pilot.
Enable it in Settings, accept the resource notice and explicitly download the
English model (about 32 MB). Process saved/imported English audio up to ten
minutes, then save corrections or copy/share TXT and timestamped Markdown.
Recognition runs on your device. Model download needs internet; processing can
use substantial memory, CPU and battery. Live captions are still planned.

Direct-download builds may show an optional support prompt after export, with
GBP 5, 10, 20 or Other confirmed on PayPal. Your export always remains available.
Maybe later allows one reminder; Don't ask again stops prompts on this device.
No payment or subscription unlocks transcription or core features.
Open **Settings > Support Attenlume** at any time on eligible direct builds,
even after dismissing reminders. You can also [support Attenlume on PayPal](https://www.paypal.com/donate/?hosted_button_id=EMQCVQHTPDR2U).
Choose GBP 5, 10, 20 or a custom amount there; gifts are entirely voluntary.

## Current development source

The following changes are in source after the last published test build; they
require a new build before download links above can provide them:

- Import external MP3, M4A, WAV and AAC audio into a conference activity, with
  progress and cancellation. Imported MP3/WAV/AAC files support playback,
  transcription and original-audio export; cuts and trimming require M4A.
- Optional speech detection skips long pauses before local transcription.
  Its small Silero file downloads only when the user requests model installation.
- Likely session-name fixes are stored as transcript corrections; the original
  recognised text remains available.
- Android/Windows summaries offer a larger model and a smaller Gemma 3 1B
  option, plus editable summary instructions. Smaller-model question quality
  varies. Device memory recommendations currently work on Windows; Android
  memory detection is pending. No language model downloads automatically.
- iOS retains shared recording/transcription/import features, but the current
  canonical source explicitly disables local AI summaries pending Mac runtime
  integration. iOS builds and device checks must be performed on the Mac.

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
- Direct Windows gifts: add `-DirectSupport` to the installer script. Direct Android gifts: build with `--dart-define=ATTENLUME_SUPPORT_DISTRIBUTION=android-direct`. Store/iOS builds remain disabled pending platform review; see [support configuration](lib/features/support/README.md).
- End-to-end check with the real microphone and camera: `flutter test integration_test/app_capture_journey_test.dart -d windows` (or `-d <android device>`).
- Design tokens: edit `design/tokens.json`, then run `dart run tool/gen_tokens.dart`. A test fails if you forget.
- Third-party notices: run `dart run tool/licence_audit.dart` after any `pubspec.lock` change. A test fails if they are stale.

App data lives in `%LOCALAPPDATA%\Samlytics\Attenlume` on Windows and in the app's private storage on Android.

## Export format

A conference, a day or chosen activities export as a folder or ZIP with `conference.json`, one folder per activity (audio, photos, `activity.json`, `notes.md`, `bookmarks.csv`, cut ranges) and `checksums.sha256`. On Android and iOS a ZIP can be shared straight from the app. A summary README, a timeline and a prompt for AI tools are included. Saved transcripts are included in Everything and Notes-and-details exports as text, timestamped Markdown and re-importable JSON. Original machine text is kept alongside corrections; private items follow the export selections.

## Known limits

- These are early test builds. Most real-device checks are still to do.
- There is no published iPhone download yet; the shared iOS project needs Mac build, signing and device checks.
- On Windows the system's audio encoder records at 96 kbps or more, so every quality setting uses about 43 MB per hour.
- Android test APKs use the existing private release key; they are directly distributed outside the Play Store. Windows installers have no publisher signature yet.

## Docs

- [Quick guide (PDF)](docs/user-guide/Attenlume-Quick-Guide.pdf): how to set up, record, review and export
- [Quick guide (PowerPoint)](docs/user-guide/Attenlume-Quick-Guide.pptx): the same guide as slides
- [Privacy policy](https://www.samlytics.co.uk/attenlume-policy/attenlume-privacy.html): what Attenlume stores, where, and who to contact ([source](docs/legal/))
- [Releases](https://github.com/SamsonOluwaseun/attenlume/releases): every version, with SHA-256 checksums
- [Third-party notices](THIRD_PARTY_NOTICES.md): licences of the packages Attenlume uses

## Licences

Attenlume's own code is under the [MIT licence](LICENSE), Copyright (c) 2026 Samlytics Data Services. The licence does not cover the Attenlume name, logos and icon. Montserrat is under the SIL Open Font License 1.1 (`assets/fonts/OFL.txt`). Third-party licences are in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).