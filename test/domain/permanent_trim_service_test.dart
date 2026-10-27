import 'dart:io';
import 'dart:typed_data';

import 'package:attenlume/data/filesystem/media_paths.dart';
import 'package:attenlume/data/filesystem/mp4_sample_table.dart';
import 'package:attenlume/data/filesystem/waveform_summary.dart';
import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/models/media.dart';
import 'package:attenlume/domain/services/cut_range_math.dart';
import 'package:attenlume/domain/services/permanent_trim_service.dart';
import 'package:attenlume/platform/audio_trimmer/audio_trimmer.dart';
import 'package:attenlume/platform/audio_trimmer/mp4_sample_trimmer.dart';
import 'package:attenlume/platform/storage/free_space_probe.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fake_free_space_probe.dart';
import '../fixtures/fixtures.dart';
import '../fixtures/mp4_fixture.dart';

/// Fails on the [failOn]th call, after writing the earlier files.
class _FailingTrimmer implements AudioTrimmer {
  _FailingTrimmer(this.failOn);

  final int failOn;
  var calls = 0;

  @override
  Future<TrimResult> trim({
    required File sourceFile,
    required File targetFile,
    required List<TimeRange> keepRanges,
  }) {
    if (++calls == failOn) {
      throw const AudioTrimException('disk error');
    }
    return const Mp4SampleTrimmer().trim(
      sourceFile: sourceFile,
      targetFile: targetFile,
      keepRanges: keepRanges,
    );
  }
}

void main() {
  late TestData t;
  late Directory root;
  late Activity activity;
  late RecordingSegment seg1;
  late RecordingSegment seg2;
  final start = DateTime.utc(2026, 11, 4, 9, 30);

  Future<RecordingSegment> addSegment(
    int sequence,
    int startMs,
    int samples,
  ) async {
    final path = MediaPaths.segment(
      activity.conferenceId,
      activity.id,
      sequence,
    );
    final file = MediaPaths.resolve(root, path);
    await file.parent.create(recursive: true);
    await writeMp4Fixture(file, samples: samples);
    final at = start.add(Duration(milliseconds: startMs));
    final s = await t.media.startSegment(
      activityId: activity.id,
      filePath: path,
      requestedProfile: RecordingProfile.balanced,
      codec: 'aac_lc',
      container: 'm4a',
      channelCount: 1,
      sampleRateHz: 48000,
      requestedBitrateBps: 64000,
      startUtc: at,
    );
    final ms = (samples * 1024 * 1000 / 48000).round();
    return t.media.finaliseSegment(
      s.id,
      endUtc: at.add(Duration(milliseconds: ms)),
      endReason: SegmentEndReason.userStop,
      durationMs: ms,
      bytes: file.lengthSync(),
      sha256: 'f' * 64,
    );
  }

  PermanentTrimService service({
    AudioTrimmer trimmer = const Mp4SampleTrimmer(),
    FreeSpaceProbe freeSpace = const UnknownFreeSpaceProbe(),
  }) => PermanentTrimService(
    activities: t.activities,
    media: t.media,
    cuts: t.cuts,
    trimmer: trimmer,
    mediaRoot: () async => root,
    freeSpace: freeSpace,
    newId: t.ids.call,
  );

  Future<List<int>> sampleIndexes(String relativePath) async {
    final file = MediaPaths.resolve(root, relativePath);
    final table = await Mp4SampleTable.read(file);
    final raf = await file.open();
    try {
      return [
        for (var i = 0; i < table.sampleCount; i++)
          fixtureSampleIndex(
            await (raf..setPositionSync(table.sampleOffsets[i])).read(8),
          ),
      ];
    } finally {
      await raf.close();
    }
  }

  setUp(() async {
    t = TestData(start: start);
    root = await Directory.systemTemp.createTemp('permanent_trim_');
    final conference = await t.conference();
    activity = await t.activity(conference.id, title: 'Keynote');
    // 0 to 10.03 s, a 2 s gap, then 12 to 18.0 s.
    seg1 = await addSegment(1, 0, 470);
    seg2 = await addSegment(2, 12000, 282);
    await t.media.addPhoto(
      activityId: activity.id,
      filePath: 'photos/p.jpg',
      takenUtc: start.add(const Duration(seconds: 7)),
      source: PhotoSource.inApp,
      bytes: 1000,
    );
    await t.media.addBookmark(
      activityId: activity.id,
      source: BookmarkSource.ui,
      atUtc: start.add(const Duration(seconds: 14)),
      label: 'Key slide',
    );
  });

  tearDown(() async {
    await t.close();
    await root.delete(recursive: true);
  });

  group('FR-REV-06 permanent trim plan [P1-19]', () {
    test('FR-REV-06 plans pieces per segment from merged cuts', () async {
      await t.cuts.add(activity.id, startOffsetMs: 0, endOffsetMs: 2000);
      await t.cuts.add(activity.id, startOffsetMs: 4000, endOffsetMs: 5000);
      await t.cuts.add(activity.id, startOffsetMs: 4500, endOffsetMs: 6000);
      final plan = await service().plan(activity.id);
      expect(plan.hasWork, isTrue);
      expect(plan.changes.single.segment.id, seg1.id);
      expect(plan.changes.single.keep, const [
        TimeRange(2000, 4000),
        TimeRange(6000, 10027),
      ]);
      expect(plan.filesToWrite, 2);
      expect(plan.removedMs, 4000);
    });

    test('FR-REV-06 a cut over a whole segment drops it', () async {
      await t.cuts.add(activity.id, startOffsetMs: 11000, endOffsetMs: 19000);
      final plan = await service().plan(activity.id);
      expect(plan.changes.single.segment.id, seg2.id);
      expect(plan.changes.single.dropped, isTrue);
      expect(plan.filesToWrite, 0);
    });

    test('FR-REV-06 cuts only over the gap need no trim', () async {
      await t.cuts.add(activity.id, startOffsetMs: 10050, endOffsetMs: 11900);
      expect((await service().plan(activity.id)).hasWork, isFalse);
    });
  });

  group('FR-REV-06 apply trims permanently [P1-19]', () {
    test('FR-REV-06 writes new files, keeps the timeline in place and '
        'moves the original aside', () async {
      await t.cuts.add(activity.id, startOffsetMs: 0, endOffsetMs: 2000);
      await t.cuts.add(activity.id, startOffsetMs: 4000, endOffsetMs: 6000);
      final original = MediaPaths.resolve(root, seg1.filePath);
      final originalBytes = await original.readAsBytes();

      final result = await service().apply(activity.id);

      expect(result.filesWritten, 2);
      final rows = await t.media.segmentsFor(activity.id);
      expect(rows.map((s) => s.sequence), [1, 2, 3]);
      expect(rows[0].filePath, endsWith('audio/segment-001-trim-1.m4a'));
      expect(rows[1].filePath, endsWith('audio/segment-001-trim-2.m4a'));
      expect(rows[2].id, seg2.id);
      expect(rows[0].startUtc, start.add(const Duration(seconds: 2)));
      expect(rows[1].startUtc, start.add(const Duration(seconds: 6)));
      expect(rows[0].durationMs, closeTo(2000, 25));
      expect(rows[0].sha256, hasLength(64));
      expect(rows[0].state, SegmentState.finalised);

      // The first file holds exactly the audio from 2 s to 4 s.
      final first = (2000 * 48 / 1024).ceil();
      final end = (4000 * 48 / 1024).ceil();
      expect(await sampleIndexes(rows[0].filePath), [
        for (var i = first; i < end; i++) i,
      ]);

      // The timeline now starts 2 s later; stored offsets follow.
      final photo = (await t.media.photosFor(activity.id)).single;
      expect(photo.offsetMs, 5000);
      final bookmark = (await t.media.bookmarksFor(activity.id)).single;
      expect(bookmark.offsetMs, 12000);
      final cuts = await t.cuts.activeFor(activity.id);
      expect(cuts.map((c) => (c.startOffsetMs, c.endOffsetMs)), [(2000, 4000)]);

      // The original is moved, byte for byte, not deleted (NFR-07).
      expect(original.existsSync(), isFalse);
      final kept = result.originals.single;
      expect(MediaPaths.isKeptOriginal(kept.relativePath), isTrue);
      expect(
        await MediaPaths.resolve(root, kept.relativePath).readAsBytes(),
        originalBytes,
      );
      expect(result.sharedOriginals, 0);

      // Nothing more to apply.
      expect((await service().plan(activity.id)).hasWork, isFalse);
    });

    test('FR-REV-06 originals are removed only when asked', () async {
      await t.cuts.add(activity.id, startOffsetMs: 11000, endOffsetMs: 19000);
      final svc = service();
      final result = await svc.apply(activity.id);
      expect(result.filesWritten, 0);
      expect(await t.media.segmentsFor(activity.id), hasLength(1));
      final kept = result.originals.single;
      final file = MediaPaths.resolve(root, kept.relativePath);
      expect(file.existsSync(), isTrue);
      expect(kept.bytes, file.lengthSync());

      expect(await svc.removeOriginals(result.originals), 1);
      expect(file.existsSync(), isFalse);
      // A file a row names is never removed.
      final live = KeptOriginal(relativePath: seg1.filePath, bytes: 1);
      expect(await svc.removeOriginals([live]), 0);
      expect(MediaPaths.resolve(root, seg1.filePath).existsSync(), isTrue);
    });

    test('FR-REV-06 a file another activity still names stays put', () async {
      final other = await t.activity(activity.conferenceId, title: 'Part 2');
      await t.media
          .startSegment(
            activityId: other.id,
            filePath: seg1.filePath,
            requestedProfile: RecordingProfile.balanced,
            codec: 'aac_lc',
            container: 'm4a',
            channelCount: 1,
            sampleRateHz: 48000,
            requestedBitrateBps: 64000,
            startUtc: start,
          )
          .then(
            (s) => t.media.finaliseSegment(
              s.id,
              endUtc: start.add(const Duration(seconds: 10)),
              endReason: SegmentEndReason.userStop,
              durationMs: 10000,
            ),
          );
      await t.cuts.add(activity.id, startOffsetMs: 5000, endOffsetMs: 10100);

      final result = await service().apply(activity.id);
      expect(result.originals, isEmpty);
      expect(result.sharedOriginals, 1);
      expect(MediaPaths.resolve(root, seg1.filePath).existsSync(), isTrue);
    });

    test(
      'FR-REV-06 a failure part way leaves files and rows unchanged',
      () async {
        await t.cuts.add(activity.id, startOffsetMs: 4000, endOffsetMs: 6000);
        final before = await t.media.segmentsFor(activity.id);
        await expectLater(
          service(trimmer: _FailingTrimmer(2)).apply(activity.id),
          throwsA(
            isA<PermanentTrimException>().having(
              (e) => e.message,
              'message',
              contains('nothing was changed'),
            ),
          ),
        );
        final after = await t.media.segmentsFor(activity.id);
        expect(after.map((s) => (s.id, s.filePath)), [
          for (final s in before) (s.id, s.filePath),
        ]);
        final audio = MediaPaths.resolve(root, seg1.filePath).parent;
        expect(
          audio.listSync().map((f) => f.uri.pathSegments.last).toList()..sort(),
          ['segment-001.m4a', 'segment-002.m4a'],
        );
        expect((await t.photosOffsets(activity.id)), [7000]);
      },
    );

    test('FR-REV-06 refuses while recording, with all audio cut, or with '
        'too little space', () async {
      await t.cuts.add(activity.id, startOffsetMs: 0, endOffsetMs: 20000);
      await expectLater(
        service().apply(activity.id),
        throwsA(isA<PermanentTrimException>()),
      );
      await t.cuts.remove((await t.cuts.activeFor(activity.id)).single.id);

      await t.cuts.add(activity.id, startOffsetMs: 0, endOffsetMs: 2000);
      await expectLater(
        service(freeSpace: FakeFreeSpaceProbe(50 * 1024 * 1024))
            .apply(activity.id),
        throwsA(isA<PermanentTrimException>()),
      );

      await t.media.startSegment(
        activityId: activity.id,
        filePath: 'x.partial.m4a',
        requestedProfile: RecordingProfile.balanced,
        codec: 'aac_lc',
        container: 'm4a',
        channelCount: 1,
        sampleRateHz: 48000,
        requestedBitrateBps: 64000,
        startUtc: start.add(const Duration(minutes: 1)),
      );
      await expectLater(
        service().apply(activity.id),
        throwsA(isA<PermanentTrimException>()),
      );
      expect(MediaPaths.resolve(root, seg1.filePath).existsSync(), isTrue);
    });

    test('FR-REV-06 waveform summaries are sliced to the new files', () async {
      final wave = MediaPaths.resolve(
        root,
        MediaPaths.waveform(activity.conferenceId, activity.id, seg1.id),
      );
      await wave.parent.create(recursive: true);
      await wave.writeAsBytes([
        ...WaveformSummary.header(200),
        for (var i = 0; i < 50; i++) i,
      ]);
      await t.cuts.add(activity.id, startOffsetMs: 0, endOffsetMs: 2000);

      await service().apply(activity.id);

      final row = (await t.media.segmentsFor(activity.id)).first;
      final slice = await const WaveformSummaryReader().read(
        MediaPaths.resolve(
          root,
          MediaPaths.waveform(activity.conferenceId, activity.id, row.id),
        ),
      );
      expect(slice!.levels.first, 10);
      expect(slice.levels, hasLength(Uint8List(40).length));
      expect(wave.existsSync(), isFalse);
    });
  });
}

extension on TestData {
  Future<List<int?>> photosOffsets(String activityId) async => [
    for (final p in await media.photosFor(activityId)) p.offsetMs,
  ];
}
