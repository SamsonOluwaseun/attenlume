import 'enums.dart';

/// A conference the user attends (BUILD_GUIDE 9.4 `conferences`) [P0-09].
class Conference {
  const Conference({
    required this.id,
    required this.name,
    this.description,
    this.venue,
    this.startDate,
    this.endDate,
    required this.timezone,
    this.roleType,
    this.roleText,
    required this.requestedOutputs,
    required this.defaultRecordingProfile,
    this.policyAcknowledgedAt,
    this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? description;
  final String? venue;

  /// Calendar dates, held as UTC midnight. Only year, month and day matter.
  final DateTime? startDate;
  final DateTime? endDate;

  /// IANA timezone name, for display only. Instants are stored in UTC.
  final String timezone;
  final RoleType? roleType;
  final String? roleText;
  final List<RequestedOutput> requestedOutputs;

  /// Copied from the global default at creation (FR-QUAL-02).
  final RecordingProfile defaultRecordingProfile;
  final DateTime? policyAcknowledgedAt;
  final DateTime? archivedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isArchived => archivedAt != null;
}

/// A participant goal (FR-CONF-04). [priority] is 1 to 3 for priority goals
/// and null for extra goals.
class Goal {
  const Goal({
    required this.id,
    required this.conferenceId,
    required this.goalText,
    this.priority,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String conferenceId;
  final String goalText;
  final int? priority;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// What deleting a conference removes, shown before confirmation (FR-CONF-08).
class ConferenceDeletionSummary {
  const ConferenceDeletionSummary({
    required this.activities,
    required this.segments,
    required this.photos,
    required this.bookmarks,
    required this.audioBytes,
    required this.photoBytes,
  });

  final int activities;
  final int segments;
  final int photos;
  final int bookmarks;
  final int audioBytes;
  final int photoBytes;
}
