import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/activity_title.dart';
import 'package:attenlume/domain/services/recording_profile_rules.dart';
import 'package:attenlume/domain/services/timeline_offset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FR-QUAL-02 profile precedence', () {
    test('FR-QUAL-02 global default is Balanced', () {
      expect(RecordingProfile.globalDefault, RecordingProfile.balanced);
    });

    test('FR-QUAL-02 activity inherits the conference default', () {
      expect(
        effectiveRecordingProfile(conferenceDefault: RecordingProfile.economy),
        RecordingProfile.economy,
      );
    });

    test('FR-QUAL-02 activity override wins', () {
      expect(
        effectiveRecordingProfile(
          conferenceDefault: RecordingProfile.economy,
          activityOverride: RecordingProfile.enhanced,
        ),
        RecordingProfile.enhanced,
      );
    });
  });

  group('FR-ACT-05 default title', () {
    test('FR-ACT-05 formats "{Type} {n}, {HH:mm}"', () {
      expect(
        defaultActivityTitle(
          typeLabel: 'Session',
          ordinal: 3,
          atUtc: DateTime.utc(2026, 1, 20, 14, 5),
          timezone: 'Europe/London',
        ),
        'Session 3, 14:05',
      );
    });

    test('FR-ACT-05 uses conference local time, including summer time', () {
      // 13:05 UTC is 14:05 BST in London and 09:05 EDT in New York.
      final at = DateTime.utc(2026, 6, 1, 13, 5);
      expect(
        defaultActivityTitle(
          typeLabel: 'Keynote',
          ordinal: 1,
          atUtc: at,
          timezone: 'Europe/London',
        ),
        'Keynote 1, 14:05',
      );
      expect(
        defaultActivityTitle(
          typeLabel: 'Keynote',
          ordinal: 1,
          atUtc: at,
          timezone: 'America/New_York',
        ),
        'Keynote 1, 09:05',
      );
    });

    test('FR-ACT-05 pads single-digit hours and minutes', () {
      expect(
        defaultActivityTitle(
          typeLabel: 'Exhibit',
          ordinal: 12,
          atUtc: DateTime.utc(2026, 1, 20, 8, 7),
          timezone: 'UTC',
        ),
        'Exhibit 12, 08:07',
      );
    });

    test('FR-ACT-05 an unknown timezone falls back to UTC', () {
      expect(
        defaultActivityTitle(
          typeLabel: 'Session',
          ordinal: 1,
          atUtc: DateTime.utc(2026, 1, 20, 14, 5),
          timezone: 'Not/AZone',
        ),
        'Session 1, 14:05',
      );
    });
  });

  group('P0-09 offset rule', () {
    final first = DateTime.utc(2026, 11, 4, 9, 30);

    test('P0-09 offset is null before any segment exists', () {
      expect(
        timelineOffsetMs(eventUtc: first, firstSegmentStartUtc: null),
        isNull,
      );
    });

    test('P0-09 offset counts gaps as real time', () {
      // 25 minutes of wall clock, whatever was recorded in between.
      expect(
        timelineOffsetMs(
          eventUtc: first.add(const Duration(minutes: 25)),
          firstSegmentStartUtc: first,
        ),
        25 * 60 * 1000,
      );
    });

    test('P0-09 offset is negative before the first segment', () {
      expect(
        timelineOffsetMs(
          eventUtc: first.subtract(const Duration(seconds: 5)),
          firstSegmentStartUtc: first,
        ),
        -5000,
      );
    });

    test('P0-09 offset ignores the DateTime zone of its inputs', () {
      final local = first.add(const Duration(minutes: 1)).toLocal();
      expect(
        timelineOffsetMs(eventUtc: local, firstSegmentStartUtc: first),
        60000,
      );
    });
  });

  group('P0-09 stored enum keys', () {
    test('P0-09 keys are unique snake_case per enum', () {
      final all = <List<KeyedEnum>>[
        RecordingProfile.values,
        RoleType.values,
        RequestedOutput.values,
        ActivityStatus.values,
        RecordingPermissionStatus.values,
        SegmentState.values,
        SegmentEndReason.values,
        InterruptionReason.values,
        PhotoSource.values,
        BookmarkSource.values,
        ExportDestination.values,
        ExportFormat.values,
        ExportAudioMode.values,
        ExportJobState.values,
        VerificationLevel.values,
      ];
      for (final values in all) {
        final keys = values.map((v) => v.key).toList();
        expect(keys.toSet(), hasLength(keys.length));
        for (final k in keys) {
          expect(k, matches(RegExp(r'^[a-z][a-z0-9_]*$')));
        }
      }
    });

    test('P0-09 unknown key fails loudly', () {
      expect(
        () => enumFromKey(SegmentState.values, 'fine'),
        throwsArgumentError,
      );
    });

    test('P0-09 9.4 values are spelled as in the build guide', () {
      expect(RecordingPermissionStatus.values.map((v) => v.key), [
        'unknown',
        'permitted',
        'not_permitted',
        'participant_aware',
      ]);
      expect(SegmentEndReason.values.map((v) => v.key), [
        'user_stop',
        'pause',
        'roll',
        'interruption',
        'quality_change',
        'route_change',
        'storage_low',
        'error',
      ]);
    });
  });
}
