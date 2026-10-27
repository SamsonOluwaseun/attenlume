# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5), unattended run
Branch: main (P0-10 merged from `phase-0/P0-10-long-run-spike`)
Current task ID: P0-10 (blocked: needs real device). Next: see "Exact next step"
Status: blocked (harness done, device runs outstanding)

## Done in this session

- P0-10 spike harness for a 90-minute low-spec run: memory trend, file size, battery [AT-REC-01, AT-MEM-01, FR-REC-02]. Details in `docs/PROGRESS.md`, `docs/PLATFORM_FEASIBILITY.md` 2.4.2 and ADR-015.
  - `lib/platform/diagnostics/`: `MemoryProbe` (`ProcessInfo` RSS and peak), `BatteryProbe` with a Windows `GetSystemPowerStatus` implementation and an "unknown" one for Android and iOS. Reusable by P1-13.
  - `lib/spikes/long_run_spike.dart`: samples RSS, open-file size on disk, level and battery once a minute through the real `RecordingService`; reports RSS slope after a 5-minute warm-up, thirds, peak, whole-file kbps, MB per hour and per 8 hours, stalled intervals, flat samples, battery drain. JSON, CSV and Markdown. No verdict.
  - `integration_test/p0_10_long_run_test.dart`: device test for Android, iOS and Windows, prints each sample as it goes. Manual steps MT-19 in `docs/TEST_PLAN.md`.
  - 18 new tests, 309 total, all passing. Windows release and debug APK build.
- Ran the device test on this host with `-d windows` for 1 minute: start failed, "No audio recording device was found." (RDP session). Recorded as blocked.

## Left to do on this task

- Run MT-19 on the lowest-RAM Android phone available, an iPhone (needs a Mac) and a Windows laptop or Surface on battery. Fill the table in `PLATFORM_FEASIBILITY.md` 2.4.2, the `TEST_PLAN.md` results log and section 7 budgets.
- Re-run after P1-05 (rolling segments) and, on Android, after P1-11 (foreground service) for the locked part.

## Exact next step

Phase 0 tasks left without a harness: P0-05 (photo during recording), P0-07 (Bluetooth routing), P0-13 (App Intent and tile). All need devices. Choices:

1. **P0-07 harness** (Bluetooth routing and fallback): `AudioInterruptionSource` already emits `devicesChanged` and `becomingNoisy`; log `engine.listInputs()` before and after each event and the segment `inputRoute`. FR-QUAL / AT-QUAL-03 says never mislabel codec or channels. Automated part testable with fakes.
2. **P1-05 rolling segment writer** on branch `phase-1/P1-05-rolling-segments`: 10-minute roll through `switchingSegment`, reusing `_finishSegment` then `_tryBeginSegment` as `changeProfile` does. Temporary name then rename on finalisation, fsync before marking finalised. Inject a timer factory so tests control time. This also makes the P0-10 run meaningful (today a 90-minute run is one segment).

## Files touched

New:
- `lib/platform/diagnostics/memory_probe.dart`, `battery_probe.dart`, `windows_battery_probe.dart`
- `lib/spikes/long_run_spike.dart`
- `integration_test/p0_10_long_run_test.dart`
- `test/spikes/long_run_spike_test.dart`

Changed:
- `docs/ARCHITECTURE.md` (8.5), `docs/DECISIONS.md` (ADR-015), `docs/PLATFORM_FEASIBILITY.md` (1, 2.4.2), `docs/TEST_PLAN.md` (2.1, MT-19, results log, budgets), `docs/PROGRESS.md`, `docs/HANDOVER.md`

## Failing or skipped tests

None failing in `flutter test` (309 passed). Device tests: `integration_test/p0_10_long_run_test.dart`, `p0_12_profile_switch_test.dart` and `p0_06_windows_mic_test.dart` fail on this PC (no microphone in the Remote Desktop session, expected, blocked). `p0_04_background_recording_test.dart` is skipped on Windows and has not run on any phone.

## Open questions for the owner

- **Project licence:** ADR-007 recommends Apache 2.0. Awaiting choice between Apache 2.0 and MIT, copyright holder ("Samlytics Data Services") and brand asset exclusion.
- **Device testing** for P0-04 (MT-17), P0-05, P0-06 (MT-16), P0-07, P0-10 (MT-19), P0-12 (MT-18), P0-13. A Windows laptop with a microphone and a battery, signed in at the console, would unblock MT-16 and the Windows halves of MT-18 and MT-19 at once.
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
# On a connected low-spec phone or a Windows laptop with a microphone (MT-19):
flutter test integration_test/p0_10_long_run_test.dart -d DEVICE_ID --dart-define=P0_10_MINUTES=90
```
