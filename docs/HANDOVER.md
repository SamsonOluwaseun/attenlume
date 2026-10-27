# Handover

Date and agent: 27 October 2026, Google Antigravity, unattended run
Branch: main (merged from `phase-1/P1-11-android-notification`)
Current task ID: P1-11 (done). Next: P1-12
Status: done

## Done in this session

- Completed **P1-11: Android foreground service and notification actions** [FR-REC-10]. Details in `docs/PROGRESS.md`, `docs/ARCHITECTURE.md` and ADR-025.
  - `android/app/src/main/kotlin/com/samlytics/attenlume/RecordingForegroundService.kt`: Native Android foreground service declared with type `microphone` (`android:foregroundServiceType="microphone"`, `ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE`). Posts ongoing notification to `attenlume_recording_channel` (importance `LOW` to prevent audio chime loops) displaying activity title, state, and zero-CPU live chronometer (`setUsesChronometer(true)`) while actively recording.
  - Compact and expanded notification actions: Pause/Resume, Stop, Bookmark, and Photo. Actions dispatch via `PendingIntent.getService` directly to `onStartCommand` of `RecordingForegroundService`, which forwards them over `ForegroundServiceChannel.deliverAction` to Dart.
  - Photo action: Dispatches an activity `PendingIntent` launching `MainActivity` with deep link `attenlume://photo?source=notification`.
  - `lib/platform/foreground_service/foreground_service_bridge.dart`: `ForegroundServiceBridge` platform bridge with `MethodChannelForegroundServiceBridge` connecting to `com.samlytics.attenlume/foreground_service`, and `NoopForegroundServiceBridge` fallback on Windows and iOS.
  - `lib/domain/services/foreground_service_coordinator.dart`: Listens to `RecordingService.statusStream`, starting the foreground service on transition into `RecordingState.recording`, updating notification across segment rolls, pauses, resumes, and interruptions, and stopping service on `saved`, `idle`, `stopping`, or `errorRecoverable`. Action taps invoke `recorder.pause()`, `recorder.resume()`, `recorder.stop()`, or `media.addBookmark(source: BookmarkSource.notification)`. Implements `InterruptionNoticeSink` to update ongoing notification content on interruption events, while multiplexing notices to `InAppInterruptionNotices`.
  - `lib/features/capture/recording_providers.dart`: Added `foregroundServiceBridgeProvider` and `foregroundServiceCoordinatorProvider`. Wired `interruptionCoordinatorProvider` notices sink to `foregroundServiceCoordinatorProvider` and watched in `oneActiveCoordinatorProvider`.
  - 20 new automated unit and widget tests (550 total in the repository, all passing). Windows release and debug APK builds both succeeded locally. ADR-025 recorded in `docs/DECISIONS.md`.

## Left to do on this task

- Nothing in code for P1-11. Real Android phone verification of background recording with screen locked and notification interaction (MT-17) is unverified on physical hardware.

## Exact next step

Start **P1-12 StorageBudgetService and live budget UI** [FR-STO-01 to 04, FR-UI-07] on branch `phase-1/P1-12-storage-budget`.
- Read requirements `FR-STO-01` to `FR-STO-04` and `FR-UI-07` in `docs/BUILD_GUIDE.md`.
- Implement `StorageBudgetService`:
  - 30-second ticks while recording (measuring growth of the current segment file vs nominal profile rate).
  - Storage threshold warnings: low storage warning at 500 MB (prompting user), critical warning at 200 MB, and hard stop at 100 MB (`STORAGE_STOP` -> `saved`).
- Build live budget UI component on recording screen showing estimated time remaining and storage gauge.
- Connect platform `FreeSpaceProbe` (`lib/platform/storage/free_space_probe.dart`) to `StorageBudgetService`.

## Files touched

New:
- `android/app/src/main/kotlin/com/samlytics/attenlume/ForegroundServiceChannel.kt`
- `android/app/src/main/kotlin/com/samlytics/attenlume/RecordingForegroundService.kt`
- `lib/domain/services/foreground_service_coordinator.dart`
- `lib/platform/foreground_service/foreground_service_bridge.dart`
- `test/domain/foreground_service_coordinator_test.dart`
- `test/features/capture/recording_providers_foreground_test.dart`
- `test/fixtures/fake_foreground_service_bridge.dart`
- `test/platform/foreground_service/foreground_service_bridge_test.dart`

Changed:
- `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/com/samlytics/attenlume/MainActivity.kt`
- `android/app/src/main/res/values/strings.xml`
- `lib/features/capture/recording_providers.dart`
- `docs/ARCHITECTURE.md`
- `docs/DECISIONS.md` (ADR-025)
- `docs/PROGRESS.md`
- `docs/TEST_PLAN.md`
- `docs/HANDOVER.md`

## Failing or skipped tests

None failing in `flutter test` (all 550 tests pass). Device tests unchanged from prior sessions:
- `integration_test/p0_13_shortcut_trigger_test.dart` fails on Windows by design (no Windows shortcut bridge; Android tile/shortcuts verified in APK build).
- `integration_test/p0_05_photo_during_recording_test.dart`, `p0_07_bluetooth_routing_test.dart`, `p0_10_long_run_test.dart`, `p0_12_profile_switch_test.dart`, `p0_06_windows_mic_test.dart` fail on this build host because the headless/RDP session has no physical microphone or camera (expected, blocked: needs real device).
- `integration_test/p0_04_background_recording_test.dart` skipped on Windows (Android/iOS only; needs real Android device for MT-17 rerun).

## Open questions for the owner

- **ADR-025 (new):** Android notification channel is configured with `NotificationManager.IMPORTANCE_LOW` so ongoing timer updates and state changes do not emit repeated audible chimes. Confirm this meets expectation.
- **ADR-025 (new):** Notification actions include compact Pause/Resume, Stop, Bookmark, and Photo. Photo dispatches `MainActivity` with `attenlume://photo?source=notification` since opening the camera requires an active foreground activity.
- **ADR-024:** Recording screen uses the navy `live-surface` (#00212B) in BOTH light and dark themes ('house lights down') to prevent screen glare in dark lecture halls.
- **ADR-023:** WAV is not offered in v1 (FR-QUAL-07 allows "off by default"). Say if you want a specialist WAV option sooner.
- **ADR-023:** On Windows every profile records at 96 kbps (encoder floor), so the selector shows 43.2 MB per hour for all three.
- **ADR-022:** Crash recovery marks files automatically (parsed means `recovered`, anything else `damaged`, nothing deleted).
- **ADR-021:** Non-camera interruptions are logged as `system` ("a call or another app") because Android audio focus and iOS interruptions do not say what caused them.
- **ADR-020:** "Keep it running" leaves the old recording and lets the app open the new activity for notes and photos without audio; "Cancel" does nothing.
- **ADR-019:** Segments roll every 10 minutes (the build guide minimum).
- **Project licence:** ADR-007 recommends Apache 2.0. Waiting for your choice between Apache 2.0 and MIT, the copyright holder ("Samlytics Data Services") and whether to exclude brand assets.
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
