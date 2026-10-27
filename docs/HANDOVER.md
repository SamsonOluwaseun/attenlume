# Handover

Date and agent: 27 October 2026, Google Antigravity, unattended run
Branch: main (P0-11 merged from `phase-0/P0-11-storage-export`)
Current task ID: P0-14 (next)
Status: P0-11 done. P0-14 not started.

## Done in this session

- P0-11: Low-storage simulation and streaming export with bounded RAM [FR-STO-01, FR-STO-02, FR-STO-04, FR-EXP-02, FR-EXP-04, FR-EXP-05, FR-EXP-06, AT-STO-02, AT-STO-03].
  - `FreeSpaceProbe` interface (`lib/platform/storage/free_space_probe.dart`) and Win32 `GetDiskFreeSpaceExW` implementation (`windows_free_space_probe.dart`) via `dart:ffi`.
  - Storage threshold service `StorageThresholds` (`lib/domain/services/storage_thresholds.dart`) implementing FR-STO-01/02/04 thresholds (ok, warning, urgent, hardStop).
  - Preflight checks `preflightExport`, `estimateFolderExportBytes`, and `estimateZipExportBytes` (`lib/data/filesystem/export_space.dart`) with `defaultExportReserveBytes` (256 MB) and `InsufficientSpaceException`.
  - Streaming ZIP export `exportZip` (`lib/data/filesystem/zip_export.dart`) with store compression (level 0), embedded `checksums.sha256` and companion `<zipName>.sha256`, and atomic rename from `.partial`.
  - `exportFolder` updated to support preflight free-space checks, injected writers (`openSink`), and mapping of OS disk-full errors (112/39 on Windows, 28 on POSIX) to `ExportOutOfSpaceException`.
  - Clean failure recovery: verified that both folder and ZIP exports delete partial files and leave sources untouched on preflight failure or mid-export disk-full.
  - Large-export benchmark on Windows 11 host (1 GiB synthetic file):
    - `exportFolder`: 18.1 s, peak RSS delta 10.3 MB. Verified checksums clean.
    - `exportZip`: 18.8 s, peak RSS delta 5.6 MB. ZIP size 1,073,742,095 bytes (271 bytes overhead).
  - Spike runner `StorageExportSpike` (`lib/spikes/storage_export_spike.dart`).
  - 33 new tests added (150 total tests, 0 failed).
  - ADR-008 recorded in `docs/DECISIONS.md`.
  - Both `flutter build windows --release` and `flutter build apk --debug` succeed on `main`.

## Left to do on this task

None. P0-11 is complete.

## Exact next step

Start P0-14 on branch `phase-0/P0-14-trimming`: spike for trimming approach per platform (passthrough trimming without re-encoding, ADR-003 desk research plus harness).
Note: Spikes P0-04, P0-05, P0-07, P0-10, P0-12, and P0-13 require real devices (phone/Mac/microphone).

## Files touched

New:
- `lib/platform/storage/free_space_probe.dart`
- `lib/platform/storage/windows_free_space_probe.dart`
- `lib/domain/services/storage_thresholds.dart`
- `lib/data/filesystem/export_space.dart`
- `lib/data/filesystem/zip_export.dart`
- `lib/spikes/storage_export_spike.dart`
- `test/fixtures/fake_free_space_probe.dart`
- `test/platform/free_space_probe_test.dart`
- `test/domain/storage_thresholds_test.dart`
- `test/data/filesystem/export_space_test.dart`
- `test/data/filesystem/zip_export_test.dart`
- `test/spikes/storage_export_spike_test.dart`

Changed:
- `pubspec.yaml` and `pubspec.lock` (`archive` 4.5.2, `ffi` 2.2.0)
- `THIRD_PARTY_NOTICES.md`
- `lib/data/filesystem/folder_export.dart`
- `test/data/filesystem/folder_export_test.dart`
- `docs/PLATFORM_FEASIBILITY.md`
- `docs/DECISIONS.md`
- `docs/PROGRESS.md`
- `docs/HANDOVER.md`

## Failing or skipped tests

None failing in `flutter test` (150 passed). Nothing skipped. `integration_test/p0_06_windows_mic_test.dart` still fails on this PC (no microphone in Remote Desktop session, blocked, expected). No device tests run.

## Open questions for the owner

- **Project licence:** ADR-007 recommends Apache 2.0. Awaiting owner choice between Apache 2.0 and MIT, copyright holder confirmation ("Samlytics Data Services"), and brand asset exclusion.
- Device testing for blocked tasks (P0-04, P0-05, P0-06/MT-16, P0-07, P0-10, P0-12, P0-13).

## Commands to run

```powershell
cd C:\dev\attenlume
flutter pub get
dart run build_runner build
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed lib test tool integration_test
dart run tool/licence_audit.dart --check
flutter build windows --release
flutter build apk --debug
```
