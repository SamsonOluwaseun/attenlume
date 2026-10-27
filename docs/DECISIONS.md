# Decisions (ADR log)

Format: context, decision, alternatives, consequences.

## ADR-001: Product name, repo location and agent workflow

- **Date:** 27 October 2026. **Decided by:** owner, recorded by Claude Code (Opus 5.5).
- **Context:** `docs/BUILD_GUIDE.md` uses the working name "Conference Companion". `docs/DESIGN_GUIDE.md` (v1.3, later) names the product Attenlume. The project sat in a OneDrive folder, which syncs Flutter build output badly. The owner wants work to continue overnight using Claude Code and Google Antigravity.
- **Decision:**
  1. The product is **Attenlume** (app name, About screen, store listing). IDs: `com.samlytics.attenlume`, deep-link scheme `attenlume://`. The build guide's "Conference Companion" and `conferencecompanion://` are read as Attenlume and `attenlume://`. Confirm the IDs with the owner before the first store submission.
  2. The repo lives at `C:\dev\attenlume` (not synced). The OneDrive folder keeps the original files untouched.
  3. Local git only, branch `main`. No remote until the owner provides one. CI workflows are written but run only once pushed.
  4. Agents run unattended through `tool/overnight.ps1` (Claude Code first, then Antigravity). Rules are in the "Unattended mode" section of `AGENTS.md`.
- **Alternatives:** keep the repo in OneDrive (rejected: sync storms and file locks); GitHub now (deferred by owner).
- **Consequences:** device-dependent spikes stay blocked until the owner tests on real devices. iOS can be prepared but not built (no Mac).

## ADR-002: Initial package stack and the Windows AAC bitrate floor

- **Date:** 27 October 2026. **Decided by:** Claude Code (Opus 5.5) in unattended mode, task P0-01. Owner to review.
- **Context:** P0-01 audited candidate packages on pub.dev and the official platform docs (`docs/PLATFORM_FEASIBILITY.md`, `docs/ARCHITECTURE.md` section 6). Three findings change the build guide's assumptions: (1) the Microsoft Media Foundation AAC encoder, which `record` uses on Windows, accepts only 96, 128, 160 or 192 kbps, so the 32/48/64 kbps profiles cannot be met on Windows; (2) `just_audio` has no Windows support; (3) `photo_manager` has no Windows support, and no maintained free-space package covers all three platforms.
- **Decision:**
  1. Adopt the "chosen" list in `docs/ARCHITECTURE.md` 6.1 as the starting stack for P0-02. Pin exact versions there once builds and tests pass.
  2. On Windows, every recording profile maps to AAC-LC mono, 48 kHz, 96 kbps (about 43.2 MB per hour). The quality selector shows this effective setting. Segments store the requested profile and the effective bitrate separately (FR-QUAL-05, FR-QUAL-06). Revisit after P0-06 and P0-12.
  3. Playback on Windows uses `just_audio_windows` behind a `PlaybackEngine` interface, with `audioplayers` as the fallback.
  4. Free space uses our own `FreeSpaceProbe` interface: `win32` `GetDiskFreeSpaceExW` on Windows, small method channels on Android and iOS.
  5. Gallery import on Windows is a folder pick filtered by EXIF capture time (file modified time as fallback).
  6. Do not use `sqlite3_flutter_libs` (end of life) or `ffmpeg_kit_flutter` (discontinued).
- **Alternatives:** FLAC on Windows (lossless, several times larger); bundling a separate low-bitrate encoder (extra native dependency and licence review); `just_audio_media_kit` (stale, Unlicense, bundles libmpv); `flutter_foreground_task` instead of a native service (kept as fallback).
- **Consequences:** Windows recordings are about twice the size of Balanced on phones. Storage estimates must use the effective profile per platform. All platform code stays behind interfaces so spikes can change it.

## ADR-003: Trimming approach, cut-range maths and instruction export (P0-14)

- **Date:** 27 October 2026. **Decided by:** Google Antigravity in unattended mode, task P0-14. Owner to review.
- **Context:** Attenlume requires trimming at three distinct levels:
  1. *Non-destructive review and editing*: users trim start, end, or exclude middle ranges (coffee breaks, transit between rooms) with instant undo, without touching raw recording files (FR-REV-04, NFR-07).
  2. *Activity splitting*: when one recording session covers two activities, splitting at the playhead divides the activity into two activities, moving bookmarks, photos, and segments by offset (FR-REV-05).
  3. *Permanent trim and export*: "Apply trims permanently" is an explicit user-confirmed action that writes new files before offering to remove originals (FR-REV-06); exports support trimmed audio files or original files accompanied by machine-readable instructions (`cuts.json`) (FR-EXP-03, FR-REV-07).
- **Decision:**
  1. **Non-destructive metadata first (`cut_ranges`)**: The primary editing workflow records cut intervals (`start_offset_ms` to `end_offset_ms`) in SQLite with soft deletion (`deleted_at`) for undo. During playback, the review player skips cut ranges on the fly.
  2. **Consolidation and timeline math (`CutRangeMath`)**: All consumer operations (playback skipping, keep-range calculation, export) run cut ranges through `CutRangeMath.mergeOverlappingCutRanges`. Overlapping and contiguous cut ranges are consolidated into canonical non-overlapping intervals, solving the Product Spec edge case while keeping individual user cuts separately undoable.
  3. **Activity splitting (`ActivitySplitService`)**: Splitting at playhead offset $P$ partitions the activity timeline. Bookmarks and photos with offset $< P$ remain in Activity 1; those with offset $\ge P$ move to Activity 2 with adjusted offset $offset - P$. Cut ranges spanning $P$ are split cleanly across the boundary. If the split falls inside an interruption/pause gap between segments, segments partition without needing audio slicing.
  4. **Instruction export (`cuts.json`)**: When exporting with `audio_mode: original_with_cuts` (FR-EXP-03, FR-REV-07), Attenlume outputs a standardized `cuts.json` containing `activity_id`, `total_duration_ms`, `trimmed_duration_ms`, `cuts`, `keep_ranges`, and `segments`. The manifest includes a pre-computed external `ffmpeg` filter complex string (`atrim`, `asetpts`, `concat`) enabling zero-loss external processing.
  5. **Platform passthrough trimming without re-encoding**: Permanent trim (FR-REV-06, P1-19) uses native passthrough sample extraction without re-encoding, preserving exact original audio quality with zero generational compression loss and minimal battery/CPU usage:
     - *Android*: Native Android `MediaExtractor` + `MediaMuxer` (copies AAC sample buffers directly between input timestamps and output). AAC frames are self-contained at 1024 samples (~21.33 ms at 48 kHz), providing frame-accurate cuts suitable for speech.
     - *iOS*: Native `AVAssetExportSession` with `AVAssetExportPresetPassthrough` and `CMTimeRange`.
     - *Windows*: Media Foundation sink writer or container-level ISOBMFF/M4A box trimming (`M4aContainerTrimmer`).
  6. **Safe file transaction guarantees (NFR-07)**:
     - All trims write to a `<targetFile>.partial` temporary file first.
     - Partial files are verified (non-empty, validated with `M4aInspector`, SHA-256 computed) and renamed atomically to the target filename.
     - On failure or cancellation, `.partial` files are immediately deleted. Original recordings are **never** overwritten or deleted automatically (FR-REV-06, NFR-07).
  7. **Rejection of FFmpeg bundling**: `ffmpeg_kit_flutter` was discontinued in 2023. `ffmpeg_kit_flutter_new` is LGPL-3.0 with dynamic linking / redistribution overhead and 30–50 MB binary bloat per architecture. Rejected for core trimming.
- **Alternatives:**
  - *Full audio re-encoding*: Rejected. Unnecessary CPU/battery drain, generational audio loss, and slower by orders of magnitude compared to passthrough frame copying.
  - *FFmpeg bundling*: Rejected due to LGPL compliance obligations and binary size impact.
  - *Destructive in-place edits*: Rejected. Violates core non-destructive design tenet (NFR-07).
- **Consequences:**
  - UI tasks (`P1-18`) will use `CutRangeMath` for virtual waveform/timeline rendering and `ActivitySplitService` for playhead splits.
  - Permanent trim (`P1-19`) will implement platform method channels conforming to the `AudioTrimmer` contract.
  - Windows desktop can utilize the pure Dart container trimmer (`M4aContainerTrimmer`) or Media Foundation.

## ADR-004: Scaffold conventions (P0-02)

- **Date:** 27 October 2026. **Decided by:** Claude Code (Opus 5.5) in unattended mode, task P0-02. Owner to review.
- **Context:** P0-02 needed choices the build guide leaves open: Riverpod codegen or not, how Drift stores times, where static Montserrat files come from, how tokens reach Dart, and when to generate app icons.
- **Decision:**
  1. Riverpod without code generation for now (plain `Provider`). `riverpod_generator` can be added later without changing call sites much.
  2. Drift stores `DateTime` as ISO 8601 text (`store_date_time_values_as_text` in `build.yaml`), always written as UTC, matching build guide 9.4. Foreign keys are switched on in `beforeOpen`.
  3. Schema dumps in `drift_schemas/` with `drift_dev make-migrations`, verified by `SchemaVerifier` tests for every version.
  4. Montserrat static TTFs from the upstream Montserrat Project repo (`JulietaUla/Montserrat`, `fonts/ttf`, SIL OFL 1.1). The Google Fonts repo only ships the variable font now. Keep the `.woff` files for web and design use.
  5. `lib/app/theme/tokens.dart` is generated from `design/tokens.json` by `tool/gen_tokens.dart` and checked by a test, so the JSON stays the single source.
  6. App version starts at `0.1.0+1` (build guide 14: `0.x` during development).
  7. Launcher icons are **not** generated yet. The supplied icon has a transparent margin around a rounded tile, while iOS needs a full-bleed square without transparency and Android needs an adaptive foreground layer. Making those exports needs either designer-supplied exports or a careful crop, which the design guide forbids doing loosely. Deferred to the owner (open question) or a later task.
  8. CI (`.github/workflows/ci.yml`): Windows job (codegen drift check, format, analyze, test, Windows debug build), Ubuntu job (debug APK), macOS job (unsigned iOS debug build). Dormant until a remote exists (ADR-001).
- **Alternatives:** integer Unix timestamps (Drift's default, smaller but unreadable in exports and debugging); variable Montserrat font (one file, but weight mapping in Flutter needs `FontVariation` everywhere); hand-written token constants (drift from the JSON).
- **Consequences:** P0-09 builds the full schema on this database class and bumps `schemaVersion` with a migration test per version.

## ADR-005: Data model conventions (P0-09)

- **Date:** 27 October 2026. **Decided by:** Claude Code (Opus 5.5) in unattended mode, task P0-09. Owner to review.
- **Context:** P0-09 builds the build guide 9.4 tables. The guide leaves storage formats, some nullability and the FR-QUAL-03 mechanics open.
- **Decision:**
  1. **Schema v2, not a redefined v1.** v1 (`app_settings`) stays as dumped, and v2 adds the Phase 1 tables through drift's `stepByStep` helper, so the real upgrade path is tested. Phase 1.5 and 2 tables (`cloud_connections`, `cloud_export_files`, `transcripts`) arrive with their phases as new versions.
  2. **Drift standard layout for migrations.** `dart run drift_dev make-migrations` owns `drift_schemas/`, `lib/data/local_database/app_database.steps.dart` and `test/drift/app_database/generated/`. The P0-02 copies under `test/data/local_database/generated/` were removed.
  3. **Rows are domain classes.** Tables use `@UseRowClass` with the plain classes in `lib/domain/models/`, so there is no mapping layer. Partial updates take Drift companions.
  4. **Stored values.** Enums are stored by a stable snake_case key spelled as in 9.4 (`KeyedEnum`), never by Dart name or index. JSON lists (speakers, tags, requested outputs) and the export scope are JSON text. Conference start and end dates are calendar days stored as `YYYY-MM-DD` (read as UTC midnight) so they never shift between timezones. Instants stay UTC ISO 8601 text (ADR-004).
  5. **Goal text.** Drift cannot have a column getter named `text`, so the SQL column is `text` and the Dart field is `goalText`.
  6. **Built-in activity types** have fixed UUID v4 IDs (`00000000-0000-4000-8000-00000000000n`) and are seeded with insert-or-ignore on every open, so later releases can add types. Labels are "Conversation" and "Reflection" to match the FR-ACT-02 quick-start buttons, while the keys keep `business_conversation` and `personal_reflection`. Built-in types and types in use cannot be deleted (`ON DELETE RESTRICT`).
  7. **Offsets.** `bookmarks.offset_ms` is nullable like `photos.offset_ms` (the guide does not say). An event before the first segment gets a negative offset. When the first segment starts, null offsets in that activity are filled in.
  8. **FR-QUAL-03.** Changing a conference default pins activities that inherited the old default by writing it into their override. With the user's confirmed bulk change, inheriting activities without segments follow the new default instead. Explicit overrides are never changed.
  9. **Privacy default.** Activities of type `personal_reflection` are created with `is_private = true` (FR-UI-05, FR-EXP-10). The caller can override.
  10. **Deletes.** Deleting a conference or activity cascades to its database rows only. Media files are not touched by repositories. Removing them is a separate, user-confirmed step in P1 (NFR-07, AGENTS rule on originals).
  11. **Timezones.** Added `timezone` 0.11.2 (Dart team, BSD-3, pure Dart) for conference-local default titles from the bundled IANA data, offline. An unknown timezone name falls back to UTC. Detecting the device's IANA timezone needs a plugin and is left to P1-01.
  12. **Export enums.** `audio_mode` is `original`, `trimmed`, `original_with_cuts` or `none` (for text or photo scopes). `state` is `pending`, `running`, `completed`, `failed` or `cancelled`. The scope JSON shape is set in P1-21.
- **Alternatives:** redefining v1 (simpler history, but no tested upgrade path); a separate mapping layer between Drift rows and domain models (more code, no gain yet); storing the effective profile on every activity at creation (needs a new column the guide does not list).
- **Consequences:** every schema change is a new version with a dump and a migration test. Renaming an enum key needs a data migration.

## ADR-006: Capture interface, file inspection and folder export (P0-06)

- **Date:** 27 October 2026. **Decided by:** Claude Code (Opus 5.5) in unattended mode, task P0-06. Owner to review.
- **Context:** P0-06 needs Windows capture, a way to know what the encoder really wrote, and export to a folder. The `record` package does not report output bitrate, and its Windows code silently picks the nearest supported AAC setting. The build host's microphone is not reachable from the agent's Remote Desktop session, so the real-capture run is blocked.
- **Decision:**
  1. Capture goes through `AudioCaptureEngine` (`lib/platform/audio_capture/`). `RecordCaptureEngine` wraps `record` 7.1.2. The request (`CaptureRequest`) and the result are kept apart.
  2. Segment quality fields (FR-QUAL-06) come from the finished file, read by our own pure-Dart `M4aInspector`: codec from the `esds` AudioSpecificConfig, channels and sample rate from the `mp4a` entry, duration from `mdhd`. `observed_bitrate_bps` is the whole-file figure (bytes x 8 / duration), as ARCHITECTURE 3 says. The declared and payload bitrates are reported alongside in spikes. No media library is added for this.
  3. A file without a `moov` box is not finalised and is never marked good (FR-REC-08). Crash recovery (P1-08) can reuse the inspector.
  4. `effectiveCaptureSettings` requests 48 kHz mono everywhere, the profile target on phones and at least 96 kbps on Windows (ADR-002). The sample rate is a starting point until P0-12.
  5. Folder export (`exportFolder`) streams each file through SHA-256, writes `<name>.tmp` then renames, builds the export in `<folder>.partial` and renames it when complete, refuses to overwrite and re-hashes every copy. On failure only the partial copy is removed. This is the seed of P1-21. The user-chosen folder picker is left to P1-21.
  6. Spike harnesses live in `lib/spikes/` so integration tests can run them on devices. They are not reachable from the app UI and can be removed after Phase 0.
  7. Added `crypto` 3.0.8 (dart.dev, BSD-3, pure Dart) and the SDK's `integration_test`.
- **Alternatives:** trust the requested bitrate (rejected: the Windows plugin changes it silently); a media library such as `media_kit` or FFmpeg to probe files (large native dependency and licence review for one small job); copy with `File.copy` (no hash in the same pass, no partial-folder protection).
- **Consequences:** every format we write must stay parseable by `M4aInspector` (M4A/AAC now). If the owner later chooses another container, the inspector needs extending. Windows capture remains unverified until MT-16 is run in a console session or on a Surface.

## ADR-007: Dependency licence review and project licence (P0-08)

- **Date:** 27 October 2026. **Decided by:** Claude Code (Opus 5.5) in unattended mode, task P0-08. **Status: proposed.** The licence choice waits for the owner (build guide: "decided after the dependency licence review").
- **Context:** The build guide asks for MIT or Apache 2.0, chosen after reviewing every dependency and model licence. The review covers `pubspec.lock` (115 packages: 108 from pub.dev, 7 from the Flutter SDK), native code fetched at build time, fonts and brand assets. No AI models are used yet (Phase 2).
- **Findings:**
  1. Of the 115 packages, 77 are reachable from the app's `dependencies` and 38 only from `dev_dependencies`. Packages in the app: BSD-3-Clause 62, MIT 9, Apache-2.0 4, BSD-2-Clause 1, Flutter engine bundle 1. **No copyleft (GPL, LGPL, MPL) and no unrecognised licence**, in the app or in the tools.
  2. Reachable is a strict reading. It includes Linux, macOS and web platform packages we do not ship, the build-hook packages of `sqlite3` (`hooks`, `native_toolchain_c`, `code_assets`, `yaml`), and test libraries that `flutter_riverpod` and `riverpod` list as normal dependencies (`flutter_test`, `test_api`, `fake_async`). Tree shaking drops their unused code from release builds. Listing them costs nothing.
  3. Native code: SQLite (public domain) comes as a prebuilt library from the `sqlite3` package's GitHub release, checked against hashes in the package. `jni` (used by `path_provider_android`) brings Kotlin stdlib and kotlinx.coroutines (Apache-2.0) on Android. Windows Media Foundation and Apple frameworks are OS components, not redistributed. `record_windows` fetches GoogleTest only for its own tests.
  4. `sqlite3_flutter_libs` and `sqlcipher_flutter_libs` are end-of-life stubs with no native code, pulled in by `drift_flutter` 0.3.1. Their licence files (MIT, and Apache-2.0 plus Zetetic's notice) are listed anyway.
  5. Oddity: the `record` family's LICENSE is BSD-3-Clause text naming "openapi4j authors", clearly copied from another project. The terms are permissive. We reproduce it as published.
  6. `clock` and `fake_async` (Apache-2.0, Dart team) name no copyright holder in their LICENSE file.
  7. Montserrat is SIL OFL 1.1: it may be bundled with software under any licence, not sold alone, and a modified version may not be called Montserrat. Flutter's automatic `NOTICES` covers packages but not our bundled fonts, so the About screen must register `assets/fonts/OFL.txt` with `LicenseRegistry` (P1 About and licences screen).
  8. Lucide icons (design guide) are ISC. Not added yet. `lucide_icons_flutter` 4.0.1 and `flutter_lucide` 1.61.0 (both MIT, all platforms, updated October 2026) are maintained; `lucide_icons` is stale (Dart 2 only, 2023). Choose in the first UI task.
  9. The Attenlume name, logos and icon belong to Samlytics Data Services and are not open source.
- **Decision:**
  1. `THIRD_PARTY_NOTICES.md` is generated by `tool/licence_audit.dart` from the lock file and each package's licence file, with a hand-written section for native code, fonts, brand assets and planned components. `test/docs/third_party_notices_test.dart` fails if a locked package is missing, the file is stale, or a package in the app has a copyleft or unrecognised licence. Re-run the tool after every dependency change.
  2. **Recommend Apache License 2.0** for Attenlume's own code: (a) it has an explicit patent grant and patent retaliation clause, which MIT lacks, useful for an app around audio capture and media processing; (b) section 6 says it grants no trademark rights, which matches keeping the Attenlume brand out of the licence; (c) its NOTICE convention fits the notices file we already keep. Every dependency above is compatible with either choice, and so are the Phase 2 candidates named in the build guide (whisper.cpp MIT, Vosk Apache-2.0; model weights still need their own review).
  3. Brand assets in `assets/brand/` and `design/` are excluded from the project licence ("all rights reserved, Samlytics Data Services"). Forks must replace them.
  4. **No `LICENSE` file is added in this task.** The owner asked to choose after P0-08. Once confirmed, add the standard Apache 2.0 text as `LICENSE`, a short `NOTICE` (copyright Samlytics Data Services, pointer to `THIRD_PARTY_NOTICES.md`, brand exclusion) and set the licence in `README.md`.
- **Alternatives:** MIT (shorter and more familiar, but no patent grant and silent on trademarks; fully acceptable if the owner prefers simplicity); a hand-written notices file (drifts from the lock file); counting only packages that survive tree shaking (needs a release build per platform, and is fragile).
- **Consequences:** a new package fails `flutter test` until the notices file is regenerated, which forces a licence look at every addition. Any future copyleft dependency fails the test and needs an ADR. Model licences (Phase 2) need their own section when models are added.

## ADR-008: Free-space probing, storage thresholds and streaming export (P0-11)

- **Date:** 27 October 2026. **Decided by:** Google Antigravity in unattended mode, task P0-11. Owner to review.
- **Context:** P0-11 requires low-storage simulation, free-space probing, recording budget assessment, streaming folder and ZIP exports with bounded memory, and failure handling when the destination disk is full or near-full.
- **Decision:**
  1. **Free space probe interface:** `FreeSpaceProbe` (`lib/platform/storage/free_space_probe.dart`) queries free and total bytes for a given path. On Windows, `WindowsFreeSpaceProbe` calls Win32 `GetDiskFreeSpaceExW` directly via `dart:ffi` kernel32, walking up to the nearest existing ancestor directory so non-existent destination folders report correctly. Android and iOS will use method channels in Phase 1; unknown platforms fall back to `UnknownFreeSpaceProbe` returning `null` (reported as `unknown` in preflights, never falsely assumed plentiful).
  2. **Recording storage thresholds:** `StorageThresholds` and `assessStorage` (`lib/domain/services/storage_thresholds.dart`) implement FR-STO-02 defaults: warning below 1 GB or 60 minutes left, urgent near 300 MB, and hard stop at a platform-safe reserve (100 MB default). Usable recording space excludes the hard reserve so finalisation and DB commits never run disk to zero.
  3. **Export preflight:** `preflightExport` (`lib/data/filesystem/export_space.dart`) compares destination volume free space against export size plus a 256 MB destination reserve (`defaultExportReserveBytes`), throwing `InsufficientSpaceException` before any files are created if insufficient (FR-EXP-05, AT-STO-03).
  4. **Atomic exports and disk-full resilience:** Both `exportFolder` and `exportZip` write to `.partial` staging files/folders and atomically rename on completion. Mid-export failures (such as `ERROR_DISK_FULL` 112/39 on Windows or `ENOSPC` 28 on POSIX) delete partial targets and raise `ExportOutOfSpaceException`, leaving source files untouched (FR-EXP-05, FR-STO-04).
  5. **Streaming ZIP export:** `exportZip` (`lib/data/filesystem/zip_export.dart`) uses `archive` 4.5.2 (`ZipFileEncoder`, `InputFileStream`, `OutputFileStream`) with store compression (`level: ZipFileEncoder.store`), saving CPU/battery on already-compressed audio and photos. It embeds `checksums.sha256` inside the archive and writes a companion `<zipName>.sha256` file beside the ZIP (FR-EXP-02, FR-EXP-04, FR-EXP-06).
  6. **Bounded RAM verified:** Measured with a 1 GiB synthetic file on the Windows build host: `exportFolder` peaked at 10.3 MB delta RSS, and `exportZip` peaked at 5.6 MB delta RSS, proving streaming operates within tiny chunk buffers rather than loading whole files into RAM (FR-EXP-04).
- **Alternatives:** using a third-party disk space plugin (no maintained plugin covers Android, iOS and Windows cleanly without native bloat; Win32 FFI call is 50 lines of pure Dart/FFI); compressing audio with deflate in ZIP (wastes CPU/battery with near-zero size reduction on M4A/JPEG).
- **Consequences:** Mobile platforms need their native method channel implementations for `FreeSpaceProbe` in Phase 1 (`P1-12`). All export functions support injected writers and probes for deterministic disk-full failure testing.
