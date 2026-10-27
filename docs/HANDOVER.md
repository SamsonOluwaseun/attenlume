# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5), unattended run
Branch: main (P0-09 merged from `phase-0/P0-09-data-model`)
Current task ID: P0-06 (next)
Status: P0-09 done. P0-06 not started.

## Done in this session

- P0-09: database schema v2 with every Phase 1 table from build guide 9.4, migration from v1, built-in activity types, domain models, rules, repositories, Riverpod providers and fixtures. Details in `docs/PROGRESS.md`, decisions in ADR-005.
- 62 new tests (76 total), all passing. Analyze and format clean. Windows and APK debug builds succeed.

## Left to do on this task

Nothing. Later tasks build on it:

- P1-01 needs the device's IANA timezone for new conferences (`ConferenceRepository.create` takes it as a parameter). That needs a plugin such as `flutter_timezone`: audit it first (AGENTS rules).
- P1-08 crash recovery can use `MediaAssetRepository.unfinalisedSegments()` and `setSegmentState()`.
- P1-18 split and merge, and P1-23 re-import, are not in `ActivityRepository` yet.
- Media file deletion is deliberately not in the repositories (ADR-005 item 10).

## Exact next step

Start P0-06 on branch `phase-0/P0-06-windows-mic`: a spike harness that records from the Windows microphone with `record` (AAC-LC, ADR-002 says 96 kbps minimum on Windows), writes rolling segments to a folder, reads back codec, bitrate and size, and exports the folder. Automate what runs on this build PC. If no microphone is available, record that and mark the device part blocked. Record results in `docs/PLATFORM_FEASIBILITY.md`.

After P0-06: P0-08 (licence review, desk work, `THIRD_PARTY_NOTICES.md`), P0-11 (streaming export with bounded RAM, half automatable, now unblocked by P0-09). P0-04, P0-05, P0-07, P0-10, P0-12 and P0-13 need real devices: build harnesses and manual steps, then mark blocked.

## Watch out

- Schema changes: edit `lib/data/local_database/tables.dart`, bump `schemaVersion`, run `dart run build_runner build`, then `dart run drift_dev make-migrations` (writes the dump, `app_database.steps.dart` and `test/drift/app_database/generated/`). Add a `fromNToM` step and a data test in `test/drift/app_database/migration_test.dart`. If an unreleased dump is wrong, delete only that dump and rerun.
- Never rename an enum `key` in `lib/domain/models/enums.dart`: they are stored. Add a migration instead.
- Drift column getters cannot be named `text` (see `Goals.goalText`). Column `.check()` that refers to its own getter trips the `recursive_getters` lint: use table `customConstraints`.
- Dart 3.13 private named parameters are used in repositories (`this._clock`), called as `clock:`.
- Design tokens: edit `design/tokens.json`, then `dart run tool/gen_tokens.dart`.
- `test/**/generated/**` and `*.g.dart` are excluded from analysis. Commit generated files.
- `camera` does not include Windows. Add `camera_windows` explicitly when photos arrive. `record` has no permission check on Windows.
- Do not build from a path with `~` (8.3 short names).
- Bash heredocs with several files in one command failed in this shell. Write files with the editor tool.

## Files touched

New: `lib/domain/models/{enums,conference,activity,media,export_job}.dart`, `lib/domain/services/{recording_profile_rules,activity_title,timeline_offset}.dart`, `lib/data/local_database/{tables,converters,builtin_activity_types,app_database.steps}.dart`, `lib/data/repositories/*.dart`, `drift_schemas/app_database/drift_schema_v2.json`, `test/drift/app_database/**`, `test/fixtures/fixtures.dart`, `test/domain/domain_rules_test.dart`, `test/data/repositories/*_test.dart`.
Changed: `lib/data/local_database/app_database.dart` (+ `.g.dart`), `pubspec.yaml`, `pubspec.lock`, `docs/ARCHITECTURE.md`, `docs/TEST_PLAN.md`, `docs/DECISIONS.md`, `docs/PROGRESS.md`, `docs/HANDOVER.md`.
Removed: `test/data/local_database/migration_test.dart` and `test/data/local_database/generated/` (replaced by `test/drift/app_database/`).

## Failing or skipped tests

None failing. Nothing skipped. No device tests have been run on any platform.

## Open questions for the owner

- Please review ADR-005, especially: reflections private by default, labels "Conversation" and "Reflection" for the built-in types, and how FR-QUAL-03 pins existing activities.
- App icons: can the designer supply the platform exports (iOS 1024 full-bleed without transparency, Android adaptive foreground plus monochrome layer, Windows .ico), as listed in `assets/brand/README.md`?
- Add a GitHub remote so CI can run (ADR-001).
- Confirm `com.samlytics.attenlume` and the publisher name before the first submission.
- Choose MIT or Apache 2.0 after P0-08.
- Real-device testing (Android phone, iPhone, Surface) is needed for spikes P0-04, P0-05, P0-07, P0-10, P0-12 and P0-13. iOS also needs a Mac or macOS CI with signing.
- Windows recordings will be about 43 MB per hour (96 kbps minimum of the Windows AAC encoder). Acceptable, or should P0-06 evaluate a bundled low-bitrate encoder? (ADR-002)
- Please review the draft permission wording in `docs/PRIVACY_AND_SAFETY.md` section 6 and the release blockers in `docs/RELEASE_PLAN.md` section 8.

## Commands to run

```powershell
cd C:\dev\attenlume
flutter pub get
dart run build_runner build
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed lib test tool
```
