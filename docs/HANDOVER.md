# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5), attended session after the Antigravity P1-12 run
Branch: main (merged from `phase-1/P1-12-storage-budget`)
Current task ID: P1-12 (done). Next: P1-13
Status: done

## Done in this session

- Owner-requested Android preview (not a build guide task): MIT `LICENSE`, release signing with a keystore outside the repo, universal release APK, README download link, repo pushed to `https://github.com/SamsonOluwaseun/attenlume`. ADR-007 accepted (MIT), ADR-027. Details in `docs/PROGRESS.md`.
- To ship a new APK: raise the build number in `pubspec.yaml`, run `flutter build apk --release` on the PC that holds the keystore, and attach it to a new GitHub Release as `attenlume-android.apk` with `SHA256SUMS.txt`. Never use `--split-per-abi` for this channel (ADR-027).

Earlier in the day (Antigravity, P1-12):

- Completed **P1-12: StorageBudgetService and live budget UI** [FR-STO-01 to 04, FR-UI-07]. Details in `docs/PROGRESS.md`, `docs/ARCHITECTURE.md` and ADR-026.
  - Native platform free space channels:
    - Android: `android/app/src/main/kotlin/com/samlytics/attenlume/FreeSpaceChannel.kt` querying `StatFs.availableBytes` and `StatFs.totalBytes` over `com.samlytics.attenlume/free_space`. Attached to `MainActivity.kt`.
    - iOS: `ios/Runner/FreeSpaceChannel.swift` querying `URLResourceKey.volumeAvailableCapacityForImportantUsageKey` and `volumeTotalCapacityKey` with fallback to `fileSystemFreeSize`. Registered in `AppDelegate.swift`.
    - `lib/platform/storage/method_channel_free_space_probe.dart`: Unified Dart implementation for Android and iOS dispatching in `FreeSpaceProbe.forPlatform()` alongside `WindowsFreeSpaceProbe`.
  - `RecordingService` storage preflight and stop reason:
    - Injected `FreeSpaceProbe` and `StorageThresholds`. In `_refusal`, if `probe.availableBytes()` <= `thresholds.hardStopBytes` (100 MB), start is refused with `StartOutcome.storageFull`.
    - Added `SegmentEndReason.storageLow` (`storage_low` in database schema) for hard reserve stops.
    - Exposes `currentSegmentFile` and `currentSegmentStartUtc` for live rate measurement.
    - `OneActiveCoordinator` translates `StartOutcome.storageFull` to: "Cannot start recording: storage is nearly full (under 100 MB remaining)."
  - `StorageBudgetService` (`lib/domain/services/storage_budget_service.dart`):
    - Periodic 30-second timer (`_startPeriodicCheck` / `_stopPeriodicCheck`) while recording.
    - Rolling write rate calculation: uses active segment file growth on disk when elapsed >= 5s; else prior segment history; else nominal profile rate.
    - Computes remaining minutes above 100 MB hard reserve (`hardStopBytes`).
    - Conference folder disk usage calculation via recursive directory sizing (`MediaPaths.conferenceFolder`).
    - Hard stop enforcement: stops recording safely with `SegmentEndReason.storageLow` when space drops <= 100 MB and notifies via `hardStopNoticeStream`.
    - Protected with `SerialLock` to avoid race conditions.
  - `StorageMeter` component (`lib/presentation/components/storage_meter.dart`):
    - Conforms to `docs/design/components/StorageMeter.md`.
    - Compact mode: single muted line under timer on `RecordingScreen` when OK; staged warning banner when <1 GB or <60 min; danger banner when <= 300 MB or <= 100 MB.
    - Expanded mode: used/free progress bar, conference usage, and optional `onManage` action.
  - `RecordingScreen` integration:
    - Embedded compact `StorageMeter` inside `RecordButton` below timer.
    - Storage check pre-record, post-photo, and every 30s.
    - Alert SnackBar on hard stop reserve trigger.
  - 28 new automated unit and widget tests (578 total in the repository, all passing). Windows release and debug APK builds both succeeded locally. ADR-026 recorded in `docs/DECISIONS.md`.

## Left to do on this task

- Nothing in code for P1-12. Real device free space channel verification on physical Android and iOS devices is unverified on physical hardware.

## Exact next step

Start **P1-13 Safety prompts (duration, silence, battery) [FR-REC-06]** on branch `phase-1/P1-13-safety-prompts`.
- Read requirement `FR-REC-06` in `docs/BUILD_GUIDE.md`:
  - Safety prompts (configurable):
    1. Recording longer than 2 hours ("Still in 'Keynote'?").
    2. Near-silence for 10 minutes ("No sound detected. Still in the session?").
    3. Low battery below 15% (connect to `BatteryProbe`, Android/iOS battery channels).
  - Prompts never stop recording on their own (only the 100 MB storage hard limit from P1-12 stops recording).
  - Configurable prompt thresholds in app settings (or sensible defaults).
  - Visual non-intrusive banner on the recording screen with dismiss / confirm actions.

## Files touched

New:
- `android/app/src/main/kotlin/com/samlytics/attenlume/FreeSpaceChannel.kt`
- `ios/Runner/FreeSpaceChannel.swift`
- `lib/domain/services/storage_budget_service.dart`
- `lib/platform/storage/method_channel_free_space_probe.dart`
- `lib/presentation/components/storage_meter.dart`
- `test/domain/recording_service_storage_test.dart`
- `test/domain/storage_budget_service_test.dart`
- `test/features/capture/recording_screen_storage_test.dart`
- `test/platform/storage/method_channel_free_space_probe_test.dart`
- `test/presentation/components/storage_meter_test.dart`

Changed:
- `android/app/src/main/kotlin/com/samlytics/attenlume/MainActivity.kt`
- `ios/Runner/AppDelegate.swift`
- `lib/data/filesystem/media_paths.dart`
- `lib/domain/services/one_active_coordinator.dart`
- `lib/domain/services/recording_service.dart`
- `lib/features/capture/recording_providers.dart`
- `lib/features/capture/recording_screen.dart`
- `lib/platform/storage/free_space_probe.dart`
- `lib/presentation/components/record_button.dart`
- `docs/ARCHITECTURE.md`
- `docs/DECISIONS.md` (ADR-026)
- `docs/PROGRESS.md`
- `docs/HANDOVER.md`

## Failing or skipped tests

None failing in `flutter test` (all 578 tests pass). Device tests unchanged from prior sessions:
- `integration_test/p0_13_shortcut_trigger_test.dart` fails on Windows by design (no Windows shortcut bridge; Android tile/shortcuts verified in APK build).
- `integration_test/p0_05_photo_during_recording_test.dart`, `p0_07_bluetooth_routing_test.dart`, `p0_10_long_run_test.dart`, `p0_12_profile_switch_test.dart`, `p0_06_windows_mic_test.dart` fail on this build host because the headless/RDP session has no physical microphone or camera (expected, blocked: needs real device).
- `integration_test/p0_04_background_recording_test.dart` skipped on Windows (Android/iOS only; needs real Android device for MT-17 rerun).

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
