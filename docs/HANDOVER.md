# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5), unattended run
Branch: main (P0-01 merged from `phase-0/P0-01-feasibility-audit`)
Current task ID: P0-02 (next)
Status: P0-01 done. P0-02 not started.

## Done in this session

- P0-01 desk audit: `docs/PLATFORM_FEASIBILITY.md` (spike matrix, capability audit, official sources) and `docs/ARCHITECTURE.md` (layers, recording lifecycle, export design, dependency audit with versions and licences).
- ADR-002: starting package stack, plus the Windows AAC finding (Media Foundation only allows 96 to 192 kbps, so every profile maps to 96 kbps mono on Windows).
- `tool/pub_audit.py`: re-runnable pub.dev audit (`python -I tool/pub_audit.py <packages>`).

## Left to do on this task

Nothing on P0-01. Device results come from the spikes (P0-04 onwards).

## Exact next step

Start P0-02 on branch `phase-0/P0-02-scaffold`:

1. `flutter create --org com.samlytics --project-name attenlume --platforms=android,ios,windows .` in the repo root. Keep existing files.
2. Add packages from `docs/ARCHITECTURE.md` 6.1 that P0-02 needs now: `flutter_riverpod`, `drift`, `drift_flutter`, `sqlite3`, `path_provider`, `path`, `uuid`, dev: `drift_dev`, `build_runner`, `flutter_lints`, `mocktail`. **Do not add `sqlite3_flutter_libs`** (end of life).
3. Lints in `analysis_options.yaml`. Montserrat TTFs and theme tokens (see below).
4. `flutter analyze`, `flutter test`, `flutter build windows --debug`, `flutter build apk --debug`. Fill section 7 "Tested versions" in `docs/ARCHITECTURE.md` from `pubspec.lock`.
5. CI workflow file (runs only once a remote exists, ADR-001).

## Watch out

- **Fonts:** `assets/fonts/` holds Montserrat as `.woff`, which Flutter cannot load. Download the Montserrat TTFs (400, 500, 600, 700) from the official Google Fonts repo (SIL OFL, `OFL.txt` already present) into `assets/fonts/` and declare them in `pubspec.yaml`. Keep the `.woff` files.
- Do not build from a path containing `~` (8.3 short names). CMake fails on it. `C:\dev\attenlume` is fine.
- Logos: use the PNGs exactly as supplied (see `docs/DESIGN_GUIDE.md`). Generate launcher icons with `flutter_launcher_icons`.
- `camera` does not include Windows. Add `camera_windows` explicitly when photos arrive.
- `record` has no permission check on Windows. See `PLATFORM_FEASIBILITY.md` 2.6.

## Files touched

docs/PLATFORM_FEASIBILITY.md (new), docs/ARCHITECTURE.md (new), docs/DECISIONS.md (ADR-002), docs/PROGRESS.md, docs/HANDOVER.md, tool/pub_audit.py (new)

## Failing or skipped tests

None. No app code exists yet, so `flutter analyze` and `flutter test` were not applicable.

## Open questions for the owner

- Confirm the store identifiers `com.samlytics.attenlume` before the first submission.
- Choose MIT or Apache 2.0 after P0-08.
- Real-device testing (Android phone, iPhone, Surface) is needed for spikes P0-04, P0-05, P0-07, P0-10, P0-12 and P0-13. iOS also needs a Mac or macOS CI with signing.
- Windows recordings will be about 43 MB per hour (96 kbps minimum of the Windows AAC encoder) instead of 14 to 29 MB. Is that acceptable, or should P0-06 evaluate a bundled low-bitrate encoder? (ADR-002)

## Commands to run

```powershell
cd C:\dev\attenlume
flutter analyze
flutter test
flutter build windows --debug
flutter build apk --debug
python -I tool/pub_audit.py record drift camera   # refresh package data
```
