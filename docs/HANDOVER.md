# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5), unattended run
Branch: main (P0-06 merged from `phase-0/P0-06-windows-mic`)
Current task ID: P0-08 (next)
Status: P0-06 blocked: needs real device (all automated parts done). P0-08 not started.

## Done in this session

- P0-06: capture interface (`lib/platform/audio_capture/`), effective encoder settings per platform, pure-Dart M4A inspector, streaming folder export with SHA-256 verification, spike harness (`lib/spikes/windows_mic_spike.dart`) and Windows device test (`integration_test/p0_06_windows_mic_test.dart`). ADR-006.
- 24 new unit tests (100 total), all passing. Analyze and format clean. APK debug and Windows release builds succeed.
- Real run on this PC: no capture device. The agent runs in a disconnected Remote Desktop session, which does not expose the PC's "Microphone Array". `record` returned no inputs and `start()` threw "No audio recording device was found.". Recorded in `docs/PLATFORM_FEASIBILITY.md` 2.6.1 and the `docs/TEST_PLAN.md` results log.

## Left to do on this task

Only the device part (manual test MT-16): run the integration test while signed in at the PC's console or on a Surface, listen to the segments, record the actual bitrate for 32/48/64/96 kbps requests and what happens with the microphone privacy switch off. Then set P0-06 to done.

Also carried forward: M4A seeking accuracy with `just_audio_windows` moved to P1-17 (nothing to play yet).

## Exact next step

Start P0-08 on branch `phase-0/P0-08-licences`: list every direct and transitive dependency from `pubspec.lock` with its licence (pub.dev API or the package's LICENSE file in the pub cache, `tool/pub_audit.py` may help), plus Montserrat (OFL 1.1) and brand assets. Flag anything not permissive (MPL, LGPL, GPL, unknown). Write `THIRD_PARTY_NOTICES.md`, choose MIT or Apache 2.0 in an ADR (the owner asked to choose after P0-08, so recommend one and put the choice under open questions), add a `LICENSE` file only if the ADR decides. Add a test that every package in `pubspec.lock` appears in `THIRD_PARTY_NOTICES.md`.

After P0-08: P0-11 (streaming export with bounded RAM and low-storage simulation; `exportFolder` is a start), P0-14 (trimming approach, ADR-003, desk research plus harness). P0-04, P0-05, P0-07, P0-10, P0-12 and P0-13 need real devices: build harnesses and manual steps, then mark blocked.

## Files touched

New: `lib/platform/audio_capture/{audio_capture_engine,record_capture_engine}.dart`, `lib/domain/services/capture_settings.dart`, `lib/data/filesystem/{m4a_inspector,folder_export}.dart`, `lib/spikes/windows_mic_spike.dart`, `integration_test/p0_06_windows_mic_test.dart`, `test/fixtures/m4a_builder.dart`, `test/data/filesystem/{m4a_inspector,folder_export}_test.dart`, `test/domain/capture_settings_test.dart`, `test/spikes/windows_mic_spike_test.dart`.
Changed: `pubspec.yaml`, `pubspec.lock`, `windows/flutter/generated_plugin_registrant.cc`, `windows/flutter/generated_plugins.cmake`, `docs/PLATFORM_FEASIBILITY.md`, `docs/ARCHITECTURE.md`, `docs/TEST_PLAN.md`, `docs/DECISIONS.md`, `docs/PROGRESS.md`, `docs/HANDOVER.md`.

## Watch out

- This PC's agent session is Remote Desktop: no microphone, and probably no camera either. Device spikes cannot run here unattended.
- `record` on Windows silently picks the nearest supported AAC setting. Always store what `M4aInspector` reads from the file, never the request.
- Android: `RECORD_AUDIO` is not in the manifest yet (P0-04 / P1-11). The APK builds, but capture would fail.
- The integration test is not part of `flutter test`. Run it with `-d windows`.
- Earlier notes still apply: schema changes need `make-migrations` and a migration test, never rename enum keys, commit generated files, write files with the editor tool rather than multi-file bash heredocs, do not build from a path with `~`.
- Holding a Windows file lock in the same process and then reading the file made a test hang. Do not use locks for failure injection; `exportFolder` has an `onFileDone` callback instead.

## Failing or skipped tests

None failing in `flutter test`. Nothing skipped. `integration_test/p0_06_windows_mic_test.dart` fails on this PC because there is no microphone in the session (blocked, expected). No device tests have been run on any platform.

## Open questions for the owner

- Please run MT-16 (`docs/TEST_PLAN.md`): sign in at this PC (or a Surface), then `flutter test integration_test/p0_06_windows_mic_test.dart -d windows`. It records about 12 seconds of room audio into your temp folder. Or enable RDP audio recording redirection for the agent's session.
- Please review ADR-006 (own M4A reader, folder export rules, spike code in `lib/spikes/`).
- Earlier questions still open: ADR-005 review (private reflections, labels, FR-QUAL-03 pinning); app icon exports; GitHub remote for CI; `com.samlytics.attenlume` and publisher name; MIT or Apache 2.0 after P0-08; real devices for P0-04, P0-05, P0-07, P0-10, P0-12, P0-13 (iOS needs a Mac or macOS CI with signing); Windows 96 kbps (43 MB per hour) acceptable or evaluate a bundled low-bitrate encoder (ADR-002); permission wording in `docs/PRIVACY_AND_SAFETY.md` 6 and release blockers in `docs/RELEASE_PLAN.md` 8.

## Commands to run

```powershell
cd C:\dev\attenlume
flutter pub get
dart run build_runner build
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed lib test tool integration_test
# Device test (needs a microphone in the session):
flutter test integration_test/p0_06_windows_mic_test.dart -d windows
```
