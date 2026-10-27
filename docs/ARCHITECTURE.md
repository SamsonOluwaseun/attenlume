# Architecture

**Status:** draft from task P0-01, 27 October 2026, Claude Code (Opus 5.5). No app code exists yet. This describes the planned design. Update it as each task lands.
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

Data pulled from pub.dev on 27 October 2026 with `tool/pub_audit.py` (latest version, publish date, verified publisher, licence and platform tags from pub.dev analysis). "Tested" versions get pinned in `pubspec.yaml` during P0-02 and listed in section 7 once a build and tests pass with them. Licences are pub.dev's detected licence. The full review is P0-08.

Toolchain: Flutter 3.47.8 stable, Dart 3.13.7. Every package below accepts Dart 3.13.

### 6.1 Chosen for Phase 0 and 1

| Package | Version | Released | Publisher | Licence | Platforms (pub.dev) | Use |
|---|---|---|---|---|---|---|
| flutter_riverpod | 3.4.3 | 2026-09-03 | dash-overflow.net | MIT | A, I, W | State |
| riverpod_annotation / riverpod_generator | 4.0.7 / 4.0.9 | 2026-09-03 | dash-overflow.net | MIT | A, I, W | Optional codegen. Decide in P0-02 |
| drift | 2.35.3 | 2026-10-23 | simonbinder.eu | MIT | A, I, W | Database |
| drift_flutter | 0.3.1 | 2026-07-11 | simonbinder.eu | MIT | A, I, W | Opens the DB on each platform |
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

None yet. P0-02 fills this table from `pubspec.lock` after the first passing `flutter analyze`, `flutter test`, Windows build and Android build.

| Package | Version | Tested on | Date |
|---|---|---|---|

## 8. Open risks

| Risk | Where | Mitigation |
|---|---|---|
| Windows AAC minimum is 96 kbps | 2.3 of feasibility | ADR-002 mapping, effective settings shown |
| iOS camera reconfigures audio session | P0-05 | Treat as interruption, segment boundary |
| OEM battery managers kill the Android service | P0-04 | Test on Samsung or Xiaomi, document user steps |
| No Mac: iOS unbuildable here | all iOS | Prepare code, mark iOS blocked until the owner has a Mac or CI with signing |
| No Windows playback package from a big publisher | P0-06 | `PlaybackEngine` interface, `audioplayers` fallback |
| No Windows gallery API | P1-15 | Folder pick plus EXIF time filter |
