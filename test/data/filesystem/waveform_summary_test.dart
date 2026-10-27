import 'dart:io';

import 'package:attenlume/data/filesystem/waveform_summary.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/models/media.dart';
import 'package:attenlume/domain/services/review_timeline.dart';
import 'package:attenlume/features/playback_review/waveform_pages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final _t0 = DateTime.utc(2026, 11, 4, 9, 30);

RecordingSegment _segment(String id, int atSec, int lengthSec) =>
    RecordingSegment(
      id: id,
      activityId: 'act',
      sequence: 1,
      filePath: '$id.m4a',
      state: SegmentState.finalised,
      requestedProfile: RecordingProfile.balanced,
      codec: 'aac_lc',
      container: 'm4a',
      channelCount: 1,
      sampleRateHz: 48000,
      requestedBitrateBps: 48000,
      startUtc: _t0.add(Duration(seconds: atSec)),
      durationMs: lengthSec * 1000,
      createdAt: _t0,
      updatedAt: _t0,
    );

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('waveform_test_');
  });

  tearDown(() => dir.delete(recursive: true));

  Future<File> writeSummary(String name, int buckets, {int bucketMs = 200}) {
    final file = File(p.join(dir.path, name));
    final writer = WaveformSummaryWriter(file, bucketMs: bucketMs);
    for (var i = 0; i < buckets; i++) {
      // A ramp, so tests can tell which bytes came back.
      writer.add(-60 + (i % 61).toDouble());
    }
    return writer.close().then((_) => file);
  }

  group('FR-REV-03 waveform summaries [P1-17]', () {
    test('FR-REV-03 maps dBFS to one byte, quiet floor at -60', () {
      expect(WaveformSummary.levelByte(-90), 0);
      expect(WaveformSummary.levelByte(double.nan), 0);
      expect(WaveformSummary.levelByte(-60), 0);
      expect(WaveformSummary.levelByte(-30), 128);
      expect(WaveformSummary.levelByte(0), 255);
      expect(WaveformSummary.levelByte(3), 255);
    });

    test('FR-REV-03 one byte per bucket after an 8-byte header', () async {
      final file = await writeSummary('a.wave', 3000);
      expect(await file.length(), 8 + 3000);
      final slice = await const WaveformSummaryReader().read(file);
      expect(slice!.bucketMs, 200);
      expect(slice.levels, hasLength(3000));
      expect(slice.endMs, 600000);
    });

    test('FR-REV-03 reads only the requested range', () async {
      final file = await writeSummary('b.wave', 3000);
      final slice = await const WaveformSummaryReader().read(
        file,
        fromMs: 60000,
        toMs: 61000,
      );
      expect(slice!.startMs, 60000);
      expect(slice.levels, hasLength(5));
      // Bucket 300 is the ramp at 300 % 61 = 56 steps above -60 dBFS.
      expect(slice.levels.first, WaveformSummary.levelByte(-4));
    });

    test('FR-REV-03 a missing or foreign file gives no summary', () async {
      const reader = WaveformSummaryReader();
      expect(await reader.read(File(p.join(dir.path, 'none.wave'))), isNull);
      final foreign = File(p.join(dir.path, 'x.wave'))
        ..writeAsBytesSync(List.filled(20, 7));
      expect(await reader.read(foreign), isNull);
    });

    test('FR-REV-03 an empty segment still writes a valid header', () async {
      final file = await writeSummary('c.wave', 0);
      final slice = await const WaveformSummaryReader().read(file);
      expect(slice!.levels, isEmpty);
    });
  });

  group('FR-REV-03 waveform pages [P1-17]', () {
    test(
      'FR-REV-03 pages read only their part, across segments and gaps',
      () async {
        // seg-a 0:00 to 3:00, gap, seg-b 3:30 to 5:00 with no summary.
        await writeSummary('seg-a.wave', 900);
        final timeline = ReviewTimeline.build(
          segments: [_segment('seg-a', 0, 180), _segment('seg-b', 210, 90)],
        );
        final pager = WaveformPager(
          timeline: timeline,
          summaryFile: (s) async => File(p.join(dir.path, '${s.id}.wave')),
        );
        expect(pager.pageCount, 3);
        expect(pager.pageOf(130000), 1);

        final first = await pager.load(0);
        expect(first.spans.single.levels, hasLength(600));
        expect(first.missing, isEmpty);

        final second = await pager.load(1);
        expect(second.startMs, 120000);
        expect(second.spans.single.startMs, 120000);
        expect(second.spans.single.levels, hasLength(300));
        expect(second.missing.single, (startMs: 210000, endMs: 240000));

        final third = await pager.load(2);
        expect(third.spans, isEmpty);
        expect(third.missing.single, (startMs: 240000, endMs: 300000));
      },
    );

    test(
      'FR-REV-03 a summary shorter than its audio leaves the end flat',
      () async {
        await writeSummary('seg-a.wave', 100); // 20 s of a 60 s segment.
        final pager = WaveformPager(
          timeline: ReviewTimeline.build(segments: [_segment('seg-a', 0, 60)]),
          summaryFile: (s) async => File(p.join(dir.path, '${s.id}.wave')),
        );
        final page = await pager.load(0);
        expect(page.spans.single.endMs, 20000);
        expect(page.missing.single, (startMs: 20000, endMs: 60000));
      },
    );
  });
}
