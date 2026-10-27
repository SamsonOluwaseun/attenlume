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
