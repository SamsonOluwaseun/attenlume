# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5), unattended run
Branch: main (P0-03 merged from `phase-0/P0-03-docs`)
Current task ID: P0-09 (next)
Status: P0-03 done. P0-09 not started.

## Done in this session

- P0-03: created `docs/PRODUCT_SPEC.md`, `docs/PRIVACY_AND_SAFETY.md`, `docs/TEST_PLAN.md` and `docs/RELEASE_PLAN.md` with initial content from the build guide. Every document in build guide 1.6 is now linked from `README.md`, which also gained export format, caveats and Windows downloads sections.
- Test `test/docs/docs_index_test.dart` (P0-03) checks the 1.6 documents exist and are linked from the README.
- `flutter analyze` clean, `flutter test` 14 pass, format clean.
- No ADR needed (docs only, no decisions beyond the build guide).

## Left to do on this task

Nothing. Keep the new docs current as work lands:

- `TEST_PLAN.md` 2.1 lists the current test files. Update it when tests are added. Device cells stay unverified until a real run is logged in section 6.
- `PRIVACY_AND_SAFETY.md` 6 has draft permission strings. Use them when adding permissions to `AndroidManifest.xml` and `Info.plist`.
- `PRODUCT_SPEC.md` 5 has acceptance detail (default title format, profile precedence, offset rule) that P0-09 and P1 tasks should test against.

## Exact next step

Start P0-09 on branch `phase-0/P0-09-data-model`: implement the Drift tables in build guide 9.4 (conferences, goals, activity_types, activities, recording_segments, interruptions, photos, bookmarks, cut_ranges, export_jobs, app_settings; leave Phase 1.5 and 2 tables out), seed built-in activity types (NFR-03), repositories in `lib/data/repositories/`, domain models in `lib/domain/models/`, and fixtures in `test/fixtures/`. Nothing has shipped, so schema v1 may be redefined, but regenerate the dump (see Watch out). Tests: FR-QUAL-02 precedence, FR-ACT-05 default titles, offset rule across gaps, cascade deletes, UTC storage, migration test.

After P0-09: P0-06 (Windows mic and AAC, partly doable on this PC), P0-08 (licence review, desk work), P0-11 (export half automatable). P0-04, P0-05, P0-07, P0-10, P0-12, P0-13 need real devices: build harnesses and manual steps, then mark blocked.

## Watch out

- Design tokens: edit `design/tokens.json`, then `dart run tool/gen_tokens.dart`. `test/app/theme/tokens_sync_test.dart` fails if `tokens.dart` is stale.
- Drift: run `dart run build_runner build` after table changes. If redefining v1: `dart run drift_dev make-migrations` and `dart run drift_dev schema generate drift_schemas/app_database/ test/data/local_database/generated/`.
- `test/**/generated/**` and `*.g.dart` are excluded from analysis. Commit generated files (CI checks they are current).
- `.gitattributes` forces LF for `*.dart` and `*.yaml`.
- `camera` does not include Windows. Add `camera_windows` explicitly when photos arrive. `record` has no permission check on Windows.
- Do not build from a path with `~` (8.3 short names).
- If you add or rename a 1.6 document, update `test/docs/docs_index_test.dart` and the README list.

## Files touched

New: `docs/PRODUCT_SPEC.md`, `docs/PRIVACY_AND_SAFETY.md`, `docs/TEST_PLAN.md`, `docs/RELEASE_PLAN.md`, `test/docs/docs_index_test.dart`.
Changed: `README.md`, `docs/PROGRESS.md`, `docs/HANDOVER.md`.

## Failing or skipped tests

None failing. Nothing skipped. No device tests have been run on any platform.

## Open questions for the owner

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
