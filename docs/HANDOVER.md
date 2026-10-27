# Handover

Date and agent: 27 October 2026, Google Antigravity, unattended run
Branch: main (P1-01 merged from `phase-1/P1-01-conference-wizard`)
Current task ID: P1-02 (next)
Status: done

## Done in this session

- P1-01: Conference wizard and quick start [FR-CONF-01 to 08].
  - Quick start on `WelcomeScreen` (`lib/features/onboarding/welcome_screen.dart`): creates a named conference in under 30 seconds with 1 text field and 1 button interaction (FR-CONF-01, interaction count test passes). Shows recording policy notice, inherits global default profile (Balanced), detects device timezone, stamps policy acknowledgement timestamp, and navigates directly to `ConferenceHomeScreen`.
  - Device timezone detection (`lib/domain/services/device_timezone.dart`): added `flutter_timezone` 5.1.1 (Apache 2.0, audited in P0-01) with 500 ms timeout and graceful offline fallback to `Europe/London` and `Etc/UTC` (FR-CONF-02). Bundled IANA database provides offline list of available timezones.
  - Conference wizard and editor (`lib/features/conferences/conference_wizard_screen.dart`): multi-section form supporting both new conference creation and editing existing conferences (FR-CONF-08):
    - Section 1: Details (name required, venue, start/end dates with date pickers, timezone dropdown, description) [FR-CONF-02].
    - Section 2: Participant role (`RoleType` choice chips: attendee, speaker, exhibitor, student, journalist, custom; free-text profession/organisational role) [FR-CONF-03].
    - Section 3: Goals (3 priority goals with tap-to-populate example chips; dynamic optional goals with add/remove actions) [FR-CONF-04].
    - Section 4: Expected outputs (multi-select filter chips for all 7 `RequestedOutput` values) [FR-CONF-05].
    - Section 5: Default recording profile (`RadioGroup` with Economy 32 kbps, Balanced 48 kbps, Enhanced 64 kbps, showing MB/h estimates) [FR-CONF-07].
    - Section 6: Recording policy notice with required acknowledgement checkbox [FR-CONF-06].
  - Conference home landing screen (`lib/features/conferences/conference_home_screen.dart`): displays conference metadata, role, priority goals, outputs, profile badge, archive status banner, and dominant "Start activity" action [FR-ACT-01].
  - Conference list & archive (`lib/features/conferences/conference_list_screen.dart`): tabbed views for active and archived conferences, cards with dates/venue/profile, and FAB to create new conferences [FR-CONF-08, NFR-02].
  - Deletion confirmation dialog (`lib/features/conferences/conference_delete_dialog.dart`): queries `deletionSummary` and presents itemized counts of activities, segments, audio MB, photos, photo MB, and bookmarks before confirming deletion [FR-CONF-08].
  - Date formatting utilities (`lib/shared/utilities/date_formatters.dart`): UK English date and range formatting in pure Dart.
  - 11 new tests added (190 total tests, 0 failed).
  - ADR-009 recorded in `docs/DECISIONS.md`.
  - Both `flutter build windows --release` and `flutter build apk --debug` succeed on `main`.

## Left to do on this task

None. P1-01 is complete.

## Exact next step

Start Phase 1 task P1-02 on branch `phase-1/P1-02-conference-home`: Conference home and activity list [FR-ACT-01 to 03].
Note: Phase 0 spike tasks requiring real devices (P0-04, P0-05, P0-06/MT-16, P0-07, P0-10, P0-12, P0-13) are documented and blocked pending physical device sessions (phone/Mac/mic).

## Files touched

New:
- `lib/domain/services/device_timezone.dart`
- `lib/features/conferences/conference_delete_dialog.dart`
- `lib/features/conferences/conference_home_screen.dart`
- `lib/features/conferences/conference_list_screen.dart`
- `lib/features/conferences/conference_wizard_screen.dart`
- `lib/shared/utilities/date_formatters.dart`
- `test/domain/device_timezone_test.dart`
- `test/features/conferences/conference_list_test.dart`
- `test/features/conferences/conference_wizard_test.dart`
- `test/features/conferences/quick_start_test.dart`

Changed:
- `lib/data/repositories/conference_repository.dart`
- `lib/data/repositories/repository_providers.dart`
- `lib/domain/models/enums.dart`
- `lib/features/onboarding/welcome_screen.dart`
- `test/app/app_test.dart`
- `pubspec.yaml`
- `pubspec.lock`
- `THIRD_PARTY_NOTICES.md`
- `docs/DECISIONS.md` (ADR-009)
- `docs/PROGRESS.md`
- `docs/HANDOVER.md`

## Failing or skipped tests

None failing in `flutter test` (190 passed). Nothing skipped. `integration_test/p0_06_windows_mic_test.dart` still fails on this PC (no microphone in Remote Desktop session, blocked, expected). No device tests run.

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
dart format --output=none --set-exit-if-changed lib test tool
dart run tool/licence_audit.dart --check
flutter build windows --release
flutter build apk --debug
```
