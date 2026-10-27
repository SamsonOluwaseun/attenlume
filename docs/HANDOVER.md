# Handover

Date and agent: 27 October 2026, Google Antigravity, unattended run
Branch: main (P1-02 merged from `phase-1/P1-02-conference-home`)
Current task ID: P1-03 (next)
Status: done

## Done in this session

- P1-02: Conference home and activity list [FR-ACT-01 to 03].
  - Reusable presentation components conforming to DESIGN_GUIDE:
    - `StatusPill` (`lib/presentation/components/status_pill.dart`): implements exact status mapping per DESIGN_GUIDE (`recording`, `paused`, `interrupted`, `saved`, `exported`, `verified`, `private`, `draft`). On cream surfaces, `recording` renders a navy pill with a lime dot and cream text, strictly observing the core brand rule: "Never a lime mark on cream." On navy surfaces, uses live lime fill.
    - `AttenlumeButton` (`lib/presentation/components/attenlume_button.dart`): implements primary (brand blue fill, cream 19px semibold text meeting large-text contrast, 52px height), secondary (transparent with 1.5px outline), ghost, and danger variants.
    - `ActivityCard` (`lib/presentation/components/activity_card.dart`): 4-row card anatomy (`surface-raised` background, `radius-md` 16px, padding `space-4` 16px). Row 1 displays type icon/label, optional private lock badge, and StatusPill. Row 2 displays heading title (max 2 lines with ellipsis). Row 3 displays "09:30 · Hall A · 47 min" metadata. Row 4 displays photo/bookmark counts with icons and effective profile pill. Accessible semantic tap target with compound label.
  - Conference home stats card (FR-ACT-01):
    - Displays activity count, total recorded duration (`formatDuration`), and total storage used (`formatStorageBytes`) in Montserrat Bold `stat` typography (24px/28px).
    - Single dominant "Start activity" action (`AttenlumeButton` variant primary, 52px height, 19px semibold cream label on brand blue fill, mic icon).
    - Dominant action opens `StartActivitySheet` allowing selection of any built-in or custom activity type or custom title entry.
  - Quick-start activity buttons (FR-ACT-02):
    - Row of 4 dedicated action buttons for the most used types: Session (`Icons.slideshow_rounded`), Conversation (`Icons.handshake_rounded`), Exhibit (`Icons.store_rounded`), and Reflection (`Icons.lightbulb_rounded`).
    - Tapping creates an activity with default title "{Type} {n}, {HH:mm}" in conference local time (FR-ACT-05, FR-CONF-02), stamps reflections as private (FR-EXP-10), and updates the timeline instantly with confirmation feedback.
  - Chronological activity list and elevation of active recordings (FR-ACT-03):
    - Chronological ordering by actual start, else planned start, else creation time.
    - Actively recording activity (`StatusPillStatus.recording`) automatically moves to index 0 at the top of the timeline list.
    - Empty state displays design guide prompt: "Nothing captured yet. Start your first activity when the session begins."
    - Activity details inspector: tapping an activity card opens `ActivityDetailSheet` showing detailed asset counts, metadata, and privacy notice.
  - Pure Dart formatting utilities (`lib/shared/utilities/date_formatters.dart`):
    - `formatDuration`: UK English formatted duration ("0 min", "< 1 min", "47 min", "1 h 12 min").
    - `formatStorageBytes`: formatted byte representation ("0 B", "512 B", "350.0 KB", "14.2 MB", "1.2 GB").
    - `formatTimeOfDayInTimezone`: local "HH:mm" time from UTC instant in conference timezone.
  - High-performance database queries:
    - `ConferenceRepository.stats` and `watchStats`: aggregates activity count, total duration, and storage used in a single SQLite query (FR-ACT-01).
    - `ActivityRepository.listSummariesForConference` and `watchSummariesForConference`: compiles duration, photo counts, bookmark counts, active segments, and effective profile without N+1 query overhead.
  - 28 new tests added (218 total tests, 0 failed).
  - ADR-010 recorded in `docs/DECISIONS.md`.
  - Both `flutter build windows --release` and `flutter build apk --debug` succeed on `main`.

## Left to do on this task

None. P1-02 is complete.

## Exact next step

Start Phase 1 task P1-03 on branch `phase-1/P1-03-activity-crud`: Activity CRUD, custom types, consent check, contact fields [FR-ACT-04 to 08].
Note: Phase 0 spike tasks requiring real devices (P0-04, P0-05, P0-06/MT-16, P0-07, P0-10, P0-12, P0-13) are documented and blocked pending physical device sessions (phone/Mac/mic).

## Files touched

New:
- `lib/features/conferences/activity_detail_sheet.dart`
- `lib/features/conferences/start_activity_sheet.dart`
- `lib/presentation/components/activity_card.dart`
- `lib/presentation/components/attenlume_button.dart`
- `lib/presentation/components/status_pill.dart`
- `test/data/repositories/activity_repository_summary_test.dart`
- `test/features/conferences/conference_home_test.dart`
- `test/presentation/components/activity_card_test.dart`
- `test/presentation/components/attenlume_button_test.dart`
- `test/presentation/components/status_pill_test.dart`
- `test/shared/date_formatters_test.dart`

Changed:
- `lib/data/repositories/activity_repository.dart`
- `lib/data/repositories/conference_repository.dart`
- `lib/domain/models/activity.dart`
- `lib/domain/models/conference.dart`
- `lib/features/conferences/conference_home_screen.dart`
- `lib/shared/utilities/date_formatters.dart`
- `docs/DECISIONS.md` (ADR-010)
- `docs/PROGRESS.md`
- `docs/HANDOVER.md`

## Failing or skipped tests

None failing in `flutter test` (218 passed). Nothing skipped. `integration_test/p0_06_windows_mic_test.dart` still fails on this PC (no microphone in Remote Desktop session, blocked, expected). No device tests run.

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
