# Architecture

**Status:** draft from task P0-01, updated in P0-02 (27 October 2026, Claude Code, Opus 5.5). The scaffold exists (section 8). The rest describes the planned design. Update it as each task lands.
**Spec:** `docs/BUILD_GUIDE.md` sections 9 and 12. Platform evidence: `docs/PLATFORM_FEASIBILITY.md`.

---

## 1. Principles

1. **Offline-first (NFR-01).** No network code in the core. Cloud and AI live in separate feature folders added in later phases.
2. **Platform behind interfaces.** Every OS-specific capability (capture, free space, foreground service, interruptions, camera, gallery) is a Dart interface in `lib/platform/` with one implementation per platform and a fake for tests. Spikes can change an implementation without touching features.
3. **Database first, then disk.** Write metadata in a Drift transaction before any media byte is written (FR-REC-01). Recovery reconciles the two (FR-REC-08).
4. **Originals are immutable.** No code path deletes or rewrites a finalised segment or photo except an explicit, confirmed user action (NFR-07, FR-STO-06).
5. **Bounded memory.** Stream all file I/O. Hashing, export and import run in isolates (section 12 of the build guide).

## 2. Layers

```text
features/*            Widgets and Riverpod providers (UI state only)
   |
domain/services       RecordingService, StorageBudgetService, ConferenceExportService ...
domain/models         Plain immutable Dart classes, no Flutter imports
   |
data/repositories     Map Drift rows <-> domain models
data/local_database   Drift tables, DAOs, migrations
data/filesystem       MediaPaths, atomic writes, safe filenames
   |
platform/*            Interfaces + Android / iOS / Windows implementations + fakes
```

Rules:

- `domain/` does not import `package:flutter` or any plugin. That keeps services unit-testable on the Dart VM.
- Features talk to services through Riverpod providers. Services get their dependencies through constructors. Providers wire them up.
- Native code (Kotlin, Swift, C++) stays thin: start or stop, report events. State lives in Dart.

The folder layout is build guide section 9.2.

## 3. Recording lifecycle

```text
UI / notification / shortcut
        |
        v
RecordingService  (one instance, mutex around every command, FR-REC-09)
   |  state stream: IDLE, STARTING, RECORDING, PAUSED, SWITCHING_SEGMENT,
   |                INTERRUPTED, RECOVERING, USER_RESUME_REQUIRED,
   |                STOPPING, SAVED, STORAGE_STOP, ERROR_RECOVERABLE
   |
   +-- SegmentWriter       create row (state=writing) -> start AudioCaptureEngine
   |                        -> on roll/stop: stop engine, fsync, measure bytes and
   |                           duration, compute observed bitrate, state=finalised
   +-- InterruptionCoordinator  audio_session / audio focus / route events -> commands
   +-- StorageBudgetService     30 s ticks while recording, hard stop -> STORAGE_STOP
   +-- ForegroundServiceBridge  Android only: notification, actions
```

- **Built in P1-04 (ADR-012):** `RecordingService` in `lib/domain/services/recording_service.dart`, states and transitions in `recording_state.dart`, commands serialised by `SerialLock`. Pause and resume, start-failure handling, finalisation from the inspected file and mid-recording profile change (P0-12, ADR-014) are in. The 10-minute roll, interruptions and route changes are not yet.
- **One active recording (FR-REC-04):** `RecordingService` holds at most one active activity ID. A start request for another activity returns a `ConflictPending` result for the UI to resolve. Non-visual triggers use the documented default (stop old, start new) and post a notification.
- **Segment rolling (FR-REC-03):** roll on pause, interruption, profile change, route change and a 10-minute timer. Each roll is stop then start of a new file. The gap between them is recorded as real time (offset rule, build guide 9.4).
- **Crash recovery (FR-REC-08):** on launch, every segment with `state=writing` is checked. If its file exists and parses as a valid container, mark it `recovered`. If not, mark it `damaged` and keep the file. Never mark a damaged file as good.
- **Observed bitrate (FR-QUAL-06):** the `record` package does not report encoder output bitrate, so we compute `bytes * 8 * 1000 / duration_ms` after finalisation.

## 4. Storage and files

- Media root: `<app documents>/media/`. Paths in the database are relative to it (build guide 9.5) so iOS container moves do not break them.
- Atomic writes for every metadata file and every export member: write `name.tmp`, flush, rename.
- Export temp folder `<app cache>/exports-temp/<job_id>/` is tracked in `export_jobs` and safe to clear.
- `FreeSpaceProbe` per platform (see `PLATFORM_FEASIBILITY.md` 2.9). `StorageBudgetService` estimates minutes left from measured growth of the current segment, falling back to the profile's nominal rate.

## 5. Export

- `ConferenceExportService` builds an export plan (list of members with source path, target path, size), runs preflight (size and free space, FR-EXP-05), then streams members one at a time into a folder or a ZIP (`archive`, store method, ZIP64 when needed).
- SHA-256 per member computed while copying, written to `checksums.sha256` last.
- `SafeNames` turns titles into ASCII slugs, rejects Windows reserved names, trims trailing dots and spaces, caps folder names at 60 characters and relative paths at 180 (FR-EXP-07).
- Re-import (FR-EXP-11) reads `conference.json` and `activity.json`, checks checksums, then inserts with fresh IDs mapped from the originals.

## 6. Dependencies (audited in P0-01)

Data pulled from pub.dev on 27 October 2026 with `tool/pub_audit.py` (latest version, publish date, verified publisher, licence and platform tags from pub.dev analysis). "Tested" versions get pinned in `pubspec.yaml` during P0-02 and listed in section 7 once a build and tests pass with them. Licences are pub.dev's detected licence. The full review was P0-08: `THIRD_PARTY_NOTICES.md` and ADR-007.

Toolchain: Flutter 3.47.8 stable, Dart 3.13.7. Every package below accepts Dart 3.13.

### 6.1 Chosen for Phase 0 and 1

| Package | Version | Released | Publisher | Licence | Platforms (pub.dev) | Use |
|---|---|---|---|---|---|---|
| flutter_riverpod | 3.4.3 | 2026-09-03 | dash-overflow.net | MIT | A, I, W | State |
| riverpod_annotation / riverpod_generator | 4.0.7 / 4.0.9 | 2026-09-03 | dash-overflow.net | MIT | A, I, W | Optional codegen. Decide in P0-02 |
| drift | 2.35.3 | 2026-10-23 | simonbinder.eu | MIT | A, I, W | Database |
| drift_flutter | 0.3.1 | 2026-07-11 | simonbinder.eu | MIT | A, I, W | Opens the DB on each platform |
| timezone | 0.11.2 | 2026 (dart-lang/labs) | dart.dev labs (Dart team) | BSD-3 | pure Dart, all | Conference-local times from the bundled IANA database, offline (added in P0-09, ADR-005) |
| drift_dev (dev) | 2.35.2 | 2026-10-23 | simonbinder.eu | MIT | tooling | Codegen, schema dumps for migration tests |
| sqlite3 | 3.8.0 | 2026-10-23 | simonbinder.eu | MIT | A, I, W | Bundles SQLite through build hooks |
| build_runner (dev) | 2.17.1 | 2026-10-14 | tools.dart.dev | BSD-3 | tooling | |
| record | 7.1.2 | 2026-10-09 | cow-level.ovh | BSD-3 | A, I, W | Audio capture |
| audio_session | 0.2.4 | 2026-06-29 | ryanheise.com | MIT | A, I | Interruptions, routing |
| just_audio | 0.10.6 | 2026-06-29 | ryanheise.com | MIT, Apache-2.0 | A, I | Playback |
| just_audio_windows | 0.2.3 | 2026-04-04 | bdlukaa.dev | MIT | W | Playback on Windows |
| camera | 0.12.1 | 2026-09-03 | flutter.dev | BSD-3 | A, I | Photos |
| camera_windows | 0.3.0+1 | 2026-10-21 | flutter.dev | BSD-3 | W | Photos on Windows, add explicitly |
| photo_manager | 3.12.0 | 2026-08-09 | fluttercandies.com | Apache-2.0 | A, I | Gallery time-window import |
| image | 4.12.0 | 2026-10-11 | taosengine.com | MIT | all | Resize, thumbnails, in an isolate |
| archive | 4.5.2 | 2026-10-13 | taosengine.com | MIT | all | Streaming ZIP with ZIP64 |
| audio_session | 0.2.4 | Adopted in P0-04 behind `AudioInterruptionSource` (ADR-013). Unit tests use a fake. Android and iOS: builds only (APK), iOS not built | 2026-10-27 |
| rxdart | 0.28.0 | Transitive through `audio_session` (Apache-2.0). Builds only | 2026-10-27 |
| camera | 0.12.1 (camera_android_camerax 0.7.6, camera_avfoundation 0.10.3+1, camera_platform_interface 2.15.0) | Adopted in P0-05 behind `PhotoCamera` (ADR-017). Windows release and APK debug builds. No photo taken on any device | 2026-10-27 |
| camera_windows | 0.3.0+1 | Added explicitly in P0-05. `availableCameras()` returns an empty list on the build host (no webcam in RDP) | 2026-10-27 |
| cross_file, flutter_plugin_android_lifecycle, camera_web | 0.3.5+5, 2.0.35, 0.3.5+6 | Transitive through `camera` (BSD-3). Builds only | 2026-10-27 |
| crypto | 3.0.8 | 2026-10-26 | dart.dev | BSD-3 | all | SHA-256 |
| path_provider | 2.1.6 | 2026-06-15 | flutter.dev | BSD-3 | A, I, W | App folders |
| path | 1.9.1 | 2024-10-17 | dart.dev | BSD-3 | all | Stable core package |
| permission_handler | 13.0.2 | 2026-09-04 | baseflow.com | MIT | A, I, W | Runtime permissions (Windows support is partial) |
| file_picker | 13.3.0 | 2026-10-26 | victorcarreras.dev | MIT | A, I, W | Export folder, manual import |
| share_plus | 13.3.1 | 2026-10-01 | fluttercommunity.dev | BSD-3 | A, I, W | Share exports |
| uuid | 4.6.0 | 2026-07-15 | yuli.dev | MIT | all | UUID v4 IDs |
| go_router | 18.1.1 | 2026-10-20 | flutter.dev | BSD-3 | A, I, W | Routing and `attenlume://` deep links |
| intl | 0.20.3 | 2026-06-25 | dart.dev | BSD-3 | all | Dates, UK English |
| timezone / flutter_timezone | 0.11.2 / 5.1.1 | 2026-10 | labs.dart.dev / wolverinebeach.net | BSD-2 / Apache-2.0 | all | Conference timezone |
| wakelock_plus | 1.8.2 | 2026-10-22 | fluttercommunity.dev | BSD-3 | A, I, W | Stop Windows sleeping mid-recording |
| battery_plus | 7.1.2 | 2026-10-01 | fluttercommunity.dev | BSD-3 | A, I, W | Battery safety prompt |
| flutter_local_notifications | 22.3.3 | 2026-10-25 | dexterx.dev | BSD-3 | A, I, W | "Recording resumed" and similar |
| win32 | 6.4.0 | 2026-08-05 | halildurmus.dev | BSD-3 | W | Free space, later hotkeys |
| local_auth | 3.0.2 | 2026-07-09 | flutter.dev | BSD-3 | A, I, W | Optional app lock |
| package_info_plus / device_info_plus | 10.2.2 / 13.3.0 | 2026-10-01 | fluttercommunity.dev | BSD-3 | A, I, W | App version in manifest, device in logs |
| lucide_icons_flutter | 4.0.1 | 2026-10-21 | vqhapp.name.vn | MIT (icons ISC) | all | Icon set per design guide |
| tray_manager | 0.8.0 | 2026-10-08 | leanflutter.dev | MIT | W | Tray indicator (P1-27). Needs Flutter 3.47+ |
| flutter_lints (dev) | 6.0.0 | 2025-05-27 | flutter.dev | BSD-3 | tooling | Lints, stricter rules added in `analysis_options.yaml` |
| mocktail (dev) | 1.0.5 | 2026-04-10 | felangel.dev | MIT | tooling | Test doubles |
| fake_async (dev) | 1.3.3 | 2025-01-28 | dart.dev | Apache-2.0 | tooling | Timer tests (10-minute roll, 30 s storage ticks) |
| flutter_launcher_icons (dev) | 0.14.4 | 2025-06-10 | fluttercommunity.dev | MIT | tooling | App icons from supplied PNG |

A = Android, I = iOS, W = Windows.

### 6.2 Fallbacks, kept in reserve

| Package | Version | Licence | Why reserve |
|---|---|---|---|
| flutter_foreground_task | 11.0.3 | MIT | If our own Kotlin foreground service is too costly (P1-11) |
| storage_space | 1.4.0 | BSD-3 | Free space on Android and iOS if the method channel is not enough |
| audioplayers | 6.8.1 | MIT | If `just_audio_windows` fails P0-06 |
| ffmpeg_kit_flutter_new | 4.6.7 | LGPL-3.0 | Trimming last resort, needs licence review (P0-14, P0-08) |
| flutter_image_compress | 2.5.1 | MIT | Faster native JPEG on mobile if `image` is too slow. No Windows |
| very_good_analysis (dev) | 11.0.0 | MIT | Stricter lint set if wanted |

### 6.3 Rejected

| Package | Reason |
|---|---|
| sqlite3_flutter_libs | Marked end of life (`0.6.0+eol`). `sqlite3` 3.x bundles SQLite itself |
| ffmpeg_kit_flutter | Discontinued on pub.dev (last release 2023) |
| lucide_icons | No release since 2023, Dart 2 only |
| system_tray | No release since 2023, Dart 2 only |
| disk_space_plus | No verified publisher, low adoption |
| just_audio_media_kit | Unlicense, no release since April 2025, bundles libmpv |
| flutter_sound | MPL-2.0 adds file-level copyleft obligations. `record` covers the need |
| audio_waveforms, just_waveform | No Windows. Waveform summaries are computed by our own code from decoded PCM pages (FR-REV-03) |
| webview_flutter | Not needed. No embedded sign-in forms (build guide 7.2) |

### 6.4 Phase 1.5 and 2, noted only

| Package | Version | Licence | Note |
|---|---|---|---|
| flutter_secure_storage | 11.2.0 | BSD-3 | All three platforms |
| flutter_appauth | 12.1.0 | BSD-3 | No Windows. Windows needs loopback PKCE |
| app_links | 7.2.2 | Apache-2.0 | Deep links if `go_router` alone is not enough |
| quick_actions | 1.1.1 | BSD-3 | Android and iOS app shortcuts |
| live_activities | 2.6.0 | MIT | iOS Live Activity bridge, needs Xcode target |
| hotkey_manager | 0.2.3 | MIT | No release since May 2024. Prefer `win32` `RegisterHotKey` |

## 7. Tested versions

Versions from `pubspec.lock` on `main` after P0-02. "Tested" means `flutter analyze` clean, `flutter test` passing (Dart VM, Windows host), `flutter build windows --debug` and `flutter build apk --debug` succeeding. No real-device run yet: every platform is **unverified** at runtime, except that the Windows debug build was launched on the build PC and opened a window titled "Attenlume". iOS has not been built (no Mac).

| Package | Version | Tested on | Date |
|---|---|---|---|
| Flutter / Dart | 3.47.8 / 3.13.7 | Windows 11 Pro 10.0.26200 build host | 2026-10-27 |
| flutter_riverpod (riverpod) | 3.4.3 | Unit and widget tests, Windows and APK builds | 2026-10-27 |
| drift | 2.35.3 | In-memory DB tests, schema verifier, v1 to v2 migration (P0-09) | 2026-10-27 |
| drift_flutter | 0.3.1 | Builds only (on-device open not yet exercised) | 2026-10-27 |
| sqlite3 | 3.8.0 | Build hooks bundle SQLite for tests and both builds | 2026-10-27 |
| path_provider | 2.1.6 | Builds only | 2026-10-27 |
| path | 1.9.1 | Builds only | 2026-10-27 |
| uuid | 4.6.0 | Repository tests (row IDs) | 2026-10-27 |
| timezone | 0.11.2 | Default title tests (Europe/London, America/New_York, Asia/Tokyo) | 2026-10-27 |
| drift_dev (dev) | 2.35.2 | Codegen, `make-migrations`, `schema generate` | 2026-10-27 |
| build_runner (dev) | 2.17.1 | Codegen | 2026-10-27 |
| flutter_lints (dev) | 6.0.0 | `flutter analyze` | 2026-10-27 |
| mocktail (dev) | 1.0.5 | Added, not used yet | 2026-10-27 |
| record | 7.1.2 (record_windows 2.3.0, record_android 2.2.0, record_ios 2.1.1) | Windows: encoder query true, no capture device in RDP session (P0-06). Android and iOS: builds only | 2026-10-27 |
| crypto | 3.0.8 | Streaming SHA-256 in folder export tests (P0-06) | 2026-10-27 |
| integration_test (dev, SDK) | Flutter 3.47.8 | P0-06 harness on Windows desktop | 2026-10-27 |
| yaml (dev) | 3.1.4 | Reads `pubspec.lock` in `tool/licence_audit.dart` (P0-08). Already in the lock through `hooks` | 2026-10-27 |

Build notes: Gradle installed CMake 3.22.1 into the Android SDK on the first APK build. Montserrat static TTFs (400, 500, 600, 700) come from the upstream Montserrat Project repo (`JulietaUla/Montserrat`, `fonts/ttf`), because the Google Fonts repo now ships only the variable font. SHA-256:

```text
3e8abe50c44c82e2242e97d1ec8c0d385c4890cdc50447bcdb8605c81a38cfb2  Montserrat-Regular.ttf
dae47428bb041f9716604e0e07b5b0c8585b3bdd8183362f75c69fe7bb3cfaf4  Montserrat-Medium.ttf
b4e1563393d73fdff491a869441245aef31add2ec03d9c97a6dae4de07c52fd0  Montserrat-SemiBold.ttf
bc6e854971cea46b463be6f9eef4d9cd52f51cfc1fc0dd90c9d3e6483dc0ec61  Montserrat-Bold.ttf
```

## 8. Code layout so far (P0-02)

- `lib/app/theme/tokens.dart`: generated from `design/tokens.json` by `tool/gen_tokens.dart`. Never edit by hand.
- `lib/app/theme/app_theme.dart`: `AppTheme.light()`, `.dark()`, `.live()` and the `AttenlumeColors` theme extension.
- `lib/data/local_database/app_database.dart`: Drift `AppDatabase`, schema v1 with `app_settings` only. DateTimes stored as UTC ISO 8601 text (`build.yaml`). Foreign keys on.
- `drift_schemas/`: schema dumps for migration tests. `test/data/local_database/generated/`: generated schema helpers.

### 8.1 Added in P0-06

- `lib/platform/audio_capture/`: `AudioCaptureEngine` interface and `RecordCaptureEngine` (`record` package). One file per start, rolling is stop then start.
- `lib/domain/services/capture_settings.dart`: profile to encoder request per platform (Windows 96 kbps floor, ADR-002).
- `lib/data/filesystem/m4a_inspector.dart`: reads codec, channels, sample rate, duration and bitrates from a finished M4A by walking box headers. Loads only `moov`. Rejects files without `moov`.
- `lib/data/filesystem/folder_export.dart`: streaming copy with SHA-256, partial folder then rename, no overwrite, `checksums.sha256`, `verifyChecksums`. Seed of P1-21.
- `lib/spikes/`: spike harnesses. Not wired into the app UI (ADR-006).

### 8.2 Added in P0-08

- `tool/licence_audit.dart`: reads `pubspec.lock`, `.dart_tool/package_config.json` and each package's licence file, works out which packages are reachable from the app's `dependencies`, and writes `THIRD_PARTY_NOTICES.md`. `--check` exits 1 if the file is stale or a package in the app is copyleft or unrecognised. Native components, fonts and brand assets are a hand-written section in the same tool.

### 8.3 Added in P0-04

- `lib/platform/interruptions/`: `AudioInterruptionSource` interface (began, ended with `shouldResume`, becoming noisy, devices changed), `AudioSessionInterruptionSource` (`audio_session`, Android and iOS) and `NoAudioInterruptions` (Windows). Seed of the `InterruptionCoordinator` (P1-07).
- `lib/spikes/background_recording_spike.dart`: drives `RecordingService` for a fixed time and logs lifecycle, audio session events, states, level samples, segments and interruption rows. Device test `integration_test/p0_04_background_recording_test.dart` (MT-17).
- Android manifest: `RECORD_AUDIO`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE`, `POST_NOTIFICATIONS` declared. No service yet (P1-11). iOS `Info.plist`: `NSMicrophoneUsageDescription` and `UIBackgroundModes: audio`.

### 8.4 Added in P0-12

- `RecordingService.changeProfile` (FR-QUAL-04, ADR-014): while recording, goes through `switchingSegment`, ends the segment with reason `quality_change` and starts a new one with the new profile. A refused profile restarts with the previous one and returns `declined` with a reason. While paused, only the activity override changes. A successful change is stored as `activity.recording_profile_override`.
- `lib/spikes/profile_switch_spike.dart`: records one segment per profile through `changeProfile`, reinspects every file and reports requested, declared, payload and whole-file bitrate, deviation, MB per hour and the gap per switch. Device test `integration_test/p0_12_profile_switch_test.dart` (MT-18).

### 8.5 Added in P0-10

- `lib/platform/diagnostics/`: `MemoryProbe` with `ProcessMemoryProbe` (`ProcessInfo` RSS and peak), `BatteryProbe` with `WindowsBatteryProbe` (`GetSystemPowerStatus` through `dart:ffi`) and `UnknownBatteryProbe` (Android and iOS until P1-13). ADR-015.
- `lib/spikes/long_run_spike.dart`: records for a fixed time through `RecordingService`, samples RSS, open-file size, level and battery, and reports the RSS trend, file rate, MB per hour and battery drain. Device test `integration_test/p0_10_long_run_test.dart` (MT-19).

### 8.6 Added in P0-07

- `lib/platform/audio_route/`: `AudioRouteProbe` with `InputRoute` and `InputRouteKind`, `AudioSessionRouteProbe` (Android and iOS through `audio_session`; only iOS reports the active input) and `EngineRouteProbe` (Windows, from the engine's device list, kind guessed from the name). Provider `audioRouteProbeProvider`. ADR-016.
- `RecordingService` stores the active input in `recording_segments.input_route` and `RecordingStatus.inputRoute`, and `routeChanged({force})` rolls the segment with reason `route_change`, or waits in `userResumeRequired` when no mic can start (FR-REC-03, FR-REC-07).
- `lib/spikes/bluetooth_routing_spike.dart`: logs inputs at start, on device events and once a second, rolls on change, logs `route_lost` markers and checks every row against its file (AT-QUAL-03). Device test `integration_test/p0_07_bluetooth_routing_test.dart` (MT-20).

### 8.7 Added in P0-05

- `lib/platform/camera/`: `PhotoCamera` interface (list, open, take photo, close), `CameraLens`, `moveCapturedFile` (rename, or copy, size check, then remove the plugin's temp file; never overwrites) and `PluginPhotoCamera` on the `camera` plugin with `enableAudio: false` and `ResolutionPreset.veryHigh`. ADR-017.
- `MediaPaths.photo` (`photos/<photo_id>.jpg`) and an optional `id` on `MediaAssetRepository.addPhoto`, so the file is named after its row.
- Android `CAMERA` permission and iOS `NSCameraUsageDescription`.
- `lib/spikes/photo_during_recording_spike.dart`: photos during a recording, `camera` interruptions with resume after the shot, gaps matched to interruption rows (AT-PHO-01). Device test `integration_test/p0_05_photo_during_recording_test.dart` (MT-21).

### 8.8 Added in P0-13

- `lib/platform/shortcuts/`: `ShortcutCommand` (the `attenlume://` URI parser, the only one), `ShortcutBridge` interface, `MethodChannelShortcutBridge` on `com.samlytics.attenlume/shortcuts`, `NoShortcutBridge` for Windows until P2-05. ADR-018.
- Android: `ShortcutChannel.kt` (channel, initial-command hold, tile mode), `RecordTileService.kt` (Quick Settings tile), `MainActivity.kt` passes `attenlume://` intents on, `res/xml/shortcuts.xml` launcher shortcuts, `VIEW` intent filter, Flutter route deep linking off.
- iOS: `ShortcutCommandCenter.swift` (in-app plugin, scene URL events through `addSceneDelegate`), `ShortcutIntents.swift` (App Intents and Siri phrases), `CFBundleURLTypes`, `FlutterDeepLinkingEnabled` off. Not built yet (needs a Mac).
- `lib/spikes/shortcut_trigger_spike.dart`: commands drive `RecordingService` with the one-active rule; lifecycle, tap-to-recording time and level after each start. Device test `integration_test/p0_13_shortcut_trigger_test.dart` (MT-22). The app itself does not listen to the bridge yet (P2-01, P2-03).

## 9. Open risks

| Risk | Where | Mitigation |
|---|---|---|
| Windows AAC minimum is 96 kbps | 2.3 of feasibility | ADR-002 mapping, effective settings shown |
| iOS camera reconfigures audio session | P0-05 | `enableAudio: false` (plugin source then leaves the session alone, ADR-017); if it still interrupts: `camera` interruption, segment boundary, resume after the shot. Unverified until MT-21 |
| OEM battery managers kill the Android service | P0-04 | Test on Samsung or Xiaomi, document user steps |
| No Mac: iOS unbuildable here | all iOS | Prepare code, mark iOS blocked until the owner has a Mac or CI with signing |
| Windows AAC bitrate silently snapped to 96 kbps by `record_windows` | P0-06 | Store bitrate read from the file, never the request (ADR-006) |
| No Windows playback package from a big publisher | P0-06 | `PlaybackEngine` interface, `audioplayers` fallback |
| No Windows gallery API | P1-15 | Folder pick plus EXIF time filter |
| A shortcut cannot start the microphone from the background | P0-13 | Default opens the app first (tile, Start intent), ADR-018. Direct mode measured in MT-22 |
| Hand-edited `project.pbxproj` and unbuilt Swift for App Intents | P0-13 | First Mac build checks it; the files are self-contained and can be re-added in Xcode |
| Android and Windows packages do not report which mic is recording | P0-07 | Cut a boundary on every device change (ADR-016); add `AudioRecord.getRoutedDevice` and a Windows default-device query in P1-07 |
