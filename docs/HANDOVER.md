# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5), unattended run
Branch: main (P1-08 merged from `phase-1/P1-08-crash-recovery`)
Current task ID: P1-08 (done). Next: P1-09
Status: done

## Done in this session

- P1-08 crash recovery and reconciliation [FR-REC-08, AT-REC-03]. Details in `docs/PROGRESS.md`, `docs/ARCHITECTURE.md` 3 and 8.12, ADR-022.
  - `CrashRecoveryService.reconcile()`: `writing` rows checked at their path and at the final name; parsed files `recovered` (fields from the file, renamed to the final name, never over an existing file), others `damaged` with zero span and kept. Open interruptions closed, `active` activities completed or back to draft, the held activity skipped, unlinked audio files listed.
  - `CrashRecoveryGate` wraps the welcome screen in `AttenlumeApp` and shows `CrashRecoveryDialog` once per start, with "Carry on recording" through the one-active coordinator.
  - 26 new tests, 481 total, all passing. Windows release and debug APK build. No new packages.

## Left to do on this task

- Nothing in code. P1-17 (timeline) and P1-21 (export) must treat `recovered` segments like finalised ones and `damaged` ones as gaps. Device check MT-13 / AT-REC-03 (force-kill on a phone and on Windows) is outstanding.

## Exact next step

Start **P1-09 Recording profiles and selector with estimates** [FR-QUAL-01 to 08, FR-UI-08] on branch `phase-1/P1-09-profiles`. Existing pieces to extend, not replace: `recording_profile_rules.dart` (precedence), `capture_settings.dart` (effective encoder settings, Windows 96 kbps floor, ADR-002), `RecordingService.changeProfile` (FR-QUAL-04, ADR-014), `storage_thresholds.dart` and the free-space probe (P0-11). Build the selector widget (MB per hour and safe time left, kept apart from Record), show effective settings when a profile is unavailable (FR-QUAL-05), and bulk change confirmation for unrecorded activities (FR-QUAL-03, see `ConferenceRepository`).

## Files touched

New:
- `lib/domain/services/crash_recovery_service.dart`, `lib/features/capture/crash_recovery_dialog.dart`
- `test/domain/crash_recovery_service_test.dart`, `test/features/capture/crash_recovery_dialog_test.dart`

Changed:
- `lib/app/app.dart`, `lib/data/filesystem/media_paths.dart`, `lib/data/repositories/activity_repository.dart`, `lib/data/repositories/media_asset_repository.dart`, `lib/features/capture/recording_providers.dart`
- `test/app/app_test.dart`, `test/data/filesystem/segment_commit_test.dart`
- `docs/ARCHITECTURE.md`, `docs/DECISIONS.md` (ADR-022), `docs/TEST_PLAN.md`, `docs/PROGRESS.md`, `docs/HANDOVER.md`

## Failing or skipped tests

None failing in `flutter test` (481 passed). Device tests unchanged from the last run: `p0_13` fails on Windows by design (no shortcut bridge); `p0_05`, `p0_07`, `p0_10`, `p0_12` and `p0_06` fail on this PC because the Remote Desktop session has no microphone (expected, blocked). `p0_04` is skipped on Windows and has not run on any phone.

Note for widget tests that pump `AttenlumeApp`: override `crashRecoveryReportProvider` (see `test/app/app_test.dart`), otherwise recovery reaches for `path_provider` and the real recorder. For widget tests that use the real database and `RecordingService`, futures made inside `testWidgets` only complete while the fake zone is pumped (see `test/features/capture/one_active_prompt_test.dart`).

## Open questions for the owner

- **ADR-022 (new):** crash recovery marks files automatically (parsed means `recovered`, anything else `damaged`, nothing deleted) and the prompt only reports and offers "Carry on recording". Say if you want a per-file choice. A force-killed segment will usually be damaged because M4A is unreadable until its index is written, so a crash can lose up to 10 minutes. Say if you want a spike on salvaging such files (rebuilding the index) sooner rather than later.
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
