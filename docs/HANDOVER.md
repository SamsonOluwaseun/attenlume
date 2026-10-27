# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5), attended
Branch: main (merged from `fix/P1-capture-entry`)
Current task ID: capture entry fixes (owner request, ADR-028). Next: P1-13
Status: done (Android device check pending)

## Done in this session

- Earlier: Android preview release on GitHub, MIT licence, release signing (ADR-007, ADR-027).
- Owner's first Android tablet install: microphone, camera preview and other features did not work. Fixed in ADR-028: microphone permission prompt, quick start opens the recording screen, specific refusal messages, Windows data moved out of the OneDrive-synced Documents folder into `%LOCALAPPDATA%\Samlytics\Attenlume`.
- `integration_test/app_capture_journey_test.dart`: the J2 capture journey in the real app with real plugins. On this PC it reaches the recording screen and checks that a refused start is explained (no microphone in the RDP session).
- `tool/build_windows_preview.ps1`: versioned Windows preview build outside the repo plus a desktop shortcut, for the owner to test while work continues.
- Agreed working loop with the owner: build and check on the Windows laptop first, then ship to Android.

## Left to do on this task

- Ship 0.1.1 to Android (raise the build number in `pubspec.yaml`, `flutter build apk --release`, new GitHub Release) once the owner has checked the Windows preview.
- Android 13+ notification permission is never requested (needs a small native method or `permission_handler`).

## Exact next step

Ask the owner how the Windows preview went. Then either ship 0.1.1 to Android or start **P1-13 Safety prompts** on branch `phase-1/P1-13-safety-prompts` (see `FR-REC-06` in `docs/BUILD_GUIDE.md`). P1-14 (photo screen with viewfinder) is the next most visible gap for the owner.

## Files touched

New: `lib/data/filesystem/app_data_directory.dart`, `integration_test/app_capture_journey_test.dart`, `test/data/filesystem/app_data_directory_test.dart`, `tool/build_windows_preview.ps1`.
Changed: `lib/platform/audio_capture/record_capture_engine.dart`, `lib/features/conferences/conference_home_screen.dart`, `lib/features/capture/recording_screen.dart`, `lib/features/capture/mic_test_sheet.dart`, `lib/features/capture/recording_providers.dart`, `lib/data/local_database/app_database.dart`, tests for these, `README.md`, `docs/ARCHITECTURE.md`, `docs/PRIVACY_AND_SAFETY.md`, `docs/DECISIONS.md`, `docs/PROGRESS.md`, `docs/HANDOVER.md`.

## Failing or skipped tests

None failing in `flutter test`. Device tests: the spikes in `integration_test/` still need a real microphone or camera (unchanged). `app_capture_journey_test.dart` passes on this PC but only up to Record, because there is no microphone.

## Open questions for the owner

- **ADR-026 (new):** Free space calculation for Android queries `StatFs.availableBytes` on `context.filesDir`, and iOS queries `volumeAvailableCapacityForImportantUsageKey` on the documents directory. Measured file growth rate averages over the active segment (after 5s) or prior activity segments, falling back to nominal profile rate. Hard stop reserve is 100 MB (`storage_low`). Confirm this meets expectations.
- **ADR-025:** Android notification channel is configured with `NotificationManager.IMPORTANCE_LOW` so ongoing timer updates and state changes do not emit repeated audible chimes. Confirm this meets expectation.
- **ADR-025:** Notification actions include compact Pause/Resume, Stop, Bookmark, and Photo. Photo dispatches `MainActivity` with `attenlume://photo?source=notification` since opening the camera requires an active foreground activity.
- **ADR-024:** Recording screen uses the navy `live-surface` (#00212B) in BOTH light and dark themes ('house lights down') to prevent screen glare in dark lecture halls.
- **ADR-023:** WAV is not offered in v1 (FR-QUAL-07 allows "off by default"). Say if you want a specialist WAV option sooner.
- **ADR-023:** On Windows every profile records at 96 kbps (encoder floor), so the selector shows 43.2 MB per hour for all three.
- **ADR-022:** Crash recovery marks files automatically (parsed means `recovered`, anything else `damaged`, nothing deleted).
- **ADR-021:** Non-camera interruptions are logged as `system` ("a call or another app") because Android audio focus and iOS interruptions do not say what caused them.
- **ADR-020:** "Keep it running" leaves the old recording and lets the app open the new activity for notes and photos without audio; "Cancel" does nothing.
- **ADR-019:** Segments roll every 10 minutes (the build guide minimum).
- **Signing key (ADR-027):** back up `%USERPROFILE%\attenlume-signing\` (keystore and `key.properties.backup` with the password) somewhere safe off this PC. Losing it means testers must uninstall, and lose their data, to update.
- **Device testing:** Outstanding for real devices (MT-16 to MT-22).

## Commands to run

```powershell
cd C:\dev\attenlume
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed lib test tool integration_test
dart run tool/licence_audit.dart --check
flutter build windows --release
flutter build apk --debug
```
