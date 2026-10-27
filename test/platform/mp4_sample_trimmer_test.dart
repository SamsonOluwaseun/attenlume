import 'dart:io';
import 'dart:typed_data';

import 'package:attenlume/data/filesystem/m4a_inspector.dart';
import 'package:attenlume/data/filesystem/mp4_sample_table.dart';
import 'package:attenlume/domain/services/cut_range_math.dart';
import 'package:attenlume/platform/audio_trimmer/audio_trimmer.dart';
import 'package:attenlume/platform/audio_trimmer/mp4_sample_trimmer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fixtures/mp4_fixture.dart';

void main() {
  late Directory temp;
  const trimmer = Mp4SampleTrimmer();

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mp4_trimmer_');
  });
  tearDown(() => temp.delete(recursive: true));

  File at(String name) => File(p.join(temp.path, name));

  /// Sample indexes held by [file], read through its own tables.
  Future<List<int>> samplesIn(File file) async {
    final table = await Mp4SampleTable.read(file);
    final raf = await file.open();
    try {
      final indexes = <int>[];
      for (var i = 0; i < table.sampleCount; i++) {
        await raf.setPosition(table.sampleOffsets[i]);
        final bytes = await raf.read(table.sampleSizes[i]);
        final index = fixtureSampleIndex(bytes);
        expect(bytes.skip(4), everyElement(index % 251));
        indexes.add(index);
      }
      return indexes;
    } finally {
      await raf.close();
    }
  }

  // 1024 / 48000 s per sample: sample i starts at i * 21.333 ms.
  int firstSampleAtOrAfter(int ms) => (ms * 48000 / 1000 / 1024).ceil();

  group('FR-REV-07 Mp4SampleTable', () {
    test(
      'FR-REV-07 reads offsets across stsc rows and moov at the end',
      () async {
        final file = await writeMp4Fixture(
          at('a.m4a'),
          samples: 25,
          perChunk: 10,
        );
        final table = await Mp4SampleTable.read(file);
        expect(table.sampleCount, 25);
        expect(table.mediaTimescale, 48000);
        expect(await samplesIn(file), List.generate(25, (i) => i));
      },
    );

    test('FR-REV-07 reads 64-bit chunk offsets', () async {
      final file = await writeMp4Fixture(
        at('a.m4a'),
        samples: 12,
        use64BitOffsets: true,
      );
      expect(await samplesIn(file), List.generate(12, (i) => i));
    });

    test('FR-REV-07 refuses a file that was not finalised', () async {
      final file = await writeMp4Fixture(at('a.m4a'), samples: 30);
      final bytes = await file.readAsBytes();
      // Drop the moov box at the end, as a crash would.
      final cut = at('cut.m4a')..writeAsBytesSync(bytes.sublist(0, 2000));
      expect(
        () => Mp4SampleTable.read(cut),
        throwsA(isA<MediaInspectionException>()),
      );
    });
  });

  group('FR-REV-06 FR-REV-07 Mp4SampleTrimmer', () {
    test(
      'FR-REV-07 copies exactly the samples inside the keep range',
      () async {
        final source = await writeMp4Fixture(at('segment-001.m4a'));
        final before = await source.readAsBytes();
        final result = await trimmer.trim(
          sourceFile: source,
          targetFile: at('segment-001-trimmed.m4a'),
          keepRanges: const [TimeRange(2000, 7000)],
        );

        final first = firstSampleAtOrAfter(2000);
        final end = firstSampleAtOrAfter(7000);
        expect(await samplesIn(result.targetFile), [
          for (var i = first; i < end; i++) i,
        ]);
        expect(result.durationMs, closeTo(5000, 25));
        final info = await const M4aInspector().inspect(result.targetFile);
        expect(info.codec, 'aac_lc');
        expect(info.sampleRateHz, 48000);
        expect(info.channelCount, 1);
        expect(info.durationMs, closeTo(5000, 25));
        // The original is untouched (NFR-07).
        expect(await source.readAsBytes(), before);
        expect(File('${result.targetFile.path}.partial').existsSync(), isFalse);
      },
    );

    test('FR-REV-07 joins several keep ranges in order', () async {
      final source = await writeMp4Fixture(at('s.m4a'));
      final result = await trimmer.trim(
        sourceFile: source,
        targetFile: at('t.m4a'),
        keepRanges: const [TimeRange(6000, 8000), TimeRange(0, 1000)],
      );
      final expected = [
        for (var i = 0; i < firstSampleAtOrAfter(1000); i++) i,
        for (
          var i = firstSampleAtOrAfter(6000);
          i < firstSampleAtOrAfter(8000);
          i++
        )
          i,
      ];
      expect(await samplesIn(result.targetFile), expected);
      expect(result.durationMs, closeTo(3000, 45));
    });

    test('FR-REV-07 writes a fast-start file without the edit list', () async {
      final source = await writeMp4Fixture(at('s.m4a'));
      final result = await trimmer.trim(
        sourceFile: source,
        targetFile: at('t.m4a'),
        keepRanges: const [TimeRange(0, 3000)],
      );
      final bytes = await result.targetFile.readAsBytes();
      final top = [for (final b in mp4Children(bytes, 0, bytes.length)) b.type];
      expect(top, ['ftyp', 'moov', 'mdat']);
      final text = String.fromCharCodes(bytes.sublist(0, 2000));
      expect(text.contains('edts'), isFalse);
      expect(text.contains('udta'), isFalse);
      expect(result.bytes, bytes.length);
      expect(result.sha256, hasLength(64));
    });

    test('FR-REV-07 handles a sample count that fills whole chunks', () async {
      final source = await writeMp4Fixture(at('s.m4a'), samples: 64);
      final result = const Mp4SampleTrimmer(samplesPerChunk: 8).trim(
        sourceFile: source,
        targetFile: at('t.m4a'),
        keepRanges: const [TimeRange(0, 100000)],
      );
      expect(
        await samplesIn((await result).targetFile),
        List.generate(64, (i) => i),
      );
    });

    test('FR-REV-06 refuses to overwrite an existing file', () async {
      final source = await writeMp4Fixture(at('s.m4a'));
      final existing = at('t.m4a')..writeAsStringSync('keep me');
      await expectLater(
        trimmer.trim(
          sourceFile: source,
          targetFile: existing,
          keepRanges: const [TimeRange(0, 1000)],
        ),
        throwsA(isA<AudioTrimException>()),
      );
      expect(existing.readAsStringSync(), 'keep me');
    });

    test('FR-REV-06 a range with no audio fails and leaves no files', () async {
      final source = await writeMp4Fixture(at('s.m4a'), samples: 40);
      await expectLater(
        trimmer.trim(
          sourceFile: source,
          targetFile: at('t.m4a'),
          keepRanges: const [TimeRange(50000, 60000)],
        ),
        throwsA(isA<AudioTrimException>()),
      );
      expect(at('t.m4a').existsSync(), isFalse);
      expect(at('t.m4a.partial').existsSync(), isFalse);
    });

    test('FR-REV-07 a damaged source fails cleanly', () async {
      final source = at('s.m4a')..writeAsBytesSync(Uint8List(64));
      await expectLater(
        trimmer.trim(
          sourceFile: source,
          targetFile: at('t.m4a'),
          keepRanges: const [TimeRange(0, 1000)],
        ),
        throwsA(isA<AudioTrimException>()),
      );
      expect(at('t.m4a.partial').existsSync(), isFalse);
    });
  });
}
