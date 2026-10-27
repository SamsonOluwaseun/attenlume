# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5), unattended run
Branch: main (P1-06 merged from `phase-1/P1-06-one-active`)
Current task ID: P1-06 (done). Next: P1-07
Status: done

## Done in this session

- P1-06 one-active rule across all triggers [FR-REC-04, AT-REC-04]. Details in `docs/PROGRESS.md`, `docs/ARCHITECTURE.md` 3 and 8.10, ADR-020.
  - `RecordingService.switchTo(activityId, {replacing})`: checks the new activity, stops and saves the old one, starts the new one, under one lock hold.
  - `OneActiveCoordinator` with `RecordingTrigger` (`ui`, `notification` prompt; `shortcut`, `voice` stop old, start new and confirm via `TriggerConfirmationSink`).
  - `OneActivePromptDialog` and `startRecordingFromUi`; `oneActiveCoordinatorProvider`, `triggerConfirmationsProvider`.
  - 27 new tests, 419 total, all passing. Windows release and debug APK build. No new packages.

## Left to do on this task

- Nothing in code. P1-10 (recording screen), P1-11 (notification actions) and P2 shortcut handlers must start recordings through `oneActiveCoordinatorProvider`, never `RecordingService.start` directly.
- Show `InAppTriggerConfirmations.messages` as a banner once there is a screen for it (P1-10); replace with notification and haptic in P1-11.
- Device check of a background shortcut switch (MT-22).

## Exact next step

Start **P1-07 InterruptionCoordinator** [FR-REC-05, FR-PHO-07] on branch `phase-1/P1-07-interruptions`. Seed code is in `lib/platform/interruptions/` and the P0-04 and P0-05 spikes (`lib/spikes/background_recording_spike.dart`, `photo_during_recording_spike.dart`) already map audio session events. Add `RecordingService` commands for `recording -> interrupted -> recovering -> recording` and `interrupted -> userResumeRequired`, finalise the segment with an interruption end reason, log interruption rows (reason, start, end), and never record the call. Then P1-08 crash recovery, which must handle `writing` rows whose partial file was already renamed (ADR-019 point 3).

## Files touched

New:
- `lib/domain/services/one_active_coordinator.dart`
- `lib/features/capture/one_active_prompt_dialog.dart`
- `test/domain/one_active_coordinator_test.dart`, `test/features/capture/one_active_prompt_test.dart`

Changed:
- `lib/domain/services/recording_service.dart`, `lib/features/capture/recording_providers.dart`, `lib/spikes/shortcut_trigger_spike.dart` (comment only)
- `docs/ARCHITECTURE.md`, `docs/DECISIONS.md` (ADR-020), `docs/TEST_PLAN.md`, `docs/PROGRESS.md`, `docs/HANDOVER.md`

## Failing or skipped tests

None failing in `flutter test` (419 passed). Device tests unchanged from the last run: `p0_13` fails on Windows by design (no shortcut bridge); `p0_05`, `p0_07`, `p0_10`, `p0_12` and `p0_06` fail on this PC because the Remote Desktop session has no microphone (expected, blocked). `p0_04` is skipped on Windows and has not run on any phone.

Note for widget tests that use the real database and `RecordingService`: futures made inside `testWidgets` only complete while the fake zone is pumped. Pump with `tester.runAsync` ticks and dispose the recorder inside the test body (see `test/features/capture/one_active_prompt_test.dart`), or `tearDown` hangs.

## Open questions for the owner

- **ADR-020 (new):** "Keep it running" leaves the old recording and lets the app open the new activity for notes and photos without audio; "Cancel" does nothing. Say if you meant something else by the two options. Notification start actions are treated as able to show the prompt; say if they should switch straight away like shortcuts.
- **ADR-019 (new):** segments roll every 10 minutes (the build guide minimum). Say if you would rather have shorter segments (less lost on a crash, more files) or longer ones.
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
