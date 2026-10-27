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

- Start-of-session check on main: flutter analyze no issues, flutter test 117 passed.
- Free space probing: FreeSpaceProbe interface (lib/platform/storage/free_space_probe.dart) and Win32 GetDiskFreeSpaceExW implementation (windows_free_space_probe.dart) via dart:ffi.
- Storage thresholds: StorageThresholds and assessStorage (lib/domain/services/storage_thresholds.dart) implementing FR-STO-01, FR-STO-02, and FR-STO-04 defaults (ok, warning, urgent, hardStop).
- Export preflight and estimation: preflightExport, estimateFolderExportBytes, and estimateZipExportBytes (lib/data/filesystem/export_space.dart) with defaultExportReserveBytes (256 MB) and InsufficientSpaceException (FR-EXP-05, AT-STO-03).
- Streaming ZIP export: exportZip (lib/data/filesystem/zip_export.dart) using archive 4.5.2 with store compression (ZipFileEncoder.store), embedded checksums.sha256 and companion <zipName>.sha256, and atomic rename from .partial (FR-EXP-02, FR-EXP-04, FR-EXP-06).
- Folder export update: exportFolder now includes preflight free space check and disk-full exception mapping (ExportOutOfSpaceException).
- Failure injection: tested preflight rejection and mid-export disk full via injected writer (openSink), verifying partial targets are removed and source media is untouched.
- Spike runner: StorageExportSpike (lib/spikes/storage_export_spike.dart).
- Benchmarking on Windows 11 host (1 GiB synthetic file):
  - exportFolder: 18.1 s, peak RSS delta 10.3 MB. Verified checksums clean.
  - exportZip: 18.8 s, peak RSS delta 5.6 MB. ZIP size 1,073,742,095 bytes (271 bytes overhead).
- Decisions recorded in ADR-008.

Test results on phase-0/P0-11-storage-export (Windows 11 build host):

- flutter analyze: no issues.
- flutter test: 150 passed, 0 failed (33 new, P0-11).
- dart run tool/licence_audit.dart --check: up to date, nothing flagged.
- dart format --output=none --set-exit-if-changed lib test tool: clean.
- flutter build windows --release and flutter build apk --debug: both built successfully.

## 2026-10-27, Google Antigravity: P0-14 trimming approach and non-destructive cut maths

- Start-of-session check on main: flutter analyze no issues, flutter test 150 passed.
- Cut-range mathematics and consolidation: `CutRangeMath` (`lib/domain/services/cut_range_math.dart`) consolidating overlapping and contiguous cut ranges (FR-REV-04, Product Spec edge case: "Cut ranges overlap: Merged for playback and export. Each stays separately undoable"), deriving keep ranges, trimmed durations, and bidirectional timeline offset mapping.
- Activity split planning: `ActivitySplitService` (`lib/domain/services/activity_split_service.dart`) implementing playhead splitting (FR-REV-05). Bookmarks and photos partition by offset, cut ranges spanning split point divide cleanly across the boundary, and splits occurring inside interruption gaps partition segments without needing audio file slicing.
- Instruction export: `CutsManifest` (`lib/data/filesystem/cuts_manifest.dart`) generating and parsing `cuts.json` (FR-REV-07, FR-EXP-03) with pre-computed external `ffmpeg` filter complex expressions (`atrim`, `asetpts`, `concat`) and atomic file writes via `.partial` staging.
- Audio trimming engine: `AudioTrimmer` abstract interface (`lib/platform/audio_trimmer/audio_trimmer.dart`), pure Dart `M4aContainerTrimmer` (`m4a_container_trimmer.dart`), and `SimulatedAudioTrimmer` (`simulated_audio_trimmer.dart`). Tested atomic `.partial` transaction contract and failure recovery: partial files are cleaned up on failure, and source recordings are never deleted or modified (FR-REV-06, NFR-07). Trimmed output validated with `M4aInspector`.
- Trimming spike runner: `TrimmingSpike` (`lib/spikes/trimming_spike.dart`) exercising cut math consolidation, split planning, `cuts.json` round-trip, M4A container trimming with bounded RSS, and failure recovery.
- Architecture Decision Record: ADR-003 recorded in `docs/DECISIONS.md`.

Test results on phase-0/P0-14-trimming (Windows 11 build host):

- flutter analyze: no issues.
- flutter test: 179 passed, 0 failed (29 new, P0-14).
- dart run tool/licence_audit.dart --check: up to date, nothing flagged.
- dart format --output=none --set-exit-if-changed lib test tool: clean.
- flutter build windows --release and flutter build apk --debug: both built successfully.

## 2026-10-27, Google Antigravity: P1-01 conference wizard and quick start

- Start-of-session check on main: flutter analyze no issues, flutter test 179 passed.
- Quick start inline on WelcomeScreen (`lib/features/onboarding/welcome_screen.dart`, FR-CONF-01, FR-CONF-06): creates a named conference in under 30 seconds with exactly one text field and one button interaction. Shows recording policy notice, inherits global default profile (Balanced), detects device timezone, stamps policy acknowledgement, and navigates directly to `ConferenceHomeScreen`.
- Device timezone detection (`lib/domain/services/device_timezone.dart`, FR-CONF-02): added `flutter_timezone` 5.1.1 (Apache 2.0, audited in P0-01) with 500 ms timeout and graceful offline fallback to `Europe/London` and `Etc/UTC`. Available IANA timezones loaded offline from bundled `timezone` package.
- Full conference set-up wizard and editor (`lib/features/conferences/conference_wizard_screen.dart`, FR-CONF-02 to 08):
  - Section 1: Details (name required, venue, start/end dates with date pickers, timezone dropdown, description).
  - Section 2: Role (`RoleType` choice chips: attendee, speaker, exhibitor, student, journalist, custom; free-text organisational role).
  - Section 3: Goals (3 priority goals with tap-to-populate example chips; unlimited optional goals with add/remove actions).
  - Section 4: Expected outputs (multi-select filter chips for all 7 `RequestedOutput` values).
  - Section 5: Default recording profile (`RadioGroup` with Economy 32 kbps, Balanced 48 kbps, Enhanced 64 kbps, showing MB/h estimates).
  - Section 6: Recording policy notice with required acknowledgement checkbox.
- Conference home landing screen (`lib/features/conferences/conference_home_screen.dart`, FR-ACT-01): displays conference metadata, role, priority goals, outputs, profile badge, archive status banner, and dominant "Start activity" action.
- Conference list & archive (`lib/features/conferences/conference_list_screen.dart`, FR-CONF-08, NFR-02): tabbed views for active and archived conferences, cards with dates/venue/profile, and FAB to create new conferences.
- Deletion confirmation dialog (`lib/features/conferences/conference_delete_dialog.dart`, FR-CONF-08): queries `deletionSummary` and presents itemized counts of activities, segments, audio MB, photos, photo MB, and bookmarks before confirming deletion.
- Architecture Decision Record: ADR-009 recorded in `docs/DECISIONS.md`.

Test results on phase-1/P1-01-conference-wizard (Windows 11 build host):

- flutter analyze: no issues.
- flutter test: 190 passed, 0 failed (11 new, P1-01).
- dart run tool/licence_audit.dart --check: up to date, nothing flagged.
- dart format --output=none --set-exit-if-changed lib test tool: clean.
- flutter build windows --release and flutter build apk --debug: both built successfully.

## 2026-10-27, Google Antigravity: P1-02 conference home and activity list

- Start-of-session check on main: flutter analyze no issues, flutter test 190 passed.
- Conference home landing screen (`lib/features/conferences/conference_home_screen.dart`, FR-ACT-01):
  - Displays conference name, formatted date range (`formatDateRange`), venue, timezone, description, and profile/role chips.
  - Dedicated Stats Card in Montserrat Bold `stat` typography displaying activity count, formatted recorded duration (`formatDuration`), and formatted storage used (`formatStorageBytes`).
  - Single dominant "Start activity" action (`AttenlumeButton` variant primary, 52px height, 19px semibold cream label on brand blue fill, mic icon). Opens `StartActivitySheet` where users can select any activity type or enter a custom title.
- Quick-start activity buttons (`lib/features/conferences/conference_home_screen.dart`, FR-ACT-02):
  - Offers 4 dedicated action buttons for the most used types: Session (`Icons.slideshow_rounded`), Conversation (`Icons.handshake_rounded`), Exhibit (`Icons.store_rounded`), and Reflection (`Icons.lightbulb_rounded`).
  - Tapping any quick-start button creates an activity with default title "{Type} {n}, {HH:mm}" in conference local time (FR-ACT-05, FR-CONF-02), stamps reflections as private (FR-EXP-10), and updates the timeline instantly with confirmation feedback.
- Chronological activity list and elevation of active recordings (`lib/presentation/components/activity_card.dart`, `lib/data/repositories/activity_repository.dart`, FR-ACT-03):
  - Chronological ordering by actual start, else planned start, else creation time.
  - Actively recording activity (`StatusPillStatus.recording`) automatically moves to index 0 at the top of the timeline list.
  - Empty state displays design guide prompt: "Nothing captured yet. Start your first activity when the session begins."
  - Activity details inspector: tapping an activity card opens `ActivityDetailSheet` showing detailed asset counts, metadata, and privacy notice.
- Reusable presentation components:
  - `StatusPill` (`lib/presentation/components/status_pill.dart`): implements exact status mapping per DESIGN_GUIDE. On light/cream surfaces, recording renders as navy pill with lime dot and cream text ("Never a lime mark on cream"); on navy surfaces uses live lime fill. Supports paused, interrupted, saved, exported, verified, private, and draft.
  - `AttenlumeButton` (`lib/presentation/components/attenlume_button.dart`): implements primary (brand blue fill, cream 19px semibold text, 52px min height), secondary, ghost, and danger variants.
  - `ActivityCard` (`lib/presentation/components/activity_card.dart`): 4-row card anatomy with type icon/label, optional lock badge, StatusPill, heading title (max 2 lines with ellipsis), "09:30 · Hall A · 47 min" metadata, asset counts with icons, and recording profile badge. Accessible semantic tap target with compound label.
- Date, duration, and storage formatting utilities (`lib/shared/utilities/date_formatters.dart`):
  - `formatDuration`: UK English formatted duration ("0 min", "< 1 min", "47 min", "1 h 12 min").
  - `formatStorageBytes`: formatted byte representation ("0 B", "512 B", "350.0 KB", "14.2 MB", "1.2 GB").
  - `formatTimeOfDayInTimezone`: local "HH:mm" time from UTC instant in conference timezone.
- Aggregate summary and stats queries:
  - `ConferenceRepository.stats` and `watchStats`: aggregates activity count, duration, and storage in a single query (FR-ACT-01).
  - `ActivityRepository.listSummariesForConference` and `watchSummariesForConference`: compiles duration, photo counts, bookmark counts, active segments, and effective profile.
- Architecture Decision Record: ADR-010 recorded in `docs/DECISIONS.md`.

Test results on phase-1/P1-02-conference-home (Windows 11 build host):

- flutter analyze: no issues.
- flutter test: 218 passed, 0 failed (28 new, P1-02).
- dart run tool/licence_audit.dart --check: up to date, nothing flagged.
- dart format --output=none --set-exit-if-changed lib test tool: clean.
- flutter build windows --release and flutter build apk --debug: both built successfully.

## 2026-10-27, Google Antigravity: P1-03 activity CRUD, custom types, consent check, contact fields

- P1-03: Activity CRUD, custom types, consent check, contact fields [FR-ACT-04 to 08].
  - Full Activity CRUD Editor (`lib/features/activities/activity_editor_screen.dart`):
    - Supports both new activity creation and editing existing activities (FR-ACT-04).
    - Blank title defaults to "{Type} {n}, {HH:mm}" in conference timezone (FR-ACT-05). Rename any time.
    - All session fields supported: `title`, `type`, `speaker_names` (comma-separated), `organisation`, `room`, `notes` (Markdown), `tags` (comma-separated), `planned_start` (date/time picker), `recording_permission_status`, `recording_profile_override`, `is_private` (FR-ACT-04).
    - Save action (`AttenlumeButton` primary) and destructive Delete action (`AttenlumeButton` danger with confirmation dialog).
  - Custom activity types (FR-ACT-06):
    - `CustomTypeDialog` (`lib/features/activities/custom_type_dialog.dart`): user-defined type creation with label validation and 12 Lucide/Material icon choices (`tag`, `presentation`, `mic`, `users`, `sparkles`, `coffee`, `school`, `store`, `camera`, `folder`, `book`, `chat`).
    - Integrated "+ Custom type" chip/button in `StartActivitySheet` and `ActivityEditorScreen`.
    - Safe custom type deletion in editor; types in use are protected from deletion (`ON DELETE RESTRICT` and StateError handling).
  - Conversation awareness consent check (FR-ACT-07, FR-PRI-01, J3):
    - `ConsentCheckDialog` (`lib/features/activities/consent_check_dialog.dart`): "Does the other person know you are recording?" with "Yes" (`RecordingPermissionStatus.participantAware`), "Not recording audio" (`RecordingPermissionStatus.notPermitted`), and Cancel options.
    - Prominently integrated into quick-start Conversation button on `ConferenceHomeScreen`, Conversation/Networking chips in `StartActivitySheet`, and consent banner in `ActivityEditorScreen`.
  - Manual contact details and follow-up (FR-ACT-08):
    - Contact name, contact details (email/phone/social), and follow-up action.
    - Explicit UK English etiquette note: "Manual entry only. No facial recognition or automatic identity extraction."
    - Contact & follow-up card displayed in `ActivityDetailSheet` and `ActivityEditorScreen`.
  - Activity details sheet enhancements (`lib/features/conferences/activity_detail_sheet.dart`):
    - "Edit" button opens `ActivityEditorScreen` and refreshes details on return.
    - "Delete activity" button with confirmation dialog.
    - Displays contact card, speaker names, organisation, room, tags, recording permission status, effective profile.
  - 19 new tests added across 4 test suites (237 total tests, 0 failed).
  - Architecture Decision Record: ADR-011 recorded in `docs/DECISIONS.md`.

Test results on phase-1/P1-03-activity-crud (Windows 11 build host):

- flutter analyze: no issues.
- flutter test: 237 passed, 0 failed (19 new, P1-03).
- dart run tool/licence_audit.dart --check: up to date, nothing flagged.
- dart format --output=none --set-exit-if-changed lib test tool: clean.

## 2026-10-27, Claude Code (Opus 5.5): P1-04 RecordingService with state machine and mutex

- Start-of-session check on main: flutter analyze no issues, flutter test 237 passed.
- `RecordingState`, `recordingTransitions`, `canTransition` and `RecordingStatus` (`lib/domain/services/recording_state.dart`): the build guide 5.4 state machine, with the small additions in ADR-012.
- `SerialLock` (`lib/shared/utilities/serial_lock.dart`): runs commands one at a time in order (FR-REC-09).
- `RecordingService` (`lib/domain/services/recording_service.dart`): `start`, `pause`, `resume`, `stop`, `dispose`, a status stream and `StartOutcome` results. Segment row in state `writing` before the encoder starts (FR-REC-01). Encoder writes straight to a file under the media root (FR-REC-02). Finalisation stores what `M4aInspector` reads from the file plus a SHA-256 hashed in an isolate. Unparseable files are kept as `damaged`. Refuses activities marked "not recording audio" and returns `conflict` for a second activity (NFR-04, prompt in P1-06).
- `MediaPaths` (`lib/data/filesystem/media_paths.dart`): relative segment paths per build guide 9.5, never overwriting an existing file.
- `MediaAssetRepository`: added `nextSegmentSequence`; `finaliseSegment` takes the observed codec, container, channels and sample rate (FR-QUAL-06).
- Providers: `recordingServiceProvider`, `recordingStatusProvider`, `audioCaptureEngineProvider`, `mediaRootProvider` (`lib/features/capture/recording_providers.dart`). No UI yet (recording screen is P1-10).
- Tests: 28 new (`test/domain/recording_service_test.dart` 20, `test/domain/recording_state_test.dart` 6, `test/data/filesystem/media_paths_test.dart` 2), using `FakeCaptureEngine` (`test/fixtures/fake_capture_engine.dart`). Real capture is **unverified**: the tests use a fake engine, no microphone was used.
- ADR-012 recorded.

Test results on phase-1/P1-04-recording-service (Windows 11 build host):

- flutter analyze: no issues.
- flutter test: 265 passed, 0 failed (28 new, P1-04).
- dart run tool/licence_audit.dart --check: up to date, nothing flagged (no new packages).
- dart format --output=none --set-exit-if-changed lib test tool: clean.
- flutter build windows --release and flutter build apk --debug: both built successfully.

## 2026-10-27, Claude Code (Opus 5.5): P0-04 background recording and call interruption spike harness

- Start-of-session check on main: flutter analyze no issues, flutter test 265 passed.
- Picked P0-04 over P1-05 because the agent prompt puts Phase 0 first and P0-04's dependency (P0-02) is done.
- `AudioInterruptionSource` interface, `AudioSessionInterruptionSource` (`audio_session` 0.2.4) and `NoAudioInterruptions` (`lib/platform/interruptions/`). Seed of the `InterruptionCoordinator` (P1-07).
- `BackgroundRecordingSpike` (`lib/spikes/background_recording_spike.dart`): runs the real `RecordingService` for a fixed time, logs lifecycle, audio session events, states, level samples split by foreground and background, segment rows and interruption rows. Ends the segment on an interruption and resumes on the system signal or when the app is visible again. Report in JSON and Markdown, observations only, no verdict.
- Device test `integration_test/p0_04_background_recording_test.dart` (Android and iOS only) and manual steps MT-17 in `TEST_PLAN.md`.
- Android manifest: `RECORD_AUDIO`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE`, `POST_NOTIFICATIONS`. iOS `Info.plist`: `NSMicrophoneUsageDescription` and `UIBackgroundModes: audio`. No foreground service yet (P1-11), so Android background capture is expected to be silent.
- New packages: `audio_session` 0.2.4 (MIT, Android and iOS, audited in P0-01) and transitive `rxdart` 0.28.0 (Apache-2.0). `THIRD_PARTY_NOTICES.md` regenerated: 121 packages, nothing flagged.
- `FakeCaptureEngine` gained a settable `level`.
- ADR-013 recorded. `PLATFORM_FEASIBILITY.md` 1 and 2.4.1, `TEST_PLAN.md` and `ARCHITECTURE.md` 7 and 8.3 updated.
- **Not run on any phone.** No device is attached to the build host. P0-04 is blocked: needs real device (Android) and Mac plus iPhone (iOS).

Test results on phase-0/P0-04-background-spike (Windows 11 build host):

- flutter analyze: no issues.
- flutter test: 275 passed, 0 failed (10 new, P0-04).
- dart run tool/licence_audit.dart --check: up to date, nothing flagged.
- dart format --output=none --set-exit-if-changed lib test tool integration_test: clean.
- flutter build windows --release and flutter build apk --debug: both built. APK not installed on a phone. iOS not built (no Mac).

## 2026-10-27, Claude Code (Opus 5.5): P0-12 per-segment profile switching and observed bitrate spike harness

- Start-of-session check on main: flutter analyze no issues, flutter test 275 passed.
- Picked P0-12 over P1-05 because the agent prompt puts Phase 0 first and P0-12's dependency (P0-04) is blocked-on-device.
- `RecordingService.changeProfile` (`lib/domain/services/recording_service.dart`) with `ProfileChangeOutcome` and `ProfileChangeResult` [FR-QUAL-04]: recording goes through `switchingSegment`, the segment ends with `quality_change`, a new one starts with the new profile. A refused profile restarts with the previous one and is `declined` with the encoder's reason. Success stores the activity override. `_beginSegment` split into `_tryBeginSegment` (no state change on refusal) and `_beginSegment`.
- `ProfileSwitchSpike` (`lib/spikes/profile_switch_spike.dart`): Economy, Balanced, Enhanced, Economy through `changeProfile`, reinspects each file, reports requested, declared, payload and whole-file kbps, deviation, MB per hour, gap per switch and the start error. Observations only.
- Device test `integration_test/p0_12_profile_switch_test.dart` (Android, iOS, Windows) and manual steps MT-18 in `TEST_PLAN.md`.
- `FakeCaptureEngine` gained `deliveredBitrateBps` and `refuse`.
- ADR-014 recorded. `PLATFORM_FEASIBILITY.md` 1 and 2.3.1, `TEST_PLAN.md` and `ARCHITECTURE.md` 3 and 8.4 updated. No new packages.
- **No audio captured.** The device test was run on the build host with `-d windows`: start failed with "No audio recording device was found." (Remote Desktop session, same as P0-06). P0-12 is blocked: needs real device on all three platforms.

Test results on phase-0/P0-12-profile-switch-spike (Windows 11 build host):

- flutter analyze: no issues.
- flutter test: 291 passed, 0 failed (16 new: 8 FR-QUAL-04 in `recording_service_test.dart`, 8 P0-12 in `profile_switch_spike_test.dart`).
- `integration_test/p0_12_profile_switch_test.dart -d windows`: failed as expected, no microphone (blocked, not a code fault).
- dart run tool/licence_audit.dart --check: up to date, nothing flagged.
- dart format --output=none --set-exit-if-changed lib test tool integration_test: clean.
- flutter build windows --release and flutter build apk --debug: both built.

## 2026-10-27, Claude Code (Opus 5.5): P0-10 90-minute low-spec run spike harness

- Start-of-session check on main: flutter analyze no issues, flutter test 291 passed.
- Picked P0-10 over P1-05 because the agent prompt puts Phase 0 first and P0-10's dependency (P0-04) is blocked-on-device.
- `lib/platform/diagnostics/`: `MemoryProbe` and `ProcessMemoryProbe` (`ProcessInfo` RSS and peak), `BatteryProbe`, `WindowsBatteryProbe` (`GetSystemPowerStatus` through `dart:ffi`) and `UnknownBatteryProbe` (Android and iOS until P1-13).
- `LongRunSpike` (`lib/spikes/long_run_spike.dart`): runs the real `RecordingService` for a fixed time, samples RSS, on-disk size of the open file, level and battery once a minute, prints each sample as a CSV row, and reports the RSS slope after a 5-minute warm-up, first and last third means, peak, whole-file kbps, MB per hour and per 8 hours, stalled intervals, flat samples and battery drain. JSON, CSV and Markdown. Observations only.
- Device test `integration_test/p0_10_long_run_test.dart` (Android, iOS, Windows) and manual steps MT-19 in `TEST_PLAN.md`.
- ADR-015 recorded. `PLATFORM_FEASIBILITY.md` 1 and 2.4.2, `TEST_PLAN.md` and `ARCHITECTURE.md` 8.5 updated. No new packages.
- **No audio captured.** The device test was run on the build host with `-d windows` for 1 minute: start failed with "No audio recording device was found." (Remote Desktop session). Battery unknown, the PC reports no system battery. P0-10 is blocked: needs real device on all three platforms.

Test results on phase-0/P0-10-long-run-spike (Windows 11 build host):

- flutter analyze: no issues.
- flutter test: 309 passed, 0 failed (18 new, P0-10, in `test/spikes/long_run_spike_test.dart`).
- `integration_test/p0_10_long_run_test.dart -d windows`: failed as expected, no microphone (blocked, not a code fault).
- dart run tool/licence_audit.dart --check: up to date, nothing flagged.
- dart format --output=none --set-exit-if-changed lib test tool integration_test: clean.
- flutter build windows --release and flutter build apk --debug: both built.

## 2026-10-27, Claude Code (Opus 5.5): P0-07 Bluetooth mic routing and fallback spike harness

- Start-of-session check on main: flutter analyze no issues, flutter test 309 passed.
- Picked P0-07 over P1-05 because the agent prompt puts Phase 0 first and P0-07's dependency (P0-04) is blocked-on-device.
- `lib/platform/audio_route/`: `AudioRouteProbe`, `InputRoute`, `InputRouteKind`, `classifyInputLabel`, `NoAudioRouteProbe`; `AudioSessionRouteProbe` (iOS active input from `AVAudioSession.currentRoute`, Android and iOS device list from `audio_session`); `EngineRouteProbe` (Windows, engine device list). Provider `audioRouteProbeProvider`, wired into `recordingServiceProvider`.
- `RecordingService`: each segment stores the active input in `input_route` and `RecordingStatus.inputRoute` (null when unknown, never guessed) [FR-QUAL-06]. New `routeChanged({force})` with `RouteChangeResult` [FR-REC-03, FR-REC-07]: rolls through `switchingSegment` with end reason `route_change`; if no mic can start, keeps the written segment and waits in `userResumeRequired`. New transition `switchingSegment -> userResumeRequired`.
- `BluetoothRoutingSpike` (`lib/spikes/bluetooth_routing_spike.dart`): inputs at start, on device events and once a second; rolls on change; `route_lost` markers; reinspects every file against its row (AT-QUAL-03); per-route max level; JSON and Markdown. Observations only.
- Device test `integration_test/p0_07_bluetooth_routing_test.dart` (Android, iOS, Windows) and manual steps MT-20 in `TEST_PLAN.md`.
- `FakeCaptureEngine` gained `deliveredChannels`, `deliveredSampleRateHz` and `inputs`. New `test/fixtures/fake_route_probe.dart`.
- ADR-016 recorded. `PLATFORM_FEASIBILITY.md` 1 and 2.4.3, `TEST_PLAN.md` (2.1, MT-20, AT-QUAL-03, results log) and `ARCHITECTURE.md` 8.6 and 9 updated. No new packages.
- **No audio captured, no headset used.** The device test was run on the build host with `-d windows` for 10 s: start failed with "No audio recording device was found." (Remote Desktop session). P0-07 is blocked: needs real devices and Bluetooth headsets on all three platforms.

Test results on phase-0/P0-07-bluetooth-routing-spike (Windows 11 build host):

- flutter analyze: no issues.
- flutter test: 335 passed, 0 failed (26 new: 10 in `recording_service_route_test.dart`, 5 in `audio_route_probe_test.dart`, 11 in `bluetooth_routing_spike_test.dart`; 1 path added to `recording_state_test.dart`).
- `integration_test/p0_07_bluetooth_routing_test.dart -d windows`: failed as expected, no microphone (blocked, not a code fault).
- dart run tool/licence_audit.dart --check: up to date, nothing flagged.
- dart format --output=none --set-exit-if-changed lib test tool integration_test: clean.
- flutter build windows --release and flutter build apk --debug: both built.

## 2026-10-27, Claude Code (Opus 5.5): P0-05 photo capture during recording spike harness

- Start-of-session check on main: flutter analyze no issues, flutter test 335 passed.
- Picked P0-05 over P0-13 and P1-05 because the agent prompt puts Phase 0 first and P0-05's dependency (P0-04) is blocked-on-device.
- New packages: `camera` 0.12.1 and `camera_windows` 0.3.0+1 (flutter.dev, BSD-3, audited in P0-01), with transitive `camera_android_camerax` 0.7.6, `camera_avfoundation` 0.10.3+1, `camera_platform_interface` 2.15.0, `camera_web` 0.3.5+6, `cross_file` 0.3.5+5, `flutter_plugin_android_lifecycle` 2.0.35. `THIRD_PARTY_NOTICES.md` regenerated: 129 packages, nothing flagged.
- `lib/platform/camera/`: `PhotoCamera` interface, `CameraLens`, `CapturedPhoto`, `CameraUnavailableException`, `moveCapturedFile` (never overwrites) and `PluginPhotoCamera` (`enableAudio: false`, `ResolutionPreset.veryHigh`) [FR-PHO-01, FR-PHO-07].
- Desk finding from source: `camera_avfoundation` 0.10.3+1 sets `automaticallyConfiguresApplicationAudioSession = false` and only changes the `AVAudioSession` category when `enableAudio` is true. Expectation only, not observed.
- `MediaPaths.photo` and optional `id` on `MediaAssetRepository.addPhoto` (`photos/<photo_id>.jpg`).
- `PhotoDuringRecordingSpike` (`lib/spikes/photo_during_recording_spike.dart`): lists cameras, records, opens the camera, takes 20 photos, logs state, segment and level around each shot and every audio session event; interruptions near a shot become `camera` rows and resume after the shot; gaps between segments matched to interruption rows (AT-PHO-01). JSON and Markdown.
- Android `CAMERA` permission, iOS `NSCameraUsageDescription`.
- Device test `integration_test/p0_05_photo_during_recording_test.dart` and manual steps MT-21 in `TEST_PLAN.md`.
- ADR-017 recorded. `PLATFORM_FEASIBILITY.md` 1 and 2.7.1, `TEST_PLAN.md` (2.1, MT-21, AT-PHO-01, results log) and `ARCHITECTURE.md` (7, 8.7, 9) updated.
- **No photo taken, no audio captured.** The device test was run on the build host with `-d windows` and 2 photos: start failed with "No audio recording device was found." and `camera_windows` listed no camera (Remote Desktop session). P0-05 is blocked: needs real devices on all three platforms.

Test results on phase-0/P0-05-photo-during-recording-spike (Windows 11 build host):

- flutter analyze: no issues.
- flutter test: 349 passed, 0 failed (14 new, P0-05, in `test/spikes/photo_during_recording_spike_test.dart`).
- `integration_test/p0_05_photo_during_recording_test.dart -d windows`: failed as expected, no microphone and no camera (blocked, not a code fault).
- dart run tool/licence_audit.dart --check: up to date, nothing flagged.
- dart format --output=none --set-exit-if-changed lib test tool integration_test: clean.
- flutter build windows --release and flutter build apk --debug: both built.

## 2026-10-27, Claude Code (Opus 5.5): P0-13 shortcut trigger spike harness

- Start-of-session check on main: flutter analyze no issues, flutter test 349 passed.
- Picked P0-13 because it was the last Phase 0 task without a harness (agent prompt: Phase 0 first). Its dependency P0-04 is blocked-on-device.
- No new packages.
- `lib/platform/shortcuts/`: `ShortcutCommand` parses `attenlume://` URIs (`record/start|stop|toggle`, `bookmark`, `photo`, `conversation/new`, optional `source` and UUID v4 `activity`) and channel payloads; `ShortcutBridge`, `MethodChannelShortcutBridge` (`com.samlytics.attenlume/shortcuts`), `NoShortcutBridge` [FR-HF-01, FR-HF-04, FR-HF-05].
- Android: `ShortcutChannel.kt`, `RecordTileService.kt` (Quick Settings tile; opens the app via `startActivityAndCollapse(PendingIntent)` on API 34+, `unlockAndRun` when locked; spike-only direct mode), `MainActivity.kt` forwards `attenlume://` intents, launcher shortcuts in `res/xml/shortcuts.xml`, `VIEW` intent filter, Flutter route deep linking off. Compiles into the debug APK. Not run on a phone.
- iOS: `ShortcutCommandCenter.swift` (in-app plugin, URLs through `addSceneDelegate`), `ShortcutIntents.swift` (Start, Stop, Bookmark, New conversation, Take photo, a test-only start without opening, Siri phrases), `CFBundleURLTypes`, `FlutterDeepLinkingEnabled` off, both Swift files added to `project.pbxproj` by hand. **Not built** (needs a Mac).
- `ShortcutTriggerSpike` (`lib/spikes/shortcut_trigger_spike.dart`): each command drives the real `RecordingService` (one-active rule, bookmarks only while recording), logs lifecycle on arrival, tap-to-recording time and the level for 5 s after each start, flags background and silent starts. JSON and Markdown.
- Device test `integration_test/p0_13_shortcut_trigger_test.dart` and manual steps MT-22 in `TEST_PLAN.md`.
- ADR-018 recorded. `PLATFORM_FEASIBILITY.md` 1, 2.13.1 and 3, `TEST_PLAN.md` (2.1, MT-22, AT-HF-01, results log) and `ARCHITECTURE.md` (8.8, 9) updated.
- **No trigger observed on any phone.** The device test was run on the build host with `-d windows` for 10 s: the harness ran, microphone permission true, no trigger arrived (Windows has no tile or intents; it fails by design). P0-13 is blocked: needs an Android 14+ phone, and a Mac and iPhone.

Test results on phase-0/P0-13-shortcut-trigger-spike (Windows 11 build host):

- flutter analyze: no issues.
- flutter test: 372 passed, 0 failed (23 new: 14 in `test/platform/shortcut_command_test.dart`, 9 in `test/spikes/shortcut_trigger_spike_test.dart`).
- `integration_test/p0_13_shortcut_trigger_test.dart -d windows` (10 s): failed as expected, no trigger on Windows (not a code fault).
- dart run tool/licence_audit.dart --check: up to date, nothing flagged.
- dart format --output=none --set-exit-if-changed lib test tool integration_test: clean.
- flutter build windows --release and flutter build apk --debug: both built.

## 2026-10-27, Claude Code (Opus 5.5): P1-05 rolling segment writer and atomic finalisation

- Start-of-session check on `main`: `flutter analyze` no issues, `flutter test` 372 passed.
- `RecordingService` rolls every `segmentMaxDuration` (default 10 minutes) through `switchingSegment` with end reason `roll`, same profile, reusing `_finishSegment` and `_beginSegment`. The timer is injected (`RollTimerFactory`), restarts with every new segment and is cancelled on pause, stop, profile or route change, error and dispose. A late timer for an ended segment does nothing [FR-REC-03].
- Atomic finalisation: the encoder writes `segment-NNN.partial.m4a` and the row points there while `writing`. Finalising inspects, hashes, flushes (`commitSegmentFile`, new `lib/data/filesystem/segment_commit.dart`), renames to `segment-NNN.m4a` and only then updates the row. Damaged files keep the partial name. A failed flush or rename keeps the good file under its partial name. Names are chosen so neither the partial nor the final file is overwritten (NFR-07).
- `MediaPaths.partial`/`isPartial`; `MediaAssetRepository.finaliseSegment` takes an optional `filePath`.
- Found by a test and fixed before merge: opening a missing file for append creates it, so `commitSegmentFile` checks the file exists first.
- One existing test changed on purpose: the row path while writing is now `segment-001.partial.m4a`.
- ADR-019 recorded. `ARCHITECTURE.md` (3, 8.9) and `TEST_PLAN.md` (2.1, 2.2) updated. No new packages.
- Not checked on a device: whether the roll timer fires on time with the screen locked (iOS background audio, Android after P1-11). Unverified.

Test results on phase-1/P1-05-rolling-segments (Windows 11 build host):

- flutter analyze: no issues.
- flutter test: 392 passed, 0 failed (20 new: 15 in `test/domain/recording_service_roll_test.dart`, 5 in `test/data/filesystem/segment_commit_test.dart`).
- dart run tool/licence_audit.dart --check: up to date, nothing flagged.
- dart format --output=none --set-exit-if-changed lib test tool integration_test: clean.
- flutter build windows --release and flutter build apk --debug: both built.

## 2026-10-27, Claude Code (Opus 5.5): P1-06 one-active rule across all triggers

- Start-of-session check on `main`: `flutter analyze` no issues, `flutter test` 392 passed.
- `RecordingService.switchTo(activityId, {replacing})`: checks the new activity first, then stops and saves the old one and starts the new one under one lock hold. `start` and `stop` share the same locked bodies [FR-REC-04, FR-REC-09].
- `OneActiveCoordinator` (`lib/domain/services/one_active_coordinator.dart`): one entry point for every trigger. `ui` and `notification` ask; `shortcut` and `voice` stop old, start new and confirm through `TriggerConfirmationSink` (`InAppTriggerConfirmations` stream until P1-11). Recorded minutes come from segment spans, pauses excluded [AT-REC-04].
- `OneActivePromptDialog` and `startRecordingFromUi` (`lib/features/capture/one_active_prompt_dialog.dart`): "'Data Mesh Keynote' is still recording (47 min)." with Stop it and start new / Keep it running / Cancel; paused wording. Providers added. No screen calls it yet (recording screen is P1-10).
- P0-13 spike comment corrected; it still logs conflicts instead of switching, on purpose (ADR-020).
- ADR-020 recorded. `ARCHITECTURE.md` (3, 8.10) and `TEST_PLAN.md` (2.1, 2.2, AT-REC-04) updated. No new packages.
- A widget test that drives the real database hung at first: futures made in the test's fake zone only complete while it is pumped, so the test pumps with real-time ticks and disposes the recorder inside the test body.
- Not checked on a device: whether a background shortcut is allowed to start the new recording after stopping the old one (MT-22). Unverified.

Test results on phase-1/P1-06-one-active (Windows 11 build host):

- flutter analyze: no issues.
- flutter test: 419 passed, 0 failed (27 new: 20 in `test/domain/one_active_coordinator_test.dart`, 7 in `test/features/capture/one_active_prompt_test.dart`).
- dart format --output=none --set-exit-if-changed lib test tool integration_test: clean.
- dart run tool/licence_audit.dart --check: up to date, nothing flagged.
- flutter build windows --release and flutter build apk --debug: both built.

## 2026-10-27, Claude Code (Opus 5.5): P1-07 InterruptionCoordinator

- Start-of-session check on `main`: `flutter analyze` no issues, `flutter test` 419 passed.
- `RecordingService.interrupt(reason)`: `recording -> interrupted`, segment ends with `interruption`, microphone released, `interruptions` row opened at the segment end. `resume()` refuses while interrupted, so the call is never recorded [FR-REC-05].
- `RecordingService.interruptionEnded(mayResume:)`: closes the row; with system permission `interrupted -> recovering -> recording` in a new segment (row auto-resumed), otherwise or on a failed restart `userResumeRequired` with "Your audio so far is saved. Tap Resume to carry on." `stop()` closes any open row.
- `InterruptionCoordinator` (`lib/domain/services/interruption_coordinator.dart`): audio session `began` (ducks ignored), `ended`, `devicesChanged` and `becomingNoisy` events handled one at a time. Camera use through `duringCameraUse` makes nearby interruptions `camera`, resumed straight after the shot [FR-PHO-07]. Notices ("Recording resumed", resume needed) through `InAppInterruptionNotices` until P1-11.
- Lost mic after a route change now opens a `route_lost` row in the service, closed on resume. The P0-07 spike's own row for that case removed (it caused a duplicate, found by the existing spike test).
- `RecordingService` owns the audio session: activated before capture, on resume and on recovery, deactivated once saved. `RecordingStatus.interruption` added for the P1-10 banner.
- Providers: `audioInterruptionSourceProvider`, `interruptionNoticesProvider`, `interruptionCoordinatorProvider` (started with `oneActiveCoordinatorProvider`).
- ADR-021 recorded. `ARCHITECTURE.md` (3, 8.11) and `TEST_PLAN.md` (2.1, 2.2) updated. No new packages.
- Not checked on a device: whether `audio_session` reports call start and end with the right resume flag, whether iOS lets recording restart after a call, and whether the camera interrupts audio at all (MT-17, MT-21). Unverified.

Test results on phase-1/P1-07-interruptions (Windows 11 build host):

- flutter analyze: no issues.
- flutter test: 455 passed, 0 failed (36 new: 17 in `test/domain/recording_service_interruption_test.dart`, 19 in `test/domain/interruption_coordinator_test.dart`).
- dart format --output=none --set-exit-if-changed lib test tool integration_test: clean.
- dart run tool/licence_audit.dart --check: up to date, nothing flagged.
- flutter build windows --release and flutter build apk --debug: both built.

## 2026-10-27, Claude Code (Opus 5.5): P1-08 crash recovery and reconciliation

- Start-of-session check on `main`: `flutter analyze` no issues, `flutter test` 455 passed.
- `CrashRecoveryService.reconcile()` (`lib/domain/services/crash_recovery_service.dart`) [FR-REC-08, AT-REC-03]: every `writing` row is checked at its path and, for a partial path, under the final name (ADR-019 rename-before-row case). Parsing files become `recovered` with fields read from the file and their final name; anything else becomes `damaged`, zero span (a gap), file kept under its partial name. Nothing deleted, no rename over an existing file (NFR-07).
- Open interruption rows closed (next segment start, else their own start). Activities left `active` become `completed`, or `draft` with no audio. The activity the recorder holds is skipped. Unlinked `.m4a` files in activity audio folders are listed and kept.
- `CrashRecoveryDialog` and `CrashRecoveryGate` (`lib/features/capture/crash_recovery_dialog.dart`): shown once per start when something was recovered; "Carry on recording" through the one-active coordinator when one activity was recording. `AttenlumeApp` wraps the welcome screen in the gate.
- Repository helpers: `MediaPaths.finalName`, `MediaAssetRepository.openInterruptions` and `segmentPaths`, `ActivityRepository.listByStatus`. `test/app/app_test.dart` overrides the report provider.
- ADR-022 recorded. `ARCHITECTURE.md` (3, 8.12) and `TEST_PLAN.md` (2.1 to 2.3) updated. No new packages.
- Not checked on a device: how a real encoder leaves its file after a force-kill (expected: no `moov`, so damaged) and whether the prompt appears on the next launch (MT-13, AT-REC-03). Unverified.

Test results on phase-1/P1-08-crash-recovery (Windows 11 build host):

- flutter analyze: no issues.
- flutter test: 481 passed, 0 failed (26 new: 20 in `test/domain/crash_recovery_service_test.dart`, 5 in `test/features/capture/crash_recovery_dialog_test.dart`, 1 in `test/data/filesystem/segment_commit_test.dart`).
- dart format --output=none --set-exit-if-changed lib test tool integration_test: clean.
- dart run tool/licence_audit.dart --check: up to date, nothing flagged.
- flutter build windows --release and flutter build apk --debug: both built.

## 2026-10-27, Claude Code (Opus 5.5): P1-09 recording profiles and selector

- Start-of-session check on `main`: `flutter analyze` no issues, `flutter test` 481 passed.
- `profile_estimates.dart`: MB per hour from the settings that will really be requested (Windows 43.2 for every profile, ADR-002) and safe minutes left above the 100 MiB hard reserve. Unknown free space reads "Space left unknown". FR-QUAL-05 notice when a profile cannot be met ("Economy records at 96 kbps instead of 32 kbps").
- `RecordingProfileSelector` (FR-UI-08): three profiles with MB per hour and time left, no record control. On the activity detail sheet until P1-10: a pick before the first segment stores the activity override; while the activity is recording or paused it shows the profile in use and changes go through `RecordingService.changeProfile` with the reason shown if declined; hidden once recorded.
- FR-QUAL-03: the wizard used to move unrecorded activities to a new default without asking. It now counts them (`ConferenceRepository.countUnrecordedInheritingActivities`) and asks "New activities only", "Change them too" or "Cancel".
- FR-QUAL-06 and the FR-QUAL-05 metadata were already in place (P0-09, P0-12). FR-QUAL-07: no WAV offered in v1. FR-QUAL-08: photos keep their own setting. ADR-023.
- New providers: `capturePlatformProvider`, `freeSpaceProbeProvider`, `mediaFreeBytesProvider`. No new packages.
- Not checked on a device: estimates against real file growth and free space on phones (unknown until P1-12), live change on a real recording (MT-18). Unverified.

Test results on phase-1/P1-09-profiles (Windows 11 build host):

- flutter analyze: no issues.
- flutter test: 504 passed, 0 failed (23 new: 9 in `test/domain/profile_estimates_test.dart`, 7 in `test/features/capture/recording_profile_selector_test.dart`, 3 in `test/features/activities/activity_detail_sheet_test.dart`, 3 in `test/features/conferences/conference_wizard_test.dart`, 1 in `test/data/repositories/conference_repository_test.dart`).
- dart format --output=none --set-exit-if-changed lib test tool integration_test: clean.
- dart run tool/licence_audit.dart --check: up to date, nothing flagged.
- flutter build windows --release and flutter build apk --debug: both built.

## 2026-10-27, Google Antigravity: P1-10 recording screen UI with level meter and mic test

- Start-of-session check on `main`: `flutter analyze` no issues, `flutter test` 504 passed.
- Full Recording Screen UI in navy `live-surface` (#00212B) in both light and dark themes ('house lights down', BUILD_GUIDE 5.3, ADR-024).
- FR-UI-01: 96px Record button (idle), Pause/Resume (live-raised) and Stop (2px muted ring, red square) controls. Elapsed time display in large `timer` typography with tabular figures. Debounced taps at 600ms (FR-REC-09) with haptic feedback.
- FR-UI-02: Header displaying conference name, activity title, and room (if set).
- FR-UI-03: One-tap Photo action button using `PluginPhotoCamera` wrapped in `InterruptionCoordinator.duringCameraUse`, persisting photo row with metadata and snackbar confirmation while keeping the shutter ready for immediate follow-up shots.
- FR-UI-04: One-tap Bookmark button and horizontally scrolling standard bookmark chips ("Important moment", "Question", "Follow-up", "Key slide", "Quote") meeting minimum 48px touch target height with 600ms live flash and haptics.
- FR-UI-05: Quick Thought / Reflection bottom sheet with private reflection toggle, saving text bookmark and appending markdown reflections to `activity.notesMd` without speaking into speaker audio.
- FR-UI-06: Active microphone input device label, live multi-bar waveform level meter in lime (`live` #DCFF38), and 10-second microphone test sheet with countdown and active vs. flat signal (peak <= -70.0 dBFS) detection.
- FR-UI-08: `RecordingProfileSelector` integrated apart from the Record button, allowing override changes before recording and live profile changes during recording (`RecordingService.changeProfile`).
- ADR-020 & ADR-021: Start delegates to `startRecordingFromUi` via `oneActiveCoordinatorProvider`, and interruptions display a navy/warning banner with a direct "Resume" button.
- ADR-024 recorded. `docs/ARCHITECTURE.md` and `docs/TEST_PLAN.md` updated. No new dependencies.

Test results on `phase-1/P1-10-recording-screen` (Windows 11 build host):

- `flutter analyze`: no issues.
- `flutter test`: 530 passed, 0 failed (26 new: 5 in `test/presentation/components/record_button_test.dart`, 4 in `test/presentation/components/bookmark_chip_test.dart`, 4 in `test/features/capture/level_meter_test.dart`, 3 in `test/features/capture/mic_test_sheet_test.dart`, 10 in `test/features/capture/recording_screen_test.dart`).
- `dart format --output=none --set-exit-if-changed lib test tool integration_test`: clean.
- `dart run tool/licence_audit.dart --check`: up to date, nothing flagged.
- `flutter build windows --release` and `flutter build apk --debug`: both built. Not tested on physical microphone/camera hardware (unverified).

## 2026-10-27, Google Antigravity: P1-11 Android foreground service and notification actions

- Start-of-session check on `main`: `flutter analyze` no issues, `flutter test` 530 passed.
- Requirement FR-REC-10: Persistent ongoing Android notification while recording with Pause/Resume, Stop, Bookmark and Photo actions.
- Built `RecordingForegroundService.kt`: Native Android foreground service declared with type `microphone` (`android:foregroundServiceType="microphone"`, `ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE`).
- Notification channel `attenlume_recording_channel` configured with `NotificationManager.IMPORTANCE_LOW` preventing continuous audible chimes on state and timer updates.
- Live Chronometer: Sets `setUsesChronometer(true)` with `setWhen(baseTimeMs)` while actively recording, giving zero-CPU live ticking in the Android status bar and notification shade without battery-draining wake locks. Pausing stops the chronometer and renders total elapsed duration.
- Notification action dispatch: Action buttons (Pause, Resume, Stop, Bookmark) dispatch via `PendingIntent.getService` directly to `onStartCommand` of `RecordingForegroundService`, which forwards them over `ForegroundServiceChannel.deliverAction` to Dart.
- Photo action: Dispatches an activity `PendingIntent` launching `MainActivity` with deep link `attenlume://photo?source=notification`.
- Platform channel bridge `ForegroundServiceBridge` (`lib/platform/foreground_service/foreground_service_bridge.dart`): `MethodChannelForegroundServiceBridge` on Android and `NoopForegroundServiceBridge` fallback on Windows and iOS.
- Coordinator `ForegroundServiceCoordinator` (`lib/domain/services/foreground_service_coordinator.dart`):
  - Listens to `RecordingService.statusStream`: starts foreground service on transition into `RecordingState.recording`, updates notification across segment rolls, pauses, resumes, and interruptions, and stops service on `saved`, `idle`, `stopping`, or `errorRecoverable`.
  - Notification action taps directly invoke `recorder.pause()`, `recorder.resume()`, `recorder.stop()`, or `media.addBookmark(source: BookmarkSource.notification)`.
  - Implements `InterruptionNoticeSink` to update ongoing notification content on interruption events, while multiplexing notices to `InAppInterruptionNotices`.
  - Computes total audio duration across finished segments plus the active open segment.
- ADR-025 recorded. `docs/ARCHITECTURE.md` and `docs/TEST_PLAN.md` updated. No new dependencies.

Test results on `phase-1/P1-11-android-notification` (Windows 11 build host):

- `flutter analyze`: no issues.
- `flutter test`: 550 passed, 0 failed (20 new: 7 in `test/platform/foreground_service/foreground_service_bridge_test.dart`, 10 in `test/domain/foreground_service_coordinator_test.dart`, 3 in `test/features/capture/recording_providers_foreground_test.dart`).
- `dart format --output=none --set-exit-if-changed lib test tool integration_test`: clean.
- `dart run tool/licence_audit.dart --check`: up to date, nothing flagged.
- `flutter build windows --release` and `flutter build apk --debug`: both built locally. Device verification (MT-17) remains unverified until real phone run.

## 2026-10-27, Google Antigravity: P1-12 StorageBudgetService and live budget UI

- Start-of-session check on `main`: `flutter analyze` no issues, `flutter test` 550 passed.
- Requirements FR-STO-01 through FR-STO-04 and FR-UI-07.
- Native platform free space channels:
  - Android: `FreeSpaceChannel.kt` querying `StatFs.availableBytes` and `totalBytes` over `com.samlytics.attenlume/free_space`. Attached to `MainActivity.kt`.
  - iOS: `FreeSpaceChannel.swift` querying `URLResourceKey.volumeAvailableCapacityForImportantUsageKey` and `volumeTotalCapacityKey` with fallback to `fileSystemFreeSize`. Registered in `AppDelegate.swift`.
  - `MethodChannelFreeSpaceProbe` (`lib/platform/storage/method_channel_free_space_probe.dart`): Unified Dart implementation for Android and iOS dispatching in `FreeSpaceProbe.forPlatform()`.
- `RecordingService` storage preflight and stop reason:
  - Injected `FreeSpaceProbe` and `StorageThresholds`. In `_refusal`, if `probe.availableBytes()` <= `thresholds.hardStopBytes` (100 MB), start is refused with `StartOutcome.storageFull`.
  - Added `SegmentEndReason.storageLow` (`storage_low` in database schema) for hard reserve stops.
  - Exposes `currentSegmentFile` and `currentSegmentStartUtc` for live rate measurement.
  - `OneActiveCoordinator` translates `StartOutcome.storageFull` to: "Cannot start recording: storage is nearly full (under 100 MB remaining)."
- `StorageBudgetService` (`lib/domain/services/storage_budget_service.dart`):
  - Periodic 30-second timer (`_startPeriodicCheck` / `_stopPeriodicCheck`) while recording.
  - Rolling write rate calculation: uses active segment file growth on disk when elapsed >= 5s; else prior segment history; else nominal profile rate.
  - Computes remaining minutes above 100 MB hard reserve (`hardStopBytes`).
  - Conference folder disk usage calculation via recursive directory sizing.
  - Hard stop enforcement: stops recording safely with `SegmentEndReason.storageLow` when space drops <= 100 MB and notifies via `hardStopNoticeStream`.
  - Protected with `SerialLock` to avoid race conditions.
- `StorageMeter` component (`lib/presentation/components/storage_meter.dart`):
  - Compact mode: single muted line under timer on `RecordingScreen` when OK; staged warning banner when <1 GB or <60 min; danger banner when <= 300 MB or <= 100 MB.
  - Expanded mode: used/free progress bar, conference usage, and optional `onManage` action.
- `RecordingScreen` integration:
  - Embedded compact `StorageMeter` inside `RecordButton` below timer.
  - Storage check pre-record, post-photo, and every 30s.
  - Alert SnackBar on hard stop reserve trigger.
- ADR-026 recorded. `docs/ARCHITECTURE.md` and `docs/TEST_PLAN.md` updated. No new dependencies.

Test results on `phase-1/P1-12-storage-budget` (Windows 11 build host):

- `flutter analyze`: no issues.
- `flutter test`: 578 passed, 0 failed (28 new: 3 in `test/platform/storage/method_channel_free_space_probe_test.dart`, 4 in `test/domain/recording_service_storage_test.dart`, 11 in `test/domain/storage_budget_service_test.dart`, 7 in `test/presentation/components/storage_meter_test.dart`, 3 in `test/features/capture/recording_screen_storage_test.dart`).
- `dart format --output=none --set-exit-if-changed lib test tool integration_test`: clean.
- `dart run tool/licence_audit.dart --check`: up to date, nothing flagged.
- `flutter build windows --release` and `flutter build apk --debug`: both built locally. Device free space verification remains unverified on physical phones.


## 27 October 2026: Android preview release, signing and MIT licence (Claude Code, Opus 5.5, attended)

Owner request: publish to `https://github.com/SamsonOluwaseun/attenlume` under MIT, with a README link that installs the app on Android.

- Before changes: `flutter test` 578 passed.
- `LICENSE` (MIT, Copyright (c) 2026 Samlytics Data Services, brand assets excluded). ADR-007 accepted as MIT. `tool/licence_audit.dart` wording updated and `THIRD_PARTY_NOTICES.md` regenerated (129 packages, 0 flagged).
- Release signing: upload keystore created outside the repo, `android/key.properties` (gitignored) points to it, `android/app/build.gradle.kts` uses it with debug-key fallback. ADR-027.
- `flutter build apk --release`: universal APK built, 63.9 MB, signer `CN=Samlytics Data Services` (SHA-256 aa55cabbf285ce80592bfc20253b36e2bed37b01028a6f95675e680c14b17315), checked with `apksigner verify`.
- README: "Try it on Android" section with the `releases/latest/download/attenlume-android.apk` link and install steps. `RELEASE_PLAN.md` 4.2 updated.
- After changes: `flutter analyze` no issues, `flutter test` 578 passed, `dart format` clean.
- Not yet observed: installing the APK on a real phone or tablet.

## 27 October 2026: capture entry, permission prompts, Windows data location (Claude Code, Opus 5.5, attended)

Owner report from the first Android tablet install: microphone, camera preview and the rest "not working". Findings and fixes in ADR-028.

- Before changes: `flutter test` 578 passed, `flutter analyze` clean.
- Microphone permission was never requested (`request: false`). Fixed; the mic test sheet checks permission first.
- Quick start and the Start activity sheet now open the recording screen (PRODUCT_SPEC J2).
- The recording screen says why a start was refused instead of "Couldn't start recording.".
- Windows data moved from `Documents` (OneDrive-synced on this PC) to `%LOCALAPPDATA%\Samlytics\Attenlume`.
- New: `integration_test/app_capture_journey_test.dart`, the J2 journey in the real app with real plugins, and `tool/build_windows_preview.ps1`.
- Windows run of the journey on this PC (Remote Desktop, no microphone redirected): conference created, Session opened the recording screen, Record refused with a visible message. Recording, photo, bookmark and stop steps not run: no microphone. Blocked: needs a microphone.
- Still open: Android 13+ notification permission is never requested; no camera viewfinder (P1-14).

## 27 October 2026: notification permission and P1-14 camera screen (Claude Code, Opus 5.5, owner away)

- Before changes: `flutter test` 581 passed, `flutter analyze` clean.
- ADR-029: Android 13+ notification permission requested when the recording service starts. Compiles in the release APK; unverified on a device.
- ADR-030 (P1-14 first slice): camera screen with live viewfinder, shutter ready after each shot, photo count and last thumbnail; `PhotoCaptureService`; `processPhoto` (EXIF rotation, 2048 px long edge, JPEG 85, 320 px thumbnail, SHA-256) on a background isolate; camera access denied and no camera messages. New dependency `image` 4.12.0 (MIT); notices regenerated (130 packages, 0 flagged).
- Tests: 15 new (6 photo processor, 7 capture service, 3 camera on the recording screen, minus the replaced blind-photo test). `flutter test` 596 passed, `flutter analyze` clean, `dart format` clean.
- `integration_test/app_capture_journey_test.dart` on Windows: Session opens the recorder, Record refused with a microphone message, Photo opens the camera screen, which says "No camera found on this device.", Close returns. Passed. No microphone or camera on this PC (Remote Desktop), so recording and shots are unverified here.
- Left in P1-14: FR-PHO-06 manual import with labels and captions.

## 27 October 2026: P1-14 photo import, captions and labels (Claude Code, Opus 5.5, owner away)

- Before changes: `flutter test` 596 passed.
- ADR-031: `file_selector` 1.1.0 (BSD-3); `importFiles` copies, compresses and thumbnails picked JPEG and PNG files with a batch label; photos section with thumbnails, photo sheet with caption and label; `updatePhotoText`.
- Fixed during testing: the import label dialog disposed its text controller while closing (crash in debug builds); it now owns the controller.
- Tests: 4 new (2 service, 2 widget). `flutter test` 600 passed, `flutter analyze` clean, notices up to date (131 packages incl. file_selector family).
- P1-14 done in code. Devices unverified.

## 27 October 2026: P1-13 safety prompts (Claude Code, Opus 5.5, owner away)

- Before changes: `flutter test` 600 passed.
- ADR-032: `SafetyPromptService` (2 hours, 10 minutes near-silence at -55 dBFS, battery under 15 % and not charging; never stops recording), banner on the recording screen with Keep recording and Stop and save, Android `BatteryChannel.kt` and `MethodChannelBatteryProbe`. iOS battery stays unknown.
- Tests: 12 new (8 service, 2 battery channel, 2 recording screen). `flutter test` 612 passed, `flutter analyze` clean.
- Devices unverified (thresholds and battery channel).

## 27 October 2026: P1-16 bookmarks and notes (Claude Code, Opus 5.5, overnight relay)

- Before changes: `flutter analyze` clean, `flutter test` 612 passed.
- ADR-033: bookmarks section in the activity details (offset, time of day, label, note; edit and remove), notes section with a plain-Markdown editor, Ctrl+B on the recording screen adds a `hotkey` bookmark. `MediaAssetRepository.updateBookmarkText`, `deleteBookmark`; `formatOffset`.
- Tests: 8 new (2 repository, 1 formatter, 4 widget, 1 recording screen hotkey). `flutter test` 620 passed, `flutter analyze` clean, `dart format` clean, notices up to date.
- `integration_test/app_capture_journey_test.dart` on Windows passed (no microphone or camera on this PC, so recording, bookmark and shutter steps not run).
- Devices unverified (notification bookmark, Ctrl+B on a Surface keyboard).

## 27 October 2026: P1-17 player, timeline and waveform summaries (Claude Code, Opus 5.5, overnight relay)

- Before changes: `flutter analyze` clean, `flutter test` 620 passed.
- ADR-034: `audioplayers` 6.8.1 (MIT) behind `AudioPlaybackEngine`, instead of the planned `just_audio` + `just_audio_windows`. `ReviewTimeline` (segments, gaps, interruptions, photos, bookmarks at offsets), `ReviewPlayerController` (joins segments, play/pause, scrub, 15 s skips in audio time, speeds 0.75 to 2), waveform summaries written from the live input level while recording (`waveforms/<segment_id>.wave`, 200 ms buckets) and drawn in 2-minute pages that read only their bytes, `ReviewScreen` from "Play and review" in the activity details.
- Tests: 28 new (6 timeline, 7 summary and pager, 3 summary recorder, 7 player, 5 widget). `flutter test` 648 passed, `flutter analyze` clean, `dart format` clean, notices regenerated (146 packages, 0 flagged).
- `flutter build windows --release` and `flutter build apk --debug` succeed with the new plugin. `integration_test/app_capture_journey_test.dart` on Windows passed (no microphone or camera on this PC).
- Playback, seeking and speed are unverified on every platform: no real recording can be made on the build host. MT-23 written.

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
| P0-14 | done | Cut-range maths, split logic, cuts.json manifest, M4A container trimmer, failure rollback pass 29 tests (179 total). ADR-003 |
| P1-01 | done | Quick start (<30 s, 1 field + 1 button), wizard, role, goals, outputs, profile, policy notice, archive, deletion summary pass 11 tests (190 total). ADR-009 |
| P1-02 | done | Conference home, stats card, dominant button, 4 quick-start buttons, chronological activity list, ActivityCard, StatusPill, AttenlumeButton, 28 new tests (218 total). ADR-010 |
| P1-03 | done | Activity CRUD editor, custom types, awareness consent check, contact fields, 19 new tests (237 total). ADR-011 |
| P1-04 | done (real capture unverified) | RecordingService, state machine, serial lock, media paths, 28 new tests (265 total). ADR-012 |
| P0-04 | blocked: needs real device | Harness, device test and MT-17 steps built, 10 unit tests with fakes pass (275 total). ADR-013. Android rerun needed after P1-11 |
| P0-12 | blocked: needs real device | Harness, `RecordingService.changeProfile`, device test and MT-18 steps built, 16 unit tests with fakes pass (291 total). ADR-014. Windows run on build host blocked (no capture device) |
| P0-10 | blocked: needs real device | Harness, memory and battery probes, device test and MT-19 steps built, 18 unit tests with fakes pass (309 total). ADR-015. Windows run on build host blocked (no capture device) |
| P0-07 | blocked: needs real device and headsets | Route probe, `RecordingService.routeChanged`, harness, device test and MT-20 steps built, 26 unit tests with fakes pass (335 total). ADR-016. Windows run on build host blocked (no capture device) |
| P0-05 | blocked: needs real device | `PhotoCamera` on `camera` 0.12.1, harness, device test and MT-21 steps built, 14 unit tests with fakes pass (349 total). ADR-017. Windows run on build host blocked (no capture device, no camera) |
| P0-13 | blocked: needs real device | `ShortcutBridge`, `attenlume://` parser, Android tile and launcher shortcuts (APK builds), iOS App Intents (not built, needs Mac), harness, device test and MT-22 steps, 23 unit tests with fakes pass (372 total). ADR-018 |
| P1-05 | done (device timing unverified) | 10-minute roll timer, partial names, flush then rename, 20 new tests (392 total). ADR-019. Interruption rolls come with P1-07 |
| P1-06 | done (device triggers unverified) | `switchTo`, `OneActiveCoordinator`, prompt dialog, 27 new tests (419 total). ADR-020 |
| P1-07 | done (device interruptions unverified) | `interrupt`, `interruptionEnded`, `InterruptionCoordinator`, camera and route events, 36 new tests (455 total). ADR-021 |
| P1-08 | done (device crash unverified) | `CrashRecoveryService`, recovery prompt and gate, 26 new tests (481 total). ADR-022 |
| P1-09 | done (device estimates unverified) | `estimateProfile`, `RecordingProfileSelector`, bulk change confirmation, 23 new tests (504 total). ADR-023 |
| P1-10 | done (device capture unverified) | Recording screen UI, 96px record button, debounce, tabular timer, level meter, mic test, photo, bookmarks, quick thought, 26 new tests (530 total). ADR-024 |
| P1-11 | done (real device unverified) | Native Android foreground service (type microphone), ongoing notification, chronometer, actions (pause/resume, stop, bookmark, photo), 20 new tests (550 total). ADR-025 |
| P1-12 | done (device storage unverified) | StorageBudgetService, rolling write rate, 30s checks, 100 MB hard reserve stop (storage_low), native Android/iOS free space channels, live StorageMeter compact/expanded UI, 28 new tests (578 total). ADR-026 |
| Android preview | done (device install unverified) | MIT `LICENSE`, release signing, universal release APK 63.9 MB, README download link. ADR-007 accepted, ADR-027 |
| Capture entry fixes | done (Android device check pending) | Mic permission prompt, quick start opens recorder, refusal messages, Windows data in local app data, J2 journey test on Windows, preview build script. ADR-028 |
| P1-14 | in progress (device camera unverified) | Camera screen with viewfinder, compression, thumbnails, SHA-256, 15 new tests (596 total). ADR-030. FR-PHO-06 still to do |
| Notification permission | done (device unverified) | Android 13+ POST_NOTIFICATIONS requested on first recording. ADR-029 |
| P1-14 | done (device camera unverified) | Camera screen, compression, thumbnails, SHA-256, import with labels, captions. 19 new tests (600 total). ADR-030, ADR-031 |
| P1-13 | done (device thresholds unverified) | SafetyPromptService, recording screen banner, Android battery channel, 12 new tests (612 total). ADR-032 |
| P1-16 | done (devices unverified) | Bookmarks list with edit and remove, notes editor, Ctrl+B hotkey bookmark, 8 new tests (620 total). ADR-033. Timeline and export use come with P1-17 and P1-21/22 |
| P1-17 | done (playback unverified on devices) | Review timeline, player across segments and gaps, waveform summaries and paged view, review screen, 28 new tests (648 total). ADR-034. MT-23 for devices |
