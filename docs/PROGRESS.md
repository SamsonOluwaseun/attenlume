# Progress

Status values: todo, in progress, blocked, done (with test evidence).

## 2026-10-27, Claude Code (Opus 5.5): environment set-up

- Installed and verified: Flutter 3.47.8 (Dart 3.13.7) at `C:\dev\flutter`, Visual Studio Build Tools 2022 17.14 (C++ desktop), Microsoft OpenJDK 17.0.19, Android SDK (platform 36, build-tools 36.0.0, platform-tools, NDK r28c fetched by Gradle). Windows Developer Mode enabled (symlinks for plugins).
- `flutter doctor`: Windows, Android and Visual Studio all OK.
- Smoke test of a throwaway `flutter create` app: `flutter build windows --debug` and `flutter build apk --debug` both succeeded.
- Repo created at `C:\dev\attenlume`. Brand kit merged into `assets/`, `design/` and `docs/`. No Flutter project yet, so no tests to run.
- Overnight supervisor added (`tool/overnight.ps1`, `tool/agent-prompt.md`).

## 2026-10-27, Claude Code (Opus 5.5): P0-01 platform and package audit

- Start-of-session check: no Flutter project yet, so `flutter analyze` and `flutter test` were not applicable.
- Audited 82 candidate packages on pub.dev (version, date, publisher, licence, platforms) with the new `tool/pub_audit.py`. Checked 19 official Android, Apple and Microsoft doc links (all HTTP 200).
- Findings: Windows Media Foundation AAC encoder only allows 96 to 192 kbps (profiles can't be met on Windows); `just_audio` and `photo_manager` have no Windows support; `sqlite3_flutter_libs` is end of life; `archive` 4.5.2 supports ZIP64. Decisions in ADR-002.
- Wrote `docs/PLATFORM_FEASIBILITY.md` (spike matrix, all cells unverified) and `docs/ARCHITECTURE.md` (layers, lifecycle, dependency audit).
- No code, so no tests added. Nothing claimed as working.

## 2026-10-27, Claude Code (Opus 5.5): P0-02 Flutter scaffold

- Start-of-session check: no Flutter project yet, so `flutter analyze` and `flutter test` were not applicable.
- `flutter create` (org `com.samlytics`, project `attenlume`, Android, iOS, Windows). Display name "Attenlume" on all three. Version `0.1.0+1`.
- Packages: flutter_riverpod, drift, drift_flutter, sqlite3, path_provider, path, uuid; dev: drift_dev, build_runner, flutter_lints, mocktail. No `sqlite3_flutter_libs`. Exact versions in `docs/ARCHITECTURE.md` 7.
- Stricter `analysis_options.yaml` (strict casts, inference, raw types, extra lints).
- Montserrat static TTFs 400 to 700 added and declared. Logos bundled as assets.
- Theme: `tool/gen_tokens.dart` generates `lib/app/theme/tokens.dart` from `design/tokens.json`. `AppTheme.light/dark/live` plus `AttenlumeColors` extension. `ThemeMode.system`.
- Drift `AppDatabase` v1 with `app_settings`, ISO 8601 UTC text dates, foreign keys on, schema dump and verifier test. Riverpod `appDatabaseProvider`.
- Placeholder welcome screen (logo, tagline, onboarding line, no sign-in).
- CI workflow written (`.github/workflows/ci.yml`). Not run: no remote (ADR-001).
- Decisions in ADR-004.

Test results on `phase-0/P0-02-scaffold` (Windows 11 build host):

- `flutter analyze`: no issues.
- `flutter test`: 12 passed, 0 failed. Tests: `P0-02` app shell (3), `NFR-01` no sign-in, `NFR-09` contrast pairs light and dark, button label size, navy live theme, `P0-02` token file in sync, `P0-02` database (3), `P0-02` v1 schema migration.
- `dart format --set-exit-if-changed lib test tool`: clean.
- `flutter build windows --debug`: built. Launched once on the build PC: window "Attenlume" opened and stayed up for 8 s. That is a build-host smoke check, not a Surface test.
- `flutter build apk --debug`: built. Not installed on any phone (unverified).
- iOS: not built (no Mac). Unverified.

## 2026-10-27, Claude Code (Opus 5.5): P0-03 project docs

- Start-of-session check on `main`: `flutter analyze` no issues, `flutter test` 12 passed.
- New docs from build guide 1.6: `docs/PRODUCT_SPEC.md` (11 journeys, 18 user stories, edge cases, acceptance detail), `docs/PRIVACY_AND_SAFETY.md` (consent, stored data, retention, sharing, permission wording drafts, cloud and AI summaries), `docs/TEST_PLAN.md` (current suite, planned unit, widget and integration tests, manual tests MT-01 to 15, AT list with every device cell unverified, AT-CLD-01 to 10 and Phase 2 placeholders, device matrix, empty results log), `docs/RELEASE_PLAN.md` (milestones, versioning, CI, Windows, Android and iOS distribution, iOS blocked without a Mac, identifiers, checklist).
- `README.md`: every 1.6 document linked, plus export format, caveats and Windows downloads sections.
- `pubspec.lock`: `flutter pub get` dropped a stale `cupertino_icons` entry (removed from `pubspec.yaml` in P0-02 but left in the lock). No dependency change.
- New test `test/docs/docs_index_test.dart` (P0-03, 2 tests): every 1.6 document exists and is linked from the README.

Test results on `phase-0/P0-03-docs` (Windows 11 build host):

- `flutter analyze`: no issues.
- `flutter test`: 14 passed, 0 failed.
- `dart format --set-exit-if-changed lib test tool`: clean.

## 2026-10-27, Claude Code (Opus 5.5): P0-09 data model

- Start-of-session check on `main`: `flutter analyze` no issues, `flutter test` 14 passed.
- Schema v2 (`lib/data/local_database/tables.dart`): conferences, goals, activity_types, activities, recording_segments, interruptions, photos, bookmarks, cut_ranges, export_jobs, plus v1 app_settings. Foreign keys cascade from conference and activity, restrict on activity type. CHECK constraints for goal priority, segment sequence and cut ranges. Unique (activity, sequence). Indexes on every parent key.
- Migration v1 to v2 through drift `stepByStep`. Dump `drift_schemas/app_database/drift_schema_v2.json`. Migration tests moved to drift's standard `test/drift/app_database/`.
- Built-in activity types seeded on every open, with fixed UUID v4 IDs (NFR-03).
- Domain models and enums in `lib/domain/models/`. Rules in `lib/domain/services/`: profile precedence (FR-QUAL-02), default title in conference timezone (FR-ACT-05), offset rule (9.4).
- Repositories in `lib/data/repositories/`: settings, conference (with goals, archive, FR-QUAL-03 default change, deletion summary), activity (with custom types), media assets (segments, interruptions, photos, bookmarks, offset backfill), cut ranges (soft delete with undo), export jobs. Riverpod providers in `repository_providers.dart`.
- Fixtures in `test/fixtures/fixtures.dart`.
- New package `timezone` 0.11.2 (Dart team, BSD-3, pure Dart). Decisions in ADR-005.

Test results on `phase-0/P0-09-data-model` (Windows 11 build host):

- `flutter analyze`: no issues.
- `flutter test`: 76 passed, 0 failed (62 new).
- `dart format --set-exit-if-changed lib test tool`: clean.
- `flutter build windows --debug` and `flutter build apk --debug`: both built. Not run on any device (on-device database open is unverified).

## 2026-10-27, Claude Code (Opus 5.5): P0-06 Windows mic spike

- Start-of-session check on `main`: `flutter analyze` no issues, `flutter test` 76 passed.
- Capture interface `AudioCaptureEngine` with `RecordCaptureEngine` (`record` 7.1.2, `record_windows` 2.3.0). Effective encoder request per platform (`capture_settings.dart`, Windows 96 kbps floor).
- Pure-Dart `M4aInspector`: reads codec, channels, sample rate, duration and declared, payload and whole-file bitrates from a finished M4A. Loads only `moov`. Rejects unfinalised files.
- Streaming `exportFolder` with SHA-256, partial folder then rename, no overwrite, re-hash of every copy, `checksums.sha256`, `verifyChecksums`.
- Spike harness `lib/spikes/windows_mic_spike.dart` and device test `integration_test/p0_06_windows_mic_test.dart`.
- New packages: `crypto` 3.0.8 (dart.dev, BSD-3), `integration_test` (SDK). `record` was already audited in P0-01. Decisions in ADR-006.
- **Real run on the build PC:** AAC-LC encoder reported present, but `listInputDevices()` was empty and every `start()` threw "No audio recording device was found.". Cause: the agent runs in a disconnected Remote Desktop session, which does not see the PC's microphone. No audio was recorded. Device part **blocked: needs real device session** (manual test MT-16). Details in `docs/PLATFORM_FEASIBILITY.md` 2.6.1.
- Read from `record_windows` source (unverified): unsupported bitrates are snapped to the nearest supported one without an error, so 32/48/64 kbps requests are expected to give 96 kbps.

Test results on `phase-0/P0-06-windows-mic` (Windows 11 build host):

- `flutter analyze`: no issues.
- `flutter test`: 100 passed, 0 failed (24 new). All 24 run on any host.
- `integration_test/p0_06_windows_mic_test.dart -d windows`: **failed as expected without a microphone** (blocked, not a code fault). Not part of `flutter test`.
- `dart format --set-exit-if-changed lib test tool integration_test`: clean.
- `flutter build apk --debug` and `flutter build windows --release`: both built. APK not installed on a phone.

## 2026-10-27, Claude Code (Opus 5.5): P0-08 licence review

- Start-of-session check on `main`: `flutter analyze` no issues, `flutter test` 100 passed.
- New `tool/licence_audit.dart`: reads `pubspec.lock`, `.dart_tool/package_config.json` and every package's licence file, works out which packages are reachable from the app's `dependencies`, and writes `THIRD_PARTY_NOTICES.md` (tables, native components, fonts, brand assets, deduplicated licence texts). `--check` mode for CI.
- Result: 115 packages (77 in the app graph, 38 build and test only). In the app: BSD-3 62, MIT 9, Apache-2.0 4, BSD-2 1, Flutter engine bundle 1. **Nothing copyleft or unrecognised.** SQLite (public domain) via the `sqlite3` hook, Kotlin libraries (Apache-2.0) via `jni` on Android, Montserrat OFL 1.1. Brand assets excluded from the open-source licence.
- ADR-007: recommends Apache 2.0 (patent grant, explicit trademark carve-out). **Status proposed.** No `LICENSE` file added, waiting for the owner.
- New dev dependency `yaml` 3.1.4 (dart.dev, MIT), already in the lock through `hooks`.
- Docs updated: README licences section, ARCHITECTURE 6, 7 and 8.2, RELEASE_PLAN 6, TEST_PLAN 2.1.

Test results on `phase-0/P0-08-licences` (Windows 11 build host):

- `flutter analyze`: no issues.
- `flutter test`: 117 passed, 0 failed (17 new, `P0-08`).
- `dart run tool/licence_audit.dart --check`: up to date, nothing flagged.
- `dart format --set-exit-if-changed lib test tool integration_test`: clean.
- `flutter build windows --release` and `flutter build apk --debug`: both built. Not run on a device.

## 2026-10-27, Google Antigravity: P0-11 low storage and streaming export spike

- Start-of-session check on main: lutter analyze no issues, lutter test 117 passed.
- Free space probing: FreeSpaceProbe interface (lib/platform/storage/free_space_probe.dart) and Win32 GetDiskFreeSpaceExW implementation (windows_free_space_probe.dart) via dart:ffi.
- Storage thresholds: StorageThresholds and ssessStorage (lib/domain/services/storage_thresholds.dart) implementing FR-STO-01, FR-STO-02, and FR-STO-04 defaults (ok, warning, urgent, hardStop).
- Export preflight and estimation: preflightExport, estimateFolderExportBytes, and estimateZipExportBytes (lib/data/filesystem/export_space.dart) with defaultExportReserveBytes (256 MB) and InsufficientSpaceException (FR-EXP-05, AT-STO-03).
- Streaming ZIP export: exportZip (lib/data/filesystem/zip_export.dart) using rchive 4.5.2 with store compression (ZipFileEncoder.store), embedded checksums.sha256 and companion <zipName>.sha256, and atomic rename from .partial (FR-EXP-02, FR-EXP-04, FR-EXP-06).
- Folder export update: exportFolder now includes preflight free space check and disk-full exception mapping (ExportOutOfSpaceException).
- Failure injection: tested preflight rejection and mid-export disk full via injected writer (openSink), verifying partial targets are removed and source media is untouched.
- Spike runner: StorageExportSpike (lib/spikes/storage_export_spike.dart).
- Benchmarking on Windows 11 host (1 GiB synthetic file):
  - exportFolder: 18.1 s, peak RSS delta 10.3 MB. Verified checksums clean.
  - exportZip: 18.8 s, peak RSS delta 5.6 MB. ZIP size 1,073,742,095 bytes (271 bytes overhead).
- Decisions recorded in ADR-008.

Test results on phase-0/P0-11-storage-export (Windows 11 build host):

- lutter analyze: no issues.
- lutter test: 150 passed, 0 failed (33 new, P0-11).
- dart run tool/licence_audit.dart --check: up to date, nothing flagged.
- dart format --output=none --set-exit-if-changed lib test tool: clean.
- lutter build windows --release and lutter build apk --debug: both built successfully.

## Task status

| Task | Status | Evidence |
|---|---|---|
| P0-01 | done | `docs/PLATFORM_FEASIBILITY.md` and `docs/ARCHITECTURE.md` drafted, ADR-002. Desk audit only, no device results |
| P0-02 | done (CI unverified) | analyze clean, 12 tests pass, Windows and APK debug builds succeed locally. CI file written, not run (no remote). No device runs |
| P0-03 | done | Four docs created, all 1.6 docs linked from README, `P0-03` docs index tests pass (14 total) |
| P0-09 | done | Schema v2, migration and repository tests pass (76 total). On-device DB open unverified |
| P0-06 | blocked: needs real device | Harness, inspector, export and 24 unit tests pass (100 total). Real capture blocked: no mic in the build host's RDP session. Run MT-16 |
| P0-08 | done (licence choice awaits owner) | `THIRD_PARTY_NOTICES.md` generated and tested (117 total), ADR-007 recommends Apache 2.0 |
| P0-11 | done | Windows probe, thresholds, preflight, folder and ZIP streaming exports pass 33 tests (150 total). 1 GiB RAM benchmark: 10.3 MB / 5.6 MB peak RSS delta. ADR-008 |
| P0-14 | todo | Next |
