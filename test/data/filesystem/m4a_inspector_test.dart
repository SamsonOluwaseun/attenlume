import 'dart:io';
import 'dart:typed_data';

import 'package:attenlume/data/filesystem/m4a_inspector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../fixtures/m4a_builder.dart';

void main() {
  late Directory dir;
  const inspector = M4aInspector();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('m4a_inspector_test');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<File> write(Uint8List bytes) async {
    final file = File(p.join(dir.path, 'segment-001.m4a'));
    await file.writeAsBytes(bytes);
    return file;
  }

  group('FR-QUAL-06 M4A inspection [P0-06]', () {
    test(
      'FR-QUAL-06 reads AAC-LC mono 48 kHz, duration and bitrates',
      () async {
        final file = await write(buildM4a());
        final info = await inspector.inspect(file);
        expect(info.majorBrand, 'M4A ');
        expect(info.codec, 'aac_lc');
        expect(info.container, 'm4a');
        expect(info.channelCount, 1);
        expect(info.sampleRateHz, 48000);
        expect(info.durationMs, 3000);
        expect(info.declaredAvgBitrateBps, 96000);
        expect(info.declaredMaxBitrateBps, 96000);
        expect(info.mediaDataBytes, 36000);
        expect(info.bytes, file.lengthSync());
        expect(info.payloadBitrateBps, 96000);
        expect(info.observedBitrateBps, greaterThan(96000));
      },
    );

    test('FR-QUAL-06 moov before mdat is read the same', () async {
      final info = await inspector.inspect(
        await write(buildM4a(moovFirst: true)),
      );
      expect(info.codec, 'aac_lc');
      expect(info.durationMs, 3000);
    });

    test('FR-QUAL-06 version 1 mdhd with 64-bit duration', () async {
      final info = await inspector.inspect(
        await write(
          buildM4a(mdhdVersion1: true, timescale: 1000, durationUnits: 600000),
        ),
      );
      expect(info.durationMs, 600000);
    });

    test('FR-QUAL-06 four-byte descriptor lengths are parsed', () async {
      final info = await inspector.inspect(
        await write(buildM4a(longDescriptorLengths: true)),
      );
      expect(info.codec, 'aac_lc');
      expect(info.declaredAvgBitrateBps, 96000);
    });

    test('FR-QUAL-06 HE-AAC and stereo are reported, not relabelled', () async {
      final info = await inspector.inspect(
        await write(
          buildM4a(audioObjectType: 5, channels: 2, sampleRateHz: 44100),
        ),
      );
      expect(info.codec, 'aac_he');
      expect(info.channelCount, 2);
      expect(info.sampleRateHz, 44100);
    });

    test('FR-QUAL-06 audio track is found after a video track', () async {
      final info = await inspector.inspect(
        await write(buildM4a(videoTrackFirst: true)),
      );
      expect(info.codec, 'aac_lc');
      expect(info.durationMs, 3000);
    });
  });

  group('FR-REC-08 damaged files are never reported as good [P0-06]', () {
    test('FR-REC-08 file without moov (not finalised) throws', () async {
      final file = await write(buildM4a(includeMoov: false));
      expect(
        () => inspector.inspect(file),
        throwsA(isA<MediaInspectionException>()),
      );
    });

    test('FR-REC-08 truncated file throws', () async {
      final full = buildM4a();
      final file = await write(
        Uint8List.sublistView(full, 0, full.length - 40),
      );
      expect(
        () => inspector.inspect(file),
        throwsA(isA<MediaInspectionException>()),
      );
    });

    test('FR-REC-08 non-MP4 bytes throw', () async {
      final file = await write(Uint8List.fromList(List.filled(64, 7)));
      expect(
        () => inspector.inspect(file),
        throwsA(isA<MediaInspectionException>()),
      );
    });
  });
}
