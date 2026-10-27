# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5), overnight relay
Branch: main (merged from `phase-1/P1-17-player-timeline`)
Current task ID: P1-17 (done). Next: P1-15
Status: done

## Done in this session

- ADR-034 (P1-17 done): review screen opened with "Play and review" in the activity details. Player joins an activity's segments (play/pause, tap or drag to scrub, 15 s skips in audio time, speeds 0.75 to 2), timeline strip with segments, gaps, interruptions, photos and bookmarks at their offsets, paged waveform (2-minute pages that read only their bytes), Key moments list that jumps to bookmarks and photos.
- `audioplayers` 6.8.1 behind `AudioPlaybackEngine`; `WaveformSummaryRecorder` writes `waveforms/<segment_id>.wave` while each segment records.
- 28 new tests; `flutter test` 648 passed, analyze and format clean, notices regenerated. Windows release and Android debug builds succeed. J2 journey test passes on Windows.

## Left to do on this task

- Nothing in code. Device checks in MT-23 (playback, seeking accuracy in M4A, speed, gap handling, lock screen). The design board's Highlights / Timeline / Photos tabs can come with P1-18, which adds trim and split to `ReviewScreen`.

## Exact next step

Start **P1-15 Gallery import by time window** on branch `phase-1/P1-15-gallery-import` (FR-PHO-05 in `docs/BUILD_GUIDE.md`): "Import photos taken during this activity" lists camera-roll photos between the activity's start and end with a 2-minute margin, confirm before import, warn on large or duplicate files. Check `photo_manager` (planned, Apache-2.0, no Windows support: on Windows fall back to the existing `file_selector` import, ADR-031) before adopting it; reuse `PhotoCaptureService.importFiles` for copying, compression and thumbnails. Then P1-18 (trim with undo and split) builds on `lib/features/playback_review/review_screen.dart` and `lib/domain/services/cut_range_math.dart`. Keep `integration_test/app_capture_journey_test.dart` passing on Windows and run `powershell -File tool\build_windows_preview.ps1 -SkipTests` after each merge. Do not push or publish.

## Files touched

New: `lib/domain/services/review_timeline.dart`, `lib/domain/services/waveform_summary_recorder.dart`, `lib/data/filesystem/waveform_summary.dart`, `lib/platform/audio_playback/audio_playback_engine.dart`, `lib/platform/audio_playback/audioplayers_playback_engine.dart`, `lib/features/playback_review/` (`review_screen.dart`, `review_player_controller.dart`, `timeline_strip.dart`, `waveform_pages.dart`, `waveform_view.dart`), tests `test/domain/review_timeline_test.dart`, `test/domain/waveform_summary_recorder_test.dart`, `test/data/filesystem/waveform_summary_test.dart`, `test/features/playback_review/`, fixture `test/fixtures/fake_playback_engine.dart`.
Changed: `pubspec.yaml`, `pubspec.lock`, `THIRD_PARTY_NOTICES.md`, `lib/data/filesystem/media_paths.dart`, `lib/features/capture/recording_providers.dart`, `lib/features/conferences/activity_detail_sheet.dart`, docs (ARCHITECTURE, PLATFORM_FEASIBILITY, TEST_PLAN, DECISIONS, PROGRESS, HANDOVER).

## Failing or skipped tests

None failing: `flutter test` 648 passed. The P0 device spikes and MT-23 still need real hardware.

## Open questions for the owner

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
