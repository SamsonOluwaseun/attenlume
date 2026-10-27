import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/filesystem/folder_export.dart';
import '../data/filesystem/m4a_inspector.dart';
import '../platform/audio_capture/audio_capture_engine.dart';

/// Spike P0-06: Windows microphone capture, AAC support and export to a
/// folder [P0-06, FR-QUAL-01, FR-QUAL-06, FR-REC-03].
///
/// Records one short segment per requested bitrate, rolling by stop then
/// start, inspects each finished file, then exports the segment folder and
/// verifies the checksums. Spike code: not used by the app.
class WindowsMicSpike {
  WindowsMicSpike({
    required this.engine,
    required this.workDir,
    this.inspector = const M4aInspector(),
    Future<void> Function(Duration)? wait,
    DateTime Function()? clock,
  }) : _wait = wait ?? Future<void>.delayed,
       _clock = clock ?? DateTime.now;

  final AudioCaptureEngine engine;
  final Directory workDir;
  final M4aInspector inspector;
  final Future<void> Function(Duration) _wait;
  final DateTime Function() _clock;

  /// Signals at or below this level count as silence or a blocked mic.
  static const flatSignalDbfs = -90.0;

  static const levelInterval = Duration(milliseconds: 250);

  Future<WindowsMicSpikeReport> run({
    List<int> requestedBitratesBps = const [32000, 48000, 64000, 96000],
    Duration segmentLength = const Duration(seconds: 3),
    int sampleRateHz = 48000,
  }) async {
    final startedAt = _clock().toUtc();
    final permission = await engine.hasPermission();
    final aac = await engine.supportsAacLc();
    final inputs = await engine.listInputs();
    final segmentsDir = Directory(p.join(workDir.path, 'audio'));
    await segmentsDir.create(recursive: true);

    // Record every segment first, so the roll gap is stop to start only.
    final takes = <_Take>[];
    DateTime? lastStop;
    for (final (index, bitrate) in requestedBitratesBps.indexed) {
      final name = 'segment-${(index + 1).toString().padLeft(3, '0')}.m4a';
      final path = p.join(segmentsDir.path, name);
      final request = CaptureRequest(
        bitrateBps: bitrate,
        sampleRateHz: sampleRateHz,
      );
      try {
        await engine.start(request, path);
      } on Object catch (error) {
        takes.add(_Take(request, name, path, startError: '$error'));
        continue;
      }
      final started = _clock();
      final take = _Take(
        request,
        name,
        path,
        rollGap: lastStop == null ? null : started.difference(lastStop),
      );
      var elapsed = Duration.zero;
      while (elapsed < segmentLength) {
        await _wait(levelInterval);
        elapsed += levelInterval;
        take.levels.add(await engine.levelDbfs());
      }
      take.written = await engine.stop();
      lastStop = _clock();
      takes.add(take);
    }
    await engine.dispose();

    final segments = <SpikeSegmentResult>[];
    for (final take in takes) {
      AudioFileInfo? info;
      var error = take.startError;
      if (error == null) {
        try {
          info = await inspector.inspect(File(take.written ?? take.path));
        } on Object catch (e) {
          error = '$e';
        }
      }
      segments.add(
        SpikeSegmentResult(
          request: take.request,
          file: take.name,
          info: info,
          error: error,
          rollGap: take.rollGap,
          maxLevelDbfs: take.levels.isEmpty ? null : take.levels.reduce(_max),
          minLevelDbfs: take.levels.isEmpty ? null : take.levels.reduce(_min),
        ),
      );
    }

    FolderExportResult? export;
    var checksumFailures = const <String>[];
    String? exportError;
    try {
      export = await exportFolder(
        source: segmentsDir,
        destinationParent: Directory(p.join(workDir.path, 'export')),
        folderName: 'p0-06-export',
      );
      checksumFailures = await verifyChecksums(export.folder);
    } on Object catch (e) {
      exportError = '$e';
    }

    return WindowsMicSpikeReport(
      startedAtUtc: startedAt,
      os: Platform.operatingSystemVersion,
      permission: permission,
      aacLcSupported: aac,
      inputs: inputs,
      segments: segments,
      export: export,
      exportError: exportError,
      checksumFailures: checksumFailures,
    );
  }
}

class _Take {
  _Take(this.request, this.name, this.path, {this.rollGap, this.startError});

  final CaptureRequest request;
  final String name;
  final String path;
  final Duration? rollGap;
  final String? startError;
  final List<double> levels = [];
  String? written;
}

double _max(double a, double b) => a > b ? a : b;
double _min(double a, double b) => a < b ? a : b;

class SpikeSegmentResult {
  const SpikeSegmentResult({
    required this.request,
    required this.file,
    this.info,
    this.error,
    this.rollGap,
    this.maxLevelDbfs,
    this.minLevelDbfs,
  });

  final CaptureRequest request;
  final String file;
  final AudioFileInfo? info;
  final String? error;

  /// Time from the previous segment's stop to this one's start.
  final Duration? rollGap;
  final double? maxLevelDbfs;
  final double? minLevelDbfs;

  bool get flatSignal =>
      maxLevelDbfs != null && maxLevelDbfs! <= WindowsMicSpike.flatSignalDbfs;

  Map<String, Object?> toJson() => {
    'file': file,
    'request': request.toJson(),
    'info': info?.toJson(),
    'error': error,
    'roll_gap_ms': rollGap?.inMilliseconds,
    'max_level_dbfs': maxLevelDbfs,
    'min_level_dbfs': minLevelDbfs,
    'flat_signal': flatSignal,
  };
}

class WindowsMicSpikeReport {
  const WindowsMicSpikeReport({
    required this.startedAtUtc,
    required this.os,
    required this.permission,
    required this.aacLcSupported,
    required this.inputs,
    required this.segments,
    required this.export,
    required this.exportError,
    required this.checksumFailures,
  });

  final DateTime startedAtUtc;
  final String os;
  final bool permission;
  final bool aacLcSupported;
  final List<CaptureInput> inputs;
  final List<SpikeSegmentResult> segments;
  final FolderExportResult? export;
  final String? exportError;
  final List<String> checksumFailures;

  bool get exportVerified =>
      export != null && exportError == null && checksumFailures.isEmpty;

  Map<String, Object?> toJson() => {
    'spike': 'P0-06',
    'started_at_utc': startedAtUtc.toIso8601String(),
    'os': os,
    'permission': permission,
    'aac_lc_supported': aacLcSupported,
    'inputs': [for (final i in inputs) i.toJson()],
    'segments': [for (final s in segments) s.toJson()],
    'export': export == null
        ? null
        : {
            'folder': export!.folder.path,
            'total_bytes': export!.totalBytes,
            'files': [for (final f in export!.files) f.toJson()],
          },
    'export_error': exportError,
    'checksum_failures': checksumFailures,
    'export_verified': exportVerified,
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Table for `docs/PLATFORM_FEASIBILITY.md`.
  String toMarkdownTable() {
    final rows = StringBuffer()
      ..writeln(
        '| Requested kbps | Codec | Channels | Sample rate | Duration ms '
        '| Declared avg kbps | Payload kbps | File kbps | Bytes | Roll gap ms '
        '| Peak dBFS |',
      )
      ..writeln('|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
    for (final s in segments) {
      final i = s.info;
      if (i == null) {
        rows.writeln(
          '| ${s.request.bitrateBps ~/ 1000} | error: ${s.error} '
          '| | | | | | | | | |',
        );
        continue;
      }
      rows.writeln(
        '| ${s.request.bitrateBps ~/ 1000} | ${i.codec} | ${i.channelCount} '
        '| ${i.sampleRateHz} | ${i.durationMs} '
        '| ${(i.declaredAvgBitrateBps / 1000).toStringAsFixed(1)} '
        '| ${(i.payloadBitrateBps / 1000).toStringAsFixed(1)} '
        '| ${(i.observedBitrateBps / 1000).toStringAsFixed(1)} '
        '| ${i.bytes} | ${s.rollGap?.inMilliseconds ?? '-'} '
        '| ${s.maxLevelDbfs?.toStringAsFixed(1) ?? '-'} |',
      );
    }
    return rows.toString();
  }
}
