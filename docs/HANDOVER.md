# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5), unattended run
Branch: main (P1-09 merged from `phase-1/P1-09-profiles`)
Current task ID: P1-09 (done). Next: P1-10
Status: done

## Done in this session

- P1-09 recording profiles and selector with estimates [FR-QUAL-01 to 08, FR-UI-08]. Details in `docs/PROGRESS.md`, `docs/ARCHITECTURE.md` 8.13 and ADR-023.
  - `lib/domain/services/profile_estimates.dart`: effective MB per hour and safe time left above the hard reserve, FR-QUAL-05 notice.
  - `lib/features/capture/recording_profile_selector.dart`: `RecordingProfileSelector`, used on the activity detail sheet (override before recording, live change while recording or paused, hidden once recorded).
  - Conference wizard now asks before moving unrecorded activities to a new default (`profile_bulk_change_dialog.dart`, `ConferenceRepository.countUnrecordedInheritingActivities`).
  - 23 new tests, 504 total, all passing. Windows release and debug APK build. No new packages.

## Left to do on this task

- Nothing in code. The wizard profile tiles and the activity editor dropdown still show the nominal figures (`mbPerHourLabel`); switch them to the effective ones in P1-25. Phones show "Space left unknown" until P1-12 adds their free-space probes.

## Exact next step

Start **P1-10 Recording screen UI with level meter and mic test** [FR-UI-01 to 06] on branch `phase-1/P1-10-recording-screen`. Read FR-UI-01 to 06 in the build guide and the recording screen in `docs/DESIGN_GUIDE.md` (navy `live-surface` in both themes, lime only for live status, red square Stop, 96 px record button, `timer` type). Start recordings only through `startRecordingFromUi` / `oneActiveCoordinatorProvider` (ADR-020). Put `RecordingProfileSelector` on the screen, apart from Record, with `live: true` while recording and `onChanged` to `RecordingService.changeProfile` (copy `_changeLiveProfile` from `activity_detail_sheet.dart`). Show `RecordingStatus.interruption` / `errorMessage` with Resume (ADR-021). The engine exposes levels for the meter; check `AudioCaptureEngine` and `FakeCaptureEngine`.

## Files touched

New:
- `lib/domain/services/profile_estimates.dart`, `lib/features/capture/recording_profile_selector.dart`, `lib/features/conferences/profile_bulk_change_dialog.dart`
- `test/domain/profile_estimates_test.dart`, `test/features/capture/recording_profile_selector_test.dart`

Changed:
- `lib/data/repositories/conference_repository.dart`, `lib/features/capture/recording_providers.dart`, `lib/features/conferences/activity_detail_sheet.dart`, `lib/features/conferences/conference_wizard_screen.dart`
- `test/data/repositories/conference_repository_test.dart`, `test/features/activities/activity_detail_sheet_test.dart`, `test/features/conferences/conference_wizard_test.dart`
- `docs/ARCHITECTURE.md`, `docs/DECISIONS.md` (ADR-023), `docs/TEST_PLAN.md`, `docs/PROGRESS.md`, `docs/HANDOVER.md`

## Failing or skipped tests

None failing in `flutter test` (504 passed). Device tests unchanged from the last run: `p0_13` fails on Windows by design (no shortcut bridge); `p0_05`, `p0_07`, `p0_10`, `p0_12` and `p0_06` fail on this PC because the Remote Desktop session has no microphone (expected, blocked). `p0_04` is skipped on Windows and has not run on any phone.

Notes for widget tests: any widget that shows `RecordingProfileSelector` needs `capturePlatformProvider` and `mediaFreeBytesProvider` overridden (see `test/features/activities/activity_detail_sheet_test.dart`). Widget tests that pump `AttenlumeApp` must override `crashRecoveryReportProvider` (see `test/app/app_test.dart`).

## Open questions for the owner

- **ADR-023 (new):** WAV is not offered in v1 (FR-QUAL-07 allows "off by default"). Say if you want a specialist WAV option sooner. A profile picked on an activity before recording is stored as its own setting even if it equals the conference default, so a later conference change will not move it. Say if you would rather it kept following the default.
- **ADR-023 (new):** on Windows every profile records at 96 kbps (encoder floor), so the selector shows 43.2 MB per hour for all three and a note explaining why. Say if you would rather hide the selector on Windows.
- **ADR-022:** crash recovery marks files automatically (parsed means `recovered`, anything else `damaged`, nothing deleted) and the prompt only reports and offers "Carry on recording". Say if you want a per-file choice. A force-killed segment will usually be damaged because M4A is unreadable until its index is written, so a crash can lose up to 10 minutes. Say if you want a spike on salvaging such files (rebuilding the index) sooner rather than later.
- **ADR-021:** non-camera interruptions are logged as `system` ("a call or another app") because Android audio focus and iOS interruptions do not say what caused them. Getting `call` exactly would need the phone-state permission, which ADR-013 rejected. Say if you want that.
- **ADR-021:** after a camera interruption, recording restarts as soon as the shot is done, without waiting for the system. If iOS refuses that, the user is asked to tap Resume. Say if you would rather wait for the system's signal.
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
cd C:\devttenlume
flutter pub get
dart run build_runner build
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed lib test tool integration_test
dart run tool/licence_audit.dart --check
flutter build windows --release
flutter build apk --debug
```
