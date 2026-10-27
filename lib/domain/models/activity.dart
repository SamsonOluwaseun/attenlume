import 'enums.dart';

/// A built-in or user-defined activity type (NFR-03, FR-ACT-06) [P0-09].
class ActivityType {
  const ActivityType({
    required this.id,
    required this.key,
    required this.label,
    required this.icon,
    required this.isBuiltin,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// Stable snake_case key, unique across types.
  final String key;

  /// UK English label shown in the UI and default titles (FR-ACT-05).
  final String label;

  /// Lucide icon name (DESIGN_GUIDE Iconography).
  final String icon;
  final bool isBuiltin;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// Anything captured within a conference (BUILD_GUIDE 9.4 `activities`).
class Activity {
  const Activity({
    required this.id,
    required this.conferenceId,
    required this.typeId,
    required this.title,
    required this.speakerNames,
    this.organisation,
    this.room,
    this.notesMd,
    required this.tags,
    this.plannedStart,
    this.actualStart,
    this.actualEnd,
    required this.status,
    required this.recordingPermissionStatus,
    this.recordingProfileOverride,
    required this.isPrivate,
    this.contactName,
    this.contactDetails,
    this.followUpText,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String conferenceId;
  final String typeId;
  final String title;
  final List<String> speakerNames;
  final String? organisation;
  final String? room;
  final String? notesMd;
  final List<String> tags;
  final DateTime? plannedStart;
  final DateTime? actualStart;
  final DateTime? actualEnd;
  final ActivityStatus status;
  final RecordingPermissionStatus recordingPermissionStatus;

  /// Null means "inherit the conference default" (FR-QUAL-02).
  final RecordingProfile? recordingProfileOverride;

  /// Excluded from export by default when true (FR-EXP-10).
  final bool isPrivate;
  final String? contactName;
  final String? contactDetails;
  final String? followUpText;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// The visual state displayed in a [StatusPill] for an activity (DESIGN_GUIDE StatusPill).
enum StatusPillStatus {
  recording('Recording'),
  paused('Paused'),
  interrupted('Interrupted'),
  saved('Saved'),
  exported('Exported'),
  verified('Verified'),
  private('Private'),
  draft('Draft');

  const StatusPillStatus(this.label);
  final String label;
}

/// Rich activity summary for activity list and timeline views (FR-ACT-03).
///
/// Combines the activity metadata with its resolved type, effective recording
/// profile, recording state, duration, and asset counts.
class ActivitySummary {
  const ActivitySummary({
    required this.activity,
    required this.type,
    required this.effectiveProfile,
    required this.statusPillStatus,
    required this.duration,
    required this.photoCount,
    required this.bookmarkCount,
    this.segmentCount = 0,
    this.audioBytes = 0,
    this.photoBytes = 0,
    this.hasActiveRecording = false,
  });

  final Activity activity;
  final ActivityType type;
  final RecordingProfile effectiveProfile;
  final StatusPillStatus statusPillStatus;
  final Duration duration;
  final int photoCount;
  final int bookmarkCount;
  final int segmentCount;
  final int audioBytes;
  final int photoBytes;
  final bool hasActiveRecording;
}
