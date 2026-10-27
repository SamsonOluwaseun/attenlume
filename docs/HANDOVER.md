# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5), overnight relay
Branch: main (merged from `phase-1/P1-16-bookmarks-notes`)
Current task ID: P1-16 (done). Next: P1-17
Status: done

## Done in this session

- ADR-033 (P1-16 done): bookmarks section in the activity details (offset into the recording, time of day, label, note; tap to edit or remove), notes section with a plain-Markdown editor (Add notes / Edit notes), Ctrl+B on the recording screen adds a bookmark with source `hotkey`.
- `MediaAssetRepository.updateBookmarkText` and `deleteBookmark`; `formatOffset` in `lib/shared/utilities/date_formatters.dart`.
- 8 new tests; `flutter test` 620 passed, analyze and format clean. J2 journey test passes on Windows (no mic or camera here).

## Left to do on this task

- Nothing in code. FR-BMK-01 "appears on the review timeline and in exports" is delivered when P1-17 and P1-21/22 read `bookmarksFor`. iOS lock screen bookmark is Phase 2. Global Windows hotkey: see ADR-033.

## Exact next step

Start **P1-17 Player, timeline, waveform summaries** on branch `phase-1/P1-17-player-timeline` (`FR-REV-01 to 03` in `docs/BUILD_GUIDE.md`). The timeline must show segments, gaps, interruptions, photos and bookmarks at their offsets (`MediaAssetRepository.segmentsFor`, `photosFor`, `bookmarksFor`; offset rule in `lib/domain/services/timeline_offset.dart`). Check `just_audio` Windows support before adopting it (ADR needed). P1-15 (gallery import by time window, `photo_manager`) is still todo and can follow. Keep `integration_test/app_capture_journey_test.dart` passing on Windows and run `powershell -File tooluild_windows_preview.ps1 -SkipTests` after each merge. Do not push or publish.

## Files touched

New: `lib/features/bookmarks/activity_bookmarks_section.dart`, `lib/features/bookmarks/activity_notes_section.dart`, `test/features/bookmarks/activity_bookmarks_notes_test.dart`.
Changed: `lib/data/repositories/media_asset_repository.dart`, `lib/shared/utilities/date_formatters.dart`, `lib/features/conferences/activity_detail_sheet.dart`, `lib/features/capture/recording_screen.dart`, `test/data/repositories/media_repositories_test.dart`, `test/shared/date_formatters_test.dart`, `test/features/capture/recording_screen_test.dart`, docs.

## Failing or skipped tests

None failing: `flutter test` 620 passed. The P0 device spikes still need real hardware.

## Open questions for the owner

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
