import 'dart:math' as math;

import '../models/enums.dart';
import '../models/media.dart';
import 'cut_range_math.dart';
import 'timeline_offset.dart';

/// One audio file placed on the review timeline (FR-REV-02) [P1-17].
class TimelineSegment {
  const TimelineSegment({
    required this.segment,
    required this.startMs,
    required this.durationMs,
    required this.audioStartMs,
  });

  final RecordingSegment segment;

  /// Offset of the segment start (BUILD_GUIDE 9.4 offset rule).
  final int startMs;
  final int durationMs;

  /// Where this segment starts in the joined audio, gaps left out. Only
  /// playable segments count towards it.
  final int audioStartMs;

  int get endMs => startMs + durationMs;

  /// Finalised and recovered files can be played. Damaged files and files
  /// still being written are shown but skipped (FR-REC-08).
  bool get playable =>
      durationMs > 0 &&
      (segment.state == SegmentState.finalised ||
          segment.state == SegmentState.recovered);
}

/// Time between two segments when nothing was recorded.
class TimelineGap {
  const TimelineGap({required this.startMs, required this.endMs});

  final int startMs;
  final int endMs;

  int get durationMs => endMs - startMs;
}

enum TimelineMarkerKind { interruption, photo, bookmark }

/// A photo, bookmark or interruption at its offset.
class TimelineMarker {
  const TimelineMarker({
    required this.kind,
    required this.id,
    required this.offsetMs,
    this.endOffsetMs,
    this.label,
  });

  final TimelineMarkerKind kind;
  final String id;
  final int offsetMs;

  /// End of an interruption, when it has ended.
  final int? endOffsetMs;

  /// Bookmark label, photo caption or interruption reason.
  final String? label;
}

/// A playable position: which segment and how far into it.
class TimelinePosition {
  const TimelinePosition({
    required this.segmentIndex,
    required this.inSegmentMs,
  });

  /// Index into [ReviewTimeline.segments].
  final int segmentIndex;
  final int inSegmentMs;

  @override
  bool operator ==(Object other) =>
      other is TimelinePosition &&
      other.segmentIndex == segmentIndex &&
      other.inSegmentMs == inSegmentMs;

  @override
  int get hashCode => Object.hash(segmentIndex, inSegmentMs);

  @override
  String toString() => 'TimelinePosition($segmentIndex, $inSegmentMs)';
}

/// An activity's segments, gaps, interruptions, photos and bookmarks on
/// one timeline (FR-REV-02) [P1-17].
///
/// Offsets follow the build guide 9.4 rule: milliseconds from the first
/// segment's start, gaps counted as real time. Built from database rows
/// only, never from audio.
class ReviewTimeline {
  ReviewTimeline._({
    required this.segments,
    required this.gaps,
    required this.markers,
    required this.startMs,
    required this.endMs,
  });

  factory ReviewTimeline.build({
    required List<RecordingSegment> segments,
    List<Interruption> interruptions = const [],
    List<Photo> photos = const [],
    List<Bookmark> bookmarks = const [],
  }) {
    final sorted = [...segments]
      ..sort((a, b) {
        final byStart = a.startUtc.compareTo(b.startUtc);
        return byStart != 0 ? byStart : a.sequence.compareTo(b.sequence);
      });
    final first = sorted.isEmpty ? null : sorted.first.startUtc;
    int? offsetOf(DateTime utc) =>
        timelineOffsetMs(eventUtc: utc, firstSegmentStartUtc: first);

    final placed = <TimelineSegment>[];
    final gaps = <TimelineGap>[];
    var audioMs = 0;
    var lastEnd = 0;
    for (final segment in sorted) {
      final start = offsetOf(segment.startUtc)!;
      final duration = _durationOf(segment);
      final item = TimelineSegment(
        segment: segment,
        startMs: start,
        durationMs: duration,
        audioStartMs: audioMs,
      );
      if (item.playable) audioMs += duration;
      if (placed.isNotEmpty && start > lastEnd) {
        gaps.add(TimelineGap(startMs: lastEnd, endMs: start));
      }
      placed.add(item);
      if (item.endMs > lastEnd) lastEnd = item.endMs;
    }

    final markers = <TimelineMarker>[
      for (final i in interruptions)
        if (offsetOf(i.startUtc) case final offset?)
          TimelineMarker(
            kind: TimelineMarkerKind.interruption,
            id: i.id,
            offsetMs: offset,
            endOffsetMs: i.endUtc == null ? null : offsetOf(i.endUtc!),
            label: i.reason.key,
          ),
      for (final photo in photos)
        if (photo.offsetMs ?? offsetOf(photo.takenUtc) case final offset?)
          TimelineMarker(
            kind: TimelineMarkerKind.photo,
            id: photo.id,
            offsetMs: offset,
            label: photo.caption,
          ),
      for (final bookmark in bookmarks)
        if (bookmark.offsetMs ?? offsetOf(bookmark.atUtc) case final offset?)
          TimelineMarker(
            kind: TimelineMarkerKind.bookmark,
            id: bookmark.id,
            offsetMs: offset,
            label: bookmark.label,
          ),
    ]..sort((a, b) => a.offsetMs.compareTo(b.offsetMs));

    var startMs = 0;
    var endMs = lastEnd;
    for (final m in markers) {
      if (m.offsetMs < startMs) startMs = m.offsetMs;
      final end = m.endOffsetMs ?? m.offsetMs;
      if (end > endMs) endMs = end;
    }

    return ReviewTimeline._(
      segments: List.unmodifiable(placed),
      gaps: List.unmodifiable(gaps),
      markers: List.unmodifiable(markers),
      startMs: startMs,
      endMs: endMs,
    );
  }

  /// Segment duration from the stored length, else from its end time.
  static int _durationOf(RecordingSegment s) {
    if (s.durationMs case final d? when d > 0) return d;
    final end = s.endUtc;
    if (end == null) return 0;
    final d = end.difference(s.startUtc).inMilliseconds;
    return d > 0 ? d : 0;
  }

  final List<TimelineSegment> segments;
  final List<TimelineGap> gaps;
  final List<TimelineMarker> markers;

  /// First and last offset shown. [startMs] is negative when a photo or
  /// bookmark came before Record was pressed.
  final int startMs;
  final int endMs;

  int get spanMs => endMs - startMs;

  bool get hasAudio => segments.any((s) => s.playable);

  /// Length of the joined playable audio, gaps left out.
  int get audioDurationMs {
    var total = 0;
    for (final s in segments) {
      if (s.playable) total += s.durationMs;
    }
    return total;
  }

  /// End of the last segment: where "Trim end" cuts to.
  int get audioEndMs {
    var end = 0;
    for (final s in segments) {
      if (s.endMs > end) end = s.endMs;
    }
    return end;
  }

  /// Playable audio left once [cuts] (merged, timeline offsets) are
  /// skipped (FR-REV-04) [P1-18].
  int keptAudioMs(List<TimeRange> cuts) {
    var total = 0;
    for (final s in segments) {
      if (!s.playable) continue;
      var kept = s.durationMs;
      for (final c in cuts) {
        final start = math.max(c.startMs, s.startMs);
        final end = math.min(c.endMs, s.endMs);
        if (end > start) kept -= end - start;
      }
      total += kept;
    }
    return total;
  }

  Iterable<TimelineMarker> markersOf(TimelineMarkerKind kind) =>
      markers.where((m) => m.kind == kind);

  /// The playable position for a timeline offset. Inside a gap, before the
  /// first segment or on an unplayable segment it moves forward to the
  /// next playable start; after the end it stays at the end of the last
  /// playable segment. Null when nothing can be played.
  TimelinePosition? locate(int offsetMs) {
    TimelinePosition? last;
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      if (!s.playable) continue;
      if (offsetMs < s.startMs) {
        return TimelinePosition(segmentIndex: i, inSegmentMs: 0);
      }
      if (offsetMs < s.endMs) {
        return TimelinePosition(
          segmentIndex: i,
          inSegmentMs: offsetMs - s.startMs,
        );
      }
      last = TimelinePosition(segmentIndex: i, inSegmentMs: s.durationMs);
    }
    return last;
  }

  /// The playable position [audioMs] into the joined audio, clamped to
  /// its start and end.
  TimelinePosition? locateAudio(int audioMs) {
    TimelinePosition? last;
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      if (!s.playable) continue;
      final inSegment = audioMs - s.audioStartMs;
      if (inSegment < s.durationMs) {
        return TimelinePosition(
          segmentIndex: i,
          inSegmentMs: inSegment < 0 ? 0 : inSegment,
        );
      }
      last = TimelinePosition(segmentIndex: i, inSegmentMs: s.durationMs);
    }
    return last;
  }

  /// Timeline offset of a playable position.
  int offsetOf(TimelinePosition position) =>
      segments[position.segmentIndex].startMs + position.inSegmentMs;

  /// Joined-audio time of a playable position.
  int audioOf(TimelinePosition position) =>
      segments[position.segmentIndex].audioStartMs + position.inSegmentMs;

  /// The next playable segment after [index], or null at the end.
  int? nextPlayable(int index) {
    for (var i = index + 1; i < segments.length; i++) {
      if (segments[i].playable) return i;
    }
    return null;
  }
}
