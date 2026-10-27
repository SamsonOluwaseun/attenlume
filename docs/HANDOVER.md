# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5), unattended run
Branch: main (P1-05 merged from `phase-1/P1-05-rolling-segments`)
Current task ID: P1-05 (done). Next: P1-06
Status: done

## Done in this session

- P1-05 rolling segment writer and atomic finalisation [FR-REC-03]. Details in `docs/PROGRESS.md`, `docs/ARCHITECTURE.md` 3 and 8.9, ADR-019.
  - `RecordingService`: injected `RollTimerFactory`, `segmentMaxDuration` (default 10 minutes), roll through `switchingSegment` with reason `roll`, timer cancelled on every segment end and on dispose, stale timers ignored.
  - Encoder writes `segment-NNN.partial.m4a`; finalise = inspect, hash, flush, rename to `segment-NNN.m4a`, then row update with the final path. Damaged files keep the partial name.
  - New `lib/data/filesystem/segment_commit.dart`, `MediaPaths.partial`/`isPartial`, optional `filePath` on `MediaAssetRepository.finaliseSegment`, `test/fixtures/fake_timers.dart`.
  - 20 new tests, 392 total, all passing. Windows release and debug APK build. No new packages.

## Left to do on this task

- Device check that the roll timer fires on time with the screen locked (iOS background audio; Android once P1-11 adds the foreground service). The P0-04 and P0-10 device runs will show it.
- Interruption-driven rolls belong to P1-07.

## Exact next step

Start **P1-06 one-active rule across all triggers** [FR-REC-04, AT-REC-04] on branch `phase-1/P1-06-one-active`. `RecordingService.start` already returns `StartOutcome.conflict` for a second activity. Add a `switchTo(activityId)` (stop old, start new under one lock hold) and a trigger source (ui, notification, shortcut, voice); build the prompt "'{title}' is still recording ({n} min). Stop it and start new / Keep it running / Cancel" as a widget with tests; non-visual triggers default to stop old and start new. Then P1-07 InterruptionCoordinator (seed in `lib/platform/interruptions/`) and P1-08 crash recovery, which must handle `writing` rows whose partial file was already renamed to the final name (ADR-019 point 3).

## Files touched

New:
- `lib/data/filesystem/segment_commit.dart`
- `test/domain/recording_service_roll_test.dart`, `test/data/filesystem/segment_commit_test.dart`, `test/fixtures/fake_timers.dart`

Changed:
- `lib/domain/services/recording_service.dart`, `lib/data/filesystem/media_paths.dart`, `lib/data/repositories/media_asset_repository.dart`
- `test/domain/recording_service_test.dart` (row path while writing is now the partial name)
- `docs/ARCHITECTURE.md`, `docs/DECISIONS.md` (ADR-019), `docs/TEST_PLAN.md`, `docs/PROGRESS.md`, `docs/HANDOVER.md`

## Failing or skipped tests

None failing in `flutter test` (392 passed). Device tests unchanged from the last run: `p0_13` fails on Windows by design (no shortcut bridge); `p0_05`, `p0_07`, `p0_10`, `p0_12` and `p0_06` fail on this PC because the Remote Desktop session has no microphone (expected, blocked). `p0_04` is skipped on Windows and has not run on any phone.

## Open questions for the owner

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
