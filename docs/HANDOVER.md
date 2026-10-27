# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5), overnight relay
Branch: main (merged from `phase-1/P1-15-gallery-import`)
Current task ID: P1-15 (done). Next: P1-18
Status: done

## Done in this session

- ADR-035 (P1-15 done): "Import photos taken during this activity" in the activity details. Lists gallery photos from the activity's recorded span (or actual start and end) with a margin (none, 2 min default, 5, 10), marks likely duplicates (unticked) and large files, asks "Import anyway?" for either, and imports the chosen photos as `gallery_import` with their gallery time, so offsets line up with the recording. Originals are copied, never moved or changed.
- `GallerySource` interface in `lib/platform/gallery/`: `PhotoManagerGallerySource` (Android, iOS, `photo_manager` 3.12.0, Apache-2.0) and `FolderGallerySource` (Windows: folder pick, EXIF `DateTimeOriginal`, modified-time fallback, background isolate). `PhotoCaptureService.importFile` now shared with manual import.
- Android `READ_MEDIA_IMAGES` and `READ_MEDIA_VISUAL_USER_SELECTED`, iOS `NSPhotoLibraryUsageDescription`.
- 17 new tests; `flutter test` 665 passed (twice), analyze and format clean, notices regenerated (147 packages, 0 flagged). Windows release and Android debug builds succeed. J2 journey test passes on Windows.

## Left to do on this task

- Nothing in code. Device checks in MT-24 (phone permissions including partial access, HEIC on iPhone and Android, Windows Camera Roll folder).

## Exact next step

Start **P1-18 Non-destructive trim with undo, split activity** on branch `phase-1/P1-18-trim-split` (FR-REV-04, FR-REV-05 in `docs/BUILD_GUIDE.md`). Build on `lib/features/playback_review/review_screen.dart`, `lib/domain/services/cut_range_math.dart`, `lib/domain/services/activity_split_service.dart` and `lib/data/repositories/cut_range_repository.dart` (inspect them first; much of the maths and storage already exists from P0-14 and P0-09). Trim start and end, exclude middle ranges stored in `cut_ranges` with soft-delete undo, show cuts on the timeline strip, and "Split at playhead" moving media and bookmarks by offset. The design board's Highlights / Timeline / Photos tabs can come with it. Keep `integration_test/app_capture_journey_test.dart` passing on Windows and run `powershell -File tooluild_windows_preview.ps1 -SkipTests` after each merge. Do not push or publish.

## Files touched

New: `lib/platform/gallery/gallery_source.dart`, `lib/platform/gallery/photo_manager_gallery_source.dart`, `lib/platform/gallery/folder_gallery_source.dart`, `lib/domain/services/gallery_import_service.dart`, `lib/features/photos/gallery_import_sheet.dart`, tests `test/domain/gallery_import_service_test.dart`, `test/platform/folder_gallery_source_test.dart`, `test/features/photos/gallery_import_sheet_test.dart`, fixture `test/fixtures/fake_gallery_source.dart`.
Changed: `lib/domain/services/photo_capture_service.dart` (`importFile`), `lib/features/photos/activity_photos_section.dart` (new button, `timezone`), `lib/features/conferences/activity_detail_sheet.dart`, `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`, `pubspec.yaml`, `pubspec.lock`, `THIRD_PARTY_NOTICES.md`, `windows/flutter/` generated files, docs (ARCHITECTURE, PLATFORM_FEASIBILITY, TEST_PLAN, DECISIONS, PROGRESS, HANDOVER).

## Failing or skipped tests

None failing: `flutter test` 665 passed. The P0 device spikes, MT-23 and MT-24 still need real hardware.

## Open questions for the owner

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
