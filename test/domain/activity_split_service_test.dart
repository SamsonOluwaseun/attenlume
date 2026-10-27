import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/models/media.dart';
import 'package:attenlume/domain/services/activity_split_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 4, 10, 0);

  Activity makeActivity({
    String id = 'act-original',
    String title = 'Morning Sessions',
  }) => Activity(
    id: id,
    conferenceId: 'conf-1',
    typeId: 'type-keynote',
    title: title,
    speakerNames: const ['Dr Alice'],
    tags: const ['keynote'],
    status: ActivityStatus.completed,
    recordingPermissionStatus: RecordingPermissionStatus.permitted,
    isPrivate: false,
    actualStart: now,
    actualEnd: now.add(const Duration(hours: 1)),
    createdAt: now,
    updatedAt: now,
  );

  RecordingSegment makeSegment({
    required String id,
    required int sequence,
    required DateTime start,
    required Duration duration,
  }) => RecordingSegment(
    id: id,
    activityId: 'act-original',
    sequence: sequence,
    filePath: 'audio/seg-$sequence.m4a',
    state: SegmentState.finalised,
    requestedProfile: RecordingProfile.balanced,
    codec: 'aac_lc',
    container: 'm4a',
    channelCount: 1,
    sampleRateHz: 48000,
    requestedBitrateBps: 96000,
    startUtc: start,
    endUtc: start.add(duration),
    durationMs: duration.inMilliseconds,
    bytes: duration.inSeconds * 12000,
    createdAt: start,
    updatedAt: start.add(duration),
  );

  Bookmark makeBookmark({
    required String id,
    required DateTime atUtc,
    int? offsetMs,
    String? label,
  }) => Bookmark(
    id: id,
    activityId: 'act-original',
    atUtc: atUtc,
    offsetMs: offsetMs,
    label: label,
    source: BookmarkSource.ui,
    createdAt: atUtc,
    updatedAt: atUtc,
  );

  Photo makePhoto({
    required String id,
    required DateTime takenUtc,
    int? offsetMs,
  }) => Photo(
    id: id,
    activityId: 'act-original',
    filePath: 'photos/$id.jpg',
    takenUtc: takenUtc,
    offsetMs: offsetMs,
    source: PhotoSource.inApp,
    originalKept: true,
    createdAt: takenUtc,
    updatedAt: takenUtc,
  );

  CutRange makeCut({
    required String id,
    required int start,
    required int end,
    String? reason,
  }) => CutRange(
    id: id,
    activityId: 'act-original',
    startOffsetMs: start,
    endOffsetMs: end,
    reason: reason,
    createdAt: now,
    updatedAt: now,
  );

  group('FR-REV-05 activity split validation [P0-14]', () {
    test('FR-REV-05 rejects split offset <= 0 or >= totalDuration', () {
      final act = makeActivity();
      expect(
        () => ActivitySplitService.planSplit(
          activity: act,
          splitOffsetMs: 0,
          totalDurationMs: 60000,
          newActivityId: 'act-new',
          segments: [],
          bookmarks: [],
          photos: [],
          cutRanges: [],
        ),
        throwsArgumentError,
      );
      expect(
        () => ActivitySplitService.planSplit(
          activity: act,
          splitOffsetMs: 60000,
          totalDurationMs: 60000,
          newActivityId: 'act-new',
          segments: [],
          bookmarks: [],
          photos: [],
          cutRanges: [],
        ),
        throwsArgumentError,
      );
    });
  });

  group('FR-REV-05 split inside a gap between segments [P0-14]', () {
    test(
      'FR-REV-05 splits at gap without needing audio slicing (Product Spec)',
      () {
        final act = makeActivity();
        final seg1 = makeSegment(
          id: 's1',
          sequence: 1,
          start: now,
          duration: const Duration(minutes: 20),
        );
        // 10 min gap (min 20 to 30)
        final seg2 = makeSegment(
          id: 's2',
          sequence: 2,
          start: now.add(const Duration(minutes: 30)),
          duration: const Duration(minutes: 20),
        );

        final bmk1 = makeBookmark(
          id: 'b1',
          atUtc: now.add(const Duration(minutes: 5)),
          offsetMs: 5 * 60 * 1000,
        );
        final bmk2 = makeBookmark(
          id: 'b2',
          atUtc: now.add(const Duration(minutes: 35)),
          offsetMs: 35 * 60 * 1000,
        );

        final photo1 = makePhoto(
          id: 'p1',
          takenUtc: now.add(const Duration(minutes: 10)),
          offsetMs: 10 * 60 * 1000,
        );
        final photo2 = makePhoto(
          id: 'p2',
          takenUtc: now.add(const Duration(minutes: 40)),
          offsetMs: 40 * 60 * 1000,
        );

        // Split at minute 25 (inside the 10 min gap)
        final plan = ActivitySplitService.planSplit(
          activity: act,
          splitOffsetMs: 25 * 60 * 1000,
          totalDurationMs: 50 * 60 * 1000,
          newActivityId: 'act-part2',
          segments: [seg1, seg2],
          bookmarks: [bmk1, bmk2],
          photos: [photo1, photo2],
          cutRanges: [],
        );

        expect(plan.splitOccurredInGap, isTrue);
        expect(plan.segmentToSplit, isNull);

        // Segments partition cleanly
        expect(plan.activity1Segments, hasLength(1));
        expect(plan.activity1Segments.first.segment.id, 's1');
        expect(plan.activity1Segments.first.targetActivityId, 'act-original');
        expect(plan.activity1Segments.first.newSequence, 1);

        expect(plan.activity2Segments, hasLength(1));
        expect(plan.activity2Segments.first.segment.id, 's2');
        expect(plan.activity2Segments.first.targetActivityId, 'act-part2');
        expect(plan.activity2Segments.first.newSequence, 1); // re-indexed to 1

        // Bookmarks moved by offset
        expect(plan.bookmarks[0].targetActivityId, 'act-original');
        expect(plan.bookmarks[0].newOffsetMs, 5 * 60 * 1000);

        expect(plan.bookmarks[1].targetActivityId, 'act-part2');
        expect(
          plan.bookmarks[1].newOffsetMs,
          (35 - 25) * 60 * 1000,
        ); // shifted by 25 min

        // Photos moved by offset
        expect(plan.photos[0].targetActivityId, 'act-original');
        expect(plan.photos[0].newOffsetMs, 10 * 60 * 1000);

        expect(plan.photos[1].targetActivityId, 'act-part2');
        expect(
          plan.photos[1].newOffsetMs,
          (40 - 25) * 60 * 1000,
        ); // shifted by 25 min
      },
    );
  });

  group('FR-REV-05 split mid-segment and cut ranges partitioning [P0-14]', () {
    test(
      'FR-REV-05 mid-segment split identifies slice point and divides cuts',
      () {
        final act = makeActivity();
        final seg = makeSegment(
          id: 's1',
          sequence: 1,
          start: now,
          duration: const Duration(minutes: 60),
        );

        final cutBefore = makeCut(
          id: 'c1',
          start: 5 * 60 * 1000,
          end: 10 * 60 * 1000,
        );
        final cutSpanning = makeCut(
          id: 'c2',
          start: 25 * 60 * 1000,
          end: 35 * 60 * 1000,
        );
        final cutAfter = makeCut(
          id: 'c3',
          start: 45 * 60 * 1000,
          end: 50 * 60 * 1000,
        );

        // Split at minute 30 (right in the middle of cutSpanning)
        final plan = ActivitySplitService.planSplit(
          activity: act,
          splitOffsetMs: 30 * 60 * 1000,
          totalDurationMs: 60 * 60 * 1000,
          newActivityId: 'act-part2',
          segments: [seg],
          bookmarks: [],
          photos: [],
          cutRanges: [cutBefore, cutSpanning, cutAfter],
        );

        expect(plan.splitOccurredInGap, isFalse);
        expect(plan.segmentToSplit, isNotNull);
        expect(plan.segmentToSplit!.splitOffsetWithinSegmentMs, 30 * 60 * 1000);
        expect(plan.segmentToSplit!.part1DurationMs, 30 * 60 * 1000);
        expect(plan.segmentToSplit!.part2DurationMs, 30 * 60 * 1000);

        // Cut ranges:
        // cutBefore -> in Act 1: 5m..10m
        // cutSpanning -> split into Act 1 (25m..30m) and Act 2 (0m..5m)
        // cutAfter -> in Act 2: (45-30)m..(50-30)m = 15m..20m
        expect(plan.cutRanges, hasLength(4));

        final cBefore = plan.cutRanges[0];
        expect(cBefore.targetActivityId, 'act-original');
        expect(cBefore.startOffsetMs, 5 * 60 * 1000);
        expect(cBefore.endOffsetMs, 10 * 60 * 1000);

        final cSpan1 = plan.cutRanges[1];
        expect(cSpan1.targetActivityId, 'act-original');
        expect(cSpan1.startOffsetMs, 25 * 60 * 1000);
        expect(cSpan1.endOffsetMs, 30 * 60 * 1000);

        final cSpan2 = plan.cutRanges[2];
        expect(cSpan2.targetActivityId, 'act-part2');
        expect(cSpan2.startOffsetMs, 0);
        expect(cSpan2.endOffsetMs, 5 * 60 * 1000);

        final cAfter = plan.cutRanges[3];
        expect(cAfter.targetActivityId, 'act-part2');
        expect(cAfter.startOffsetMs, 15 * 60 * 1000);
        expect(cAfter.endOffsetMs, 20 * 60 * 1000);
      },
    );
  });
}
