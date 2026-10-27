import 'enums.dart';

/// One audio file of an activity (BUILD_GUIDE 9.4 `recording_segments`)
/// [P0-09]. Quality fields follow FR-QUAL-06.
class RecordingSegment {
  const RecordingSegment({
    required this.id,
    required this.activityId,
    required this.sequence,
    required this.filePath,
    required this.state,
    required this.requestedProfile,
    required this.codec,
    required this.container,
    required this.channelCount,
    required this.sampleRateHz,
    required this.requestedBitrateBps,
    this.observedBitrateBps,
    this.inputRoute,
    required this.startUtc,
    this.endUtc,
    this.durationMs,
    this.bytes,
    this.sha256,
    this.endReason,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String activityId;

  /// 1-based order within the activity.
  final int sequence;

  /// Relative to the app media root (BUILD_GUIDE 9.5).
  final String filePath;
  final SegmentState state;
  final RecordingProfile requestedProfile;
  final String codec;
  final String container;
  final int channelCount;
  final int sampleRateHz;
  final int requestedBitrateBps;
  final int? observedBitrateBps;
  final String? inputRoute;
  final DateTime startUtc;
  final DateTime? endUtc;
  final int? durationMs;
  final int? bytes;
  final String? sha256;
  final SegmentEndReason? endReason;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// A logged call, alarm, route loss or similar (FR-REC-05).
class Interruption {
  const Interruption({
    required this.id,
    required this.activityId,
    required this.reason,
    required this.startUtc,
    this.endUtc,
    required this.autoResumed,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String activityId;
  final InterruptionReason reason;
  final DateTime startUtc;
  final DateTime? endUtc;
  final bool autoResumed;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class Photo {
  const Photo({
    required this.id,
    required this.activityId,
    required this.filePath,
    this.thumbnailPath,
    required this.takenUtc,
    this.offsetMs,
    this.caption,
    this.label,
    required this.source,
    this.width,
    this.height,
    this.bytes,
    this.sha256,
    required this.originalKept,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String activityId;
  final String filePath;
  final String? thumbnailPath;
  final DateTime takenUtc;

  /// Null when the activity had no recording when the photo was taken.
  final int? offsetMs;
  final String? caption;
  final String? label;
  final PhotoSource source;
  final int? width;
  final int? height;
  final int? bytes;
  final String? sha256;
  final bool originalKept;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// A marked moment (FR-BMK-01).
class Bookmark {
  const Bookmark({
    required this.id,
    required this.activityId,
    required this.atUtc,
    this.offsetMs,
    this.label,
    this.note,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String activityId;
  final DateTime atUtc;

  /// Null when the activity had no recording at [atUtc].
  final int? offsetMs;
  final String? label;
  final String? note;
  final BookmarkSource source;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// A non-destructive excluded range (FR-REV-04). Soft-deleted for undo.
class CutRange {
  const CutRange({
    required this.id,
    required this.activityId,
    required this.startOffsetMs,
    required this.endOffsetMs,
    this.reason,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String activityId;
  final int startOffsetMs;
  final int endOffsetMs;
  final String? reason;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isDeleted => deletedAt != null;
}
