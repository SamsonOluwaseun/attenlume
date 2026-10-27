# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5), overnight relay
Branch: main (merged from `phase-1/P1-18-trim-split`)
Current task ID: P1-18 (done). Next: P1-19
Status: done

## Done in this session

- ADR-036 (P1-18 done): the review screen has a "Trim and split" panel. Trim start to here, Trim end from here, and Start cut here / End cut here add rows to `cut_ranges`; each add or remove shows a snackbar with Undo (soft delete and restore). The cut list shows each range with its reason; tap to jump, x to remove.
- `ReviewPlayerController.cutRanges`: merged cuts are skipped while playing, across gaps; a trimmed end stops playback. The timeline strip draws hatched cut spans and counts them in its semantics label; the position row shows time "after cuts" (`ReviewTimeline.keptAudioMs`, `audioEndMs`).
- `ActivityRepository.split` (one transaction) and `ActivitySplitter` (moves waveform summaries): Split here asks for the Part 2 name, moves later segments, photos, bookmarks and interruptions, divides cuts, and shares a segment the split falls inside (second row, same file, a cut on each side). New activity offsets follow the 9.4 rule from its first segment.
- 16 new tests; `flutter test` 681 passed, analyze and format clean, J2 journey test passes on Windows.

## Left to do on this task

- Nothing in code. Device checks in MT-25.

## Exact next step

Start **P1-19 Permanent trim per ADR-003** on branch `phase-1/P1-19-permanent-trim` (FR-REV-06, FR-REV-07). Read ADR-003 and ADR-036 first. Important: `lib/platform/audio_trimmer/m4a_container_trimmer.dart` writes placeholder audio bytes (it was a P0-14 container spike), so a real trimmer is needed: native `MediaExtractor` + `MediaMuxer` on Android, `AVAssetExportSession` passthrough on iOS, and on Windows either Media Foundation or a real Dart MP4 sample-table rewrite (copy `stsz`/`stco` sample ranges). Keep it behind `AudioTrimmer`; "Apply trims permanently" must be a separate confirmed action that writes new files and only then offers to remove originals. After ADR-036, two segment rows can name the same file: never offer to remove a file another row still names. Keep `integration_test/app_capture_journey_test.dart` passing on Windows and run `powershell -File tooluild_windows_preview.ps1 -SkipTests` after each merge. Do not push or publish.

## Files touched

New: `lib/domain/services/activity_splitter.dart`, `lib/features/playback_review/trim_panel.dart`, `test/data/repositories/activity_split_test.dart`.
Changed: `lib/data/repositories/activity_repository.dart` (`split`, `ActivitySplitResult`), `lib/domain/services/review_timeline.dart` (`audioEndMs`, `keptAudioMs`), `lib/features/playback_review/review_player_controller.dart` (cut skipping), `lib/features/playback_review/review_screen.dart` (panel, undo snackbars, split dialog), `lib/features/playback_review/timeline_strip.dart` (cuts), tests `test/features/playback_review/review_player_controller_test.dart`, `test/features/playback_review/review_screen_test.dart`, `test/domain/review_timeline_test.dart`, docs (DECISIONS, TEST_PLAN, PROGRESS, HANDOVER).

## Failing or skipped tests

None failing: `flutter test` 681 passed. The P0 device spikes and MT-23 to MT-25 still need real hardware.

## Open questions for the owner

- **ADR-036 (new):** a split inside a segment does not cut the audio file: both activities point to the same file, each with a cut hiding the other part, so nothing is rewritten or deleted. Part 2 is named in the confirm dialog (default "{title} (Part 2)") and copies type, room, organisation, tags and privacy but not speakers or notes. There is no undo for a split yet. Say if you want an "undo split" or a merge action.
- **ADR-035 (new):** gallery import needs Android `READ_MEDIA_IMAGES`. Google Play only allows it for apps whose core use needs broad photo access; before a Play listing, decide whether to argue the case or switch Android to the system photo picker (no time-window filter). HEIC originals on Android are skipped (iOS hands over a JPEG). Duplicates are judged by time (within 1 s), large means over 15 MB or 24 MP. Say if you want different rules.

- **ADR-034 (new):** playback uses `audioplayers` (one publisher for Android, iOS and Windows) instead of the planned `just_audio` + `just_audio_windows`. The waveform is drawn from the input level sampled while recording (200 ms), not decoded from the audio, so it shows loudness rather than exact peaks, and recordings made before this change show a flat line. Say if you want decoded waveforms (needs a native decoder or FFmpeg).
- **ADR-033 (new):** Ctrl+B adds a bookmark only while the Attenlume window has focus. A system-wide hotkey needs a new native package (for example `hotkey_manager`) and is left for Phase 2 or P1-27. Notes are shown as plain Markdown text, not rendered. Say if you want either sooner.
- **ADR-030 (new):** Photo opens a full-screen camera (two taps for the first photo, one for each after). Photos are stored at a 2048 px long edge, JPEG quality 85. Say if you want a different size or a small preview on the recording screen instead.
- **Overnight relay:** Claude Code blocked me from adding Codex to `tool/overnight.ps1` and from starting the relay, because the relay runs agents with all permission checks switched off (`--dangerously-skip-permissions`, and for Codex `--dangerously-bypass-approvals-and-sandbox`). Your decision: start it yourself, or allow it in Claude Code settings. Codex also needs `npm i -g @openai/codex` and `codex login`.
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
flutter build windows --release
flutter build apk --debug
```
