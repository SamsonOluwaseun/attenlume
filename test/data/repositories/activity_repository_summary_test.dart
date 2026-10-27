import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fixtures.dart';

void main() {
  late TestData t;

  setUp(() => t = TestData());
  tearDown(() => t.close());

  group('FR-ACT-01 conference stats', () {
    test(
      'FR-ACT-01 stats aggregates duration, storage bytes and activity count',
      () async {
        final sample = await SampleConference.build(t);

        final stats = await t.conferences.stats(sample.conference.id);
        expect(stats.activityCount, 3);
        // Keynote had 2 segments: 10 min + 7 min = 17 min (1,020,000 ms)
        expect(stats.totalRecordedDuration, const Duration(minutes: 17));
        // Audio bytes (~6.12 MB) + Photo bytes (400 KB) > 0
        expect(stats.totalStorageBytes, greaterThan(6000000));
      },
    );

    test('FR-ACT-01 stats for empty conference returns zeroes', () async {
      final c = await t.conference(name: 'Empty Conf');
      final stats = await t.conferences.stats(c.id);
      expect(stats.activityCount, 0);
      expect(stats.totalRecordedDuration, Duration.zero);
      expect(stats.totalStorageBytes, 0);
    });
  });

  group('FR-ACT-03 activity summaries', () {
    test('FR-ACT-03 listSummariesForConference compiles counts, duration, and status', () async {
      final sample = await SampleConference.build(t);

      final summaries = await t.activities.listSummariesForConference(
        sample.conference.id,
      );
      expect(summaries, hasLength(3));

      // Keynote has 17 min duration, 1 photo, 1 bookmark, balanced profile, saved status
      final keynoteSummary = summaries.firstWhere(
        (s) => s.activity.id == sample.keynote.id,
      );
      expect(keynoteSummary.type.label, 'Keynote');
      expect(keynoteSummary.duration, const Duration(minutes: 17));
      expect(keynoteSummary.photoCount, 1);
      expect(keynoteSummary.bookmarkCount, 1);
      expect(keynoteSummary.effectiveProfile, RecordingProfile.balanced);
      expect(keynoteSummary.statusPillStatus, StatusPillStatus.saved);

      // Reflection is private by default
      final reflectionSummary = summaries.firstWhere(
        (s) => s.activity.id == sample.reflection.id,
      );
      expect(reflectionSummary.activity.isPrivate, isTrue);
      expect(reflectionSummary.statusPillStatus, StatusPillStatus.private);
    });

    test(
      'FR-ACT-03 actively recording activity moves to the top of summaries',
      () async {
        final c = await t.conference();
        t.clock.set(DateTime.utc(2026, 11, 4, 9));

        // Activity 1: earlier, saved
        final act1 = await t.activity(c.id, title: 'Morning Keynote');
        await t.segment(
          act1.id,
          start: DateTime.utc(2026, 11, 4, 9),
          length: const Duration(minutes: 30),
        );

        // Activity 2: later, currently recording (has segment in state writing)
        t.clock.set(DateTime.utc(2026, 11, 4, 10));
        final act2 = await t.activity(c.id, title: 'Panel Debate');
        await t.media.startSegment(
          activityId: act2.id,
          filePath: 'panel.m4a',
          requestedProfile: RecordingProfile.balanced,
          codec: 'aac_lc',
          container: 'm4a',
          channelCount: 1,
          sampleRateHz: 48000,
          requestedBitrateBps: 48000,
        );

        // Activity 3: latest, draft
        t.clock.set(DateTime.utc(2026, 11, 4, 11));
        final act3 = await t.activity(c.id, title: 'Afternoon Workshop');

        final summaries = await t.activities.listSummariesForConference(c.id);
        expect(summaries, hasLength(3));

        // act2 is recording -> MUST be at the top (index 0)
        expect(summaries[0].activity.id, act2.id);
        expect(summaries[0].statusPillStatus, StatusPillStatus.recording);
        expect(summaries[0].hasActiveRecording, isTrue);

        // Remaining activities are in chronological order (act1 then act3)
        expect(summaries[1].activity.id, act1.id);
        expect(summaries[2].activity.id, act3.id);
      },
    );

    test(
      'FR-ACT-03 paused and interrupted states are reflected in status pill',
      () async {
        final c = await t.conference();
        final act = await t.activity(c.id, title: 'Paused Session');
        await t.activities.update(
          act.id,
          const ActivitiesCompanion(status: Value(ActivityStatus.active)),
        );

        // Segment ended with pause
        final seg = await t.media.startSegment(
          activityId: act.id,
          filePath: 'seg1.m4a',
          requestedProfile: RecordingProfile.balanced,
          codec: 'aac_lc',
          container: 'm4a',
          channelCount: 1,
          sampleRateHz: 48000,
          requestedBitrateBps: 48000,
        );
        await t.media.finaliseSegment(
          seg.id,
          endUtc: DateTime.utc(2026, 11, 4, 9, 10),
          endReason: SegmentEndReason.pause,
        );

        var summaries = await t.activities.listSummariesForConference(c.id);
        expect(summaries.single.statusPillStatus, StatusPillStatus.paused);

        // Now start an unended interruption
        await t.media.startInterruption(act.id, InterruptionReason.call);
        summaries = await t.activities.listSummariesForConference(c.id);
        expect(summaries.single.statusPillStatus, StatusPillStatus.interrupted);
      },
    );
  });
}
