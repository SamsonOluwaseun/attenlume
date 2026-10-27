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

## Task status

| Task | Status | Evidence |
|---|---|---|
| P0-01 | done | `docs/PLATFORM_FEASIBILITY.md` and `docs/ARCHITECTURE.md` drafted, ADR-002. Desk audit only, no device results |
| P0-02 | done (CI unverified) | analyze clean, 12 tests pass, Windows and APK debug builds succeed locally. CI file written, not run (no remote). No device runs |
| P0-03 | todo | |
