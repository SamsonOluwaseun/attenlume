/// Stored enum values (BUILD_GUIDE 9.4) [P0-09].
///
/// Each value has a stable snake_case [KeyedEnum.key] that is written to the
/// database and to exports. Never rename a key: add a migration instead.
library;

/// An enum whose values are stored by a stable string key.
abstract interface class KeyedEnum {
  String get key;
}

/// Looks up the value of [values] whose key is [key].
///
/// Throws [ArgumentError] for an unknown key, so damaged rows fail loudly
/// instead of being read as a default.
T enumFromKey<T extends KeyedEnum>(List<T> values, String key) {
  for (final value in values) {
    if (value.key == key) return value;
  }
  throw ArgumentError.value(key, 'key', 'Unknown ${T.toString()} key');
}

/// Audio recording profile (BUILD_GUIDE 5.5). Targets are not guaranteed
/// output: segments store what was actually used (FR-QUAL-06).
enum RecordingProfile implements KeyedEnum {
  economy('economy', 32000),
  balanced('balanced', 48000),
  enhanced('enhanced', 64000);

  const RecordingProfile(this.key, this.targetBitrateBps);

  @override
  final String key;

  /// Requested AAC-LC mono bitrate before any platform floor (ADR-002).
  final int targetBitrateBps;

  /// The global default (FR-QUAL-02).
  static const RecordingProfile globalDefault = balanced;
}

/// Participant role at a conference (FR-CONF-03).
enum RoleType implements KeyedEnum {
  attendee('attendee'),
  speaker('speaker'),
  exhibitor('exhibitor'),
  student('student'),
  journalist('journalist'),
  custom('custom');

  const RoleType(this.key);
  @override
  final String key;
}

/// Outputs the user wants from a conference (FR-CONF-05).
enum RequestedOutput implements KeyedEnum {
  personalNotes('personal_notes'),
  briefing('briefing'),
  presentation('presentation'),
  linkedinPost('linkedin_post'),
  blog('blog'),
  researchSummary('research_summary'),
  followUpList('follow_up_list');

  const RequestedOutput(this.key);
  @override
  final String key;
}

enum ActivityStatus implements KeyedEnum {
  draft('draft'),
  active('active'),
  completed('completed');

  const ActivityStatus(this.key);
  @override
  final String key;
}

/// Whether recording this activity is allowed (FR-ACT-07, FR-PRI-01).
enum RecordingPermissionStatus implements KeyedEnum {
  unknown('unknown'),
  permitted('permitted'),
  notPermitted('not_permitted'),
  participantAware('participant_aware');

  const RecordingPermissionStatus(this.key);
  @override
  final String key;
}

enum SegmentState implements KeyedEnum {
  writing('writing'),
  finalised('finalised'),
  damaged('damaged'),
  recovered('recovered');

  const SegmentState(this.key);
  @override
  final String key;
}

/// Why a segment ended (FR-REC-03).
enum SegmentEndReason implements KeyedEnum {
  userStop('user_stop'),
  pause('pause'),
  roll('roll'),
  interruption('interruption'),
  qualityChange('quality_change'),
  routeChange('route_change'),
  storageLow('storage_low'),
  error('error');

  const SegmentEndReason(this.key);
  @override
  final String key;
}

enum InterruptionReason implements KeyedEnum {
  call('call'),
  alarm('alarm'),
  otherApp('other_app'),
  camera('camera'),
  routeLost('route_lost'),
  permissionRevoked('permission_revoked'),
  system('system');

  const InterruptionReason(this.key);
  @override
  final String key;
}

enum PhotoSource implements KeyedEnum {
  inApp('in_app'),
  galleryImport('gallery_import'),
  manualImport('manual_import');

  const PhotoSource(this.key);
  @override
  final String key;
}

enum BookmarkSource implements KeyedEnum {
  ui('ui'),
  notification('notification'),
  shortcut('shortcut'),
  hotkey('hotkey'),
  voice('voice');

  const BookmarkSource(this.key);
  @override
  final String key;
}

enum ExportDestination implements KeyedEnum {
  local('local'),
  googleDrive('google_drive'),
  onedrive('onedrive');

  const ExportDestination(this.key);
  @override
  final String key;
}

enum ExportFormat implements KeyedEnum {
  folder('folder'),
  zip('zip');

  const ExportFormat(this.key);
  @override
  final String key;
}

/// Audio options for an export (FR-EXP-03).
enum ExportAudioMode implements KeyedEnum {
  original('original'),
  trimmed('trimmed'),
  originalWithCuts('original_with_cuts'),
  none('none');

  const ExportAudioMode(this.key);
  @override
  final String key;
}

enum ExportJobState implements KeyedEnum {
  pending('pending'),
  running('running'),
  completed('completed'),
  failed('failed'),
  cancelled('cancelled');

  const ExportJobState(this.key);
  @override
  final String key;
}

enum VerificationLevel implements KeyedEnum {
  none('none'),
  receipt('receipt'),
  size('size'),
  checksum('checksum');

  const VerificationLevel(this.key);
  @override
  final String key;
}
