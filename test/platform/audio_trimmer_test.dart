import 'dart:io';

import 'package:attenlume/data/filesystem/m4a_inspector.dart';
import 'package:attenlume/domain/services/cut_range_math.dart';
import 'package:attenlume/platform/audio_trimmer/audio_trimmer.dart';
import 'package:attenlume/platform/audio_trimmer/m4a_container_trimmer.dart';
import 'package:attenlume/platform/audio_trimmer/simulated_audio_trimmer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  const inspector = M4aInspector();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('audio_trimmer_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<File> createSyntheticM4a({
    required String name,
    int durationMs = 10000,
  }) async {
    final file = File(p.join(tempDir.path, name));
    final bytes = M4aContainerTrimmer.buildM4aContainer(
      channels: 1,
      sampleRateHz: 48000,
      durationMs: durationMs,
      avgBitrateBps: 96000,
      maxBitrateBps: 96000,
      mediaDataBytes: (durationMs * 12).round(),
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  group('FR-REV-06 M4aContainerTrimmer [P0-14, FR-REV-07, NFR-07]', () {
    test(
      'FR-REV-06 trims M4A file to keep-range duration and validates format',
      () async {
        final source = await createSyntheticM4a(
          name: 'source_10s.m4a',
          durationMs: 10000,
        );
        final target = File(p.join(tempDir.path, 'trimmed_6s.m4a'));

        const trimmer = M4aContainerTrimmer();
        final result = await trimmer.trim(
          sourceFile: source,
          targetFile: target,
          keepRanges: const [TimeRange(2000, 8000)], // 6 seconds
        );

        expect(result.durationMs, 6000);
        expect(result.targetFile.path, target.path);
        expect(target.existsSync(), isTrue);
        expect(File('${target.path}.partial').existsSync(), isFalse);

        // Verify trimmed file metadata with M4aInspector
        final info = await inspector.inspect(target);
        expect(info.durationMs, 6000);
        expect(info.codec, 'aac_lc');
        expect(info.channelCount, 1);
        expect(info.sampleRateHz, 48000);
        expect(info.container, 'm4a');
      },
    );

    test('FR-REV-06 non-destructive failure recovery: cleans partial and preserves original', () async {
      final source = await createSyntheticM4a(
        name: 'source_recovery.m4a',
        durationMs: 8000,
      );
      final originalLength = source.lengthSync();
      final target = File(p.join(tempDir.path, 'failed_output.m4a'));
      final partial = File('${target.path}.partial');

      const failingTrimmer = M4aContainerTrimmer(failBeforeRename: true);

      await expectLater(
        () => failingTrimmer.trim(
          sourceFile: source,
          targetFile: target,
          keepRanges: const [TimeRange(1000, 4000)],
        ),
        throwsA(isA<AudioTrimException>()),
      );

      // Verify partial was deleted, target was never created, source untouched
      expect(target.existsSync(), isFalse);
      expect(partial.existsSync(), isFalse);
      expect(source.existsSync(), isTrue);
      expect(source.lengthSync(), originalLength);
    });

    test('FR-REV-07 empty keep ranges throws AudioTrimException', () async {
      final source = await createSyntheticM4a(name: 'source_empty.m4a');
      final target = File(p.join(tempDir.path, 'target.m4a'));
      const trimmer = M4aContainerTrimmer();

      await expectLater(
        () => trimmer.trim(
          sourceFile: source,
          targetFile: target,
          keepRanges: const [],
        ),
        throwsA(isA<AudioTrimException>()),
      );
    });
  });

  group('FR-REV-06 SimulatedAudioTrimmer [P0-14, NFR-07]', () {
    test('FR-REV-06 performs simulated trim and computes hash', () async {
      final source = await createSyntheticM4a(name: 'sim_source.m4a');
      final target = File(p.join(tempDir.path, 'sim_target.m4a'));

      final trimmer = SimulatedAudioTrimmer();
      final result = await trimmer.trim(
        sourceFile: source,
        targetFile: target,
        keepRanges: const [TimeRange(0, 5000)],
      );

      expect(result.durationMs, 5000);
      expect(result.bytes, greaterThan(0));
      expect(result.sha256, hasLength(64));
      expect(target.existsSync(), isTrue);
    });

    test(
      'FR-REV-06 failure removes partial file and preserves source',
      () async {
        final source = await createSyntheticM4a(name: 'sim_fail_src.m4a');
        final target = File(p.join(tempDir.path, 'sim_fail_tgt.m4a'));
        final partial = File('${target.path}.partial');

        final trimmer = SimulatedAudioTrimmer(shouldFail: true);

        await expectLater(
          () => trimmer.trim(
            sourceFile: source,
            targetFile: target,
            keepRanges: const [TimeRange(0, 5000)],
          ),
          throwsA(isA<AudioTrimException>()),
        );

        expect(target.existsSync(), isFalse);
        expect(partial.existsSync(), isFalse);
        expect(source.existsSync(), isTrue);
      },
    );
  });
}
