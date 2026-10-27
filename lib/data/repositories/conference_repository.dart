import 'package:drift/drift.dart';

import '../../domain/models/conference.dart';
import '../../domain/models/enums.dart';
import '../local_database/app_database.dart';
import 'repository_support.dart';
import 'settings_repository.dart';

/// Conference and goal storage (BUILD_GUIDE 9.3 `ConferenceRepository`)
/// [P0-09].
///
/// Deleting here removes database rows only. Removing media files is a
/// separate, user-confirmed step (NFR-07, FR-CONF-08).
class ConferenceRepository {
  ConferenceRepository(
    this._db, {
    this._clock = systemUtcClock,
    this._newId = uuidV4,
  }) : _settings = SettingsRepository(_db);

  final AppDatabase _db;
  final UtcClock _clock;
  final IdGenerator _newId;
  final SettingsRepository _settings;

  /// Creates a conference. Only [name] and [timezone] are needed
  /// (FR-CONF-01, FR-CONF-02).
  ///
  /// The recording profile is copied from the global default unless given
  /// (FR-QUAL-02).
  Future<Conference> create({
    required String name,
    required String timezone,
    String? description,
    String? venue,
    DateTime? startDate,
    DateTime? endDate,
    RoleType? roleType,
    String? roleText,
    List<RequestedOutput> requestedOutputs = const [],
    RecordingProfile? defaultRecordingProfile,
    DateTime? policyAcknowledgedAt,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'A conference needs a name');
    }
    final profile =
        defaultRecordingProfile ??
        await _settings.globalDefaultRecordingProfile();
    final now = _clock();
    final id = _newId();
    await _db
        .into(_db.conferences)
        .insert(
          ConferencesCompanion.insert(
            id: id,
            name: trimmed,
            description: Value(description),
            venue: Value(venue),
            startDate: Value(startDate),
            endDate: Value(endDate),
            timezone: timezone,
            roleType: Value(roleType),
            roleText: Value(roleText),
            requestedOutputs: requestedOutputs,
            defaultRecordingProfile: profile,
            policyAcknowledgedAt: Value(policyAcknowledgedAt),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (await get(id))!;
  }

  Future<Conference?> get(String id) => (_db.select(
    _db.conferences,
  )..where((c) => c.id.equals(id))).getSingleOrNull();

  /// All conferences, newest start date first (FR-CONF-08).
  Future<List<Conference>> getAll({bool includeArchived = false}) {
    final query = _db.select(_db.conferences);
    if (!includeArchived) query.where((c) => c.archivedAt.isNull());
    query.orderBy([
      (c) => OrderingTerm(
        expression: c.startDate,
        mode: OrderingMode.desc,
        nulls: NullsOrder.last,
      ),
      (c) => OrderingTerm.desc(c.createdAt),
    ]);
    return query.get();
  }

  /// Recent conferences, newest first (FR-CONF-01).
  Future<List<Conference>> getRecent({
    int limit = 5,
    bool includeArchived = false,
  }) {
    final query = _db.select(_db.conferences);
    if (!includeArchived) query.where((c) => c.archivedAt.isNull());
    query.orderBy([
      (c) => OrderingTerm(
        expression: c.startDate,
        mode: OrderingMode.desc,
        nulls: NullsOrder.last,
      ),
      (c) => OrderingTerm.desc(c.createdAt),
    ]);
    query.limit(limit);
    return query.get();
  }

  /// Conferences, newest start date first. Archived ones are hidden unless
  /// [includeArchived] (NFR-02 keeps them accessible).
  Stream<List<Conference>> watchAll({bool includeArchived = false}) {
    final query = _db.select(_db.conferences);
    if (!includeArchived) query.where((c) => c.archivedAt.isNull());
    query.orderBy([
      (c) => OrderingTerm(
        expression: c.startDate,
        mode: OrderingMode.desc,
        nulls: NullsOrder.last,
      ),
      (c) => OrderingTerm.desc(c.createdAt),
    ]);
    return query.watch();
  }

  /// Applies [changes] and stamps `updated_at` (FR-CONF-08: edit any field).
  ///
  /// Use [changeDefaultRecordingProfile] for the profile.
  Future<void> update(String id, ConferencesCompanion changes) async {
    if (changes.defaultRecordingProfile.present) {
      throw ArgumentError('Use changeDefaultRecordingProfile');
    }
    await (_db.update(_db.conferences)..where((c) => c.id.equals(id))).write(
      changes.copyWith(id: const Value.absent(), updatedAt: Value(_clock())),
    );
  }

  /// Changes the conference default for new activities only (FR-QUAL-03).
  ///
  /// Existing activities that inherited the old default are pinned to it.
  /// With [includeUnrecordedActivities] (after the user confirms a bulk
  /// change), inheriting activities with no segments follow the new default
  /// instead. Explicit activity overrides are never touched.
  Future<void> changeDefaultRecordingProfile(
    String id,
    RecordingProfile profile, {
    bool includeUnrecordedActivities = false,
  }) => _db.transaction(() async {
    final conference = await get(id);
    if (conference == null) throw StateError('No conference $id');
    final old = conference.defaultRecordingProfile;
    if (old == profile) return;
    final now = _clock();

    final inheriting =
        await (_db.select(_db.activities)..where(
              (a) =>
                  a.conferenceId.equals(id) &
                  a.recordingProfileOverride.isNull(),
            ))
            .get();
    for (final activity in inheriting) {
      if (includeUnrecordedActivities && !await _hasSegments(activity.id)) {
        continue;
      }
      await (_db.update(
        _db.activities,
      )..where((a) => a.id.equals(activity.id))).write(
        ActivitiesCompanion(
          recordingProfileOverride: Value(old),
          updatedAt: Value(now),
        ),
      );
    }
    await (_db.update(_db.conferences)..where((c) => c.id.equals(id))).write(
      ConferencesCompanion(
        defaultRecordingProfile: Value(profile),
        updatedAt: Value(now),
      ),
    );
  });

  Future<bool> _hasSegments(String activityId) async {
    final row =
        await (_db.selectOnly(_db.recordingSegments)
              ..addColumns([_db.recordingSegments.id])
              ..where(_db.recordingSegments.activityId.equals(activityId))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  /// Records the recording policy acknowledgement (FR-CONF-06).
  Future<void> acknowledgePolicy(String id) =>
      update(id, ConferencesCompanion(policyAcknowledgedAt: Value(_clock())));

  Future<void> archive(String id) =>
      update(id, ConferencesCompanion(archivedAt: Value(_clock())));

  Future<void> unarchive(String id) =>
      update(id, const ConferencesCompanion(archivedAt: Value(null)));

  /// Counts what [delete] would remove, for the confirmation (FR-CONF-08).
  Future<ConferenceDeletionSummary> deletionSummary(String id) async {
    final row = await _db
        .customSelect(
          'SELECT '
          '(SELECT COUNT(*) FROM activities a WHERE a.conference_id = ?1) '
          '  AS activities, '
          '(SELECT COUNT(*) FROM recording_segments s '
          '  JOIN activities a ON a.id = s.activity_id '
          '  WHERE a.conference_id = ?1) AS segments, '
          '(SELECT COALESCE(SUM(s.bytes), 0) FROM recording_segments s '
          '  JOIN activities a ON a.id = s.activity_id '
          '  WHERE a.conference_id = ?1) AS audio_bytes, '
          '(SELECT COUNT(*) FROM photos p '
          '  JOIN activities a ON a.id = p.activity_id '
          '  WHERE a.conference_id = ?1) AS photos, '
          '(SELECT COALESCE(SUM(p.bytes), 0) FROM photos p '
          '  JOIN activities a ON a.id = p.activity_id '
          '  WHERE a.conference_id = ?1) AS photo_bytes, '
          '(SELECT COUNT(*) FROM bookmarks b '
          '  JOIN activities a ON a.id = b.activity_id '
          '  WHERE a.conference_id = ?1) AS bookmarks',
          variables: [Variable.withString(id)],
          readsFrom: {
            _db.activities,
            _db.recordingSegments,
            _db.photos,
            _db.bookmarks,
          },
        )
        .getSingle();
    return ConferenceDeletionSummary(
      activities: row.read<int>('activities'),
      segments: row.read<int>('segments'),
      photos: row.read<int>('photos'),
      bookmarks: row.read<int>('bookmarks'),
      audioBytes: row.read<int>('audio_bytes'),
      photoBytes: row.read<int>('photo_bytes'),
    );
  }

  /// Deletes the conference and, by cascade, its goals, activities, media
  /// rows and export jobs. Files on disk are not touched here.
  Future<void> delete(String id) =>
      (_db.delete(_db.conferences)..where((c) => c.id.equals(id))).go();

  // Goals (FR-CONF-04).

  /// Adds a goal at the end. [priority] 1 to 3 marks a priority goal.
  Future<Goal> addGoal(String conferenceId, String text, {int? priority}) =>
      _db.transaction(() async {
        if (priority != null && (priority < 1 || priority > 3)) {
          throw RangeError.range(priority, 1, 3, 'priority');
        }
        final maxOrder = _db.goals.sortOrder.max();
        final last =
            await (_db.selectOnly(_db.goals)
                  ..addColumns([maxOrder])
                  ..where(_db.goals.conferenceId.equals(conferenceId)))
                .map((r) => r.read(maxOrder))
                .getSingle();
        final now = _clock();
        final id = _newId();
        await _db
            .into(_db.goals)
            .insert(
              GoalsCompanion.insert(
                id: id,
                conferenceId: conferenceId,
                goalText: text.trim(),
                priority: Value(priority),
                sortOrder: (last ?? -1) + 1,
                createdAt: now,
                updatedAt: now,
              ),
            );
        return (_db.select(
          _db.goals,
        )..where((g) => g.id.equals(id))).getSingle();
      });

  /// Goals in display order: priority goals first, then extras.
  Future<List<Goal>> goalsFor(String conferenceId) =>
      (_db.select(_db.goals)
            ..where((g) => g.conferenceId.equals(conferenceId))
            ..orderBy([
              (g) =>
                  OrderingTerm(expression: g.priority, nulls: NullsOrder.last),
              (g) => OrderingTerm.asc(g.sortOrder),
            ]))
          .get();

  Future<void> updateGoal(String id, {String? text, Value<int?>? priority}) =>
      (_db.update(_db.goals)..where((g) => g.id.equals(id))).write(
        GoalsCompanion(
          goalText: text == null ? const Value.absent() : Value(text.trim()),
          priority: priority ?? const Value.absent(),
          updatedAt: Value(_clock()),
        ),
      );

  Future<void> deleteGoal(String id) =>
      (_db.delete(_db.goals)..where((g) => g.id.equals(id))).go();
}
