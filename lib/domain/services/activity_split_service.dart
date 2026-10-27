import '../models/activity.dart';
import '../models/media.dart';

/// Specification for splitting a single segment file into two pieces
/// across an activity split boundary.
class SegmentSplitSpec {
  const SegmentSplitSpec({
    required this.originalSegment,
    required this.splitOffsetWithinSegmentMs,
    required this.part1DurationMs,
    required this.part2DurationMs,
  });

  final RecordingSegment originalSegment;
  final int splitOffsetWithinSegmentMs;
  final int part1DurationMs;
  final int part2DurationMs;
}

/// A bookmark assigned to a target activity after a split.
class SplitBookmarkItem {
  const SplitBookmarkItem({
    required this.original,
    required this.targetActivityId,
    required this.newOffsetMs,
  });

  final Bookmark original;
  final String targetActivityId;
  final int? newOffsetMs;
}

/// A photo assigned to a target activity after a split.
class SplitPhotoItem {
  const SplitPhotoItem({
    required this.original,
    required this.targetActivityId,
    required this.newOffsetMs,
  });

  final Photo original;
  final String targetActivityId;
  final int? newOffsetMs;
}

/// A cut range assigned or partitioned across a split.
class SplitCutRangeItem {
  const SplitCutRangeItem({
    required this.sourceCutRangeId,
    required this.targetActivityId,
    required this.startOffsetMs,
    required this.endOffsetMs,
    this.reason,
  });

  final String sourceCutRangeId;
  final String targetActivityId;
  final int startOffsetMs;
  final int endOffsetMs;
  final String? reason;
}

/// A segment assigned to a target activity after a split.
class SplitSegmentAssignment {
  const SplitSegmentAssignment({
    required this.segment,
    required this.targetActivityId,
    required this.newSequence,
  });

  final RecordingSegment segment;
  final String targetActivityId;
  final int newSequence;
}

/// Detailed plan for splitting an activity at the playhead (FR-REV-05) [P0-14].
class ActivitySplitPlan {
  const ActivitySplitPlan({
    required this.originalActivity,
    required this.splitOffsetMs,
    required this.splitUtc,
    required this.activity1Id,
    required this.activity2Id,
    required this.activity1Title,
    required this.activity2Title,
    required this.activity1Segments,
    required this.activity2Segments,
    this.segmentToSplit,
    required this.bookmarks,
    required this.photos,
    required this.cutRanges,
  });

  final Activity originalActivity;
  final int splitOffsetMs;
  final DateTime splitUtc;
  final String activity1Id;
  final String activity2Id;
  final String activity1Title;
  final String activity2Title;

  /// Existing segments assigned to Activity 1 without needing audio trimming.
  final List<SplitSegmentAssignment> activity1Segments;

  /// Existing segments assigned to Activity 2 without needing audio trimming.
  final List<SplitSegmentAssignment> activity2Segments;

  /// If the split point falls inside a segment, this specification details
  /// how that segment is divided. Null if the split occurred inside a gap.
  final SegmentSplitSpec? segmentToSplit;

  final List<SplitBookmarkItem> bookmarks;
  final List<SplitPhotoItem> photos;
  final List<SplitCutRangeItem> cutRanges;

  bool get splitOccurredInGap => segmentToSplit == null;
}

/// Calculates non-destructive split plans for activities (FR-REV-05, NFR-07) [P0-14].
///
/// Implements playhead splitting of activities into two distinct activities,
/// recalculating timeline offsets for bookmarks and photos, partitioning cut
/// ranges, and determining whether segment audio needs slicing or cleanly splits
/// at a gap.
class ActivitySplitService {
  const ActivitySplitService._();

  /// Plans the split of [activity] at [splitOffsetMs] into two activities.
  static ActivitySplitPlan planSplit({
    required Activity activity,
    required int splitOffsetMs,
    required int totalDurationMs,
    required String newActivityId,
    required List<RecordingSegment> segments,
    required List<Bookmark> bookmarks,
    required List<Photo> photos,
    required List<CutRange> cutRanges,
    String? activity1TitleOverride,
    String? activity2TitleOverride,
  }) {
    if (splitOffsetMs <= 0 || splitOffsetMs >= totalDurationMs) {
      throw ArgumentError(
        'splitOffsetMs must be between 0 and totalDurationMs ($totalDurationMs), '
        'got $splitOffsetMs',
      );
    }

    final sortedSegments = List<RecordingSegment>.from(segments)
      ..sort((a, b) => a.sequence.compareTo(b.sequence));

    final firstStartUtc = sortedSegments.isEmpty
        ? activity.actualStart ?? DateTime.utc(2026)
        : sortedSegments.first.startUtc;

    final splitUtc = firstStartUtc.add(Duration(milliseconds: splitOffsetMs));

    final activity1Id = activity.id;
    final activity2Id = newActivityId;

    final baseTitle = activity.title.isEmpty ? 'Session' : activity.title;
    final act1Title = activity1TitleOverride ?? baseTitle;
    final act2Title = activity2TitleOverride ?? '$baseTitle (Part 2)';

    // 1. Partition Bookmarks (by offset)
    final splitBookmarks = <SplitBookmarkItem>[];
    for (final b in bookmarks) {
      final offset = b.offsetMs;
      if (offset == null) {
        // Pre-recording or unindexed bookmark: stays with Activity 1
        splitBookmarks.add(
          SplitBookmarkItem(
            original: b,
            targetActivityId: activity1Id,
            newOffsetMs: null,
          ),
        );
      } else if (offset < splitOffsetMs) {
        splitBookmarks.add(
          SplitBookmarkItem(
            original: b,
            targetActivityId: activity1Id,
            newOffsetMs: offset,
          ),
        );
      } else {
        splitBookmarks.add(
          SplitBookmarkItem(
            original: b,
            targetActivityId: activity2Id,
            newOffsetMs: offset - splitOffsetMs,
          ),
        );
      }
    }

    // 2. Partition Photos (by offset)
    final splitPhotos = <SplitPhotoItem>[];
    for (final p in photos) {
      final offset = p.offsetMs;
      if (offset == null) {
        splitPhotos.add(
          SplitPhotoItem(
            original: p,
            targetActivityId: activity1Id,
            newOffsetMs: null,
          ),
        );
      } else if (offset < splitOffsetMs) {
        splitPhotos.add(
          SplitPhotoItem(
            original: p,
            targetActivityId: activity1Id,
            newOffsetMs: offset,
          ),
        );
      } else {
        splitPhotos.add(
          SplitPhotoItem(
            original: p,
            targetActivityId: activity2Id,
            newOffsetMs: offset - splitOffsetMs,
          ),
        );
      }
    }

    // 3. Partition Cut Ranges
    final splitCuts = <SplitCutRangeItem>[];
    for (final cut in cutRanges.where((c) => !c.isDeleted)) {
      if (cut.endOffsetMs <= splitOffsetMs) {
        // Entirely in Activity 1
        splitCuts.add(
          SplitCutRangeItem(
            sourceCutRangeId: cut.id,
            targetActivityId: activity1Id,
            startOffsetMs: cut.startOffsetMs,
            endOffsetMs: cut.endOffsetMs,
            reason: cut.reason,
          ),
        );
      } else if (cut.startOffsetMs >= splitOffsetMs) {
        // Entirely in Activity 2
        splitCuts.add(
          SplitCutRangeItem(
            sourceCutRangeId: cut.id,
            targetActivityId: activity2Id,
            startOffsetMs: cut.startOffsetMs - splitOffsetMs,
            endOffsetMs: cut.endOffsetMs - splitOffsetMs,
            reason: cut.reason,
          ),
        );
      } else {
        // Crosses split point: divide into two pieces
        splitCuts.add(
          SplitCutRangeItem(
            sourceCutRangeId: cut.id,
            targetActivityId: activity1Id,
            startOffsetMs: cut.startOffsetMs,
            endOffsetMs: splitOffsetMs,
            reason: cut.reason,
          ),
        );
        splitCuts.add(
          SplitCutRangeItem(
            sourceCutRangeId: cut.id,
            targetActivityId: activity2Id,
            startOffsetMs: 0,
            endOffsetMs: cut.endOffsetMs - splitOffsetMs,
            reason: cut.reason,
          ),
        );
      }
    }

    // 4. Partition Segments
    final act1Segments = <SplitSegmentAssignment>[];
    final act2Segments = <SplitSegmentAssignment>[];
    SegmentSplitSpec? segmentToSplit;

    var seq1 = 1;
    var seq2 = 1;

    for (final seg in sortedSegments) {
      final segStartMs = seg.startUtc.difference(firstStartUtc).inMilliseconds;
      final segDuration =
          seg.durationMs ??
          (seg.endUtc != null
              ? seg.endUtc!.difference(seg.startUtc).inMilliseconds
              : 0);
      final segEndMs = segStartMs + segDuration;

      if (segEndMs <= splitOffsetMs) {
        // Cleanly in Activity 1
        act1Segments.add(
          SplitSegmentAssignment(
            segment: seg,
            targetActivityId: activity1Id,
            newSequence: seq1++,
          ),
        );
      } else if (segStartMs >= splitOffsetMs) {
        // Cleanly in Activity 2
        act2Segments.add(
          SplitSegmentAssignment(
            segment: seg,
            targetActivityId: activity2Id,
            newSequence: seq2++,
          ),
        );
      } else {
        // Split falls within this segment
        final splitWithinSeg = splitOffsetMs - segStartMs;
        segmentToSplit = SegmentSplitSpec(
          originalSegment: seg,
          splitOffsetWithinSegmentMs: splitWithinSeg,
          part1DurationMs: splitWithinSeg,
          part2DurationMs: segDuration - splitWithinSeg,
        );
      }
    }

    return ActivitySplitPlan(
      originalActivity: activity,
      splitOffsetMs: splitOffsetMs,
      splitUtc: splitUtc,
      activity1Id: activity1Id,
      activity2Id: activity2Id,
      activity1Title: act1Title,
      activity2Title: act2Title,
      activity1Segments: List.unmodifiable(act1Segments),
      activity2Segments: List.unmodifiable(act2Segments),
      segmentToSplit: segmentToSplit,
      bookmarks: List.unmodifiable(splitBookmarks),
      photos: List.unmodifiable(splitPhotos),
      cutRanges: List.unmodifiable(splitCuts),
    );
  }
}
