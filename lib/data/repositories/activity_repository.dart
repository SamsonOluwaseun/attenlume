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
    List<String> speakerNames = const [],
    String? organisation,
    String? room,
    List<String> tags = const [],
    RecordingPermissionStatus recordingPermissionStatus =
        RecordingPermissionStatus.unknown,
    RecordingProfile? recordingProfileOverride,
    bool? isPrivate,
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
            tags: tags,
            plannedStart: Value(plannedStart),
            status: ActivityStatus.draft,
            recordingPermissionStatus: recordingPermissionStatus,
            recordingProfileOverride: Value(recordingProfileOverride),
            isPrivate: isPrivate ?? type.key == reflectionTypeKey,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (await get(id))!;
  });

  Future<Activity?> get(String id) => (_db.select(
    _db.activities,
  )..where((a) => a.id.equals(id))).getSingleOrNull();

  /// Activities of a conference in chronological order (FR-ACT-03): by
  /// actual start, else planned start, else creation time.
  Stream<List<Activity>> watchForConference(String conferenceId) {
    final a = _db.activities;
    return (_db.select(a)
          ..where((t) => t.conferenceId.equals(conferenceId))
          ..orderBy([
            (t) => OrderingTerm.asc(
              coalesce([t.actualStart, t.plannedStart, t.createdAt]),
            ),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .watch();
  }

  Future<List<Activity>> listForConference(String conferenceId) =>
      watchForConference(conferenceId).first;

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
