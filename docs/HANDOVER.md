# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5), unattended run
Branch: main (P0-04 merged from `phase-0/P0-04-background-spike`)
Current task ID: P0-04 (blocked: needs real device). Next: see "Exact next step"
Status: blocked (harness done, device runs outstanding)

## Done in this session

- P0-04 spike harness for background recording with the screen locked, and call interruption and resume [NFR-05, NFR-06, FR-REC-05]. Details in `docs/PROGRESS.md`, `docs/PLATFORM_FEASIBILITY.md` 2.4.1 and ADR-013.
  - `lib/platform/interruptions/audio_interruption_source.dart`: `AudioInterruptionSource`, `AudioInterruption`, `NoAudioInterruptions`.
  - `lib/platform/interruptions/audio_session_interruption_source.dart`: `audio_session` 0.2.4 implementation (iOS `playAndRecord`, Android media usage with speech content and full focus).
  - `lib/spikes/background_recording_spike.dart`: drives `RecordingService`, logs lifecycle, session events, states, level samples (foreground or background), segments and interruption rows. Has `settle()` for tests.
  - `integration_test/p0_04_background_recording_test.dart`: device test, Android and iOS only. Manual steps MT-17 in `docs/TEST_PLAN.md`.
  - Android manifest permissions and iOS `NSMicrophoneUsageDescription` plus `UIBackgroundModes: audio`.
  - 10 new tests, 275 total, all passing. Windows release and debug APK build.

## Left to do on this task

- Run MT-17 on an Android phone and on an iPhone (needs a Mac). Record results in `PLATFORM_FEASIBILITY.md` 1 and 2.4.1 and the `TEST_PLAN.md` results log.
- Android: rerun after P1-11 adds the microphone foreground service. Until then, locked-screen audio is expected to be silent.
- iOS: if `record_ios` replaces our session category, turn off its session management (ADR-013 point 5).

## Exact next step

Phase 0 tasks left are all device spikes (P0-05, P0-07, P0-10, P0-12, P0-13), each with no harness yet. Two reasonable choices:

1. **P0-12 harness** (per-segment profile switching and observed bitrate): small, reuses `RecordingService` and `M4aInspector`. Record one segment per profile with stop-then-start, report requested versus observed bitrate. Much of it can follow `WindowsMicSpike`.
2. **P1-05 rolling segment writer** on branch `phase-1/P1-05-rolling-segments`: 10-minute roll through `RecordingState.switchingSegment` in `RecordingService`, reusing `_finishSegment` and `_beginSegment`. Temporary name then rename on finalisation, fsync before marking finalised. Inject a timer factory so tests control time.

## Files touched

New:
- `lib/platform/interruptions/audio_interruption_source.dart`
- `lib/platform/interruptions/audio_session_interruption_source.dart`
- `lib/spikes/background_recording_spike.dart`
- `integration_test/p0_04_background_recording_test.dart`
- `test/spikes/background_recording_spike_test.dart`

Changed:
- `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`
- `pubspec.yaml`, `pubspec.lock`, `THIRD_PARTY_NOTICES.md`
- `test/fixtures/fake_capture_engine.dart` (settable `level`)
- `docs/ARCHITECTURE.md`, `docs/DECISIONS.md` (ADR-013), `docs/PLATFORM_FEASIBILITY.md`, `docs/TEST_PLAN.md`, `docs/PROGRESS.md`, `docs/HANDOVER.md`

## Failing or skipped tests

None failing in `flutter test` (275 passed). `integration_test/p0_04_background_recording_test.dart` is skipped on Windows and has not been run on any phone. `integration_test/p0_06_windows_mic_test.dart` still fails on this PC (no microphone in the Remote Desktop session, expected, blocked).

## Open questions for the owner

- **Project licence:** ADR-007 recommends Apache 2.0. Awaiting choice between Apache 2.0 and MIT, copyright holder ("Samlytics Data Services") and brand asset exclusion.
- **Device testing** for P0-04 (MT-17), P0-05, P0-06/MT-16, P0-07, P0-10, P0-12, P0-13. P0-04 needs an Android phone, a Mac with an iPhone, and a second phone to make calls.
- ADR-012 lets a recording start for an activity whose permission status is still `unknown` (only `not_permitted` is refused). Say if you want a per-activity prompt before the first recording.
- ADR-013 picks Android audio usage `media` rather than `voiceCommunication` for audio focus. Review after the first Android run.

## Commands to run

```powershell
cd C:\dev\attenlume
flutter pub get
dart run build_runner build
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed lib test tool integration_test
dart run tool/licence_audit.dart --check
flutter build windows --release
flutter build apk --debug
# On a connected phone (MT-17):
flutter test integration_test/p0_04_background_recording_test.dart -d DEVICE_ID --dart-define=P0_04_SECONDS=300
```
