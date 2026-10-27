# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5), attended session continued while the owner was away
Branch: main (merged from `phase-1/P1-13-safety-prompts`)
Current task ID: P1-13 (done). Next: P1-16
Status: done

## Done in this session

- ADR-028: microphone permission prompt, quick start opens the recorder, specific refusal messages, Windows data in `%LOCALAPPDATA%\Samlytics\Attenlume`, J2 journey integration test, `tool/build_windows_preview.ps1`.
- ADR-029: Android 13+ notification permission requested when the recording service starts.
- ADR-032: safety prompts (2 hours, silence, low battery) on the recording screen, Android battery channel (P1-13 done).
- ADR-031: photo import with labels, captions, photos section in the activity details (P1-14 done).
- ADR-030 (P1-14 first slice): camera screen with live viewfinder, `PhotoCaptureService`, `processPhoto` (EXIF rotation, 2048 px, JPEG 85, 320 px thumbnails, SHA-256), access-denied and no-camera messages, new dependency `image` 4.12.0.
- Working loop agreed with the owner: check on the Windows laptop first, then ship to Android. Windows previews go to `C:\dev\attenlume-release\windows\` with the desktop shortcut "Attenlume (preview)".

## Left to do on this task

- Nothing in code for P1-13 or P1-14. Thresholds become editable in P1-25 (Settings). iOS battery channel needs a Mac.

## Exact next step

Start **P1-16 Bookmarks and notes** on branch `phase-1/P1-16-bookmarks-notes` (`FR-BMK-01 to 03` in `docs/BUILD_GUIDE.md`). Then P1-17 (player, timeline, waveform). Keep `integration_test/app_capture_journey_test.dart` passing on Windows and run `powershell -File tool\build_windows_preview.ps1 -SkipTests` after each merge. Do not push or publish; the owner releases Android 0.1.1 after checking Windows.

## Files touched

New: `lib/features/capture/camera_screen.dart`, `lib/domain/services/photo_capture_service.dart`, `lib/data/filesystem/photo_processor.dart`, `test/domain/photo_capture_service_test.dart`, `test/data/filesystem/photo_processor_test.dart`.
Changed: `lib/platform/camera/photo_camera.dart`, `lib/platform/camera/plugin_photo_camera.dart`, `lib/data/filesystem/media_paths.dart`, `lib/features/capture/recording_screen.dart`, `lib/features/capture/recording_providers.dart`, `android/.../ForegroundServiceChannel.kt`, `test/fixtures/fake_photo_camera.dart`, `test/features/capture/recording_screen_test.dart`, `integration_test/app_capture_journey_test.dart`, `pubspec.yaml`, `pubspec.lock`, `THIRD_PARTY_NOTICES.md`, docs.

## Failing or skipped tests

None failing: `flutter test` 596 passed. `app_capture_journey_test.dart` passes on this PC up to the microphone and camera checks (none in the Remote Desktop session). The P0 device spikes still need real hardware.

## Open questions for the owner

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
