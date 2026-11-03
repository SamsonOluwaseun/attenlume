import 'package:drift/drift.dart';

import '../../domain/models/planned_session.dart';
import '../../domain/services/agenda_parser.dart';
import '../local_database/app_database.dart';
import 'repository_support.dart';

/// Storage for a conference's imported agenda (ADR-082) [P2-07].
///
/// Planned sessions are not activities and hold no media, so deleting them
/// never touches recordings or photos.
class PlannedSessionRepository {
  PlannedSessionRepository(
    this._db, {
    this._clock = systemUtcClock,
    this._newId = uuidV4,
  });

  final AppDatabase _db;
  final UtcClock _clock;
  final IdGenerator _newId;

  /// The conference's planned sessions in time order.
  Future<List<PlannedSession>> listFor(String conferenceId) =>
      (_db.select(_db.plannedSessions)
            ..where((p) => p.conferenceId.equals(conferenceId))
            ..orderBy([
              (p) => OrderingTerm.asc(p.startUtc),
              (p) => OrderingTerm.asc(p.title),
            ]))
          .get();

  Future<int> countFor(String conferenceId) async {
    final count = _db.plannedSessions.id.count();
    return (_db.selectOnly(_db.plannedSessions)
          ..addColumns([count])
          ..where(_db.plannedSessions.conferenceId.equals(conferenceId)))
        .map((r) => r.read(count)!)
        .getSingle();
  }

  /// Saves [entries] to the conference's agenda in one transaction and
  /// returns how many were saved. Callers drop duplicates first
  /// ([AgendaImportPreview.toSave]).
  Future<int> addAll(
    String conferenceId,
    List<AgendaEntry> entries, {
    required AgendaSource source,
  }) => _db.transaction(() async {
    final now = _clock();
    await _db.batch((b) {
      for (final e in entries) {
        b.insert(
          _db.plannedSessions,
          PlannedSessionsCompanion.insert(
            id: _newId(),
            conferenceId: conferenceId,
            title: e.title,
            speakerNames: e.speakerNames,
            room: Value(e.room),
            typeText: Value(e.typeText),
            description: Value(e.description),
            startUtc: e.startUtc,
            endUtc: Value(e.endUtc),
            allDay: e.allDay,
            source: source,
            sourceUid: Value(e.uid),
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
    });
    return entries.length;
  });

  Future<void> delete(String id) =>
      (_db.delete(_db.plannedSessions)..where((p) => p.id.equals(id))).go();

  /// Removes the whole agenda of a conference. Activities started from it
  /// keep their details.
  Future<int> deleteAllFor(String conferenceId) => (_db.delete(
    _db.plannedSessions,
  )..where((p) => p.conferenceId.equals(conferenceId))).go();
}
