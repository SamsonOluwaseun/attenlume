# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5)
Branch: main
Current task ID: P0-01
Status: todo (environment ready, no app code yet)

## Done in this session

- Toolchain installed and proven with Windows and Android debug builds (see `docs/PROGRESS.md`).
- Repo laid out: `docs/BUILD_GUIDE.md`, `docs/DESIGN_GUIDE.md`, `docs/design/components/`, `design/tokens.json`, `assets/brand/`, `assets/fonts/`.
- ADR-001 recorded (Attenlume name, repo location, unattended workflow).

## Left to do on this task

All of P0-01: audit packages and platform docs, then write `docs/PLATFORM_FEASIBILITY.md` and `docs/ARCHITECTURE.md`.

## Exact next step

Start P0-01. Then P0-02 scaffolds the Flutter app in the repo root: `flutter create --org com.samlytics --project-name attenlume --platforms=android,ios,windows .`. Keep the existing files, then add Riverpod, Drift and lints.

## Watch out

- **Fonts:** `assets/fonts/` holds Montserrat as `.woff`, which Flutter cannot load. Download the Montserrat TTFs (400, 500, 600, 700) from the official Google Fonts repo (SIL OFL, `OFL.txt` already present) into `assets/fonts/` and declare them in `pubspec.yaml`. Keep the `.woff` files.
- Do not build from a path containing `~` (8.3 short names). CMake fails on it. `C:\dev\attenlume` is fine.
- Logos: use the PNGs exactly as supplied (see `docs/DESIGN_GUIDE.md`). Generate launcher icons with `flutter_launcher_icons`.
- `ffmpeg_kit_flutter` is retired. See FR-REV-07 and ADR-003 (to be written in P0-14).

## Files touched

AGENTS.md (read order plus the unattended mode section), .gitignore, docs/*, tool/*

## Failing or skipped tests

None yet. No app code exists.

## Open questions for the owner

- Confirm the store identifiers `com.samlytics.attenlume` before the first submission.
- Choose MIT or Apache 2.0 after P0-08.
- Real-device testing (Android phone, iPhone, Surface) is needed for spikes P0-04, P0-05, P0-07, P0-10, P0-12 and P0-13.

## Commands to run

```powershell
cd C:\dev\attenlume
flutter analyze
flutter test
flutter build windows --debug
flutter build apk --debug
```
