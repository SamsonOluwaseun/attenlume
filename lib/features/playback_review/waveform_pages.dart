import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../data/filesystem/waveform_summary.dart';
import '../../domain/models/media.dart';
import '../../domain/services/review_timeline.dart';

/// Levels on the timeline, from one segment's summary.
class WaveformSpan {
  const WaveformSpan({
    required this.startMs,
    required this.bucketMs,
    required this.levels,
  });

  /// Timeline offset of the first bucket.
  final int startMs;
  final int bucketMs;
  final Uint8List levels;

  int get endMs => startMs + levels.length * bucketMs;
}

/// One page of the waveform (FR-REV-03) [P1-17].
class WaveformPage {
  const WaveformPage({
    required this.index,
    required this.startMs,
    required this.endMs,
    required this.spans,
    required this.missing,
  });

  final int index;
  final int startMs;
  final int endMs;
  final List<WaveformSpan> spans;

  /// Recorded parts of this page with no summary to draw (recorded before
  /// summaries existed, or the file is gone). Drawn flat, never guessed.
  final List<({int startMs, int endMs})> missing;

  int get lengthMs => endMs - startMs;
}

/// Splits a timeline into fixed-length pages and reads only the summary
/// bytes one page needs, so memory stays bounded however long the
/// session is (FR-REV-03, BUILD_GUIDE 12.2) [P1-17].
class WaveformPager {
  WaveformPager({
    required this.timeline,
    required this.summaryFile,
    this.pageMs = defaultPageMs,
    this.reader = const WaveformSummaryReader(),
  });

  static const defaultPageMs = 2 * 60 * 1000;

  final ReviewTimeline timeline;
  final Future<File> Function(RecordingSegment segment) summaryFile;
  final int pageMs;
  final WaveformSummaryReader reader;

  int get pageCount => math.max(1, (timeline.spanMs / pageMs).ceil());

  /// The page holding a timeline offset.
  int pageOf(int offsetMs) =>
      ((offsetMs - timeline.startMs) ~/ pageMs).clamp(0, pageCount - 1);

  Future<WaveformPage> load(int index) async {
    final start = timeline.startMs + index * pageMs;
    final end = start + pageMs;
    final spans = <WaveformSpan>[];
    final missing = <({int startMs, int endMs})>[];
    for (final s in timeline.segments) {
      if (s.durationMs <= 0 || s.endMs <= start || s.startMs >= end) continue;
      final from = math.max(0, start - s.startMs);
      final to = math.min(s.durationMs, end - s.startMs);
      final slice = await reader.read(
        await summaryFile(s.segment),
        fromMs: from,
        toMs: to,
      );
      if (slice == null || slice.levels.isEmpty) {
        missing.add((startMs: s.startMs + from, endMs: s.startMs + to));
        continue;
      }
      spans.add(
        WaveformSpan(
          startMs: s.startMs + slice.startMs,
          bucketMs: slice.bucketMs,
          levels: slice.levels,
        ),
      );
      // A summary shorter than its audio (the last moments before a stop)
      // leaves the rest flat.
      final covered = s.startMs + slice.endMs;
      final wanted = s.startMs + to;
      if (covered < wanted) missing.add((startMs: covered, endMs: wanted));
    }
    return WaveformPage(
      index: index,
      startMs: start,
      endMs: end,
      spans: spans,
      missing: missing,
    );
  }
}
