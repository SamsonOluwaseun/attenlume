import '../models/enums.dart';

/// Recording profile precedence (FR-QUAL-02) [P0-09]:
/// global default, copied into the conference at creation, then the
/// activity override if one is set.
RecordingProfile effectiveRecordingProfile({
  required RecordingProfile conferenceDefault,
  RecordingProfile? activityOverride,
}) => activityOverride ?? conferenceDefault;
