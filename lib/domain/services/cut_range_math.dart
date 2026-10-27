import 'dart:math' as math;

import '../models/media.dart';

/// A contiguous time interval [startMs, endMs] (inclusive start, exclusive end).
class TimeRange {
  const TimeRange(this.startMs, this.endMs)
    : assert(startMs >= 0, 'startMs must be non-negative: $startMs'),
      assert(endMs >= startMs, 'endMs ($endMs) must be >= startMs ($startMs)');

  final int startMs;
  final int endMs;

  int get durationMs => endMs - startMs;

  bool contains(int timestampMs) =>
      timestampMs >= startMs && timestampMs < endMs;

  bool overlaps(TimeRange other) =>
      startMs < other.endMs && other.startMs < endMs;

  bool isAdjacent(TimeRange other) =>
      startMs == other.endMs || endMs == other.startMs;

  Map<String, int> toJson() => {'start_ms': startMs, 'end_ms': endMs};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimeRange &&
          runtimeType == other.runtimeType &&
          startMs == other.startMs &&
          endMs == other.endMs;

  @override
  int get hashCode => Object.hash(startMs, endMs);

  @override
  String toString() => 'TimeRange($startMs..$endMs, ${durationMs}ms)';
}

/// Result of mapping an original timestamp to a trimmed timeline offset.
class OffsetMapResult {
  const OffsetMapResult({
    required this.originalOffsetMs,
    required this.trimmedOffsetMs,
    required this.isInsideCut,
  });

  final int originalOffsetMs;

  /// The mapped offset in the trimmed audio stream.
  /// If [isInsideCut] is true, this is the trimmed offset at the cut boundary.
  final int trimmedOffsetMs;

  /// True if the original offset falls inside an excluded cut range.
  final bool isInsideCut;

  @override
  String toString() =>
      'OffsetMapResult(orig: $originalOffsetMs, trimmed: $trimmedOffsetMs, cut: $isInsideCut)';
}

/// Mathematical operations for non-destructive cut ranges and timeline trimming
/// (FR-REV-04, NFR-07) [P0-14].
///
/// Implements overlapping range consolidation, keep-range derivation,
/// timeline offset mapping, and duration calculations.
class CutRangeMath {
  const CutRangeMath._();

  /// Consolidates overlapping and adjacent cut ranges into a canonical,
  /// sorted, non-overlapping list of [TimeRange] intervals (FR-REV-04).
  ///
  /// Ignores soft-deleted ranges.
  static List<TimeRange> mergeOverlappingCutRanges(Iterable<CutRange> ranges) {
    final active = ranges.where((r) => !r.isDeleted).toList();
    if (active.isEmpty) return const [];

    final rawIntervals =
        active
            .map((r) => TimeRange(r.startOffsetMs, r.endOffsetMs))
            .where((t) => t.durationMs > 0)
            .toList()
          ..sort((a, b) => a.startMs.compareTo(b.startMs));

    if (rawIntervals.isEmpty) return const [];

    final merged = <TimeRange>[rawIntervals.first];
    for (var i = 1; i < rawIntervals.length; i++) {
      final current = rawIntervals[i];
      final last = merged.last;

      if (current.startMs <= last.endMs) {
        // Overlapping or contiguous: extend the previous range
        final newEnd = math.max(last.endMs, current.endMs);
        merged[merged.length - 1] = TimeRange(last.startMs, newEnd);
      } else {
        merged.add(current);
      }
    }
    return List.unmodifiable(merged);
  }

  /// Calculates the retained audio intervals ([keepRanges]) by subtracting
  /// merged cut ranges from the total timeline [0, totalDurationMs] (FR-REV-04).
  ///
  /// Cut ranges extending beyond [totalDurationMs] are clamped safely.
  static List<TimeRange> calculateKeepRanges({
    required int totalDurationMs,
    required Iterable<CutRange> cutRanges,
  }) {
    if (totalDurationMs <= 0) return const [];

    final mergedCuts = mergeOverlappingCutRanges(cutRanges);
    if (mergedCuts.isEmpty) {
      return List.unmodifiable([TimeRange(0, totalDurationMs)]);
    }

    final keepRanges = <TimeRange>[];
    var cursor = 0;

    for (final cut in mergedCuts) {
      final cutStart = cut.startMs.clamp(0, totalDurationMs);
      final cutEnd = cut.endMs.clamp(0, totalDurationMs);

      if (cutStart > cursor) {
        keepRanges.add(TimeRange(cursor, cutStart));
      }
      cursor = math.max(cursor, cutEnd);
      if (cursor >= totalDurationMs) break;
    }

    if (cursor < totalDurationMs) {
      keepRanges.add(TimeRange(cursor, totalDurationMs));
    }

    return List.unmodifiable(keepRanges);
  }

  /// Calculates the total duration of the audio after excluding all cut ranges.
  static int trimmedDurationMs({
    required int totalDurationMs,
    required Iterable<CutRange> cutRanges,
  }) {
    final keeps = calculateKeepRanges(
      totalDurationMs: totalDurationMs,
      cutRanges: cutRanges,
    );
    var sum = 0;
    for (final range in keeps) {
      sum += range.durationMs;
    }
    return sum;
  }

  /// Maps an offset from the original timeline into the trimmed timeline.
  ///
  /// If [originalOffsetMs] is inside a cut range, [OffsetMapResult.isInsideCut]
  /// is set to true and [OffsetMapResult.trimmedOffsetMs] points to the start
  /// boundary of that cut in the trimmed timeline.
  static OffsetMapResult mapOriginalToTrimmedOffset({
    required int originalOffsetMs,
    required int totalDurationMs,
    required Iterable<CutRange> cutRanges,
  }) {
    final mergedCuts = mergeOverlappingCutRanges(cutRanges);
    var accumulatedCutMs = 0;

    for (final cut in mergedCuts) {
      if (originalOffsetMs < cut.startMs) {
        break;
      }
      if (originalOffsetMs >= cut.startMs && originalOffsetMs < cut.endMs) {
        return OffsetMapResult(
          originalOffsetMs: originalOffsetMs,
          trimmedOffsetMs: cut.startMs - accumulatedCutMs,
          isInsideCut: true,
        );
      }
      accumulatedCutMs += (cut.endMs - cut.startMs);
    }

    final clampedOrig = originalOffsetMs.clamp(0, totalDurationMs);
    final mapped = clampedOrig - accumulatedCutMs;
    return OffsetMapResult(
      originalOffsetMs: originalOffsetMs,
      trimmedOffsetMs: math.max(0, mapped),
      isInsideCut: false,
    );
  }

  /// Maps an offset from the trimmed timeline back to the original timeline.
  static int mapTrimmedToOriginalOffset({
    required int trimmedOffsetMs,
    required int totalDurationMs,
    required Iterable<CutRange> cutRanges,
  }) {
    final keepRanges = calculateKeepRanges(
      totalDurationMs: totalDurationMs,
      cutRanges: cutRanges,
    );
    if (keepRanges.isEmpty) return 0;

    var accumulatedTrimmedMs = 0;
    for (final keep in keepRanges) {
      if (trimmedOffsetMs <= accumulatedTrimmedMs + keep.durationMs) {
        final delta = trimmedOffsetMs - accumulatedTrimmedMs;
        return keep.startMs + delta;
      }
      accumulatedTrimmedMs += keep.durationMs;
    }
    return keepRanges.last.endMs;
  }
}
