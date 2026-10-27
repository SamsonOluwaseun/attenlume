# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5), unattended run
Branch: main (P0-13 merged from `phase-0/P0-13-shortcut-trigger-spike`)
Current task ID: P0-13 (blocked: needs real device). Next: P1-05
Status: blocked (harness done, device runs outstanding)

## Done in this session

- P0-13 spike harness: iOS App Intent and Android tile triggering a recording [FR-HF-01, FR-HF-04, FR-HF-05, AT-HF-01]. Details in `docs/PROGRESS.md`, `docs/PLATFORM_FEASIBILITY.md` 2.13.1 and ADR-018.
  - `lib/platform/shortcuts/`: `ShortcutCommand` (single `attenlume://` parser), `ShortcutBridge`, `MethodChannelShortcutBridge`, `NoShortcutBridge`.
  - Android: Quick Settings tile, three launcher shortcuts, deep-link intent filter, `ShortcutChannel.kt`. Compiles into the debug APK.
  - iOS: App Intents and Siri phrases, URL scheme, `ShortcutCommandCenter.swift` on `addSceneDelegate`. Not built (no Mac). `project.pbxproj` edited by hand.
  - `lib/spikes/shortcut_trigger_spike.dart`, `integration_test/p0_13_shortcut_trigger_test.dart`, manual steps MT-22.
  - 23 new tests, 372 total, all passing. Windows release and debug APK build. No new packages.
- Every Phase 0 task now has a harness. All device-bound ones are blocked: needs real device.

## Left to do on this task

- Run MT-22 on an Android 14+ phone and, once a Mac is available, an iPhone. Fill `PLATFORM_FEASIBILITY.md` 2.13.1 and the `TEST_PLAN.md` results log.
- First Mac build: check the hand-edited `project.pbxproj` and the two Swift files compile.
- Phase 2 (P2-01, P2-03) builds the real handler, confirmation and tile state on `ShortcutBridge`.

## Exact next step

Start **P1-05 rolling segment writer** on branch `phase-1/P1-05-rolling-segments`. Do a 10-minute roll through `switchingSegment`, reusing `_finishSegment` then `_tryBeginSegment` as `changeProfile` and `routeChanged` already do. Write to a temporary name and rename on finalisation, with an fsync before marking the segment finalised. Inject a timer factory so tests control time. Check section 17 for the next Phase 1 tasks whose dependencies are done (P1-06 one-active prompt, P1-07 interruption coordinator).

## Files touched

New:
- `lib/platform/shortcuts/shortcut_command.dart`, `lib/platform/shortcuts/shortcut_bridge.dart`
- `lib/spikes/shortcut_trigger_spike.dart`
- `integration_test/p0_13_shortcut_trigger_test.dart`
- `test/platform/shortcut_command_test.dart`, `test/spikes/shortcut_trigger_spike_test.dart`, `test/fixtures/fake_shortcut_bridge.dart`
- `android/app/src/main/kotlin/com/samlytics/attenlume/ShortcutChannel.kt`, `RecordTileService.kt`
- `android/app/src/main/res/values/strings.xml`, `res/drawable/ic_tile_record.xml`, `res/xml/shortcuts.xml`
- `ios/Runner/ShortcutCommandCenter.swift`, `ios/Runner/ShortcutIntents.swift`

Changed:
- `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/kotlin/com/samlytics/attenlume/MainActivity.kt`
- `ios/Runner/AppDelegate.swift`, `ios/Runner/Info.plist`, `ios/Runner.xcodeproj/project.pbxproj`
- `docs/ARCHITECTURE.md` (8.8, 9), `docs/DECISIONS.md` (ADR-018), `docs/PLATFORM_FEASIBILITY.md` (1, 2.13.1, 3), `docs/TEST_PLAN.md` (2.1, MT-22, AT-HF-01, results log), `docs/PROGRESS.md`, `docs/HANDOVER.md`

## Failing or skipped tests

None failing in `flutter test` (372 passed). Device tests: `integration_test/p0_13_shortcut_trigger_test.dart` fails on Windows by design (no shortcut bridge, so no trigger arrives). `p0_05`, `p0_07`, `p0_10`, `p0_12` and `p0_06` fail on this PC because the Remote Desktop session has no microphone (expected, blocked). `p0_04_background_recording_test.dart` is skipped on Windows and has not run on any phone.

## Open questions for the owner

- **Deep-link scheme (ADR-018):** FR-HF-05 names `conferencecompanion://`. This run used `attenlume://` to match the product name. Say if you also want the old scheme registered.
- **Project licence:** ADR-007 recommends Apache 2.0. Still waiting for your choice between Apache 2.0 and MIT, the copyright holder ("Samlytics Data Services") and whether to exclude the brand assets.
- **Device testing** is outstanding for P0-04 (MT-17), P0-05 (MT-21), P0-06 (MT-16), P0-07 (MT-20), P0-10 (MT-19), P0-12 (MT-18) and P0-13 (MT-22). A Windows laptop with a microphone, a webcam and a battery, signed in at the console, would unblock MT-16 and the Windows halves of MT-18 to MT-21 at once. MT-20 also needs Bluetooth headsets. MT-22 needs an Android 14+ phone, and a Mac and iPhone.
- ADR-018: the iOS test-only intent "Start recording without opening (test)" is visible in the Shortcuts app. It should be removed before release (P2-01). Say if you want it hidden sooner.
- ADR-017: photos start at `ResolutionPreset.veryHigh` (about 1080p). Say if you want a higher default for slides before the P1-14 legibility tests.
- ADR-017: if the iPhone shutter sound turns up in recordings, say whether that is acceptable (it cannot be silenced in some regions).
- ADR-016: a segment boundary is cut on every audio device change on Android and Windows. Say if you would rather accept missed boundaries than extra ones.
- ADR-016: should Android record from a connected Bluetooth mic by default, or keep the built-in mic unless the user picks one?
- ADR-012 lets a recording start when an activity's permission status is still `unknown`. Say if you want a per-activity prompt first.
- ADR-013 uses Android audio usage `media`. Review after the first Android run.
- ADR-014 always cuts a new segment on a profile change, even when the encoder settings are identical (Windows).
- ADR-015 defers `battery_plus`. Say if you would rather adopt it now.

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
# On an Android 14+ phone or an iPhone (MT-22):
flutter test integration_test/p0_13_shortcut_trigger_test.dart -d DEVICE_ID --dart-define=P0_13_SECONDS=300
flutter test integration_test/p0_13_shortcut_trigger_test.dart -d DEVICE_ID --dart-define=P0_13_SECONDS=300 --dart-define=P0_13_TILE_DIRECT=true
```
