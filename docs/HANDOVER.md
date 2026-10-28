# Handover

Date and agent: 28 October 2026, Claude Code (Opus 5.5) as Lead
Branch: main (merged from `phase-1/P1-24-privacy` and `phase-1/P1-21-export`)
Current task ID: Android fixes (ADR-043) and mobile export sharing (ADR-042) done, 0.1.2. Next: P1-22, then P1-20
Status: done

## Done in this session

- **0.1.2 (ADR-042, ADR-043):** Android first-run database repair, recording no longer interrupted by `record`'s own audio focus, Resume from interrupted, branded launch screen, Share button for ZIP exports on Android and iOS. Verified on an Android 14 tablet emulator (`attenlume_test` AVD, started with `emulator -avd attenlume_test -gpu swiftshader_indirect`).

- **P1-24 Privacy UX and optional app lock** (ADR-041, report `docs/reports/P1-24.md`): `local_auth` behind `DeviceAuthenticator`, lock off by default with a 1-minute grace period, never stops a recording (Stop on the lock screen), fail-safe "Turn off app lock" when the device cannot check. Policy reminder before Record, recording banner, Privacy screen from My conferences. `MainActivity` is now `FlutterFragmentActivity` with AppCompat themes.
- **P1-21 Export service** (ADR-040, report `docs/reports/P1-21.md`): scopes, folder or stored ZIP, originals / trimmed copies / originals plus `cuts.json`, streaming on a background isolate, preflight, `checksums.sha256`, safe paths, private items excluded by default, sensitive-export warning before every export, sheet cannot be dismissed while running. `ExportContributor` is the extension point for P1-22.
- Codex review found and the builder fixed: a private-reflection leak in multi-paragraph thoughts, `activity.json` metadata for trimmed copies, `cuts.json` naming files not in the package, and the export sheet being dismissible mid-export.
- Team tooling: `tool/team_check.ps1` (analyze, format, tests and a Codex review for a worktree branch).
- `flutter test` 805 passed, analyze clean, J2 journey test passes on Windows.

## Bugs found while capturing the quick guide (28 October 2026, all four fixed in 0.1.4)

- **Android notification timer is wrong:** the recording notification shows a chronometer like 498110:29:20. The base time passed to the notification is not converted to the clock the chronometer uses (`SystemClock.elapsedRealtime`). `RecordingForegroundService.kt` / `ForegroundServiceCoordinator`.
- **Activity details sheet overlaps the status bar** on phones: the type and Saved chip sit under the clock. Needs a top safe-area inset in `activity_detail_sheet.dart`.
- **Notes show raw Markdown** (`**[Quick thought]**`) in the activity details. Render the markers as styled text.
- **"Set up with wizard"** wraps awkwardly on a phone (two lines, left aligned) on the welcome screen.
## Left to do on this task

- Nothing in code. Device checks: OS auth prompts (Android 7/8 AppCompat, iOS Face ID, Windows Hello), exports opened in Explorer and Files, trimmed exports of real recordings.

## Exact next step

1. **P1-22 Manifest, timeline CSV, README and prompt generation, Copy AI prompt** (FR-EXP-08, 09, section 15) on a new branch from main. Build on `ExportContributor` in the export service (ADR-040); `cuts.json` `file_name` is relative to the activity folder. Owner priority: one-click export for AI use.
2. **P1-20 Storage Manager**: work in progress (untested, from Antigravity and Codex) is on `phase-1/P1-20-storage-manager` (commit e7176c4, uses ADR-038). Merge main into it first; export now exists, so "delete local copies after a verified export" (FR-STO-06) can use `export_jobs` with verification `checksum`.

Keep `integration_test/app_capture_journey_test.dart` passing on Windows and run `powershell -File tool/build_windows_preview.ps1 -SkipTests` after each merge. Do not push or publish.

## Files touched

See `docs/reports/P1-21.md` and `docs/reports/P1-24.md`. Lead: `tool/team_check.ps1`, `tool/build_windows_preview.ps1`, `tool/windows_package/Install Attenlume.cmd`, docs (PROGRESS, HANDOVER).

## Failing or skipped tests

None failing: `flutter test` 805 passed. `free_space_probe_test` "Windows probe agrees with the OS figure" can fail when another process writes to the disk between its two reads (seen once with two builders running).

## Open questions for the owner

- **P1-21 (ADR-040):** contact name and contact details are left out of `activity.json` (other people's personal data). Phone exports go to the app's private documents folder with no share sheet yet (`share_plus` not added). Private reflections are found by a marker in the note text, not a database flag. Say if you want contacts included, a share sheet, or a proper private flag.
- **P1-24 (ADR-041):** app lock grace period is 1 minute; the app still locks during a recording (with Stop on the lock screen); errors where the device cannot check count as "unavailable" and let you turn the lock off. Starts from notifications or shortcuts cannot show the policy reminder. Say if you want any of these changed.
- **ADR-037 (new):** permanent trim is a pure-Dart passthrough copy of AAC frames instead of the native per-platform routes ADR-003 planned, so it works and is tested the same everywhere (iOS cannot be built here). Cuts land on AAC frames (about 21 ms). The trimmed files drop the MP4 edit list, so up to about 50 ms of encoder start-up silence may now be heard at the start. Originals are moved to `audio/originals/` and kept until you tap Remove originals; there is no undo after a permanent trim apart from those kept originals. Say if you want native trimming, a re-encode option, or originals deleted by default.

- **ADR-036 (new):** a split inside a segment does not cut the audio file: both activities point to the same file, each with a cut hiding the other part, so nothing is rewritten or deleted. Part 2 is named in the confirm dialog (default "{title} (Part 2)") and copies type, room, organisation, tags and privacy but not speakers or notes. There is no undo for a split yet. Say if you want an "undo split" or a merge action.
- **ADR-035 (new):** gallery import needs Android `READ_MEDIA_IMAGES`. Google Play only allows it for apps whose core use needs broad photo access; before a Play listing, decide whether to argue the case or switch Android to the system photo picker (no time-window filter). HEIC originals on Android are skipped (iOS hands over a JPEG). Duplicates are judged by time (within 1 s), large means over 15 MB or 24 MP. Say if you want different rules.

- **ADR-034 (new):** playback uses `audioplayers` (one publisher for Android, iOS and Windows) instead of the planned `just_audio` + `just_audio_windows`. The waveform is drawn from the input level sampled while recording (200 ms), not decoded from the audio, so it shows loudness rather than exact peaks, and recordings made before this change show a flat line. Say if you want decoded waveforms (needs a native decoder or FFmpeg).
- **ADR-033 (new):** Ctrl+B adds a bookmark only while the Attenlume window has focus. A system-wide hotkey needs a new native package (for example `hotkey_manager`) and is left for Phase 2 or P1-27. Notes are shown as plain Markdown text, not rendered. Say if you want either sooner.
- **ADR-030 (new):** Photo opens a full-screen camera (two taps for the first photo, one for each after). Photos are stored at a 2048 px long edge, JPEG quality 85. Say if you want a different size or a small preview on the recording screen instead.
- **ADR-026 (new):** Free space calculation for Android queries `StatFs.availableBytes` on `context.filesDir`, and iOS queries `volumeAvailableCapacityForImportantUsageKey` on the documents directory. Measured file growth rate averages over the active segment (after 5s) or prior activity segments, falling back to nominal profile rate. Hard stop reserve is 100 MB (`storage_low`). Confirm this meets expectations.
- **ADR-025:** Android notification channel is configured with `NotificationManager.IMPORTANCE_LOW` so ongoing timer updates and state changes do not emit repeated audible chimes. Confirm this meets expectation.
- **ADR-025:** Notification actions include compact Pause/Resume, Stop, Bookmark, and Photo. Photo dispatches `MainActivity` with `attenlume://photo?source=notification` since opening the camera requires an active foreground activity.
- **ADR-024:** Recording screen uses the navy `live-surface` (#00212B) in BOTH light and dark themes ('house lights down') to prevent screen glare in dark lecture halls.
- **ADR-023:** WAV is not offered in v1 (FR-QUAL-07 allows "off by default"). Say if you want a specialist WAV option sooner.
- **ADR-023:** On Windows every profile records at 96 kbps (encoder floor), so the selector shows 43.2 MB per hour for all three.
- **ADR-022:** Crash recovery marks files automatically (parsed means `recovered`, anything else `damaged`, nothing deleted).
- **ADR-021:** Non-camera interruptions are logged as `system` ("a call or another app") because Android audio focus and iOS interruptions do not say what caused them.
- **ADR-020:** "Keep it running" leaves the old recording and lets the app open the new activity for notes and photos without audio; "Cancel" does nothing.
- **ADR-019:** Segments roll every 10 minutes (the build guide minimum).
- **Signing key (ADR-027):** back up `%USERPROFILE%\attenlume-signing\` (keystore and `key.properties.backup` with the password) somewhere safe off this PC. Losing it means testers must uninstall, and lose their data, to update.
- **Device testing:** Outstanding for real devices (MT-16 to MT-22).

## Commands to run

```powershell
cd C:\dev\attenlume
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed lib test tool integration_test
dart run tool/licence_audit.dart --check
flutter test integration_test/app_capture_journey_test.dart -d windows
powershell -File tool/build_windows_preview.ps1 -SkipTests
powershell -File tool/team_check.ps1 -Worktree <path>
flutter build apk --debug
```