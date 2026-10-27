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

## ADR-009: Conference wizard, quick start UX and timezone detection (P1-01)

- **Date:** 27 October 2026. **Decided by:** Google Antigravity in unattended mode, task P1-01. Owner to review.
- **Context:** P1-01 implements the conference set-up wizard and quick start [FR-CONF-01 to 08]. Requirements: quick start creation in under 30 seconds with 1 text field and 1 button (FR-CONF-01), collection of conference details with only name required (FR-CONF-02), participant role and profession (FR-CONF-03), priority goals with examples and unlimited optional goals (FR-CONF-04), expected outputs multi-select (FR-CONF-05), recording policy notice and acknowledgement (FR-CONF-06), default recording profile inheriting global default (FR-CONF-07), and editing all fields, archiving and deleting with confirmation and deletion summary (FR-CONF-08).
- **Decision:**
  1. **Quick start inline on WelcomeScreen (FR-CONF-01, FR-CONF-06):** To meet the acceptance test criterion ("from the welcome screen, a conference can be created with one text field and one button"), `WelcomeScreen` incorporates a quick start card. Tapping "Create conference" creates the conference row, records policy acknowledgement, inherits the global recording profile (Balanced), and navigates directly to `ConferenceHomeScreen`.
  2. **Device timezone detection (`DeviceTimezoneService`, FR-CONF-02):** Added `flutter_timezone` 5.1.1 (Apache 2.0, audited in P0-01) wrapped in `DeviceTimezoneService` with a 500 ms timeout and graceful offline fallback to `Europe/London` and `Etc/UTC`. Available IANA timezone options are loaded offline from the bundled `timezone` package.
  3. **Conference wizard and editor (`ConferenceWizardScreen`, FR-CONF-02 to 08):** A unified form supports both new conference creation and editing existing conferences:
     - Section 1: Details (name, venue, start/end dates with date pickers, timezone dropdown, description).
     - Section 2: Role (`RoleType` choice chips: Attendee, Speaker, Exhibitor, Student, Journalist, Custom; plus free-text organisational role).
     - Section 3: Goals (3 priority goals with tap-to-populate example chips; dynamic optional goals list with "+ Add another goal").
     - Section 4: Expected outputs (multi-select filter chips for all 7 `RequestedOutput` values).
     - Section 5: Default recording profile (`RadioGroup` with Economy 32 kbps, Balanced 48 kbps, Enhanced 64 kbps, showing MB/h estimates).
     - Section 6: Recording policy notice with required acknowledgement checkbox.
  4. **Deletion confirmation with summary (`ConferenceDeleteDialog`, FR-CONF-08):** Queries `ConferenceRepository.deletionSummary(conferenceId)` and displays itemized counts of activities, segments, audio MB, photos, photo MB, and bookmarks before asking for final deletion confirmation.
  5. **Archiving & list navigation (`ConferenceListScreen`, FR-CONF-08, NFR-02):** Tabbed view for Active and Archived conferences with instant status toggling and unarchiving support.
  6. **Riverpod providers for query stability:** `recentConferencesProvider` and `allConferencesFutureProvider` use Future-based queries to guarantee zero lingering stream timers during test tree teardowns.
- **Alternatives:**
  - Multi-dialog quick start (rejected: violates 1 text field + 1 button budget).
  - Manual timezone text entry (rejected: prone to invalid IANA identifiers; dropdown backed by bundled tzdb ensures valid timezone keys).
- **Consequences:**
  - P1-02 (Conference home and activity list) can build directly on the created conference data model and navigation routes.



## ADR-010: Conference home, activity list and reusable presentation components (P1-02)

- **Date:** 27 October 2026. **Decided by:** Google Antigravity in unattended mode, task P1-02. Owner to review.
- **Context:** P1-02 implements Conference home and the chronological activity list [FR-ACT-01 to 03]. Requirements:
  1. *FR-ACT-01*: Conference home MUST show name, dates, activity count, total recorded time, local storage used and a single dominant "Start activity" action.
  2. *FR-ACT-02*: MUST offer quick-start buttons for the most used types: Session, Conversation, Exhibit, Reflection.
  3. *FR-ACT-03*: MUST list activities chronologically with type icon, title, start time, recording state, effective recording profile, photo count and bookmark count.
  4. *Design specs*: ActivityCard (`docs/design/components/ActivityCard.md`), StatusPill (`docs/design/components/StatusPill.md`), Button (`docs/design/components/Button.md`), and empty conference messaging ("Nothing captured yet. Start your first activity when the session begins.").
- **Decision:**
  1. **Reusable Presentation Components (`lib/presentation/components/`)**:
     - `StatusPill`: Complies with DESIGN_GUIDE status mapping. On cream surfaces, `recording` displays a navy pill (`paletteNavy`) with a lime dot (`live`) and cream text (`paletteCream`), adhering to the core brand requirement: "Never a lime mark on cream." Paused and interrupted render transparent pills with `lineStrong` borders and respective pause/phone-disabled icons. Saved/exported/verified render with `success` fill and check icon. Private renders with lock icon.
     - `AttenlumeButton`: Implements primary (brand blue fill, cream 19px semibold label meeting the large-text contrast rule, min height 52px), secondary (transparent with 1.5px outline), ghost, and danger variants.
     - `ActivityCard`: Implements the 4-row card anatomy (`surface-raised` background, `radius-md` 16px, padding `space-4` 16px). Row 1 displays type icon/label, optional private lock badge, and StatusPill. Row 2 displays title in Montserrat Semibold 20px heading (max 2 lines with ellipsis). Row 3 displays metadata formatted as "09:30 · Hall A · 47 min" in `body-small` `ink-muted`. Row 4 displays photo/bookmark counts with icons and effective profile pill. The whole card provides an accessible semantic tap target.
  2. **High-performance summary and stats queries**:
     - `ConferenceRepository.stats` and `watchStats` aggregate activity count, total duration (sum of segment milliseconds), and storage used (sum of segment audio bytes + photo bytes) in a single SQLite query without N+1 overhead (FR-ACT-01).
     - `ActivityRepository.listSummariesForConference` and `watchSummariesForConference` build `ActivitySummary` models with duration, photo count, bookmark count, active segment detection, and effective profile resolution.
     - **Elevation of active recordings**: An activity that is actively recording (`StatusPillStatus.recording`) moves to index 0 at the top of the timeline list, followed by remaining activities in chronological order.
  3. **Conference home layout & quick-start flow (FR-ACT-01, FR-ACT-02, FR-ACT-03)**:
     - Header: Displays conference name, formatted date range (`formatDateRange`), venue, timezone, description, and profile/role chips.
     - Stats card: 3 columns displaying activities count, total recorded duration (`formatDuration`), and storage used (`formatStorageBytes`) using Montserrat Bold `stat` typography (FR-ACT-01).
     - Dominant "Start activity" button: Prominent primary `AttenlumeButton` opening `StartActivitySheet`, enabling selection of any built-in or custom activity type or custom title entry.
     - Quick-start section: 4 buttons with 48px touch targets for the most used types (Session, Conversation, Exhibit, Reflection). Tapping any button immediately creates an activity of that type, defaulting to "{Type} {n}, {HH:mm}" in conference local time (FR-ACT-05), stamps reflections as private (FR-EXP-10), and refreshes the timeline with confirmation feedback.
     - Activity list: Renders chronological `ActivityCard` items. When empty, displays the design guide prompt ("Nothing captured yet. Start your first activity when the session begins."). Tapping any activity card opens `ActivityDetailSheet` showing detailed asset counts and metadata.
- **Alternatives:**
  - Launching directly into recording on dominant button tap without type choice (rejected: users frequently capture keynotes, panels, breakouts, workshops, or reflections).
  - Floating action button (rejected: FR-ACT-01 specifies single dominant "Start activity" action).
- **Consequences:**
  - P1-03 (Activity CRUD, custom types, consent check) builds directly on `StartActivitySheet` and `ActivityDetailSheet`.
  - P1-04 (RecordingService) can trigger live recording state, which automatically elevates the recording card to the top with `StatusPillStatus.recording`.


## ADR-011: Activity CRUD, custom types, awareness consent check, and contact fields (P1-03)

- **Date:** 27 October 2026. **Decided by:** Google Antigravity in unattended mode, task P1-03. Owner to review.
- **Context:** P1-03 implements full Activity CRUD, custom activity type creation and management, conversation awareness check, and contact details [FR-ACT-04 to 08].
  1. *FR-ACT-04*: Activity fields: `title`, `type`, `speaker_names`, `organisation`, `room`, `notes`, `tags`, `planned_start`, `actual_start`, `actual_end`, `recording_permission_status`, `recording_profile_override`.
  2. *FR-ACT-05*: Blank title defaults to "{Type} {n}, {HH:mm}" (e.g. "Session 3, 14:05"). Rename any time.
  3. *FR-ACT-06*: User-defined custom activity types with unique key generation, icon selection, and delete protection for types in use.
  4. *FR-ACT-07* & *FR-PRI-01*: Awareness check for business conversations and networking: "Does the other person know you are recording?" with "Yes" (participant aware) and "Not recording audio" (no audio) options.
  5. *FR-ACT-08*: Manual contact details and follow-up action for conversations without facial recognition or automatic identity extraction.
- **Decision:**
  1. **Activity Editor (`ActivityEditorScreen`)**:
     - Dual-mode support for creating new activities and editing existing ones.
     - Title field with automatic hint and fallback to default title formula (`{Type} {n}, {HH:mm}` in conference timezone) if left blank.
     - Type selector with built-in and custom types, inline "+ Custom type" creation button, and deletion option for unused custom types.
     - Dynamic awareness consent card for conversations and networking (`consentCheckTypeKeys`: `business_conversation`, `networking`).
     - Manual contact information card with fields: contact name, contact details (email/phone/social), and follow-up action. Explicit etiquette caption: "Manual entry only. No facial recognition or automatic identity extraction."
     - Session details: speakers, organisation, room, planned start date/time picker, recording profile override dropdown, private activity toggle switch, markdown notes, tags.
     - Primary "Save activity" button and danger "Delete activity" button with destructive confirmation dialog.
  2. **Consent Awareness Dialog (`ConsentCheckDialog`)**:
     - Modal dialog asking: "Does the other person know you are recording?"
     - Options: "Yes" (`RecordingPermissionStatus.participantAware`), "Not recording audio" (`RecordingPermissionStatus.notPermitted`), and "Cancel".
     - Hooked into:
       - `ConferenceHomeScreen` quick-start "Conversation" button: prompts consent before creating activity.
       - `StartActivitySheet`: prompts consent when selecting Conversation or Networking chips.
       - `ActivityEditorScreen`: dedicated choice chips and warning banner.
  3. **Custom Type Dialog (`CustomTypeDialog`)**:
     - Modal dialog allowing creation of custom types with user-defined label and choice of 12 Lucide/Material icons.
     - Calls `ActivityRepository.createCustomType(label, icon: icon)`, which derives a unique `custom_<slug>` key and assigns the next sort order.
     - Custom types in use are protected from deletion (`ON DELETE RESTRICT` and StateError check in repository).
  4. **Activity Details Inspector Enhancements (`ActivityDetailSheet`)**:
     - Displays contact person, contact details, and follow-up action in a dedicated card when present.
     - Displays speakers, organisation, room, tags, recording profile, and permission status.
     - Added "Edit" button navigating to `ActivityEditorScreen`, auto-refreshing sheet state on save.
     - Added "Delete activity" action with confirmation.
- **Alternatives:**
  - Mandatory contact extraction via business card scanning (rejected: privacy violation, offline simplicity, strict adherence to FR-ACT-08).
  - Silent default permission for conversations (rejected: violates FR-ACT-07 and UK GDPR / consent etiquette principles).
- **Consequences:**
  - All Phase 1 activity management is fully functional and tested.
  - Recording engine (P1-04+) will check `recording_permission_status`: if `notPermitted`, audio recording is disallowed and only notes/photos are permitted.

## ADR-012: RecordingService, state machine and command lock (P1-04)

- **Date:** 27 October 2026. **Decided by:** Claude Code (Opus 5.5) in unattended mode, task P1-04. Owner to review.
- **Context:** P1-04 needs one recorder that starts in one tap with metadata written before audio (FR-REC-01), writes straight to disk (FR-REC-02) and never creates duplicate recordings from rapid taps (FR-REC-09). Rolling timers (P1-05), the one-active prompt (P1-06), interruptions (P1-07) and crash recovery (P1-08) come later and must fit on top.
- **Decision:**
  1. **Pure-Dart state machine.** `RecordingState` and `recordingTransitions` (`lib/domain/services/recording_state.dart`) encode the build guide 5.4 diagram. Every status change goes through `canTransition`; an illegal move throws `StateError`, which is a bug, not a user path. Additions to the diagram: `saved` and `errorRecoverable` may go to `starting` (next recording or retry), `recovering` may go to `userResumeRequired` (OS refused resume), and `userResumeRequired` and `errorRecoverable` may go to `stopping` so the user can always save what was written.
  2. **One `SerialLock` around every command** (`lib/shared/utilities/serial_lock.dart`). Start, pause, resume and stop queue in request order and each re-reads the state, so repeats are no-ops: a second start for the same activity returns `alreadyRecording`, a repeat stop returns null. A start for a different activity returns `StartOutcome.conflict` and changes nothing; P1-06 turns that into the prompt.
  3. **Start order (FR-REC-01).** Check the activity exists, is not marked "not recording audio" (FR-ACT-07), and that the microphone is allowed, all before any write. Then mark the activity `active`, insert the segment row in state `writing`, and only then start the encoder.
  4. **Files.** `MediaPaths` (`lib/data/filesystem/media_paths.dart`) builds `conferences/<id>/activities/<id>/audio/segment-NNN.m4a`, stored relative with `/`. If that file already exists the name gets a suffix (`segment-001-2.m4a`), so an existing file is never overwritten. The repository gained `nextSegmentSequence` so the path can be named before the row is inserted, inside the lock.
  5. **Finalisation records the file, not the request.** After the engine stops, `M4aInspector` reads codec, channels, sample rate and duration, and the SHA-256 is streamed in a separate isolate (`Isolate.run`). `finaliseSegment` now also takes the observed format fields (FR-QUAL-06). A file that is missing or does not parse is marked `damaged` and kept (FR-REC-08). Atomic rename and fsync are left to P1-05.
  6. **Failures.** If the encoder will not start, the row is kept as `damaged` with reason `error` and the recorder goes to `errorRecoverable`; calling start again for that activity retries, stop saves. Any other unexpected error releases the microphone, leaves an open row as `writing` for crash recovery, and moves to `errorRecoverable`. Nothing is deleted.
  7. **Pause** ends the segment with reason `pause`; **resume** starts the next segment. **Dispose** saves an open recording, then releases the engine.
  8. **Wiring.** `recordingServiceProvider`, `recordingStatusProvider`, `audioCaptureEngineProvider` and `mediaRootProvider` live in `lib/features/capture/recording_providers.dart`. The input route is left null until route detection exists (P0-07, P1-07) rather than guessed.
- **Alternatives:** a package mutex (`synchronized`, `mutex`): rejected, 25 lines of our own code and no new dependency; letting the repository pick the file path inside its transaction: rejected for now, it would make the data layer name files; deleting the row when the encoder fails to start: rejected, a damaged row is honest and recovery can tidy it.
- **Consequences:** P1-05 adds the 10-minute roll through `switchingSegment` using the same `_beginSegment` and `_finishSegment` steps. Real capture through `RecordCaptureEngine` is still unverified on every platform (P0-04, P0-06/MT-16).

## ADR-013: Audio session events and the P0-04 background spike (P0-04)

- **Date:** 27 October 2026. **Decided by:** Claude Code (Opus 5.5) in unattended mode, task P0-04. Owner to review.
- **Context:** P0-04 must show whether recording carries on with the screen locked and what happens on a call, on Android and iOS. No phone is attached to the build host, so the spike can only be built and unit tested here. The `record` plugin does not handle interruptions or background capture (PLATFORM_FEASIBILITY 2.2). P1-07 needs an interruption source anyway.
- **Decision:**
  1. **Adopt `audio_session` 0.2.4** (ryanheise.com, MIT, Android and iOS, audited in P0-01) behind a new interface, `AudioInterruptionSource` (`lib/platform/interruptions/`). Events: began (with `mayDuck`), ended (with `shouldResume`, mapped from `audio_session`'s ended type `pause` versus `unknown`), becoming noisy, devices changed. Windows uses `NoAudioInterruptions`.
  2. **Session settings** (`AudioSessionInterruptionSource.recordingConfiguration`): iOS `playAndRecord`, mode default, options `allowBluetooth` and `defaultToSpeaker`. Android speech content, usage `media`, full focus gain. Usage `voiceCommunication` was rejected because it can switch Android into call audio mode. These are documented defaults, unverified on any device.
  3. **Platform declarations now**, so the spike can run: Android `RECORD_AUDIO`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE`, `POST_NOTIFICATIONS`; iOS `NSMicrophoneUsageDescription` (wording from PRIVACY_AND_SAFETY) and `UIBackgroundModes: audio`. The Android foreground service itself stays in P1-11.
  4. **Spike behaviour:** an interruption that is not a duck ends the segment through `RecordingService.pause()` and logs an interruption row with reason `system`. Resume on `shouldResume`, otherwise when the app is visible again. The report lists observations and never states pass or fail; the tester decides after listening.
  5. **`record_ios` session management** is left on for the first run. If the run shows it replacing our category, turn it off in `RecordCaptureEngine` and let `AudioInterruptionSource` own the session.
- **Alternatives:** the `record` plugin's own iOS interruption handling: rejected, it needs `mixWithOthers` and hides the events we must log; a native Kotlin and Swift bridge now: rejected until device results show `audio_session` falls short; Android call-state (`READ_PHONE_STATE`) listening: rejected, an extra sensitive permission when audio focus is the documented signal.
- **Consequences:** P1-07 builds the `InterruptionCoordinator` on `AudioInterruptionSource` and adds a `RecordingService` interruption command so segments end with reason `interruption`, not `pause`. Android background capture is expected to be silent until P1-11, so P0-04 on Android needs a second run after P1-11. All results remain unverified until MT-17 is run.

## ADR-014: Mid-recording profile change and the P0-12 spike (P0-12)

- **Date:** 27 October 2026. **Decided by:** Claude Code (Opus 5.5) in unattended mode, task P0-12. Owner to review.
- **Context:** P0-12 must show that a recording can switch profile per segment and report the bitrate each platform really writes. A switch has to go through the real recorder to be worth measuring, and `RecordingService` had no way to change profile. FR-QUAL-04 says never change a running encoder, and decline with a reason if the platform cannot switch cleanly. No phone is attached and the build host has no microphone in its Remote Desktop session.
- **Decision:**
  1. **`RecordingService.changeProfile(profile)`** returns a `ProfileChangeResult` (`changed`, `alreadyInUse`, `notRecording`, `declined`, `failed`, plus a plain reason). While recording it moves `recording -> switchingSegment -> recording`, ends the open segment with reason `quality_change` (inspected and hashed like any other) and starts a new segment with the new profile. It runs under the same `SerialLock` as every other command.
  2. **Decline by falling back.** If the encoder refuses the new profile, that attempt's row is kept as `damaged` (reason `error`), a new segment starts with the previous profile and the result is `declined` with the encoder's error. If the previous profile also fails, the recorder goes to `errorRecoverable` (result `failed`); earlier segments are untouched and stop still saves.
  3. **The change is stored** as `activity.recording_profile_override` only when it succeeds, so a later pause and resume keeps it (FR-QUAL-02 precedence). While paused, `changeProfile` only stores the override and updates the status; the next segment uses it.
  4. **Always cut a segment**, even where two profiles map to the same encoder settings (Windows, every profile is 96 kbps under ADR-002). Each segment's requested profile then stays true, at the cost of one extra boundary. Revisit if the measured gap is audible.
  5. **Spike** `ProfileSwitchSpike` (`lib/spikes/profile_switch_spike.dart`): Economy, Balanced, Enhanced, Economy, `P0_12_SECONDS` each (default 20). Reinspects every file and reports requested, declared (`esds`), payload and whole-file kbps, payload deviation from the request, observed against requested MB per hour, the gap between segments from the database timestamps and the time each command took. Observations only, no verdict. Device test `integration_test/p0_12_profile_switch_test.dart`, manual steps MT-18.
- **Alternatives:** a spike that drives the engine directly like P0-06: rejected, it would not exercise the state machine or the segment rows a real switch produces; leaving the recorder in `errorRecoverable` when the new profile is refused: rejected, FR-QUAL-04 asks for a safe decline and a recording that carries on; checking encoder support before cutting the segment: not possible, the `record` plugin reports codec support but not accepted bitrates, so refusal is only known at start.
- **Consequences:** P1-09 (selector) calls `changeProfile` and shows `reason` when declined. The declined path leaves a short gap and a damaged zero-length row per refusal, which crash recovery (P1-08) and the timeline (P1-17) must treat as a gap, not lost audio. Observed bitrates on every platform remain unverified until MT-18 runs.

## ADR-015: Resource probes and the P0-10 long-run spike (P0-10)

- **Date:** 27 October 2026. **Decided by:** Claude Code (Opus 5.5) in unattended mode, task P0-10. Owner to review.
- **Context:** P0-10 must record 90 minutes on a low-spec device and report memory trend, file size and battery. No phone is attached, the build host has no microphone in its Remote Desktop session, and BUILD_GUIDE 12.6 promises no RAM figure until one is measured. P1-13 (low-battery prompt) will need a battery reading later.
- **Decision:**
  1. **Memory** comes from `ProcessInfo.currentRss` and `ProcessInfo.maxRss` behind `MemoryProbe`. It covers the whole app process, native encoder included, which is what the OS weighs. Platform profilers stay the cross-check (MT-19, optional step).
  2. **Battery** sits behind `BatteryProbe`. No package now: Windows calls `GetSystemPowerStatus` through `dart:ffi`, as the free-space probe does, and returns unknown with no system battery. Android and iOS return unknown and the tester notes the level by hand.
  3. **Trend, not verdict.** The report gives the least-squares RSS slope in MB per hour after a 5-minute warm-up, the first-third and last-third means and the peak. There is no pass threshold until a per-device baseline exists (BUILD_GUIDE 12.6). The tester records the figures and judges "sustained growth" for AT-MEM-01.
  4. **File growth** is read from disk at each sample, so an encoder that buffers in memory, or a microphone the OS cut off, shows as a stalled interval during the run and not only at the end.
  5. **Samples print as they are taken**, as CSV rows, so a run the OS kills still leaves evidence in the console.
- **Alternatives:** `battery_plus` (BSD-3-Clause, all three platforms): deferred, because P1-13 may need a native channel anyway and a package for a spike would need its own licence and platform check; sampling every second as P0-04 does: rejected, 5,400 rows for 90 minutes and the extra calls would load a low-spec phone; a fixed "growth over N MB fails" rule: rejected, no measured baseline to set N from.
- **Consequences:** P1-13 replaces `UnknownBatteryProbe` on Android (`BatteryManager`) and iOS (`UIDevice.batteryLevel`) through a method channel. A 90-minute run writes one segment until P1-05 lands, so re-run then. All P0-10 figures remain unverified until MT-19 runs on a device.

## ADR-016: Input route probe, route-change segments and the P0-07 spike (P0-07)

- **Date:** 27 October 2026. **Decided by:** Claude Code (Opus 5.5) in unattended mode, task P0-07. Owner to review.
- **Context:** P0-07 must show what happens to a recording when a Bluetooth mic connects, disconnects or drops out, on all three platforms. FR-REC-03 wants a new segment on an input route change, FR-REC-07 wants the input in use shown and a fallback with a timeline marker (or a pause with a prompt), FR-QUAL-06 wants `input_route` per segment and AT-QUAL-03 says a route change must never mislabel codec or channels. ADR-012 left `input_route` empty until route detection existed. No headset or phone is attached to the build host and its Remote Desktop session has no microphone.
- **Decision:**
  1. **`AudioRouteProbe`** (`lib/platform/audio_route/`) with `activeInput()` and `availableInputs()`, returning `InputRoute` (id, label, kind: built-in, wired, Bluetooth, USB, other, unknown). Stored key `kind: label`, for example `bluetooth: AirPods Pro`. iOS reads `AVAudioSession.currentRoute.inputs` through `audio_session` 0.2.4 (already adopted, ADR-013). Android lists `AudioManager` devices through `audio_session` but reports **no** active input, because neither `audio_session` nor `record` exposes `AudioRecord.getRoutedDevice`. Windows lists the engine's inputs by name, guesses the kind from the name and reports no active input. `audio_session` marks `AudioDeviceType` experimental; the version is pinned and the mapping is unit tested.
  2. **Never guess the route.** When the platform does not report the active input, or the probe throws, `input_route` stays null. Recording is never blocked by the probe.
  3. **`RecordingService.routeChanged({force})`** runs under the same `SerialLock`. While recording it reads the active input and, if it changed (or `force` is set), goes `recording -> switchingSegment`, ends the segment with `route_change` and starts a new one on whatever input the system now gives. The running encoder is never redirected. The new segment's format fields come from inspecting its file, as for every segment, which is what keeps AT-QUAL-03 true.
  4. **Force a boundary on any device change where the active input is unknown** (Android, Windows). An extra boundary costs a short gap; a missed one would label Bluetooth audio as built-in or the reverse.
  5. **No mic left: wait for the user.** If no input can start after a route change, the segment already written is kept, the failed attempt's row is `damaged`, and the recorder moves to `userResumeRequired` with a plain message. This needs a new transition `switchingSegment -> userResumeRequired`. `resume()` and `stop()` already work from that state.
  6. **Timeline marker** for a lost input is an `interruptions` row with reason `route_lost` (in the spike now; the `InterruptionCoordinator` in P1-07 takes this over), auto-resumed when another mic took over, not auto-resumed when the user had to.
  7. **Spike** `BluetoothRoutingSpike` reads inputs at start, after every `devicesChanged` or `becomingNoisy` event and once a second, so the report shows whether events alone are enough. After the run every finished file is inspected again and compared with its row. Device test `integration_test/p0_07_bluetooth_routing_test.dart`, manual steps MT-20. Observations only, no verdict.
- **Alternatives:** a native Kotlin channel for `AudioRecord.getRoutedDevice` now: deferred to P1-07, it needs the `record` plugin's `AudioRecord` instance or a second recorder, and device runs should show first whether Android moves to Bluetooth at all; choosing the Bluetooth device explicitly through `RecordConfig.device` on Android: rejected for the spike, FR-REC-07 says follow the system and show what is used, and an explicit choice would need its own picker (P1-09/P1-10); rolling only on `devicesChanged` events: rejected, Windows has none and the spike must show whether the mobile events are reliable; a `damaged` or error state when no mic is left: rejected, FR-REC-07 asks for a pause with a prompt.
- **Consequences:** P1-07 moves the route handling into the `InterruptionCoordinator`, adds the Android routed-device channel and a Windows default-device query so `input_route` is filled everywhere, and replaces the spike's simulated resume with the real prompt. P1-10 shows `RecordingStatus.inputRoute` and the Bluetooth quality warning. P1-08 and P1-17 must treat the damaged zero-length row of a failed fallback as a gap. All routing behaviour remains unverified until MT-20 runs with real headsets.

## ADR-017: Camera package, photo interface and the P0-05 spike (P0-05)

- **Date:** 27 October 2026. **Decided by:** Claude Code (Opus 5.5) in unattended mode, task P0-05. Owner to review.
- **Context:** FR-PHO-07 says a photo taken during a recording must not lose audio, and if the camera interrupts the audio session that must be an interruption with a segment boundary, a marker and an auto-resume. AT-PHO-01 asks for 20 photos during a recording. P0-01 (ADR-002) listed `camera` and `camera_windows` but did not adopt them. No phone, camera or microphone is available on the build host.
- **Decision:**
  1. **Adopt `camera` 0.12.1 and `camera_windows` 0.3.0+1** (flutter.dev, BSD-3, maintained, released September and October 2026). Federated implementations: `camera_android_camerax` 0.7.6, `camera_avfoundation` 0.10.3+1. `camera_windows` is listed explicitly because `camera` does not endorse it. Licence audit regenerated: 129 packages, nothing flagged.
  2. **`PhotoCamera` interface** in `lib/platform/camera/`, with `PluginPhotoCamera` and a test fake. Features never touch `CameraController` directly, so a native capture path can replace the plugin after device tests.
  3. **Always `enableAudio: false`.** In `camera_avfoundation` 0.10.3+1 that skips the only code that changes the shared `AVAudioSession` category, and both capture sessions are created with `automaticallyConfiguresApplicationAudioSession = false`. This is the first mitigation. Read from source, not observed.
  4. **`ResolutionPreset.veryHigh`** (1080p on most devices) as the starting point for FR-PHO-02's 1600 to 2048 px long edge. Compression, thumbnails and the "keep highest quality" option are P1-14.
  5. **Second mitigation, in the spike:** an audio interruption that begins while the camera is busy or within 2 s of a shot is logged as `camera`, the segment ends, and recording resumes in a new segment straight after the shot without waiting for the system. The camera is ours, so its end is known. Other interruptions keep the P0-04 rules. The spike ends such segments with `pause` (it reuses `RecordingService.pause`); P1-07 moves this into the `InterruptionCoordinator` and should end them with `interruption`.
  6. **Photo files** are `photos/<photo_id>.jpg` with the row's ID, so `addPhoto` takes an optional `id`. The plugin's temporary file is renamed into place, or copied, size-checked and only then removed; an existing photo is never overwritten.
  7. **Spike** `PhotoDuringRecordingSpike` reports per-shot state, segment and level, every audio session event, and every gap between segments matched against interruption rows. Device test `integration_test/p0_05_photo_during_recording_test.dart` fails on an unexplained gap or a camera interruption that did not resume (AT-PHO-01). Manual steps MT-21.
- **Alternatives:** `image_picker` (system camera app): rejected, it leaves the app, which on iOS can suspend or interrupt recording, and breaks FR-UI-03 (shutter stays ready); native capture code per platform now: deferred, the plugin is maintained and the interface allows a later swap; pausing the recording for every shot: rejected, it would put a gap in the audio at every photo even when the camera does not interfere. The 2 s camera window is a guess to tune from MT-21 event timings.
- **Consequences:** P1-14 builds the in-app camera on `PhotoCamera`, adds compression, thumbnails and SHA-256, and handles camera permission denial (FR-PRI-04). P1-07 owns camera interruptions. Windows camera privacy needs the same plain message as the microphone. Everything about photos during recording stays unverified until MT-21 runs on each platform.

## ADR-018: Shortcut bridge, `attenlume://` URIs and the P0-13 spike (P0-13)

- **Date:** 27 October 2026. **Decided by:** Claude Code (Opus 5.5) in unattended mode, task P0-13. Owner to review.
- **Context:** P0-13 must document whether an iOS App Intent or an Android Quick Settings tile can start a recording, for Phase 2 (FR-HF-01, FR-HF-04, FR-HF-05, AT-HF-01). BUILD_GUIDE 6 says that where a cold start from the background is blocked, the shortcut opens the app instead. FR-HF-05 names the deep link `conferencecompanion://record/start`, but the product is now Attenlume. No phone or Mac is available, and the iOS project cannot be built here.
- **Decision:**
  1. **One URI language, `attenlume://`**, for every trigger: `record/start`, `record/stop`, `record/toggle`, `bookmark`, `photo`, `conversation/new`, with optional `source` and `activity` (UUID v4 only). The native side only forwards the URI plus timing and app-state facts. Dart's `ShortcutCommand.parse` is the only parser; anything unknown is dropped, never guessed at.
  2. **`ShortcutBridge`** interface in `lib/platform/shortcuts/` with `MethodChannelShortcutBridge` (channel `com.samlytics.attenlume/shortcuts`) and `NoShortcutBridge` for Windows until hotkeys (P2-05). A trigger that arrives before Dart is listening is held natively and returned once by `takeInitialCommand`.
  3. **Android opens the app by default.** The tile and launcher shortcuts open `MainActivity` with the URI (`startActivityAndCollapse(PendingIntent)` on API 34+, `unlockAndRun` when locked), because a microphone foreground service must start while the app is visible. A spike-only "direct" mode, switched from Dart and stored in shared preferences, sends the tap to an already running app without opening it, so MT-22 can measure what Android allows. Tile state and confirmation are Phase 2.
  4. **iOS App Intents in the Runner target** (iOS 16+, behind `@available` because the deployment target is 15). Start recording, New conversation and Take photo set `openAppWhenRun`. Stop recording and Bookmark do not open the app and only reach a running Flutter engine; they are never queued, so a stale stop or bookmark cannot run on a later launch. One test-only intent starts without opening the app. Deep links reach the bridge through `FlutterPluginRegistrar.addSceneDelegate`, since `FlutterSceneDelegate` declares no overridable methods. The Swift files were added to `project.pbxproj` by hand.
  5. **Flutter's own deep linking is off** (`flutter_deeplinking_enabled` on Android, `FlutterDeepLinkingEnabled` on iOS), so a shortcut URI never becomes a Navigator route.
  6. **Spike handling mirrors the Phase 2 rules:** start, stop and toggle go through `RecordingService` (a start for another activity is a `conflict`, never a silent switch, FR-REC-04); bookmarks only while recording or paused, with source `shortcut`; photo and new conversation only open the app for now. The app does not listen to the bridge outside the spike yet.
- **Alternatives:** `quick_actions` (flutter.dev): rejected for now, it covers launcher shortcuts only, not the tile or App Intents, and static shortcuts need no package; `app_links` for deep links: rejected, one more package for about 30 lines of native code; SiriKit `INIntent` donations: rejected, App Intents replace them; keeping `conferencecompanion://`: rejected, it names a product that no longer exists (the owner can still ask for both schemes); a second "direct" tile: rejected as clutter for a test.
- **Consequences:** P2-01 and P2-03 build the real handler on `ShortcutBridge`, add confirmation (notification or haptic), tile state and the Live Activity (needs a widget extension and Xcode). The first Mac build must check the hand-edited project file and the Swift. Everything about starting from a shortcut stays unverified until MT-22 runs on a phone.

## ADR-019: 10-minute roll timer and atomic segment finalisation (P1-05)

- **Date:** 27 October 2026. **Decided by:** Claude Code (Opus 5.5) in unattended mode, task P1-05. Owner to review.
- **Context:** FR-REC-03 asks for a new segment at least every 10 minutes, so a crash loses at most the current segment, and build guide 9.5 asks for atomic writes (temp name, flush, rename). Until now a segment was written under its final name, so a half-written file looked the same on disk as a finished one.
- **Decision:**
  1. **Roll timer per segment.** `RecordingService` arms a one-shot timer of `segmentMaxDuration` (default 10 minutes) each time a segment starts, and cancels it whenever the segment ends (pause, stop, profile or route change, error, dispose). On firing it goes through `switchingSegment`, ends the segment with reason `roll` and starts the next with the same profile, reusing `_finishSegment` and `_beginSegment`. The callback carries the segment ID and does nothing if that segment has already ended. The timer factory is injected so tests control time. If the next segment cannot start, earlier audio is kept and the recorder moves to `errorRecoverable`, from which the user can retry or stop.
  2. **Partial names while writing.** The encoder writes `segment-NNN.partial.m4a` (the extension stays last because iOS `AVAudioRecorder` and Windows Media Foundation pick the container from it). The row stores the partial path while `writing`, so the row always names the file that is really on disk. A name is chosen only if neither the partial nor the final file exists, so nothing is overwritten.
  3. **Order of finalisation:** stop encoder, inspect, hash, flush to disk (`RandomAccessFile.flush`: `fsync` on Android and iOS, `FlushFileBuffers` on Windows), rename to `segment-NNN.m4a`, then update the row with the final path and `finalised`. The rename comes before the database write, so a crash in between leaves a `writing` row whose partial file is gone and whose final file exists. P1-08 crash recovery must check for that case.
  4. **Damaged files keep their partial name**, so a final name always means a file that parsed. A good file whose flush or rename fails is still marked `finalised` but keeps its partial name, and the row points there.
- **Alternatives:** row stores the final path from the start: rejected, the row would name a file that does not exist while recording; database first, then rename: rejected, a crash would leave a `finalised` row pointing at a missing file; a `.tmp` suffix after `.m4a`: rejected, encoders choose the container from the extension; periodic `Timer` or a clock check on each level sample: rejected, a one-shot timer per segment is simpler to cancel and test; also fsyncing the folder after the rename (POSIX): not possible from `dart:io`, so a power cut right after the rename may still show the partial name. Recovery handles both names.
- **Consequences:** a 90-minute recording now gives nine or ten segments, which the P0-10 and P0-04 harnesses will show on device. Whether Dart timers fire on time with the screen locked (iOS background audio, Android foreground service from P1-11) is unverified until a device run. The storage budget (P1-12) should read the growing partial file. Crash recovery (P1-08) must look at both names for every `writing` row.

## ADR-020: One-active coordinator, trigger kinds and the switch command (P1-06)

- **Date:** 27 October 2026. **Decided by:** Claude Code (Opus 5.5) in unattended mode, task P1-06. Owner to review.
- **Context:** FR-REC-04 says a second start, from any trigger, shows "'Data Mesh Keynote' is still recording (47 min). Stop it and start new / Keep it running / Cancel", and that shortcut and voice triggers stop the old recording, start the new one and confirm by notification. `RecordingService.start` already refused a second activity with `StartOutcome.conflict`, but nothing resolved it, and stopping then starting as two calls would let another command slip in between.
- **Decision:**
  1. **One switch command.** `RecordingService.switchTo(activityId, {replacing})` runs under one lock hold: check the new activity (exists, may record, microphone allowed), stop and save the old one, start the new one. A start that would be refused never stops the old recording. With `replacing`, if a different activity holds the recorder than the one the person agreed to stop, nothing changes and the outcome is `conflict`.
  2. **Coordinator above the service.** `OneActiveCoordinator.requestStart(activityId, trigger:, prompt:)` is the one entry point for every trigger. It tries `start`; on a conflict it describes the held activity (title, state, recorded time) and either asks (`prompt`) or applies the default.
  3. **Trigger kinds.** `ui` and `notification` can prompt; `shortcut` (App Intents, tile, launcher shortcuts, deep links, Windows hotkeys) and `voice` cannot. A notification action is treated as visual because tapping it brings the app forward. A visual trigger with no prompt available (no screen) falls back to the non-visual default and confirms, so a start is never refused silently.
  4. **"Keep it running" vs "Cancel".** Both leave the old recording untouched. "Keep it running" returns `keptRunning`, so a caller may still open the new activity for notes and photos without audio; "Cancel" returns `cancelled` and the caller does nothing. Dismissing the dialog counts as Cancel. When the old activity is paused, the prompt says "'X' is paused (12 min recorded)." and the middle button reads "Keep it paused".
  5. **Recorded time** is the sum of segment wall-clock spans (the open segment up to now), so pauses are not counted. Formatted with `formatDuration` ("47 min", "3 h 12 min").
  6. **Confirmations** go to a `TriggerConfirmationSink`. Until the Android notification (P1-11) and haptics exist, `InAppTriggerConfirmations` publishes them on a stream for the app to show on return. A failing sink never undoes a recording. Copy: "Stopped and saved 'X'. Now recording 'Y'.", "Recording 'Y'.", or the refusal reason.
- **Alternatives:** prompt logic inside `RecordingService`: rejected, the service stays UI-free and testable without widgets; `stop()` then `start()` from the caller: rejected, a queued command (a roll, another trigger) could run in between; non-visual triggers refuse and open the app: rejected, FR-REC-04 names stop-old-start-new as the default; treating notification as non-visual: possible later if P1-11 handles start actions without opening the app.
- **Consequences:** P1-10 (recording screen), P1-11 (notification actions), P2-01, P2-03 and P2-04 must start recordings through `oneActiveCoordinatorProvider`, never `RecordingService.start` directly. The P0-13 spike still calls `start` and logs conflicts, on purpose: it must not stop a tester's recording. Behaviour on a real device (for example whether a background shortcut may start the new recording at all) is unverified until MT-22.

## ADR-021: Interruption coordinator, interruption commands and audio session ownership (P1-07)

- **Date:** 27 October 2026. **Decided by:** Claude Code (Opus 5.5) in unattended mode, task P1-07. Owner to review.
- **Context:** FR-REC-05 wants calls and audio interruptions to finalise the segment, log an interruption (reason, start, end), never record the call, resume only through OS-supported means with "Recording resumed", and otherwise keep the partial audio and offer a one-tap resume. FR-PHO-07 wants a camera interruption treated the same way with auto-resume. The P0-04 and P0-05 spikes did this with `pause()`, so segments ended with `pause`. ADR-013, ADR-016 and ADR-017 handed interruption, route and camera handling to P1-07. No phone or microphone is available on the build host.
- **Decision:**
  1. **Two new `RecordingService` commands under the same lock.** `interrupt(reason)`: `recording -> interrupted`, segment ends with `interruption`, mic released, `interruptions` row opened at the segment's end time. `interruptionEnded(mayResume:)`: closes the row at that moment; with `mayResume`, `interrupted -> recovering -> recording` in a new segment and the row is auto-resumed; without it, or if capture will not restart, `userResumeRequired` with a plain message. `resume()` refuses in `interrupted`, so the call is never recorded. `stop()` from any held state closes an open row.
  2. **Reason.** The platform does not say whether a call, an alarm or another app took audio focus, and phone-state access was rejected in ADR-013, so non-camera interruptions are logged as `system` and the user-facing text says "a call or another app". `call` and `alarm` stay in the schema for when a platform reports them.
  3. **Camera.** `InterruptionCoordinator.duringCameraUse(action)` marks the camera busy. An interruption that arrives while busy or within 2 s after is `camera` (judged on arrival). It resumes as soon as the shot finishes, without waiting for the system, as ADR-017 decided; an `ended` event during the shot waits for the shot. If that early restart fails, the recorder waits for the user.
  4. **Routes.** `devicesChanged` and `becomingNoisy` go to `routeChanged(force:)`, forced on Android and Windows (ADR-016). When no mic is left, the service now opens a `route_lost` row at the segment end, closed when the user resumes (not auto-resumed). A fallback to another mic after the old one was removed gets no marker yet (the service cannot tell a removal from a new device); the P0-07 spike still logs one.
  5. **Audio session ownership.** `RecordingService` takes the shared `AudioInterruptionSource` and activates it before the first segment, on resume and on recovery (iOS needs the session reactivated after an interruption), and deactivates it once saved. Activation failures do not block a start: the encoder start reports whether capture works. Activating only while recording avoids taking audio focus from the user's music when the app opens.
  6. **Notices.** `InterruptionNoticeSink` with `resumed` ("Recording resumed") and `resumeRequired` (the message). `InAppInterruptionNotices` publishes a stream until the P1-11 notification with a Resume action exists.
  7. **Wiring.** `interruptionCoordinatorProvider` is created by `oneActiveCoordinatorProvider`, which every start goes through (ADR-020), so no recording runs unwatched.
- **Alternatives:** keep using `pause()` for interruptions: rejected, the segment end reason and the state the UI shows would be wrong; interruption handling inside `RecordingService`: rejected, the service stays free of platform streams and camera timing; activating the session at app start: rejected, it would stop the user's music on Android; closing the row only when recording restarts: rejected, the row should show when the interruption ended, and any gap before a manual resume is visible anyway.
- **Consequences:** P1-10 shows `RecordingStatus.interruption` and `errorMessage` as the banner with Resume; P1-11 replaces `InAppInterruptionNotices` with a notification and handles a Resume action; P1-14 must take photos through `duringCameraUse`. The P0-04 and P0-05 spikes still use `pause()` on purpose, so their reports stay comparable. The Android routed-device channel and Windows default-device query proposed in ADR-016 are not built; `input_route` stays null on those platforms. Everything here is unverified on a device until MT-17, MT-20 and MT-21 run.

## ADR-022: Crash recovery reconciliation and the recovery prompt (P1-08)

- **Date:** 27 October 2026. **Decided by:** Claude Code (Opus 5.5) in unattended mode, task P1-08. Owner to review.
- **Context:** FR-REC-08 says that on app start the database must be reconciled with the segment files, recovery offered for orphaned or unfinalised segments, and a damaged file never marked good. AT-REC-03 says a force-kill loses at most the current segment. ADR-019 left a gap where the file is renamed before its row is updated, ADR-016 left zero-length damaged rows from failed fallbacks, and ADR-021 can leave an interruption row open if the app dies during a call.
- **Decision:**
  1. **Recovery is automatic and only ever classifies.** `CrashRecoveryService.reconcile()` runs once per start through `crashRecoveryReportProvider`. Each `writing` row is checked at its path, then at the final name for a partial path. A file that `M4aInspector` parses is `recovered`; a file that does not parse, or no file, is `damaged`. Nothing is deleted, and a rename never overwrites (NFR-07). "Offer recovery" is the prompt that follows: it says what was saved and kept, and offers to carry on recording. There is no choice to make about the files themselves: a parsed file is good and a broken one is damaged.
  2. **Recovered rows are described from the file**, as finalised ones are: duration, format, bytes, observed bitrate, SHA-256 (null if hashing fails). `end_utc` is start plus the file's duration and `end_reason` is `error`, the only schema value for an abnormal end. A recovered file still under its partial name is renamed to its final name, so a final name keeps meaning "parsed" (ADR-019 point 4).
  3. **Damaged rows span no time** (`end_utc = start_utc`, duration null), so the timeline and export treat them as a gap, like the failed-fallback rows of ADR-016. Rows already `finalised` or `damaged` are never touched.
  4. **Open interruptions** end at the start of the next segment if recording carried on, otherwise at their own start, because nothing records how long they lasted. `auto_resumed` is false.
  5. **Activities left `active`** become `completed` with `actual_end` at the end of their last segment, or go back to `draft` when they have no segments, so they can be started again.
  6. **The held activity is skipped.** Rows, interruptions and status of whatever `RecordingService` holds are left alone, so recovery is safe even if a recording starts first (for example from a shortcut).
  7. **Unlinked files** (`.m4a` in an activity's `audio/` folder that no row names) are listed in the report and the prompt says they are kept. They are not linked automatically: nothing says which sequence or time they belong to.
  8. **Prompt.** `CrashRecoveryGate` wraps the home screen and shows `CrashRecoveryDialog` once when the report has something. Title "Your recording was recovered"; one line per activity ("Attenlume closed while 'Data Mesh Keynote' was recording. The unfinished part was saved. Everything recorded before that is safe."). When exactly one activity was recording it offers "Carry on recording" (through `startRecordingFromUi`, so the one-active rule holds) and "Not now"; otherwise "OK".
- **Alternatives:** asking per segment whether to keep it: rejected, every file is kept anyway and a person cannot judge a container; salvaging audio from moov-less files (rebuilding the index from raw AAC frames): deferred, see consequences; resuming the crashed activity automatically: rejected, the person may have moved on; linking unlinked files as new segments: rejected, the timing would be guessed.
- **Consequences:** most force-killed segments will show as damaged, because AAC in M4A only becomes readable once `moov` is written. That meets AT-REC-03 (at most the current segment lost) but can lose up to 10 minutes per crash (ADR-019). Salvaging moov-less files is the way to lose less and is worth a spike once device runs show how encoders leave files after a kill. P1-17 and P1-21 must show and export `recovered` segments like finalised ones and `damaged` ones as gaps. Recovery on real devices (MT-13, AT-REC-03) is unverified.

## ADR-023: Quality selector, estimates and bulk profile changes (P1-09)

- **Date:** 27 October 2026. **Decided by:** Claude Code (Opus 5.5) in unattended mode, task P1-09. Owner to review.
- **Context:** FR-UI-08 wants a quality selector before recording, labelled with MB per hour and the estimated safe time left, kept apart from the Record button, and showing the profile in use while recording. FR-QUAL-03 wants bulk changes to unrecorded activities confirmed. FR-QUAL-05 wants the effective settings shown when a profile is unavailable. FR-QUAL-07 says WAV is off by default and only a specialist option. The recording screen (P1-10) does not exist yet. P1-01 had the wizard move unrecorded activities to a new default without asking.
- **Decision:**
  1. **Estimates use what will really be requested.** `estimateProfile` takes `effectiveCaptureSettings` for the platform, so Windows shows 43.2 MB per hour for every profile (96 kbps floor, ADR-002), not the profile target. Safe time left is `assessStorage` at the nominal bitrate, keeping the 100 MiB hard reserve free (ADR-008). Measured file growth takes over during recording in P1-12. When free space is unknown (Android and iOS until P1-12 adds their probes) the selector says "Space left unknown", never a number.
  2. **`RecordingProfileSelector`** (`lib/features/capture/`) is one widget with no record, pause or stop control. Before recording it reports a pick; with `live` it shows "Recording quality: X" and a change goes to `RecordingService.changeProfile` (FR-QUAL-04, ADR-014), with the decline reason shown in a snack bar. When the chosen profile differs from its target it shows the effective bitrate and MB per hour and says each recording notes the setting used. It never calls the fallback equivalent.
  3. **Where it lives until P1-10:** the activity detail sheet. Before the first segment, a pick is stored as the activity's explicit override (even when it equals the conference default, because the person chose it). While the activity is `active` (recording or paused) it is live. Once recorded it is hidden and the metadata row names the profile. P1-10 places the same widget on the recording screen.
  4. **Bulk change confirmation (FR-QUAL-03).** Saving a conference with a new default counts unrecorded activities that inherit it. If there are any, a dialog asks: "New activities only" (pins them to the old profile), "Change them too", or "Cancel" (nothing is saved). The barrier cannot be dismissed by a tap outside. With none, the change applies to new activities with no question.
  5. **Metadata of the difference (FR-QUAL-05)** stays as built in P0-12: each segment stores the requested profile and the bitrate actually requested. A Windows Economy segment reads `requested_profile = economy`, `requested_bitrate_bps = 96000`. No new column.
  6. **WAV (FR-QUAL-07) is not offered in v1.** All three profiles are AAC-LC. Offering WAV would need a new profile key, container, inspector support and storage estimates, and nothing in Phase 1 needs it. Off by default is met; the specialist option is deferred.
  7. **Photos (FR-QUAL-08)** keep their own setting (`PluginPhotoCamera.resolution`, ADR-017). Nothing in the audio profile reaches the camera.
- **Alternatives:** showing the build guide figures (14.4, 21.6, 28.8) on Windows: rejected, they would be wrong by up to three times; a segmented button: rejected, the estimates do not fit on a phone; silently moving unrecorded activities (the P1-01 behaviour): rejected, FR-QUAL-03 asks for confirmation; a WAV profile now: deferred.
- **Consequences:** the profile tiles in the conference wizard and the override dropdown in the activity editor still show the nominal build guide figures (`mbPerHourLabel`). They should switch to the effective figures in the P1-25 settings pass. The Android and iOS free-space probes (P1-12) will turn "Space left unknown" into minutes. The live path on the activity sheet has no widget test that runs a real `RecordingService`; `changeProfile` itself is covered by the FR-QUAL-04 tests.
