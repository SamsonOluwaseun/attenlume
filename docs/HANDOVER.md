# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5), unattended run
Branch: main (P0-05 merged from `phase-0/P0-05-photo-during-recording-spike`)
Current task ID: P0-05 (blocked: needs real device). Next: see "Exact next step"
Status: blocked (harness done, device runs outstanding)

## Done in this session

- P0-05 spike harness for photo capture during recording [FR-PHO-07, FR-PHO-01, AT-PHO-01]. Details in `docs/PROGRESS.md`, `docs/PLATFORM_FEASIBILITY.md` 2.7.1 and ADR-017.
  - Adopted `camera` 0.12.1 and `camera_windows` 0.3.0+1 (BSD-3). Licence audit regenerated, 129 packages, nothing flagged.
  - `lib/platform/camera/`: `PhotoCamera` interface, `PluginPhotoCamera` (`enableAudio: false`), `moveCapturedFile`.
  - `MediaPaths.photo`, optional `id` on `MediaAssetRepository.addPhoto`.
  - `lib/spikes/photo_during_recording_spike.dart`: 20 photos during a recording, `camera` interruptions resume after the shot, gaps matched to interruption rows.
  - `integration_test/p0_05_photo_during_recording_test.dart`, manual steps MT-21 in `docs/TEST_PLAN.md`.
  - Android `CAMERA` permission, iOS `NSCameraUsageDescription`.
  - 14 new tests, 349 total, all passing. Windows release and debug APK build.
- Ran the device test on this host with `-d windows`, 2 photos: start failed ("No audio recording device was found.") and no camera listed (RDP session). Recorded as blocked.

## Left to do on this task

- Run MT-21 on an Android phone, an iPhone (needs a Mac) and a Windows laptop or Surface with a camera. Fill `PLATFORM_FEASIBILITY.md` 2.7.1 and the `TEST_PLAN.md` results log.
- P1-14 builds the in-app camera UI on `PhotoCamera` (compression, thumbnails, SHA-256, permission denial). P1-07 takes over camera interruptions.

## Exact next step

Every Phase 0 task now has a harness except P0-13 (App Intent and Android tile, Phase 2 feasibility only). Choices:

1. **P0-13 feasibility harness**: Android Quick Settings `TileService` and an iOS App Intent that open the app and start recording through `RecordingService`, behind a `ShortcutBridge` interface. Native Kotlin and Swift; iOS cannot be built here. Document what each OS allows for starting the mic from the background.
2. **P1-05 rolling segment writer** on branch `phase-1/P1-05-rolling-segments`: 10-minute roll through `switchingSegment`, reusing `_finishSegment` then `_tryBeginSegment` as `changeProfile` and `routeChanged` do. Temporary name then rename on finalisation, fsync before marking finalised. Inject a timer factory so tests control time.

The agent prompt puts Phase 0 first, so P0-13 is next unless the owner says otherwise.

## Files touched

New:
- `lib/platform/camera/photo_camera.dart`, `lib/platform/camera/plugin_photo_camera.dart`
- `lib/spikes/photo_during_recording_spike.dart`
- `integration_test/p0_05_photo_during_recording_test.dart`
- `test/spikes/photo_during_recording_spike_test.dart`, `test/fixtures/fake_photo_camera.dart`

Changed:
- `pubspec.yaml`, `pubspec.lock`, `THIRD_PARTY_NOTICES.md`, `windows/flutter/generated_plugin_registrant.cc`, `windows/flutter/generated_plugins.cmake`
- `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`
- `lib/data/filesystem/media_paths.dart`, `lib/data/repositories/media_asset_repository.dart`
- `docs/ARCHITECTURE.md` (7, 8.7, 9), `docs/DECISIONS.md` (ADR-017), `docs/PLATFORM_FEASIBILITY.md` (1, 2.7.1), `docs/TEST_PLAN.md` (2.1, MT-21, AT-PHO-01, results log), `docs/PROGRESS.md`, `docs/HANDOVER.md`

## Failing or skipped tests

None failing in `flutter test` (349 passed). Device tests: `integration_test/p0_05_photo_during_recording_test.dart`, `p0_07_bluetooth_routing_test.dart`, `p0_10_long_run_test.dart`, `p0_12_profile_switch_test.dart` and `p0_06_windows_mic_test.dart` fail on this PC (no microphone in the Remote Desktop session, expected, blocked). `p0_04_background_recording_test.dart` is skipped on Windows and has not run on any phone.

## Open questions for the owner

- **Project licence:** ADR-007 recommends Apache 2.0. Awaiting choice between Apache 2.0 and MIT, copyright holder ("Samlytics Data Services") and brand asset exclusion.
- **Device testing** for P0-04 (MT-17), P0-05 (MT-21), P0-06 (MT-16), P0-07 (MT-20), P0-10 (MT-19), P0-12 (MT-18), P0-13. A Windows laptop with a microphone, a webcam and a battery, signed in at the console, would unblock MT-16 and the Windows halves of MT-18 to MT-21 at once. MT-20 also needs Bluetooth headsets.
- ADR-017: photos start at `ResolutionPreset.veryHigh` (about 1080p). Say if you want a higher default for slides before the P1-14 legibility tests.
- ADR-017: the spike resumes recording straight after a shot if the camera interrupted it. If the iPhone shutter sound turns up in recordings, say whether that is acceptable (it cannot be silenced in some regions).
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
# On a connected phone or a Windows laptop with a microphone and a camera (MT-21):
flutter test integration_test/p0_05_photo_during_recording_test.dart -d DEVICE_ID --dart-define=P0_05_PHOTOS=20
```
