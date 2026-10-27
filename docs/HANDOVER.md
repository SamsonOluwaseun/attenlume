# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5), unattended run
Branch: main (P0-07 merged from `phase-0/P0-07-bluetooth-routing-spike`)
Current task ID: P0-07 (blocked: needs real device and headsets). Next: see "Exact next step"
Status: blocked (harness done, device runs outstanding)

## Done in this session

- P0-07 spike harness for Bluetooth mic routing and fallback [FR-REC-07, FR-REC-03, FR-QUAL-06, AT-QUAL-03]. Details in `docs/PROGRESS.md`, `docs/PLATFORM_FEASIBILITY.md` 2.4.3 and ADR-016.
  - `lib/platform/audio_route/`: `AudioRouteProbe` and `InputRoute`. iOS reports the active input; Android and Windows only list inputs (no routed-device API in `audio_session` or `record`).
  - `RecordingService` now fills `input_route` per segment and has `routeChanged({force})`: rolls with `route_change`, or waits in `userResumeRequired` when no mic can start. New state transition `switchingSegment -> userResumeRequired`.
  - `lib/spikes/bluetooth_routing_spike.dart`: event plus 1 s polling, `route_lost` markers, reinspects every file against its row (AT-QUAL-03).
  - `integration_test/p0_07_bluetooth_routing_test.dart`, manual steps MT-20 in `docs/TEST_PLAN.md`.
  - 26 new tests, 335 total, all passing. Windows release and debug APK build.
- Ran the device test on this host with `-d windows` for 10 s: start failed, "No audio recording device was found." (RDP session). Recorded as blocked.

## Left to do on this task

- Run MT-20 on an Android phone, an iPhone (needs a Mac) and a Windows laptop or Surface, each with AirPods or similar, a typical headset and a cheap Bluetooth lapel mic. Fill the table in `PLATFORM_FEASIBILITY.md` 2.4.3 and the `TEST_PLAN.md` results log.
- P1-07 takes over route handling (coordinator, Android `AudioRecord.getRoutedDevice` channel, Windows default-device query, real resume prompt).

## Exact next step

Phase 0 tasks left without a harness: P0-05 (photo during recording) and P0-13 (App Intent and tile). Both need devices. Choices:

1. **P0-05 harness** (photo capture during recording, AT-PHO-01): 20 photos during a recording, log audio session events, level and segment rows around each shot. Needs a camera package decision (check `camera` licence and Windows support, ADR) behind an interface so the automated part is testable with fakes.
2. **P1-05 rolling segment writer** on branch `phase-1/P1-05-rolling-segments`: 10-minute roll through `switchingSegment`, reusing `_finishSegment` then `_tryBeginSegment` as `changeProfile` and `routeChanged` do. Temporary name then rename on finalisation, fsync before marking finalised. Inject a timer factory so tests control time. Also makes the P0-10 run meaningful.

## Files touched

New:
- `lib/platform/audio_route/audio_route_probe.dart`, `audio_session_route_probe.dart`, `engine_route_probe.dart`
- `lib/spikes/bluetooth_routing_spike.dart`
- `integration_test/p0_07_bluetooth_routing_test.dart`
- `test/domain/recording_service_route_test.dart`, `test/platform/audio_route_probe_test.dart`, `test/spikes/bluetooth_routing_spike_test.dart`, `test/fixtures/fake_route_probe.dart`

Changed:
- `lib/domain/services/recording_service.dart`, `lib/domain/services/recording_state.dart`, `lib/features/capture/recording_providers.dart`
- `test/fixtures/fake_capture_engine.dart`, `test/domain/recording_state_test.dart`
- `docs/ARCHITECTURE.md` (8.6, 9), `docs/DECISIONS.md` (ADR-016), `docs/PLATFORM_FEASIBILITY.md` (1, 2.4.3), `docs/TEST_PLAN.md` (2.1, MT-20, AT-QUAL-03, results log), `docs/PROGRESS.md`, `docs/HANDOVER.md`

## Failing or skipped tests

None failing in `flutter test` (335 passed). Device tests: `integration_test/p0_07_bluetooth_routing_test.dart`, `p0_10_long_run_test.dart`, `p0_12_profile_switch_test.dart` and `p0_06_windows_mic_test.dart` fail on this PC (no microphone in the Remote Desktop session, expected, blocked). `p0_04_background_recording_test.dart` is skipped on Windows and has not run on any phone.

## Open questions for the owner

- **Project licence:** ADR-007 recommends Apache 2.0. Awaiting choice between Apache 2.0 and MIT, copyright holder ("Samlytics Data Services") and brand asset exclusion.
- **Device testing** for P0-04 (MT-17), P0-05, P0-06 (MT-16), P0-07 (MT-20), P0-10 (MT-19), P0-12 (MT-18), P0-13. A Windows laptop with a microphone and a battery, signed in at the console, would unblock MT-16 and the Windows halves of MT-18, MT-19 and MT-20 at once. MT-20 also needs Bluetooth headsets.
- ADR-016 cuts a segment boundary on every audio device change on Android and Windows, because the active mic is not reported there. Say if you would rather accept missed boundaries than extra ones.
- ADR-016: should Android record from a connected Bluetooth mic by default (explicit device choice), or keep the built-in mic unless the user picks one? Current behaviour follows the system.
- ADR-012 lets a recording start for an activity whose permission status is still `unknown` (only `not_permitted` is refused). Say if you want a per-activity prompt before the first recording.
- ADR-013 picks Android audio usage `media` rather than `voiceCommunication` for audio focus. Review after the first Android run.
- ADR-014 always cuts a new segment on a profile change, even on Windows where every profile is 96 kbps. Say if you would rather skip the cut when the encoder settings are identical.
- ADR-015 defers `battery_plus`; Android and iOS battery is read by hand in MT-19 until P1-13. Say if you would rather adopt the package now.

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
# On a connected phone or a Windows laptop with a microphone and a Bluetooth headset (MT-20):
flutter test integration_test/p0_07_bluetooth_routing_test.dart -d DEVICE_ID --dart-define=P0_07_SECONDS=180
```
