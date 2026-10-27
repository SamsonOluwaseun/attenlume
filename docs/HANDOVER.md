# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5), unattended run
Branch: main (P1-07 merged from `phase-1/P1-07-interruptions`)
Current task ID: P1-07 (done). Next: P1-08
Status: done

## Done in this session

- P1-07 InterruptionCoordinator [FR-REC-05, FR-PHO-07]. Details in `docs/PROGRESS.md`, `docs/ARCHITECTURE.md` 3 and 8.11, ADR-021.
  - `RecordingService.interrupt(reason)` and `interruptionEnded(mayResume:)`: `recording -> interrupted -> recovering -> recording`, or `interrupted -> userResumeRequired`. Segments end with `interruption`; interruption rows log reason, start (segment end) and end (when the OS said it ended), `auto_resumed`. `resume()` refuses while interrupted, so the call is never recorded.
  - `InterruptionCoordinator`: audio session, camera (`duringCameraUse`, 2 s window) and route events to commands; notices through `InAppInterruptionNotices`.
  - Lost mic after a route change logs a `route_lost` row in the service (the P0-07 spike no longer writes its own).
  - `RecordingService` now activates and deactivates the audio session.
  - 36 new tests, 455 total, all passing. Windows release and debug APK build. No new packages.

## Left to do on this task

- Nothing in code. P1-10 must show `RecordingStatus.interruption` / `errorMessage` as a banner with Resume and show `InAppInterruptionNotices.notices`. P1-11 replaces the in-app notices with a notification that has a Resume action. P1-14 must take photos through `interruptionCoordinatorProvider.duringCameraUse`.
- Not built (ADR-016 consequence, still open): Android routed-device channel and Windows default-device query, so `input_route` stays null there. Also no marker yet when a recording falls back to another mic after the old one was removed (ADR-021 point 4).
- Device checks: MT-17 (calls, alarms) and MT-21 (camera) now exercise logic that lives in the app, not only the spikes. The spikes still use `pause()`.

## Exact next step

Start **P1-08 Crash recovery and reconciliation** [FR-REC-08] on branch `phase-1/P1-08-crash-recovery`. On launch, find `writing` segment rows: inspect the file at the row's path, and if it is missing, check the final name too (`MediaPaths` without `.partial`), because the rename may have happened before the row update (ADR-019 point 3). Mark rows `recovered` or `damaged`, never delete files (NFR-07). Also close any interruption row with `end_utc` null for an activity no longer held (crash during an interruption), and move `active` activities to a recoverable state. Treat the zero-length damaged row of a failed fallback as a gap (ADR-016).

## Files touched

New:
- `lib/domain/services/interruption_coordinator.dart`
- `test/domain/recording_service_interruption_test.dart`, `test/domain/interruption_coordinator_test.dart`, `test/fixtures/fake_interruption_source.dart`

Changed:
- `lib/domain/services/recording_service.dart`, `lib/domain/services/recording_state.dart`, `lib/features/capture/recording_providers.dart`, `lib/spikes/bluetooth_routing_spike.dart`
- `docs/ARCHITECTURE.md`, `docs/DECISIONS.md` (ADR-021), `docs/TEST_PLAN.md`, `docs/PROGRESS.md`, `docs/HANDOVER.md`

## Failing or skipped tests

None failing in `flutter test` (455 passed). Device tests unchanged from the last run: `p0_13` fails on Windows by design (no shortcut bridge); `p0_05`, `p0_07`, `p0_10`, `p0_12` and `p0_06` fail on this PC because the Remote Desktop session has no microphone (expected, blocked). `p0_04` is skipped on Windows and has not run on any phone.

Note for widget tests that use the real database and `RecordingService`: futures made inside `testWidgets` only complete while the fake zone is pumped. Pump with `tester.runAsync` ticks and dispose the recorder inside the test body (see `test/features/capture/one_active_prompt_test.dart`), or `tearDown` hangs.

## Open questions for the owner

- **ADR-021 (new):** non-camera interruptions are logged as `system` ("a call or another app") because Android audio focus and iOS interruptions do not say what caused them. Getting `call` exactly would need the phone-state permission, which ADR-013 rejected. Say if you want that.
- **ADR-021 (new):** after a camera interruption, recording restarts as soon as the shot is done, without waiting for the system. If iOS refuses that, the user is asked to tap Resume. Say if you would rather wait for the system's signal.
- **ADR-020:** "Keep it running" leaves the old recording and lets the app open the new activity for notes and photos without audio; "Cancel" does nothing. Say if you meant something else by the two options. Notification start actions are treated as able to show the prompt; say if they should switch straight away like shortcuts.
- **ADR-019:** segments roll every 10 minutes (the build guide minimum). Say if you would rather have shorter segments (less lost on a crash, more files) or longer ones.
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
```
