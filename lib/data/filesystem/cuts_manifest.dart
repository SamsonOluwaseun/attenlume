import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/models/media.dart';
import '../../domain/services/cut_range_math.dart';

/// One cut range instruction in `cuts.json` (FR-REV-07, FR-EXP-03).
class CutItem {
  const CutItem({
    required this.startOffsetMs,
    required this.endOffsetMs,
    this.reason,
  });

  final int startOffsetMs;
  final int endOffsetMs;
  final String? reason;

  int get durationMs => endOffsetMs - startOffsetMs;

  Map<String, Object?> toJson() => {
    'start_ms': startOffsetMs,
    'end_ms': endOffsetMs,
    if (reason != null && reason!.isNotEmpty) 'reason': reason,
  };

  factory CutItem.fromJson(Map<String, Object?> json) => CutItem(
    startOffsetMs: json['start_ms'] as int,
    endOffsetMs: json['end_ms'] as int,
    reason: json['reason'] as String?,
  );
}

/// One retained audio section instruction in `cuts.json`.
class KeepItem {
  const KeepItem({required this.startOffsetMs, required this.endOffsetMs});

  final int startOffsetMs;
  final int endOffsetMs;

  int get durationMs => endOffsetMs - startOffsetMs;

  Map<String, Object?> toJson() => {
    'start_ms': startOffsetMs,
    'end_ms': endOffsetMs,
  };

  factory KeepItem.fromJson(Map<String, Object?> json) => KeepItem(
    startOffsetMs: json['start_ms'] as int,
    endOffsetMs: json['end_ms'] as int,
  );
}

/// A segment reference in `cuts.json`.
class SegmentReference {
  const SegmentReference({
    required this.sequence,
    required this.fileName,
    required this.startOffsetMs,
    required this.durationMs,
  });

  final int sequence;
  final String fileName;
  final int startOffsetMs;
  final int durationMs;

  Map<String, Object?> toJson() => {
    'sequence': sequence,
    'file_name': fileName,
    'start_offset_ms': startOffsetMs,
    'duration_ms': durationMs,
  };

  factory SegmentReference.fromJson(Map<String, Object?> json) =>
      SegmentReference(
        sequence: json['sequence'] as int,
        fileName: json['file_name'] as String,
        startOffsetMs: json['start_offset_ms'] as int,
        durationMs: json['duration_ms'] as int,
      );
}

/// Machine-readable trimming instructions (`cuts.json`) bundled in exports
/// (FR-REV-07, FR-EXP-03) [P0-14].
///
/// Contains original duration, trimmed duration, cut ranges to exclude,
/// calculated keep ranges, and segments. Also provides external tool commands
/// (such as ffmpeg) to execute the trimming instructions outside the app.
class CutsManifest {
  const CutsManifest({
    this.version = '1.0',
    required this.activityId,
    required this.totalDurationMs,
    required this.trimmedDurationMs,
    required this.cuts,
    required this.keepRanges,
    this.segments = const [],
  });

  final String version;
  final String activityId;
  final int totalDurationMs;
  final int trimmedDurationMs;
  final List<CutItem> cuts;
  final List<KeepItem> keepRanges;
  final List<SegmentReference> segments;

  /// Builds a [CutsManifest] from domain entities.
  factory CutsManifest.fromDomain({
    required String activityId,
    required int totalDurationMs,
    required Iterable<CutRange> cutRanges,
    List<RecordingSegment> segments = const [],
    DateTime? firstSegmentStartUtc,
  }) {
    final activeCuts = cutRanges.where((c) => !c.isDeleted).toList();
    final keeps = CutRangeMath.calculateKeepRanges(
      totalDurationMs: totalDurationMs,
      cutRanges: activeCuts,
    );
    final trimmedDur = CutRangeMath.trimmedDurationMs(
      totalDurationMs: totalDurationMs,
      cutRanges: activeCuts,
    );

    final cutItems = activeCuts
        .map(
          (c) => CutItem(
            startOffsetMs: c.startOffsetMs,
            endOffsetMs: c.endOffsetMs,
            reason: c.reason,
          ),
        )
        .toList();

    final keepItems = keeps
        .map((k) => KeepItem(startOffsetMs: k.startMs, endOffsetMs: k.endMs))
        .toList();

    final segRefs = <SegmentReference>[];
    if (segments.isNotEmpty && firstSegmentStartUtc != null) {
      for (final s in segments) {
        final startOffset = s.startUtc
            .difference(firstSegmentStartUtc)
            .inMilliseconds;
        final dur =
            s.durationMs ??
            (s.endUtc?.difference(s.startUtc).inMilliseconds ?? 0);
        segRefs.add(
          SegmentReference(
            sequence: s.sequence,
            fileName: p.basename(s.filePath),
            startOffsetMs: startOffset,
            durationMs: dur,
          ),
        );
      }
    }

    return CutsManifest(
      activityId: activityId,
      totalDurationMs: totalDurationMs,
      trimmedDurationMs: trimmedDur,
      cuts: List.unmodifiable(cutItems),
      keepRanges: List.unmodifiable(keepItems),
      segments: List.unmodifiable(segRefs),
    );
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'activity_id': activityId,
    'total_duration_ms': totalDurationMs,
    'trimmed_duration_ms': trimmedDurationMs,
    'cuts': cuts.map((c) => c.toJson()).toList(),
    'keep_ranges': keepRanges.map((k) => k.toJson()).toList(),
    if (segments.isNotEmpty)
      'segments': segments.map((s) => s.toJson()).toList(),
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory CutsManifest.fromJson(Map<String, Object?> json) => CutsManifest(
    version: json['version'] as String? ?? '1.0',
    activityId: json['activity_id'] as String,
    totalDurationMs: json['total_duration_ms'] as int,
    trimmedDurationMs: json['trimmed_duration_ms'] as int,
    cuts:
        (json['cuts'] as List<dynamic>?)
            ?.map((e) => CutItem.fromJson(e as Map<String, Object?>))
            .toList() ??
        const [],
    keepRanges:
        (json['keep_ranges'] as List<dynamic>?)
            ?.map((e) => KeepItem.fromJson(e as Map<String, Object?>))
            .toList() ??
        const [],
    segments:
        (json['segments'] as List<dynamic>?)
            ?.map((e) => SegmentReference.fromJson(e as Map<String, Object?>))
            .toList() ??
        const [],
  );

  /// Generates an external ffmpeg filter expression to extract the kept ranges.
  /// Example: `[0:a]atrim=start=0.0:end=15.5,asetpts=PTS-STARTPTS[a0];[0:a]atrim=start=30.0:end=60.0,asetpts=PTS-STARTPTS[a1];[a0][a1]concat=n=2:v=0:a=1[out]`
  String toFfmpegFilterComplex() {
    if (keepRanges.isEmpty) return '';
    if (keepRanges.length == 1) {
      final k = keepRanges.first;
      final startSec = (k.startOffsetMs / 1000.0).toStringAsFixed(3);
      final endSec = (k.endOffsetMs / 1000.0).toStringAsFixed(3);
      return '[0:a]atrim=start=$startSec:end=$endSec,asetpts=PTS-STARTPTS[out]';
    }

    final buffer = StringBuffer();
    final concatInputs = StringBuffer();
    for (var i = 0; i < keepRanges.length; i++) {
      final k = keepRanges[i];
      final startSec = (k.startOffsetMs / 1000.0).toStringAsFixed(3);
      final endSec = (k.endOffsetMs / 1000.0).toStringAsFixed(3);
      buffer.write(
        '[0:a]atrim=start=$startSec:end=$endSec,asetpts=PTS-STARTPTS[a$i];',
      );
      concatInputs.write('[a$i]');
    }
    buffer.write(
      '${concatInputs.toString()}concat=n=${keepRanges.length}:v=0:a=1[out]',
    );
    return buffer.toString();
  }

  /// Writes `cuts.json` atomically via a temporary file (FR-EXP-05, NFR-07).
  Future<File> writeToFile(File destination) async {
    final parent = destination.parent;
    if (!parent.existsSync()) {
      await parent.create(recursive: true);
    }
    final partial = File('${destination.path}.partial');
    if (partial.existsSync()) {
      await partial.delete();
    }
    await partial.writeAsString(toPrettyJson(), flush: true);
    if (destination.existsSync()) {
      await destination.delete();
    }
    return partial.rename(destination.path);
  }
}
