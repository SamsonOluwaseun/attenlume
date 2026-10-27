import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/models/media.dart';
import 'package:attenlume/domain/services/cut_range_math.dart';
import 'package:attenlume/domain/services/review_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fixtures.dart';

final _t0 = DateTime.utc(2026, 11, 4, 9, 30);

Duration _min(int m) => Duration(minutes: m);

RecordingSegment _segment(
  int sequence, {
  required Duration at,
  required Duration length,
  SegmentState state = SegmentState.finalised,
  bool storeDuration = true,
}) => RecordingSegment(
  id: 'seg-$sequence',
  activityId: 'act',
  sequence: sequence,
  filePath: 'audio/segment-$sequence.m4a',
  state: state,
  requestedProfile: RecordingProfile.balanced,
  codec: 'aac_lc',
  container: 'm4a',
  channelCount: 1,
  sampleRateHz: 48000,
  requestedBitrateBps: 48000,
  startUtc: _t0.add(at),
  endUtc: _t0.add(at + length),
  durationMs: storeDuration ? length.inMilliseconds : null,
  createdAt: _t0,
  updatedAt: _t0,
);

Bookmark _bookmark(String id, Duration at, {int? offsetMs}) => Bookmark(
  id: id,
  activityId: 'act',
  atUtc: _t0.add(at),
  offsetMs: offsetMs,
  label: 'Key slide',
  source: BookmarkSource.ui,
  createdAt: _t0,
  updatedAt: _t0,
);

void main() {
  group('FR-REV-02 review timeline [P1-17]', () {
    test('FR-REV-02 places segments, gaps, interruptions, photos and '
        'bookmarks at their offsets', () async {
      final t = TestData();
      addTearDown(t.close);
      final sample = await SampleConference.build(t);
      final id = sample.keynote.id;
      final timeline = ReviewTimeline.build(
        segments: await t.media.segmentsFor(id),
        interruptions: await t.media.interruptionsFor(id),
        photos: await t.media.photosFor(id),
        bookmarks: await t.media.bookmarksFor(id),
      );

      expect(timeline.segments.map((s) => (s.startMs, s.endMs)), [
        (0, 600000),
        (780000, 1200000),
      ]);
      expect(timeline.gaps.single.startMs, 600000);
      expect(timeline.gaps.single.endMs, 780000);
      final interruption = timeline
          .markersOf(TimelineMarkerKind.interruption)
          .single;
      expect(interruption.offsetMs, 600000);
      expect(interruption.endOffsetMs, 780000);
      expect(interruption.label, 'call');
      expect(
        timeline.markersOf(TimelineMarkerKind.photo).single.offsetMs,
        840000,
      );
      expect(
        timeline.markersOf(TimelineMarkerKind.bookmark).single.offsetMs,
        900000,
      );
      expect(timeline.startMs, 0);
      expect(timeline.endMs, 1200000);
      expect(timeline.audioDurationMs, 1020000);
      expect(timeline.segments[1].audioStartMs, 600000);
    });

    test('FR-REV-02 a bookmark before Record keeps its negative offset and '
        'widens the timeline', () {
      final timeline = ReviewTimeline.build(
        segments: [_segment(1, at: Duration.zero, length: _min(5))],
        bookmarks: [
          _bookmark('early', const Duration(seconds: -12)),
          _bookmark('stored', _min(2), offsetMs: 120000),
        ],
      );
      expect(timeline.markers.map((m) => m.offsetMs), [-12000, 120000]);
      expect(timeline.startMs, -12000);
      expect(timeline.spanMs, 312000);
    });

    test('FR-REV-02 damaged segments are shown but not played', () {
      final timeline = ReviewTimeline.build(
        segments: [
          _segment(1, at: Duration.zero, length: _min(10)),
          _segment(
            2,
            at: _min(10),
            length: _min(10),
            state: SegmentState.damaged,
          ),
          _segment(
            3,
            at: _min(20),
            length: _min(10),
            state: SegmentState.recovered,
          ),
        ],
      );
      expect(timeline.segments.map((s) => s.playable), [true, false, true]);
      expect(timeline.audioDurationMs, 1200000);
      expect(timeline.segments[2].audioStartMs, 600000);
      // A scrub onto the damaged part moves on to the next good one.
      expect(
        timeline.locate(900000),
        const TimelinePosition(segmentIndex: 2, inSegmentMs: 0),
      );
      expect(timeline.nextPlayable(0), 2);
    });

    test('FR-REV-02 duration falls back to the end time when not stored', () {
      final timeline = ReviewTimeline.build(
        segments: [
          _segment(1, at: Duration.zero, length: _min(3), storeDuration: false),
        ],
      );
      expect(timeline.segments.single.durationMs, 180000);
    });

    test('FR-REV-01 locates offsets in gaps and in audio time', () {
      final timeline = ReviewTimeline.build(
        segments: [
          _segment(1, at: Duration.zero, length: _min(10)),
          _segment(2, at: _min(13), length: _min(7)),
        ],
      );
      expect(
        timeline.locate(300000),
        const TimelinePosition(segmentIndex: 0, inSegmentMs: 300000),
      );
      // In the gap: forward to the next segment start.
      expect(
        timeline.locate(700000),
        const TimelinePosition(segmentIndex: 1, inSegmentMs: 0),
      );
      // After the end: the end of the last segment.
      expect(
        timeline.locate(5000000),
        const TimelinePosition(segmentIndex: 1, inSegmentMs: 420000),
      );
      final p = timeline.locateAudio(610000)!;
      expect(p, const TimelinePosition(segmentIndex: 1, inSegmentMs: 10000));
      expect(timeline.offsetOf(p), 790000);
      expect(timeline.audioOf(p), 610000);
    });

    test('FR-REV-02 an activity with no segments has no audio but keeps its '
        'markers', () {
      final timeline = ReviewTimeline.build(
        segments: const [],
        bookmarks: [_bookmark('b', Duration.zero, offsetMs: 0)],
      );
      expect(timeline.hasAudio, isFalse);
      expect(timeline.locate(0), isNull);
      expect(timeline.markers, hasLength(1));
    });
  });

  group('FR-REV-04 kept audio [P1-18]', () {
    test('FR-REV-04 cuts over gaps only remove recorded audio', () {
      final timeline = ReviewTimeline.build(
        segments: [
          _segment(1, at: Duration.zero, length: _min(10)),
          _segment(2, at: _min(13), length: _min(7)),
        ],
      );
      expect(timeline.audioEndMs, 20 * 60000);
      expect(timeline.keptAudioMs(const []), 17 * 60000);
      // 9:00 to 14:00 covers 1 min of the first part, the gap and 1 min of
      // the second.
      expect(
        timeline.keptAudioMs(const [TimeRange(9 * 60000, 14 * 60000)]),
        15 * 60000,
      );
    });
  });
}
