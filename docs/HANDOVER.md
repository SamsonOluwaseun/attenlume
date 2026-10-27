# Handover

Date and agent: 27 October 2026, Claude Code (Opus 5.5), unattended run
Branch: main (P0-08 merged from `phase-0/P0-08-licences`)
Current task ID: P0-11 (next)
Status: P0-08 done (the licence choice itself waits for the owner). P0-11 not started.

## Done in this session

- P0-08: `tool/licence_audit.dart` generates `THIRD_PARTY_NOTICES.md` from `pubspec.lock` and each package's licence file. 115 packages, 77 reachable from the app, nothing copyleft or unrecognised. Native code (SQLite public domain, Kotlin libraries Apache-2.0), Montserrat OFL 1.1, brand assets (not open source) and planned Lucide icons covered in a hand-written section of the tool.
- `test/docs/third_party_notices_test.dart` (17 tests, `P0-08`): every locked package listed, file not stale, no flagged package in the app, classifier cases.
- ADR-007 (proposed): recommends Apache 2.0. No `LICENSE` file added.
- 117 tests pass, analyze and format clean, Windows release and APK debug builds succeed.

## Left to do on this task

Only the owner's choice. When confirmed: add `LICENSE` (standard Apache 2.0 text, or MIT), a short `NOTICE` (Apache only), set the licence line in `README.md` and mark ADR-007 accepted. Later, in the P1 About screen: `showLicensePage` plus `LicenseRegistry.addLicense` for `assets/fonts/OFL.txt` (Flutter's automatic `NOTICES` does not include our bundled fonts).

## Exact next step

Start P0-11 on branch `phase-0/P0-11-storage-export`: spike for low-storage simulation and streaming export with bounded RAM (depends on P0-09, done). `lib/data/filesystem/folder_export.dart` already streams with SHA-256; add a free-space probe interface (`FreeSpaceProbe`, ADR-002 item 4: `GetDiskFreeSpaceExW` on Windows via `win32` or FFI, method channels later for phones), a fake probe for tests, a low-storage pre-check and mid-export failure test (disk full simulated through an injected writer), and a RAM measurement for a large export (generate a multi-GB sparse or synthetic file in a temp folder, record `ProcessInfo.currentRss` peaks, and record the real numbers only). Write the result in `docs/PLATFORM_FEASIBILITY.md`.

After P0-11: P0-14 (trimming approach, ADR-003, desk research plus harness). P0-04, P0-05, P0-07, P0-10, P0-12 and P0-13 need real devices: build harnesses and manual steps, then mark blocked.

## Files touched

New: `tool/licence_audit.dart`, `THIRD_PARTY_NOTICES.md`, `test/docs/third_party_notices_test.dart`.
Changed: `pubspec.yaml` and `pubspec.lock` (`yaml` dev dependency), `README.md`, `docs/ARCHITECTURE.md`, `docs/RELEASE_PLAN.md`, `docs/TEST_PLAN.md`, `docs/DECISIONS.md`, `docs/PROGRESS.md`, `docs/HANDOVER.md`.

## Watch out

- **Any change to `pubspec.lock` now needs `dart run tool/licence_audit.dart`**, otherwise the `P0-08` stale-file test fails. Look at the new licences before committing.
- The audit reads `.dart_tool/package_config.json`, so run `flutter pub get` first.
- This PC's agent session is Remote Desktop: no microphone, and probably no camera either. Device spikes cannot run here unattended.
- `record` on Windows silently picks the nearest supported AAC setting. Always store what `M4aInspector` reads from the file, never the request.
- Android: `RECORD_AUDIO` is not in the manifest yet (P0-04 / P1-11).
- Earlier notes still apply: schema changes need `make-migrations` and a migration test, never rename enum keys, commit generated files, do not build from a path with `~`, do not use Windows file locks for failure injection in tests.

## Failing or skipped tests

None failing in `flutter test`. Nothing skipped. `integration_test/p0_06_windows_mic_test.dart` still fails on this PC (no microphone in the session, blocked, expected). No device tests have been run on any platform.

## Open questions for the owner

- **Project licence:** ADR-007 recommends Apache 2.0 (patent grant, says it grants no trademark rights). MIT is equally compatible with every dependency. Which one? Also confirm the copyright holder name ("Samlytics Data Services") and that brand assets stay all rights reserved.
- `record`'s LICENSE names "openapi4j authors" (upstream copy error). Permissive either way; report upstream if you wish.
- Please run MT-16 (`docs/TEST_PLAN.md`) at the PC's console or on a Surface: `flutter test integration_test/p0_06_windows_mic_test.dart -d windows`.
- Earlier questions still open: ADR-005 and ADR-006 review; app icon exports; GitHub remote for CI; `com.samlytics.attenlume` and publisher name; real devices for P0-04, P0-05, P0-07, P0-10, P0-12, P0-13 (iOS needs a Mac or macOS CI with signing); Windows 96 kbps acceptable (ADR-002); permission wording in `docs/PRIVACY_AND_SAFETY.md` 6 and release blockers in `docs/RELEASE_PLAN.md` 8.

## Commands to run

```powershell
cd C:\dev\attenlume
flutter pub get
dart run build_runner build
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed lib test tool integration_test
dart run tool/licence_audit.dart --check   # after any dependency change, run without --check to regenerate
# Device test (needs a microphone in the session):
flutter test integration_test/p0_06_windows_mic_test.dart -d windows
```
