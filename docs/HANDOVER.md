# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5), overnight relay
Branch: main (merged from `phase-1/P1-19-permanent-trim`)
Current task ID: P1-19 (done). Next: P1-20
Status: done

## Done in this session

- ADR-037 (P1-19 done): `Mp4SampleTrimmer` (`lib/platform/audio_trimmer/mp4_sample_trimmer.dart`) reads the MP4 sample tables (`lib/data/filesystem/mp4_sample_table.dart`) and copies the kept AAC frames byte for byte into a new fast-start file. No re-encode, pure Dart, the same on Android, iOS and Windows, behind `AudioTrimmer`.
- `PermanentTrimService` (`lib/domain/services/permanent_trim_service.dart`): plan from merged cuts, one new file per kept piece (`audio/segment-001-trim-1.m4a`), every file verified before one transaction (`MediaAssetRepository.replaceWithTrimmed`) swaps the rows. Cuts become gaps so photos and bookmarks keep their places; stored offsets shift if the first segment now starts later. Originals no other row names move to `audio/originals/` (kept out of crash recovery's unlinked check); `removeOriginals` deletes only on request. Waveform summaries are sliced.
- Review screen: "Apply trims permanently" under the cut list, a confirm dialog (removed and kept time, space needed), a spinner while writing, then "Remove the originals?" with Keep or Remove.
- 22 new tests; `flutter test` 703 passed, analyze and format clean, J2 journey test passes on Windows.

## Left to do on this task

- Nothing in code. Device checks in MT-26: real recordings from each platform, and playing trimmed files in other players.

## Exact next step

Start **P1-20 Storage Manager and cleanup** on branch `phase-1/P1-20-storage-manager` (FR-STO-05 to 07). Read ADR-036 and ADR-037 first: `file_path` can be shared by two segment rows (count bytes once, never delete a file another row names), and originals kept after a permanent trim sit in `activities/<id>/audio/originals/` with no row (list them as "originals kept after trimming" and offer to remove them; `MediaPaths.isKeptOriginal`, `PermanentTrimService.removeOriginals`). Waveform summaries (`waveforms/`) and thumbnails are derived. Deleting local copies needs a verified export first (FR-STO-06), which P1-21 provides, so build the screen and safe temporary cleanup first and keep that action off until export exists. Keep `integration_test/app_capture_journey_test.dart` passing on Windows and run `powershell -File tool/build_windows_preview.ps1 -SkipTests` after each merge. Do not push or publish.

## Files touched

New: `lib/data/filesystem/mp4_sample_table.dart`, `lib/platform/audio_trimmer/mp4_sample_trimmer.dart`, `lib/domain/services/permanent_trim_service.dart`, `test/fixtures/mp4_fixture.dart`, `test/platform/mp4_sample_trimmer_test.dart`, `test/domain/permanent_trim_service_test.dart`, `test/features/playback_review/permanent_trim_widget_test.dart`.
Changed: `lib/data/filesystem/media_paths.dart` (`trimmedSegment`, `originalsFolder`, `isKeptOriginal`), `lib/data/repositories/media_asset_repository.dart` (`replaceWithTrimmed`, `TrimmedSegment`), `lib/features/playback_review/review_screen.dart` (provider, apply flow, two dialogs), `lib/features/playback_review/trim_panel.dart` (button), docs (DECISIONS, TEST_PLAN, PROGRESS, HANDOVER).

## Failing or skipped tests

None failing: `flutter test` 703 passed. The P0 device spikes and MT-23 to MT-26 still need real hardware.

## Open questions for the owner

- **ADR-037 (new):** permanent trim is a pure-Dart passthrough copy of AAC frames instead of the native per-platform routes ADR-003 planned, so it works and is tested the same everywhere (iOS cannot be built here). Cuts land on AAC frames (about 21 ms). The trimmed files drop the MP4 edit list, so up to about 50 ms of encoder start-up silence may now be heard at the start. Originals are moved to `audio/originals/` and kept until you tap Remove originals; there is no undo after a permanent trim apart from those kept originals. Say if you want native trimming, a re-encode option, or originals deleted by default.

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
flutter test integration_test/app_capture_journey_test.dart -d windows
powershell -File tool/build_windows_preview.ps1 -SkipTests
flutter build apk --debug
```
