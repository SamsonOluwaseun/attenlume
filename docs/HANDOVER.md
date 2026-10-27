# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5), unattended run
Branch: main (P0-02 merged from `phase-0/P0-02-scaffold`)
Current task ID: P0-03 (next)
Status: P0-02 done locally (CI file written but not run, no remote). P0-03 not started.

## Done in this session

- P0-02 Flutter scaffold: Android, iOS and Windows targets, Riverpod, Drift (v1 with `app_settings`), strict lints, Montserrat TTFs, generated design tokens, light, dark and live themes, placeholder welcome screen, CI workflow, README.
- ADR-004 (scaffold conventions). Tested versions in `docs/ARCHITECTURE.md` 7, code layout in 8.
- `flutter analyze` clean, `flutter test` 12 pass, `flutter build windows --debug` and `flutter build apk --debug` succeed.

## Left to do on this task

- CI has never run. Once the owner adds a remote, check all three jobs go green (the macOS iOS job is the least certain).
- Launcher icons not generated (ADR-004 item 7, open question below).

## Exact next step

Start P0-03 on branch `phase-0/P0-03-docs`: create the docs from build guide 1.6 that do not exist yet, with initial content, and link them all from `README.md`:

- `docs/PRODUCT_SPEC.md` (journeys, stories, edge cases from build guide 2, 5 and 11)
- `docs/PRIVACY_AND_SAFETY.md` (5.12, 7.2, NFR-01, NFR-09, NFR-13)
- `docs/TEST_PLAN.md` (13, the AT- list, device matrix with every cell unverified, AT-CLD placeholders)
- `docs/RELEASE_PLAN.md` (14, 10.3 distribution, iOS signing blocked without a Mac)

Then run `flutter analyze` and `flutter test` (docs only, but keep the habit), merge with `--no-ff`.

After P0-03, P0-09 (data model) is the next fully automatable task. P0-04, P0-05, P0-07, P0-10, P0-12, P0-13 need real devices: build harnesses and manual steps, then mark blocked. P0-06 (Windows mic and AAC) can be partly done on this PC. P0-08 (licence review) is desk work.

## Watch out

- Design tokens: edit `design/tokens.json`, then `dart run tool/gen_tokens.dart`. `test/app/theme/tokens_sync_test.dart` fails if `tokens.dart` is stale.
- Drift: run `dart run build_runner build` after table changes. P0-09 may redefine schema v1 (nothing has shipped), but must then regenerate the dump: `dart run drift_dev make-migrations` and `dart run drift_dev schema generate drift_schemas/app_database/ test/data/local_database/generated/`.
- `test/**/generated/**` and `*.g.dart` are excluded from analysis. Commit generated files (CI checks they are current).
- `.gitattributes` forces LF for `*.dart` and `*.yaml`.
- `camera` does not include Windows. Add `camera_windows` explicitly when photos arrive. `record` has no permission check on Windows (`PLATFORM_FEASIBILITY.md` 2.6).
- Do not build from a path with `~` (8.3 short names). `C:\dev\attenlume` is fine.

## Files touched

New: `.github/workflows/ci.yml`, `.gitattributes`, `build.yaml`, `analysis_options.yaml`, `pubspec.yaml`, `pubspec.lock`, `.metadata`, `android/`, `ios/`, `windows/`, `lib/` (app, theme, database, welcome screen), `test/` (app, theme, database, migration, generated schema), `drift_schemas/`, `tool/gen_tokens.dart`, `assets/fonts/Montserrat-*.ttf`.
Changed: `README.md`, `docs/ARCHITECTURE.md`, `docs/DECISIONS.md` (ADR-004), `docs/PROGRESS.md`, `docs/HANDOVER.md`.

## Failing or skipped tests

None failing. Nothing skipped. No device tests have been run on any platform.

## Open questions for the owner

- App icons: can the designer supply the platform exports (iOS 1024 full-bleed without transparency, Android adaptive foreground plus monochrome layer, Windows .ico), as listed in `assets/brand/README.md`? Until then the default Flutter icons remain.
- Add a GitHub remote so CI can run (ADR-001).
- Confirm the store identifiers `com.samlytics.attenlume` before the first submission.
- Choose MIT or Apache 2.0 after P0-08.
- Real-device testing (Android phone, iPhone, Surface) is needed for spikes P0-04, P0-05, P0-07, P0-10, P0-12 and P0-13. iOS also needs a Mac or macOS CI with signing.
- Windows recordings will be about 43 MB per hour (96 kbps minimum of the Windows AAC encoder). Acceptable, or should P0-06 evaluate a bundled low-bitrate encoder? (ADR-002)

## Commands to run

```powershell
cd C:\dev\attenlume
flutter pub get
dart run build_runner build
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed lib test tool
flutter build windows --debug
flutter build apk --debug
```
