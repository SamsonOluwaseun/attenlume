# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5), unattended run
Branch: main (P1-04 merged from `phase-1/P1-04-recording-service`)
Current task ID: P1-04 (done). Next: see "Exact next step"
Status: done

## Done in this session

- P1-04: RecordingService with state machine and mutex [FR-REC-01, FR-REC-02, FR-REC-09]. Details in `docs/PROGRESS.md` and ADR-012.
  - `lib/domain/services/recording_state.dart`: `RecordingState`, `recordingTransitions`, `canTransition`, `RecordingStatus`.
  - `lib/shared/utilities/serial_lock.dart`: `SerialLock`.
  - `lib/domain/services/recording_service.dart`: `start` (returns `StartOutcome`), `pause`, `resume`, `stop`, `dispose`, `status`, `statusStream`. Segment row before audio, file under the media root, finalisation from `M4aInspector` plus SHA-256 in an isolate, damaged files kept.
  - `lib/data/filesystem/media_paths.dart`: relative segment paths, never overwrites.
  - `MediaAssetRepository.nextSegmentSequence`; `finaliseSegment` takes observed codec, container, channels and sample rate.
  - `lib/features/capture/recording_providers.dart`: providers for the service, status stream, engine and media root.
  - 28 new tests, 265 total, all passing. Windows release and debug APK build.
- Added rows to the `PROGRESS.md` task table for P0-04, P0-05, P0-07, P0-10, P0-12, P0-13 (blocked: needs real device). They were missing from the table although the last handover called them blocked. No harness exists yet for them.

## Left to do on this task

Nothing. Real capture through `RecordCaptureEngine` is unverified on every platform (no microphone in this RDP session, no phone).

## Exact next step

The agent prompt puts Phase 0 before Phase 1. Two reasonable choices:

1. **P0-04 harness** (preferred if you follow the prompt strictly): build a spike under `lib/spikes/` that drives `RecordingService` with a real `RecordCaptureEngine`, logs state and segment rows, plus manual steps for lock-screen and call tests. Mark it blocked: needs real device. Android background capture also needs the foreground service (P1-11), so note that in the steps.
2. **P1-05 rolling segment writer** on branch `phase-1/P1-05-rolling-segments`: add a 10-minute roll through `RecordingState.switchingSegment` in `RecordingService`, reusing `_finishSegment` and `_beginSegment`. Write to a temporary name and rename on finalisation (atomic), fsync before marking finalised. Inject a timer factory so tests control time.

## Files touched

New:
- `lib/domain/services/recording_service.dart`
- `lib/domain/services/recording_state.dart`
- `lib/shared/utilities/serial_lock.dart`
- `lib/data/filesystem/media_paths.dart`
- `lib/features/capture/recording_providers.dart`
- `test/domain/recording_service_test.dart`
- `test/domain/recording_state_test.dart`
- `test/data/filesystem/media_paths_test.dart`
- `test/fixtures/fake_capture_engine.dart`

Changed:
- `lib/data/repositories/media_asset_repository.dart`
- `docs/ARCHITECTURE.md`, `docs/DECISIONS.md` (ADR-012), `docs/PROGRESS.md`, `docs/HANDOVER.md`

## Failing or skipped tests

None failing in `flutter test` (265 passed). `integration_test/p0_06_windows_mic_test.dart` still fails on this PC (no microphone in the Remote Desktop session, expected, blocked). No device tests run.

## Open questions for the owner

- **Project licence:** ADR-007 recommends Apache 2.0. Awaiting choice between Apache 2.0 and MIT, copyright holder ("Samlytics Data Services") and brand asset exclusion.
- **Device testing** for P0-04, P0-05, P0-06/MT-16, P0-07, P0-10, P0-12, P0-13.
- ADR-012 lets a recording start for an activity whose permission status is still `unknown` (only `not_permitted` is refused). The policy notice is acknowledged at conference level (FR-CONF-06). Say if you want a per-activity prompt before the first recording.

## Commands to run

```powershell
cd C:\dev\attenlume
flutter pub get
dart run build_runner build
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed lib test tool
dart run tool/licence_audit.dart --check
flutter build windows --release
flutter build apk --debug
```
