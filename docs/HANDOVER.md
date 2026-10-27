# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5), unattended run
Branch: main (P0-12 merged from `phase-0/P0-12-profile-switch-spike`)
Current task ID: P0-12 (blocked: needs real device). Next: see "Exact next step"
Status: blocked (harness done, device runs outstanding)

## Done in this session

- P0-12 spike harness for per-segment profile switching and observed bitrate [FR-QUAL-01, FR-QUAL-04, FR-QUAL-05, FR-QUAL-06]. Details in `docs/PROGRESS.md`, `docs/PLATFORM_FEASIBILITY.md` 2.3.1 and ADR-014.
  - `RecordingService.changeProfile` with `ProfileChangeOutcome` (`changed`, `alreadyInUse`, `notRecording`, `declined`, `failed`) and a reason. Real production code that P1-09 will call.
  - `lib/spikes/profile_switch_spike.dart`: Economy, Balanced, Enhanced, Economy; report of requested against declared, payload and file kbps, deviation, MB per hour, gap per switch, start error.
  - `integration_test/p0_12_profile_switch_test.dart`: device test for Android, iOS and Windows. Manual steps MT-18 in `docs/TEST_PLAN.md`.
  - `FakeCaptureEngine`: `deliveredBitrateBps` and `refuse` hooks.
  - 16 new tests, 291 total, all passing. Windows release and debug APK build.
- Ran the device test on this host with `-d windows`: start failed, "No audio recording device was found." (RDP session). Recorded as blocked.

## Left to do on this task

- Run MT-18 on an Android phone, an iPhone (needs a Mac) and Windows hardware with a microphone (console session or Surface). Fill the table in `PLATFORM_FEASIBILITY.md` 2.3.1 and the `TEST_PLAN.md` results log.
- If the measured switch gap loses words, move the SHA-256 hash off the switch path (ADR-014 consequences).

## Exact next step

Phase 0 tasks left without a harness: P0-05 (photo during recording), P0-07 (Bluetooth routing), P0-10 (90-minute run), P0-13 (App Intent and tile). All need devices. Choices:

1. **P0-10 harness** (90-minute low-spec run): reuses `RecordingService` and the P0-04 level sampling; log RSS (`ProcessInfo.currentRss`) and file growth every minute, battery via a small interface. Automated part is testable with fakes.
2. **P1-05 rolling segment writer** on branch `phase-1/P1-05-rolling-segments`: 10-minute roll through `switchingSegment`, reusing the switch path that `changeProfile` now uses (`_finishSegment` then `_tryBeginSegment`). Temporary name then rename on finalisation, fsync before marking finalised. Inject a timer factory so tests control time.

## Files touched

New:
- `lib/spikes/profile_switch_spike.dart`
- `integration_test/p0_12_profile_switch_test.dart`
- `test/spikes/profile_switch_spike_test.dart`

Changed:
- `lib/domain/services/recording_service.dart`
- `test/domain/recording_service_test.dart`, `test/fixtures/fake_capture_engine.dart`
- `docs/ARCHITECTURE.md`, `docs/DECISIONS.md` (ADR-014), `docs/PLATFORM_FEASIBILITY.md`, `docs/TEST_PLAN.md`, `docs/PROGRESS.md`, `docs/HANDOVER.md`

## Failing or skipped tests

None failing in `flutter test` (291 passed). Device tests: `integration_test/p0_12_profile_switch_test.dart` and `p0_06_windows_mic_test.dart` fail on this PC (no microphone in the Remote Desktop session, expected, blocked). `p0_04_background_recording_test.dart` is skipped on Windows and has not run on any phone.

## Open questions for the owner

- **Project licence:** ADR-007 recommends Apache 2.0. Awaiting choice between Apache 2.0 and MIT, copyright holder ("Samlytics Data Services") and brand asset exclusion.
- **Device testing** for P0-04 (MT-17), P0-05, P0-06 (MT-16), P0-07, P0-10, P0-12 (MT-18), P0-13. A Windows PC with a microphone, signed in at the console, would unblock MT-16 and the Windows half of MT-18 at once.
- ADR-012 lets a recording start for an activity whose permission status is still `unknown` (only `not_permitted` is refused). Say if you want a per-activity prompt before the first recording.
- ADR-013 picks Android audio usage `media` rather than `voiceCommunication` for audio focus. Review after the first Android run.
- ADR-014 always cuts a new segment on a profile change, even on Windows where every profile is 96 kbps. Say if you would rather skip the cut when the encoder settings are identical.

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
# On a connected phone or Windows PC with a microphone (MT-18):
flutter test integration_test/p0_12_profile_switch_test.dart -d DEVICE_ID --dart-define=P0_12_SECONDS=20
```
