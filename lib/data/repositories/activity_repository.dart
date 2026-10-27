import 'package:drift/drift.dart';

import '../../domain/models/activity.dart';
import '../../domain/models/enums.dart';
import '../../domain/services/activity_title.dart';
import '../../domain/services/recording_profile_rules.dart';
import '../local_database/app_database.dart';
import 'repository_support.dart';

/// Activity and activity type storage (BUILD_GUIDE 9.3
/// `ActivityRepository`) [P0-09]. Split and merge arrive with P1-18.
class ActivityRepository {
  ActivityRepository(
    this._db, {
    this._clock = systemUtcClock,
    this._newId = uuidV4,
  });

  final AppDatabase _db;
  final UtcClock _clock;
  final IdGenerator _newId;

  /// Key of the built-in type whose activities are private by default.
  static const reflectionTypeKey = 'personal_reflection';

  // Types (NFR-03, FR-ACT-06).

  Future<List<ActivityType>> types() => (_db.select(
    _db.activityTypes,
  )..orderBy([(t) => OrderingTerm.asc(t.sortOrder)])).get();

  Future<ActivityType?> typeByKey(String key) => (_db.select(
    _db.activityTypes,
  )..where((t) => t.key.equals(key))).getSingleOrNull();

  /// Creates a user-defined type. Its key is derived from [label] and made
  /// unique, so two custom types can share a label.
  Future<ActivityType> createCustomType(String label, {String icon = 'tag'}) =>
      _db.transaction(() async {
        final trimmed = label.trim();
        if (trimmed.isEmpty) {
          throw ArgumentError.value(label, 'label', 'A type needs a label');
        }
        final base = 'custom_${_slug(trimmed)}';
        var key = base;
        for (var n = 2; await typeByKey(key) != null; n++) {
          key = '${base}_$n';
        }
        final maxOrder = _db.activityTypes.sortOrder.max();
        final last = await (_db.selectOnly(
          _db.activityTypes,
        )..addColumns([maxOrder])).map((r) => r.read(maxOrder)).getSingle();
        final now = _clock();
        final id = _newId();
        await _db
            .into(_db.activityTypes)
            .insert(
              ActivityTypesCompanion.insert(
                id: id,
                key: key,
                label: trimmed,
                icon: icon,
                isBuiltin: false,
                sortOrder: (last ?? -1) + 1,
                createdAt: now,
                updatedAt: now,
              ),
            );
        return (await typeByKey(key))!;
      });

  /// Deletes a custom type that no activity uses. Built-in types and types
  /// in use throw [StateError].
  Future<void> deleteCustomType(String typeId) => _db.transaction(() async {
    final type = await (_db.select(
      _db.activityTypes,
    )..where((t) => t.id.equals(typeId))).getSingleOrNull();
    if (type == null) return;
    if (type.isBuiltin) throw StateError('Built-in types cannot be deleted');
    final inUse =
        await (_db.selectOnly(_db.activities)
              ..addColumns([_db.activities.id])
              ..where(_db.activities.typeId.equals(typeId))
              ..limit(1))
            .getSingleOrNull();
    if (inUse != null) throw StateError('Type ${type.label} is in use');
    await (_db.delete(
      _db.activityTypes,
    )..where((t) => t.id.equals(typeId))).go();
  });

  // Activities (FR-ACT-04, FR-ACT-05).

  /// Creates an activity. A blank [title] becomes "{Type} {n}, {HH:mm}" in
  /// the conference timezone (FR-ACT-05), using [at] or now.
  ///
  /// Reflections are private by default (FR-UI-05, FR-EXP-10).
  Future<Activity> create({
    required String conferenceId,
    required String typeId,
    String? title,
    DateTime? at,
    DateTime? plannedStart,
    DateTime? actualStart,
    DateTime? actualEnd,
    List<String> speakerNames = const [],
    String? organisation,
    String? room,
    String? notesMd,
    List<String> tags = const [],
    ActivityStatus status = ActivityStatus.draft,
    RecordingPermissionStatus recordingPermissionStatus =
        RecordingPermissionStatus.unknown,
    RecordingProfile? recordingProfileOverride,
    bool? isPrivate,
    String? contactName,
    String? contactDetails,
    String? followUpText,
  }) => _db.transaction(() async {
    final conference = await (_db.select(
      _db.conferences,
    )..where((c) => c.id.equals(conferenceId))).getSingle();
    final type = await (_db.select(
      _db.activityTypes,
    )..where((t) => t.id.equals(typeId))).getSingle();
    final now = _clock();

    var resolvedTitle = title?.trim() ?? '';
    if (resolvedTitle.isEmpty) {
      final sameType = _db.activities.id.count();
      final count =
          await (_db.selectOnly(_db.activities)
                ..addColumns([sameType])
                ..where(
                  _db.activities.conferenceId.equals(conferenceId) &
                      _db.activities.typeId.equals(typeId),
                ))
              .map((r) => r.read(sameType)!)
              .getSingle();
      resolvedTitle = defaultActivityTitle(
        typeLabel: type.label,
        ordinal: count + 1,
        atUtc: at ?? now,
        timezone: conference.timezone,
      );
    }

    final id = _newId();
    await _db
        .into(_db.activities)
        .insert(
          ActivitiesCompanion.insert(
            id: id,
            conferenceId: conferenceId,
            typeId: typeId,
            title: resolvedTitle,
            speakerNames: speakerNames,
            organisation: Value(organisation),
            room: Value(room),
            notesMd: Value(notesMd),
            tags: tags,
            plannedStart: Value(plannedStart),
            actualStart: Value(actualStart),
            actualEnd: Value(actualEnd),
            status: status,
            recordingPermissionStatus: recordingPermissionStatus,
            recordingProfileOverride: Value(recordingProfileOverride),
            isPrivate: isPrivate ?? type.key == reflectionTypeKey,
            contactName: Value(contactName),
            contactDetails: Value(contactDetails),
            followUpText: Value(followUpText),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (await get(id))!;
  });

  Future<Activity?> get(String id) => (_db.select(
    _db.activities,
  )..where((a) => a.id.equals(id))).getSingleOrNull();

  /// Activities in [status] across all conferences, for crash recovery
  /// (FR-REC-08) [P1-08].
  Future<List<Activity>> listByStatus(ActivityStatus status) => (_db.select(
    _db.activities,
  )..where((a) => a.status.equalsValue(status))).get();

  /// Gets the [ActivitySummary] for [activityId], or null if not found.
  Future<ActivitySummary?> getSummary(String activityId) async {
    final activity = await get(activityId);
    if (activity == null) return null;
    final summaries = await listSummariesForConference(activity.conferenceId);
    return summaries.cast<ActivitySummary?>().firstWhere(
      (s) => s?.activity.id == activityId,
      orElse: () => null,
    );
  }

  /// Activities of a conference in chronological order (FR-ACT-03): by
  /// actual start, else planned start, else creation time.
  Stream<List<Activity>> watchForConference(String conferenceId) =>
      _conferenceActivitiesQuery(conferenceId).watch();

  Future<List<Activity>> listForConference(String conferenceId) =>
      _conferenceActivitiesQuery(conferenceId).get();

  SimpleSelectStatement<$ActivitiesTable, Activity> _conferenceActivitiesQuery(
    String conferenceId,
  ) {
    final a = _db.activities;
    return _db.select(a)
      ..where((t) => t.conferenceId.equals(conferenceId))
      ..orderBy([
        (t) => OrderingTerm.asc(
          coalesce([t.actualStart, t.plannedStart, t.createdAt]),
        ),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);
  }

  /// Watches rich activity summaries for [conferenceId] (FR-ACT-03).
  ///
  /// Activities are sorted chronologically, except any currently recording
  /// activity is elevated to the top of the list.
  Stream<List<ActivitySummary>> watchSummariesForConference(
    String conferenceId,
  ) {
    final mediaCountsQuery = _db.customSelect(
      'SELECT '
      'a.id AS activity_id, '
      '(SELECT COUNT(*) FROM photos p WHERE p.activity_id = a.id) AS photo_count, '
      '(SELECT COALESCE(SUM(p.bytes), 0) FROM photos p WHERE p.activity_id = a.id) AS photo_bytes, '
      '(SELECT COUNT(*) FROM bookmarks b WHERE b.activity_id = a.id) AS bookmark_count, '
      '(SELECT COUNT(*) FROM recording_segments s WHERE s.activity_id = a.id) AS segment_count, '
      '(SELECT COALESCE(SUM(s.duration_ms), 0) FROM recording_segments s WHERE s.activity_id = a.id) AS total_duration_ms, '
      '(SELECT COALESCE(SUM(s.bytes), 0) FROM recording_segments s WHERE s.activity_id = a.id) AS audio_bytes, '
      '(SELECT COUNT(*) FROM recording_segments s WHERE s.activity_id = a.id AND s.state = ?2) AS active_segment_count, '
      '(SELECT s.end_reason FROM recording_segments s WHERE s.activity_id = a.id ORDER BY s.sequence DESC LIMIT 1) AS last_end_reason, '
      '(SELECT COUNT(*) FROM interruptions i WHERE i.activity_id = a.id AND i.end_utc IS NULL) AS active_interruption_count '
      'FROM activities a '
      'WHERE a.conference_id = ?1',
      variables: [
        Variable.withString(conferenceId),
        Variable.withString(SegmentState.writing.key),
      ],
      readsFrom: {
        _db.activities,
        _db.recordingSegments,
        _db.photos,
        _db.bookmarks,
        _db.interruptions,
      },
    );

    return mediaCountsQuery.watch().asyncMap((mediaRows) async {
      return _buildSummaries(conferenceId, mediaRows);
    });
  }

  /// Lists rich activity summaries for [conferenceId] once (FR-ACT-03).
  Future<List<ActivitySummary>> listSummariesForConference(
    String conferenceId,
  ) async {
    final mediaRows = await _db
        .customSelect(
          'SELECT '
          'a.id AS activity_id, '
          '(SELECT COUNT(*) FROM photos p WHERE p.activity_id = a.id) AS photo_count, '
          '(SELECT COALESCE(SUM(p.bytes), 0) FROM photos p WHERE p.activity_id = a.id) AS photo_bytes, '
          '(SELECT COUNT(*) FROM bookmarks b WHERE b.activity_id = a.id) AS bookmark_count, '
          '(SELECT COUNT(*) FROM recording_segments s WHERE s.activity_id = a.id) AS segment_count, '
          '(SELECT COALESCE(SUM(s.duration_ms), 0) FROM recording_segments s WHERE s.activity_id = a.id) AS total_duration_ms, '
          '(SELECT COALESCE(SUM(s.bytes), 0) FROM recording_segments s WHERE s.activity_id = a.id) AS audio_bytes, '
          '(SELECT COUNT(*) FROM recording_segments s WHERE s.activity_id = a.id AND s.state = ?2) AS active_segment_count, '
          '(SELECT s.end_reason FROM recording_segments s WHERE s.activity_id = a.id ORDER BY s.sequence DESC LIMIT 1) AS last_end_reason, '
          '(SELECT COUNT(*) FROM interruptions i WHERE i.activity_id = a.id AND i.end_utc IS NULL) AS active_interruption_count '
          'FROM activities a '
          'WHERE a.conference_id = ?1',
          variables: [
            Variable.withString(conferenceId),
            Variable.withString(SegmentState.writing.key),
          ],
          readsFrom: {
            _db.activities,
            _db.recordingSegments,
            _db.photos,
            _db.bookmarks,
            _db.interruptions,
          },
        )
        .get();

    return _buildSummaries(conferenceId, mediaRows);
  }

  Future<List<ActivitySummary>> _buildSummaries(
    String conferenceId,
    List<QueryRow> mediaRows,
  ) async {
    final activities = await listForConference(conferenceId);
    final conf = await (_db.select(
      _db.conferences,
    )..where((c) => c.id.equals(conferenceId))).getSingleOrNull();
    if (conf == null) return [];

    final typeMap = {for (final t in await types()) t.id: t};
    final mediaMap = {
      for (final r in mediaRows) r.read<String>('activity_id'): r,
    };

    final recording = <ActivitySummary>[];
    final chronological = <ActivitySummary>[];

    for (final a in activities) {
      final type =
          typeMap[a.typeId] ??
          ActivityType(
            id: a.typeId,
            key: 'unknown',
            label: 'Activity',
            icon: 'tag',
            isBuiltin: false,
            sortOrder: 999,
            createdAt: a.createdAt,
            updatedAt: a.updatedAt,
          );
      final profile = effectiveRecordingProfile(
        conferenceDefault: conf.defaultRecordingProfile,
        activityOverride: a.recordingProfileOverride,
      );

      final media = mediaMap[a.id];
      final photoCount = media?.read<int>('photo_count') ?? 0;
      final photoBytes = media?.read<int>('photo_bytes') ?? 0;
      final bookmarkCount = media?.read<int>('bookmark_count') ?? 0;
      final segmentCount = media?.read<int>('segment_count') ?? 0;
      final duration = Duration(
        milliseconds: media?.read<int>('total_duration_ms') ?? 0,
      );
      final audioBytes = media?.read<int>('audio_bytes') ?? 0;
      final activeSegments = media?.read<int>('active_segment_count') ?? 0;
      final lastEndReasonKey = media?.readNullable<String>('last_end_reason');
      final activeInterruptions =
          media?.read<int>('active_interruption_count') ?? 0;

      final StatusPillStatus status;
      final bool hasActiveRecording;
      if (activeSegments > 0) {
        status = StatusPillStatus.recording;
        hasActiveRecording = true;
      } else if (a.status == ActivityStatus.active) {
        if (activeInterruptions > 0) {
          status = StatusPillStatus.interrupted;
          hasActiveRecording = false;
        } else if (lastEndReasonKey == SegmentEndReason.pause.key) {
          status = StatusPillStatus.paused;
          hasActiveRecording = false;
        } else {
          status = StatusPillStatus.recording;
          hasActiveRecording = true;
        }
      } else if (a.status == ActivityStatus.completed || segmentCount > 0) {
        status = StatusPillStatus.saved;
        hasActiveRecording = false;
      } else if (a.status == ActivityStatus.draft) {
        status = a.isPrivate
            ? StatusPillStatus.private
            : StatusPillStatus.draft;
        hasActiveRecording = false;
      } else {
        status = StatusPillStatus.draft;
        hasActiveRecording = false;
      }

      final summary = ActivitySummary(
        activity: a,
        type: type,
        effectiveProfile: profile,
        statusPillStatus: status,
        duration: duration,
        photoCount: photoCount,
        bookmarkCount: bookmarkCount,
        segmentCount: segmentCount,
        audioBytes: audioBytes,
        photoBytes: photoBytes,
        hasActiveRecording: hasActiveRecording,
      );

      if (hasActiveRecording) {
        recording.add(summary);
      } else {
        chronological.add(summary);
      }
    }

    return [...recording, ...chronological];
  }

  /// Applies [changes] and stamps `updated_at`.
  Future<void> update(String id, ActivitiesCompanion changes) =>
      (_db.update(_db.activities)..where((a) => a.id.equals(id))).write(
        changes.copyWith(id: const Value.absent(), updatedAt: Value(_clock())),
      );

  /// Renames an activity (FR-ACT-05: rename any time). Blank is rejected.
  Future<void> rename(String id, String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(title, 'title', 'A title cannot be blank');
    }
    return update(id, ActivitiesCompanion(title: Value(trimmed)));
  }

  /// The profile a new recording of this activity uses (FR-QUAL-02).
  Future<RecordingProfile> effectiveProfile(String activityId) async {
    final activity = (await get(activityId))!;
    final conference = await (_db.select(
      _db.conferences,
    )..where((c) => c.id.equals(activity.conferenceId))).getSingle();
    return effectiveRecordingProfile(
      conferenceDefault: conference.defaultRecordingProfile,
      activityOverride: activity.recordingProfileOverride,
    );
  }

  /// Deletes the activity and, by cascade, its media rows. Files on disk
  /// are not touched here.
  Future<void> delete(String id) =>
      (_db.delete(_db.activities)..where((a) => a.id.equals(id))).go();

  static String _slug(String text) {
    final slug = text
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return slug.isEmpty ? 'type' : slug;
  }
}
