import 'dart:convert';
import 'dart:io';

import 'package:attenlume/data/filesystem/cuts_manifest.dart';
import 'package:attenlume/domain/models/media.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cuts_manifest_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('FR-REV-07 cuts.json instruction manifest [P0-14, FR-EXP-03]', () {
    test('FR-REV-07 builds cuts manifest from domain entities', () {
      final now = DateTime.utc(2026, 11, 4, 10, 0);
      final cuts = [
        CutRange(
          id: 'c1',
          activityId: 'act-101',
          startOffsetMs: 0,
          endOffsetMs: 5000,
          reason: 'walk_in',
          createdAt: now,
          updatedAt: now,
        ),
        CutRange(
          id: 'c2',
          activityId: 'act-101',
          startOffsetMs: 25000,
          endOffsetMs: 30000,
          reason: 'interruption',
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final manifest = CutsManifest.fromDomain(
        activityId: 'act-101',
        totalDurationMs: 60000,
        cutRanges: cuts,
      );

      expect(manifest.version, '1.0');
      expect(manifest.activityId, 'act-101');
      expect(manifest.totalDurationMs, 60000);
      expect(manifest.trimmedDurationMs, 50000);
      expect(manifest.cuts, hasLength(2));
      expect(manifest.cuts[0].startOffsetMs, 0);
      expect(manifest.cuts[0].endOffsetMs, 5000);
      expect(manifest.cuts[0].reason, 'walk_in');

      // Keep ranges: [5000..25000, 30000..60000]
      expect(manifest.keepRanges, hasLength(2));
      expect(manifest.keepRanges[0].startOffsetMs, 5000);
      expect(manifest.keepRanges[0].endOffsetMs, 25000);
      expect(manifest.keepRanges[1].startOffsetMs, 30000);
      expect(manifest.keepRanges[1].endOffsetMs, 60000);
    });

    test('FR-EXP-03 serialises and deserialises JSON without loss', () {
      const manifest = CutsManifest(
        version: '1.0',
        activityId: 'act-202',
        totalDurationMs: 40000,
        trimmedDurationMs: 30000,
        cuts: [
          CutItem(startOffsetMs: 10000, endOffsetMs: 20000, reason: 'noise'),
        ],
        keepRanges: [
          KeepItem(startOffsetMs: 0, endOffsetMs: 10000),
          KeepItem(startOffsetMs: 20000, endOffsetMs: 40000),
        ],
        segments: [
          SegmentReference(
            sequence: 1,
            fileName: 'segment-001.m4a',
            startOffsetMs: 0,
            durationMs: 40000,
          ),
        ],
      );

      final prettyStr = manifest.toPrettyJson();
      final decodedMap = jsonDecode(prettyStr) as Map<String, dynamic>;

      final roundTrip = CutsManifest.fromJson(
        Map<String, Object?>.from(decodedMap),
      );

      expect(roundTrip.version, manifest.version);
      expect(roundTrip.activityId, manifest.activityId);
      expect(roundTrip.totalDurationMs, manifest.totalDurationMs);
      expect(roundTrip.trimmedDurationMs, manifest.trimmedDurationMs);
      expect(roundTrip.cuts.first.startOffsetMs, 10000);
      expect(roundTrip.cuts.first.reason, 'noise');
      expect(roundTrip.keepRanges.length, 2);
      expect(roundTrip.segments.first.fileName, 'segment-001.m4a');
    });

    test('FR-REV-07 generates external ffmpeg filter expression', () {
      const singleKeep = CutsManifest(
        activityId: 'act-1',
        totalDurationMs: 30000,
        trimmedDurationMs: 25000,
        cuts: [CutItem(startOffsetMs: 0, endOffsetMs: 5000)],
        keepRanges: [KeepItem(startOffsetMs: 5000, endOffsetMs: 30000)],
      );
      expect(
        singleKeep.toFfmpegFilterComplex(),
        '[0:a]atrim=start=5.000:end=30.000,asetpts=PTS-STARTPTS[out]',
      );

      const multiKeep = CutsManifest(
        activityId: 'act-1',
        totalDurationMs: 60000,
        trimmedDurationMs: 40000,
        cuts: [
          CutItem(startOffsetMs: 10000, endOffsetMs: 20000),
          CutItem(startOffsetMs: 40000, endOffsetMs: 50000),
        ],
        keepRanges: [
          KeepItem(startOffsetMs: 0, endOffsetMs: 10000),
          KeepItem(startOffsetMs: 20000, endOffsetMs: 40000),
          KeepItem(startOffsetMs: 50000, endOffsetMs: 60000),
        ],
      );
      final filter = multiKeep.toFfmpegFilterComplex();
      expect(
        filter,
        contains('[0:a]atrim=start=0.000:end=10.000,asetpts=PTS-STARTPTS[a0];'),
      );
      expect(
        filter,
        contains(
          '[0:a]atrim=start=20.000:end=40.000,asetpts=PTS-STARTPTS[a1];',
        ),
      );
      expect(
        filter,
        contains(
          '[0:a]atrim=start=50.000:end=60.000,asetpts=PTS-STARTPTS[a2];',
        ),
      );
      expect(filter, contains('[a0][a1][a2]concat=n=3:v=0:a=1[out]'));
    });

    test('FR-EXP-05 writes cuts.json atomically via partial file', () async {
      const manifest = CutsManifest(
        activityId: 'act-atomic',
        totalDurationMs: 10000,
        trimmedDurationMs: 8000,
        cuts: [CutItem(startOffsetMs: 0, endOffsetMs: 2000)],
        keepRanges: [KeepItem(startOffsetMs: 2000, endOffsetMs: 10000)],
      );

      final targetFile = File(p.join(tempDir.path, 'cuts.json'));
      final written = await manifest.writeToFile(targetFile);

      expect(written.existsSync(), isTrue);
      expect(File('${targetFile.path}.partial').existsSync(), isFalse);
      expect(written.readAsStringSync(), contains('act-atomic'));
    });
  });
}
