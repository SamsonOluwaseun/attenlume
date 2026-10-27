import 'dart:io';

import 'package:attenlume/platform/audio_capture/audio_capture_engine.dart';
import 'package:attenlume/spikes/windows_mic_spike.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fixtures/m4a_builder.dart';

/// Writes a synthetic M4A on stop, like an encoder that clamps to 96 kbps.
class _FakeEngine implements AudioCaptureEngine {
  _FakeEngine({this.level = -30, this.failBitrate, this.unfinalisedBitrate});

  final double level;
  final int? failBitrate;
  final int? unfinalisedBitrate;
  final List<String> calls = [];
  CaptureRequest? _request;
  String? _path;

  @override
  Future<List<CaptureInput>> listInputs() async => const [
    CaptureInput(id: 'mic-1', label: 'Microphone Array'),
  ];

  @override
  Future<bool> supportsAacLc() async => true;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start(CaptureRequest request, String path) async {
    calls.add('start ${request.bitrateBps} ${p.basename(path)}');
    if (request.bitrateBps == failBitrate) {
      throw StateError('encoder refused');
    }
    _request = request;
    _path = path;
  }

  @override
  Future<double> levelDbfs() async => level;

  @override
  Future<String?> stop() async {
    calls.add('stop');
    final finalised = _request!.bitrateBps != unfinalisedBitrate;
    await File(_path!)
        .writeAsBytes(buildM4a(includeMoov: finalised, mediaDataBytes: 36000));
    return _path;
  }

  @override
  Future<void> dispose() async => calls.add('dispose');
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('windows_mic_spike_test');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<void> noWait(Duration _) async {}

  group('P0-06 Windows mic spike runner', () {
    test(
      'FR-REC-03 rolls one segment per bitrate by stop then start',
      () async {
        final engine = _FakeEngine();
        final report = await WindowsMicSpike(
          engine: engine,
          workDir: dir,
          wait: noWait,
        ).run(requestedBitratesBps: [32000, 96000]);

        expect(engine.calls, [
          'start 32000 segment-001.m4a',
          'stop',
          'start 96000 segment-002.m4a',
          'stop',
          'dispose',
        ]);
        expect(report.segments, hasLength(2));
        expect(report.segments.first.rollGap, isNull);
        expect(report.segments.last.rollGap, isNotNull);
        expect(report.inputs.single.label, 'Microphone Array');
      },
    );

    test(
      'FR-QUAL-01 reports what the file holds, not what was asked',
      () async {
        final report = await WindowsMicSpike(
          engine: _FakeEngine(),
          workDir: dir,
          wait: noWait,
        ).run(requestedBitratesBps: [32000]);

        final segment = report.segments.single;
        expect(segment.request.bitrateBps, 32000);
        expect(segment.info!.declaredAvgBitrateBps, 96000);
        expect(segment.info!.codec, 'aac_lc');
        expect(segment.maxLevelDbfs, -30);
        expect(segment.flatSignal, isFalse);
        expect(
          report.toMarkdownTable(),
          contains('| 32 | aac_lc | 1 | 48000 |'),
        );
      },
    );

    test(
      'FR-QUAL-05 a refused start is recorded and the run goes on',
      () async {
        final report = await WindowsMicSpike(
          engine: _FakeEngine(failBitrate: 32000),
          workDir: dir,
          wait: noWait,
        ).run(requestedBitratesBps: [32000, 96000]);

        expect(report.segments.first.error, contains('encoder refused'));
        expect(report.segments.first.info, isNull);
        expect(report.segments.last.info, isNotNull);
      },
    );

    test('FR-REC-08 an unfinalised file is an error, not a result', () async {
      final report = await WindowsMicSpike(
        engine: _FakeEngine(unfinalisedBitrate: 48000),
        workDir: dir,
        wait: noWait,
      ).run(requestedBitratesBps: [48000]);

      expect(report.segments.single.info, isNull);
      expect(report.segments.single.error, contains('not finalised'));
    });

    test(
      'P0-06 flat signal is flagged (privacy switch or muted mic)',
      () async {
        final report = await WindowsMicSpike(
          engine: _FakeEngine(level: -160),
          workDir: dir,
          wait: noWait,
        ).run(requestedBitratesBps: [96000]);

        expect(report.segments.single.flatSignal, isTrue);
      },
    );

    test('FR-EXP-06 exports the segments folder and verifies it', () async {
      final report = await WindowsMicSpike(
        engine: _FakeEngine(),
        workDir: dir,
        wait: noWait,
      ).run(requestedBitratesBps: [32000, 48000]);

      expect(report.exportVerified, isTrue);
      expect(report.export!.files.map((f) => f.relativePath), [
        'segment-001.m4a',
        'segment-002.m4a',
      ]);
      final json = report.toJson();
      expect(json['spike'], 'P0-06');
      expect(json['export_verified'], isTrue);
      expect(report.toPrettyJson(), contains('"declared_avg_bitrate_bps"'));
    });
  });
}
