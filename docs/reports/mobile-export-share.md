# Mobile export sharing report (FR-EXP-02, ADR-042)

Builder: Claude Code (Opus 5.5), 28 October 2026. Branch `feat/mobile-export-share`, based on main `dd75822`. Decision record: ADR-042.

## Why

On Android and iOS an export lands in the app's private documents folder (`<app documents>/exports/`, ADR-040) and the sheet only showed the path, so a phone user could not get it out. The owner wants to export a conference on a phone or tablet and use it with an AI app or Google Drive.

## What was built

| Item | What exists now |
|---|---|
| Package | `share_plus` 13.3.1 (BSD-3-Clause; Android, iOS, Windows). `THIRD_PARTY_NOTICES.md` regenerated: 162 packages, 0 flagged. |
| Interface | `ExportSharer` (`lib/platform/share/export_sharer.dart`): `canShare` (Android and iOS), `shareFile(path, subject:, origin:)`. `SharePlusExportSharer` implements it; `exportSharerProvider` in `export_providers.dart`; `FakeExportSharer` in `test/fixtures/`. |
| ZIP default on mobile | When `canShare` is true the sheet starts on ZIP and the hint says the file can go to Files, Google Drive or an AI app. Windows still starts on Folder. |
| Share button | After a ZIP export on Android and iOS: a primary **Share** button, then the file name and size ("... .zip, 1.2 GB. A copy stays in the app after sharing."), the path, "Copy location" and Done. The share sheet is anchored to the button (iPad popover). A failure to open shows a snack bar. |
| Folder on mobile | Not shared (nested folders, clashing names, most targets take one file). The format hint warns before; the result says to export again as a ZIP. |
| Clean-up | Nothing deletes exports. On Android `share_plus` copies the file into `<app cache>/share_plus/` and clears that folder at the next share. |
| Windows | Unchanged: folder picker, "Copy location". No "Open folder" added. |
| Android manifest | Unchanged. The plugin's `ShareFileProvider` is in the merged debug manifest. No `INTERNET` permission. |

## Tests

`test/features/export/export_sheet_test.dart`, group "FR-EXP-02 ADR-042 sharing on Android and iOS" (7 new):

- FR-EXP-02 ZIP is the default format on Android and iOS
- FR-EXP-02 Folder stays the default on Windows
- FR-EXP-02 after a ZIP export Share opens the share sheet with the export file and shows its size
- FR-EXP-02 a share sheet that fails to open says so
- FR-EXP-02 a folder export on Android and iOS steers to ZIP instead of offering Share
- FR-EXP-02 on Windows there is no Share button after an export
- ADR-042 a ZIP is shared as application/zip

The existing sheet tests run with a Windows-like fake sharer (`canShare: false`). The fake export service now names a ZIP output `<name>.zip`, so one existing expectation was updated to match.

## Checks

- `flutter analyze`: no issues.
- `dart format --output=none --set-exit-if-changed lib test`: passes.
- `flutter test`: 812 passed. One earlier full run had `foreground_service_coordinator_test.dart` "stop action stops and saves the recording" fail while an APK build ran at the same time; it passed alone and in a clean full run (timing under load, not related to this change).
- `flutter build apk --debug`: succeeded.
- Windows integration test: not run (per instructions).

## Files

New: `lib/platform/share/export_sharer.dart`, `test/fixtures/fake_export_sharer.dart`, this report.

Changed: `lib/features/export/export_sheet.dart`, `lib/features/export/export_providers.dart`, `test/features/export/export_sheet_test.dart`, `pubspec.yaml`, `pubspec.lock`, `THIRD_PARTY_NOTICES.md`, `windows/flutter/generated_plugin_registrant.cc` and `generated_plugins.cmake` (new plugins registered: `share_plus`, `url_launcher_windows`), `docs/DECISIONS.md` (ADR-042), `docs/ARCHITECTURE.md` (tested versions row, section 8.18).

## Unverified and open

- No share sheet was opened on a device. Android: debug APK builds only. iOS: not built (no Mac); the iPad popover anchor is untested on hardware.
- Android copies a large ZIP into the app cache before the share sheet appears: it needs that much free space again, takes time with no progress, and stays until the next share. Worth a device check with a multi-GB export.
- How each AI app treats a ZIP (some may want the files inside) is untested; limits change often (FR-EXP-09).
- Exports build up in the private folder; a "manage exports" clean-up could come with Settings (P1-25).
- The build guide has no requirement ID for sharing; tests use FR-EXP-02 and ADR-042.
