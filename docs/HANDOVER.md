# Handover

Date and agent: 27 October 2026, Google Antigravity, unattended run
Branch: main (merged from `phase-1/P1-10-recording-screen`)
Current task ID: P1-10 (done). Next: P1-11
Status: done

## Done in this session

- Completed **P1-10: Recording screen UI with level meter and mic test** [FR-UI-01 to 06, FR-UI-08]. Details in `docs/PROGRESS.md`, `docs/ARCHITECTURE.md` and ADR-024.
  - `lib/features/capture/recording_screen.dart`: Complete Recording Screen UI rendered in navy `live-surface` (#00212B) in BOTH light and dark themes ('house lights down', BUILD_GUIDE 5.3). Provides activity/conference/room header (FR-UI-02), active microphone input device indicator, interruption banner with direct Resume action (ADR-021), primary recording controls, horizontally scrollable bookmark chips, and recording quality profile selector. Starts recordings via `startRecordingFromUi` through `oneActiveCoordinatorProvider` (ADR-020).
  - `lib/presentation/components/record_button.dart`: Oversized 96px Record button (`TokenSize.recordButton`), state-based controls (idle Record, recording Pause/Resume and Stop with 2px muted ring and red square), timer display using `AppTheme` display typography with `FontFeature.tabularFigures()`, live level meter visualizer, 600ms debounce window on taps (FR-REC-09) with haptic feedback, and secondary row for Photo, Bookmark, and Note actions.
  - `lib/features/capture/level_meter.dart`: Waveform level visualizer bars in lime (`live` #DCFF38) during active recording, muted grey when paused, normalizing dBFS range `[-60, 0]` dBFS to `[0.0, 1.0]`. Accessible static fallback when `MediaQuery.disableAnimations` is set.
  - `lib/features/capture/mic_test_sheet.dart`: 10-second microphone test bottom sheet (FR-UI-06) with real-time level meter, countdown timer, active microphone signal detection vs. flat signal (peak <= -70.0 dBFS), and automatic temporary capture cleanup on finish or cancel.
  - `lib/presentation/components/bookmark_chip.dart`: Standard bookmark chips ("Important moment", "Question", "Follow-up", "Key slide", "Quote") meeting minimum 48px touch target height with 600ms live flash and haptics (FR-UI-04).
  - `lib/features/capture/quick_thought_sheet.dart`: Quick thought / reflection bottom sheet (FR-UI-05) with private reflection lock toggle, persisting text bookmark and appending markdown reflections to `activity.notesMd` under `## Reflections` without speaking into the microphone.
  - `lib/features/conferences/activity_detail_sheet.dart`: Added "Open recorder" action navigating to `RecordingScreen`.
  - 26 new automated unit and widget tests (530 total in the repository, all passing). Windows release and debug APK builds both succeeded locally. ADR-024 recorded in `docs/DECISIONS.md`.

## Left to do on this task

- Nothing in code for P1-10. Real microphone audio input and real camera shutter in live recording are unverified on physical hardware.

## Exact next step

Start **P1-11 Android foreground service and notification actions** [FR-REC-10] on branch `phase-1/P1-11-android-notification`.
- Read requirement `FR-REC-10` in `docs/BUILD_GUIDE.md` and check `docs/ARCHITECTURE.md` section 3 (`ForegroundServiceBridge`).
- Implement Android foreground service with ongoing notification while recording, displaying activity title, elapsed timer, and actions: Pause/Resume, Stop, and Bookmark.
- Wire actions to `RecordingService` via `oneActiveCoordinatorProvider` and `interruptionCoordinatorProvider`.
- Note: Spikes P0-04 (MT-17) noted Android rerun needed after P1-11. Keep native Android code cleanly behind platform interfaces.

## Files touched

New:
- `lib/features/capture/level_meter.dart`
- `lib/features/capture/mic_test_sheet.dart`
- `lib/features/capture/quick_thought_sheet.dart`
- `lib/features/capture/recording_screen.dart`
- `lib/presentation/components/bookmark_chip.dart`
- `lib/presentation/components/record_button.dart`
- `test/features/capture/level_meter_test.dart`
- `test/features/capture/mic_test_sheet_test.dart`
- `test/features/capture/recording_screen_test.dart`
- `test/presentation/components/bookmark_chip_test.dart`
- `test/presentation/components/record_button_test.dart`

Changed:
- `lib/features/capture/recording_providers.dart`
- `lib/features/conferences/activity_detail_sheet.dart`
- `test/fixtures/fake_capture_engine.dart`
- `docs/ARCHITECTURE.md`
- `docs/DECISIONS.md` (ADR-024)
- `docs/TEST_PLAN.md`
- `docs/PROGRESS.md`
- `docs/HANDOVER.md`

## Failing or skipped tests

None failing in `flutter test` (all 530 tests pass). Device tests unchanged from prior sessions:
- `integration_test/p0_13_shortcut_trigger_test.dart` fails on Windows by design (no Windows shortcut bridge; Android tile/shortcuts verified in APK build).
- `integration_test/p0_05_photo_during_recording_test.dart`, `p0_07_bluetooth_routing_test.dart`, `p0_10_long_run_test.dart`, `p0_12_profile_switch_test.dart`, `p0_06_windows_mic_test.dart` fail on this build host because the headless/RDP session has no physical microphone or camera (expected, blocked: needs real device).
- `integration_test/p0_04_background_recording_test.dart` skipped on Windows (Android/iOS only).

## Open questions for the owner

- **ADR-024 (new):** Recording screen uses the navy `live-surface` (#00212B) in BOTH light and dark themes ('house lights down') to prevent screen glare in dark lecture halls. Confirm this meets brand expectations.
- **ADR-024 (new):** Live audio level sampling polls `audioCaptureEngineProvider.levelDbfs()` every 200ms while actively recording and maps `[-60, 0]` dBFS to `[0.0, 1.0]`. When `MediaQuery.disableAnimations` is set, a non-animating accessible level bar is displayed.
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
