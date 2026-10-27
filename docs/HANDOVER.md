# Handover

Date and agent: 27 October 2026, Google Antigravity, unattended run
Branch: main (P1-03 merged from `phase-1/P1-03-activity-crud`)
Current task ID: P1-04 (next)
Status: done

## Done in this session

- P1-03: Activity CRUD, custom types, consent check, contact fields [FR-ACT-04 to 08].
  - Full Activity CRUD Editor (`lib/features/activities/activity_editor_screen.dart`):
    - Dual mode: supports creating new activities and editing existing activities (FR-ACT-04).
    - Blank title formula: defaults to "{Type} {n}, {HH:mm}" in conference timezone (FR-ACT-05). Rename any time.
    - All session metadata fields supported: `title`, `type`, `speaker_names` (comma-separated), `organisation`, `room`, `notes` (Markdown), `tags` (comma-separated), `planned_start` (date & time pickers), `recording_permission_status`, `recording_profile_override`, `is_private` (FR-ACT-04).
    - Save action (`AttenlumeButton` primary) and destructive Delete action (`AttenlumeButton` danger with confirmation dialog).
  - Custom activity types (FR-ACT-06):
    - `CustomTypeDialog` (`lib/features/activities/custom_type_dialog.dart`): user-defined type creation with label validation and 12 Lucide/Material icon options (`tag`, `presentation`, `mic`, `users`, `sparkles`, `coffee`, `school`, `store`, `camera`, `folder`, `book`, `chat`).
    - Integrated "+ Custom type" chip/button in `StartActivitySheet` and `ActivityEditorScreen`.
    - Custom type deletion in editor; types in use are protected from deletion (`ON DELETE RESTRICT` and StateError handling).
  - Conversation awareness consent check (FR-ACT-07, FR-PRI-01, J3):
    - `ConsentCheckDialog` (`lib/features/activities/consent_check_dialog.dart`): prompts "Does the other person know you are recording?" with "Yes" (`RecordingPermissionStatus.participantAware`), "Not recording audio" (`RecordingPermissionStatus.notPermitted`), and Cancel options.
    - Integrated into quick-start Conversation button on `ConferenceHomeScreen`, Conversation/Networking chips in `StartActivitySheet`, and consent banner in `ActivityEditorScreen`.
  - Manual contact details and follow-up (FR-ACT-08):
    - Contact name, contact details (email/phone/social), and follow-up action.
    - Explicit UK English etiquette note: "Manual entry only. No facial recognition or automatic identity extraction."
    - Contact & follow-up card displayed in `ActivityDetailSheet` and `ActivityEditorScreen`.
  - Activity details sheet enhancements (`lib/features/conferences/activity_detail_sheet.dart`):
    - "Edit" button opens `ActivityEditorScreen` and refreshes details on return.
    - "Delete activity" button with confirmation dialog.
    - Displays contact card, speaker names, organisation, room, tags, recording permission status, effective profile.
  - 19 new tests added across 4 test suites (237 total tests, 0 failed).
  - Architecture Decision Record: ADR-011 recorded in `docs/DECISIONS.md`.

## Left to do on this task

None. P1-03 is complete.

## Exact next step

Start Phase 1 task P1-04 on branch `phase-1/P1-04-recording-service`: RecordingService with state machine and mutex [FR-REC-01, 02, 09].
Note: Phase 0 spike tasks requiring real devices (P0-04, P0-05, P0-06/MT-16, P0-07, P0-10, P0-12, P0-13) are documented and blocked pending physical device sessions (phone/Mac/mic).

## Files touched

New:
- `lib/features/activities/activity_editor_screen.dart`
- `lib/features/activities/consent_check_dialog.dart`
- `lib/features/activities/custom_type_dialog.dart`
- `test/features/activities/activity_detail_sheet_test.dart`
- `test/features/activities/activity_editor_test.dart`
- `test/features/activities/consent_check_test.dart`
- `test/features/activities/custom_type_test.dart`

Changed:
- `lib/data/repositories/activity_repository.dart`
- `lib/features/conferences/activity_detail_sheet.dart`
- `lib/features/conferences/conference_home_screen.dart`
- `lib/features/conferences/start_activity_sheet.dart`
- `lib/presentation/components/activity_card.dart`
- `docs/DECISIONS.md` (ADR-011)
- `docs/PROGRESS.md`
- `docs/HANDOVER.md`

## Failing or skipped tests

None failing in `flutter test` (237 passed). Nothing skipped. `integration_test/p0_06_windows_mic_test.dart` still fails on this PC (no microphone in Remote Desktop session, blocked, expected). No device tests run.

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
