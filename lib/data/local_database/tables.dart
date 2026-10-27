import 'package:drift/drift.dart';

import '../../domain/models/activity.dart';
import '../../domain/models/conference.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/export_job.dart';
import '../../domain/models/media.dart';
import 'converters.dart';

// Drift tables for BUILD_GUIDE 9.4 [P0-09]. Phase 1.5 and 2 tables
// (cloud_connections, cloud_export_files, transcripts) come with their phases.
//
// IDs are UUID v4 text. Instants are UTC ISO 8601 text (ADR-004). Rows map to
// the plain domain classes in lib/domain/models via @UseRowClass.

/// `created_at` and `updated_at`, on every table.
mixin Timestamps on Table {
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

/// Key-value app settings (BUILD_GUIDE 9.4 `app_settings`).
// Kept identical to schema v1 (no mixin) so the v1 dump stays valid.
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@UseRowClass(Conference)
class Conferences extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get venue => text().nullable()();
  TextColumn get startDate =>
      text().nullable().map(const CalendarDateConverter())();
  TextColumn get endDate =>
      text().nullable().map(const CalendarDateConverter())();
  TextColumn get timezone => text()();
  TextColumn get roleType =>
      text().nullable().map(const EnumKeyConverter(RoleType.values))();
  TextColumn get roleText => text().nullable()();
  TextColumn get requestedOutputs =>
      text().map(const EnumKeyListConverter(RequestedOutput.values))();
  TextColumn get defaultRecordingProfile =>
      text().map(const EnumKeyConverter(RecordingProfile.values))();
  DateTimeColumn get policyAcknowledgedAt => dateTime().nullable()();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@UseRowClass(Goal)
@TableIndex(name: 'goals_conference', columns: {#conferenceId})
class Goals extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get conferenceId =>
      text().references(Conferences, #id, onDelete: KeyAction.cascade)();
  // Named in SQL as `text`; the getter cannot be `text` in Drift.
  TextColumn get goalText => text().named('text')();
  IntColumn get priority => integer().nullable()();
  IntColumn get sortOrder => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (priority IS NULL OR priority BETWEEN 1 AND 3)',
  ];
}

@UseRowClass(ActivityType)
class ActivityTypes extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get key => text().unique()();
  TextColumn get label => text()();
  TextColumn get icon => text()();
  BoolColumn get isBuiltin => boolean()();
  IntColumn get sortOrder => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@UseRowClass(Activity)
@TableIndex(name: 'activities_conference', columns: {#conferenceId})
class Activities extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get conferenceId =>
      text().references(Conferences, #id, onDelete: KeyAction.cascade)();
  // A type in use cannot be deleted.
  TextColumn get typeId =>
      text().references(ActivityTypes, #id, onDelete: KeyAction.restrict)();
  TextColumn get title => text()();
  TextColumn get speakerNames => text().map(const StringListConverter())();
  TextColumn get organisation => text().nullable()();
  TextColumn get room => text().nullable()();
  TextColumn get notesMd => text().nullable()();
  TextColumn get tags => text().map(const StringListConverter())();
  DateTimeColumn get plannedStart => dateTime().nullable()();
  DateTimeColumn get actualStart => dateTime().nullable()();
  DateTimeColumn get actualEnd => dateTime().nullable()();
  TextColumn get status =>
      text().map(const EnumKeyConverter(ActivityStatus.values))();
  TextColumn get recordingPermissionStatus =>
      text().map(const EnumKeyConverter(RecordingPermissionStatus.values))();
  TextColumn get recordingProfileOverride =>
      text().nullable().map(const EnumKeyConverter(RecordingProfile.values))();
  BoolColumn get isPrivate => boolean()();
  TextColumn get contactName => text().nullable()();
  TextColumn get contactDetails => text().nullable()();
  TextColumn get followUpText => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@UseRowClass(RecordingSegment)
class RecordingSegments extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get activityId =>
      text().references(Activities, #id, onDelete: KeyAction.cascade)();
  IntColumn get sequence => integer()();
  TextColumn get filePath => text()();
  TextColumn get state =>
      text().map(const EnumKeyConverter(SegmentState.values))();
  TextColumn get requestedProfile =>
      text().map(const EnumKeyConverter(RecordingProfile.values))();
  TextColumn get codec => text()();
  TextColumn get container => text()();
  IntColumn get channelCount => integer()();
  IntColumn get sampleRateHz => integer()();
  IntColumn get requestedBitrateBps => integer()();
  IntColumn get observedBitrateBps => integer().nullable()();
  TextColumn get inputRoute => text().nullable()();
  DateTimeColumn get startUtc => dateTime()();
  DateTimeColumn get endUtc => dateTime().nullable()();
  IntColumn get durationMs => integer().nullable()();
  IntColumn get bytes => integer().nullable()();
  TextColumn get sha256 => text().nullable()();
  TextColumn get endReason =>
      text().nullable().map(const EnumKeyConverter(SegmentEndReason.values))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  // The unique key also serves as the activity index.
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {activityId, sequence},
  ];

  @override
  List<String> get customConstraints => ['CHECK (sequence > 0)'];
}

@UseRowClass(Interruption)
@TableIndex(name: 'interruptions_activity', columns: {#activityId})
class Interruptions extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get activityId =>
      text().references(Activities, #id, onDelete: KeyAction.cascade)();
  TextColumn get reason =>
      text().map(const EnumKeyConverter(InterruptionReason.values))();
  DateTimeColumn get startUtc => dateTime()();
  DateTimeColumn get endUtc => dateTime().nullable()();
  BoolColumn get autoResumed => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@UseRowClass(Photo)
@TableIndex(name: 'photos_activity', columns: {#activityId})
class Photos extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get activityId =>
      text().references(Activities, #id, onDelete: KeyAction.cascade)();
  TextColumn get filePath => text()();
  TextColumn get thumbnailPath => text().nullable()();
  DateTimeColumn get takenUtc => dateTime()();
  IntColumn get offsetMs => integer().nullable()();
  TextColumn get caption => text().nullable()();
  TextColumn get label => text().nullable()();
  TextColumn get source =>
      text().map(const EnumKeyConverter(PhotoSource.values))();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  IntColumn get bytes => integer().nullable()();
  TextColumn get sha256 => text().nullable()();
  BoolColumn get originalKept => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@UseRowClass(Bookmark)
@TableIndex(name: 'bookmarks_activity', columns: {#activityId})
class Bookmarks extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get activityId =>
      text().references(Activities, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get atUtc => dateTime()();
  IntColumn get offsetMs => integer().nullable()();
  TextColumn get label => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get source =>
      text().map(const EnumKeyConverter(BookmarkSource.values))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@UseRowClass(CutRange)
@TableIndex(name: 'cut_ranges_activity', columns: {#activityId})
class CutRanges extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get activityId =>
      text().references(Activities, #id, onDelete: KeyAction.cascade)();
  IntColumn get startOffsetMs => integer()();
  IntColumn get endOffsetMs => integer()();
  TextColumn get reason => text().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (start_offset_ms >= 0)',
    'CHECK (end_offset_ms > start_offset_ms)',
  ];
}

@UseRowClass(ExportJob)
@TableIndex(name: 'export_jobs_conference', columns: {#conferenceId})
class ExportJobs extends Table with Timestamps {
  TextColumn get id => text()();
  TextColumn get conferenceId =>
      text().references(Conferences, #id, onDelete: KeyAction.cascade)();
  TextColumn get scope => text().map(const JsonMapConverter())();
  TextColumn get destination =>
      text().map(const EnumKeyConverter(ExportDestination.values))();
  TextColumn get format =>
      text().map(const EnumKeyConverter(ExportFormat.values))();
  TextColumn get audioMode =>
      text().map(const EnumKeyConverter(ExportAudioMode.values))();
  TextColumn get state =>
      text().map(const EnumKeyConverter(ExportJobState.values))();
  IntColumn get bytesTotal => integer().nullable()();
  IntColumn get bytesDone => integer()();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  TextColumn get verificationLevel =>
      text().map(const EnumKeyConverter(VerificationLevel.values))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
