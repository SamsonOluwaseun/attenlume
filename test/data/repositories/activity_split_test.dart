import 'dart:io';

import 'package:attenlume/data/filesystem/media_paths.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/activity_splitter.dart';
import 'package:attenlume/domain/services/cut_range_math.dart';
import 'package:attenlume/domain/services/review_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fixtures.dart';

const _min = 60000;

void main() {
  late TestData t;
  late SampleConference sample;
  final start = SampleConference.keynoteStart;

  setUp(() async {
    t = TestData();
    // Keynote: 0:00 to 10:00, call 10:00 to 13:00, 13:00 to 20:00; photo at
    // 14:00, bookmark at 15:00, cut 0:00 to 0:30.
    sample = await SampleConference.build(t);
  });

  tearDown(() => t.close());

  Future<ReviewTimeline> timelineOf(String id) async => ReviewTimeline.build(
    segments: await t.media.segmentsFor(id),
    interruptions: await t.media.interruptionsFor(id),
    photos: await t.media.photosFor(id),
    bookmarks: await t.media.bookmarksFor(id),
  );

  group('FR-REV-05 split activity at the playhead [P1-18]', () {
    test('FR-REV-05 a split in a gap moves later segments, photos and '
        'bookmarks by offset', () async {
      final id = sample.keynote.id;
      final result = await t.activities.split(id, splitOffsetMs: 11 * _min);

      expect(result.part2.title, 'Data Mesh in Practice (Part 2)');
      expect(result.part2.conferenceId, sample.conference.id);
      expect(result.part2.typeId, sample.keynote.typeId);
      expect(result.part2.status, ActivityStatus.completed);
      expect(result.part1.actualEnd, start.add(const Duration(minutes: 11)));
      expect(result.part2.actualStart, start.add(const Duration(minutes: 11)));

      final first = await t.media.segmentsFor(id);
      final second = await t.media.segmentsFor(result.part2.id);
      expect(first.map((s) => s.sequence), [1]);
      expect(second.map((s) => s.sequence), [1]);
      expect(second.single.durationMs, 7 * _min);

      // The new timeline starts at its first segment (13:00 before).
      final bookmarks = await t.media.bookmarksFor(result.part2.id);
      expect(bookmarks.single.label, 'Key slide');
      expect(bookmarks.single.offsetMs, 2 * _min);
      final photos = await t.media.photosFor(result.part2.id);
      expect(photos.single.offsetMs, 1 * _min);
      expect(await t.media.photosFor(id), isEmpty);
      expect(await t.media.bookmarksFor(id), isEmpty);

      // The call started at 10:00, before the split, so it stays.
      expect(await t.media.interruptionsFor(id), hasLength(1));
      expect(await t.media.interruptionsFor(result.part2.id), isEmpty);

      // The intro cut stays with the first part; no split cuts are needed.
      expect(await t.cuts.activeFor(id), hasLength(1));
      expect(await t.cuts.activeFor(result.part2.id), isEmpty);

      final part2 = await timelineOf(result.part2.id);
      expect(part2.audioDurationMs, 7 * _min);
      expect(
        part2.markers.map((m) => (m.kind, m.offsetMs)),
        containsAll([
          (TimelineMarkerKind.photo, 1 * _min),
          (TimelineMarkerKind.bookmark, 2 * _min),
        ]),
      );
    });

    test('FR-REV-05 a split inside a segment shares the file and hides '
        'each side with a cut, writing no audio', () async {
      final id = sample.keynote.id;
      final original = (await t.media.segmentsFor(id)).first;
      final result = await t.activities.split(
        id,
        splitOffsetMs: 5 * _min,
        part2Title: 'Panel: data quality',
      );
      expect(result.part2.title, 'Panel: data quality');

      final first = await t.media.segmentsFor(id);
      final second = await t.media.segmentsFor(result.part2.id);
      expect(first.single.id, original.id);
      expect(second, hasLength(2));
      expect(second[0].filePath, original.filePath);
      expect(second[0].id, isNot(original.id));
      expect(second[0].startUtc, original.startUtc);
      expect(second[1].sequence, 2);
      expect(result.segmentMoves, {
        original.id: second[0].id,
        second[1].id: second[1].id,
      });

      final cuts1 = await t.cuts.activeFor(id);
      expect(cuts1.map((c) => (c.startOffsetMs, c.endOffsetMs)), [
        (0, 30000),
        (5 * _min, 10 * _min),
      ]);
      final cuts2 = await t.cuts.activeFor(result.part2.id);
      expect(cuts2.single.startOffsetMs, 0);
      expect(cuts2.single.endOffsetMs, 5 * _min);
      expect(cuts2.single.reason, contains('Data Mesh in Practice'));

      // Offsets keep counting from the shared segment's start.
      expect(
        (await t.media.bookmarksFor(result.part2.id)).single.offsetMs,
        15 * _min,
      );
      expect(await t.media.interruptionsFor(result.part2.id), hasLength(1));

      final part1 = await timelineOf(id);
      final part2 = await timelineOf(result.part2.id);
      expect(
        part1.keptAudioMs(CutRangeMath.mergeOverlappingCutRanges(cuts1)),
        4 * _min + 30000,
      );
      expect(
        part2.keptAudioMs(CutRangeMath.mergeOverlappingCutRanges(cuts2)),
        12 * _min,
      );
    });

    test(
      'FR-REV-05 a cut across the split is divided between the parts',
      () async {
        final id = sample.keynote.id;
        await t.cuts.add(id, startOffsetMs: 9 * _min, endOffsetMs: 14 * _min);
        final result = await t.activities.split(id, splitOffsetMs: 11 * _min);

        final cuts1 = await t.cuts.activeFor(id);
        expect(cuts1.map((c) => (c.startOffsetMs, c.endOffsetMs)), [
          (0, 30000),
          (9 * _min, 11 * _min),
        ]);
        // 11:00 to 14:00 becomes -2:00 to 1:00 in the new timeline.
        final cuts2 = await t.cuts.activeFor(result.part2.id);
        expect(cuts2.map((c) => (c.startOffsetMs, c.endOffsetMs)), [
          (0, 1 * _min),
        ]);
      },
    );

    test('FR-REV-05 refuses a split at the start, at the end or while '
        'recording, changing nothing', () async {
      final id = sample.keynote.id;
      final before = await t.activities.listForConference(sample.conference.id);
      await expectLater(
        t.activities.split(id, splitOffsetMs: 0),
        throwsArgumentError,
      );
      await expectLater(
        t.activities.split(id, splitOffsetMs: 20 * _min),
        throwsArgumentError,
      );
      await t.media.startSegment(
        activityId: id,
        filePath: 'writing.m4a.partial',
        requestedProfile: RecordingProfile.balanced,
        codec: 'aac_lc',
        container: 'm4a',
        channelCount: 1,
        sampleRateHz: 48000,
        requestedBitrateBps: 64000,
        startUtc: start.add(const Duration(minutes: 21)),
      );
      await expectLater(
        t.activities.split(id, splitOffsetMs: 5 * _min),
        throwsStateError,
      );
      final after = await t.activities.listForConference(sample.conference.id);
      expect(after, hasLength(before.length));
      expect(await t.media.segmentsFor(id), hasLength(3));
      expect(await t.cuts.activeFor(id), hasLength(1));
    });

    test('FR-REV-05 waveform summaries follow the segments; audio files '
        'stay where they are', () async {
      final root = Directory.systemTemp.createTempSync('split_wave_');
      addTearDown(() => root.deleteSync(recursive: true));
      final id = sample.keynote.id;
      final segments = await t.media.segmentsFor(id);
      File wave(String activityId, String segmentId) => MediaPaths.resolve(
        root,
        MediaPaths.waveform(sample.conference.id, activityId, segmentId),
      );
      for (final s in segments) {
        wave(id, s.id)
          ..createSync(recursive: true)
          ..writeAsStringSync(s.id);
      }

      final splitter = ActivitySplitter(
        activities: t.activities,
        mediaRoot: () async => root,
      );
      final result = await splitter.split(id, splitOffsetMs: 5 * _min);
      final shared = result.segmentMoves[segments[0].id]!;

      expect(wave(id, segments[0].id).existsSync(), isTrue);
      expect(wave(result.part2.id, shared).readAsStringSync(), segments[0].id);
      expect(wave(id, segments[1].id).existsSync(), isFalse);
      expect(wave(result.part2.id, segments[1].id).existsSync(), isTrue);
    });
  });
}
