import 'package:drift/drift.dart';

import '../../domain/models/media.dart';
import '../local_database/app_database.dart';
import 'repository_support.dart';

/// Non-destructive cut ranges with undo (FR-REV-04, NFR-07) [P0-09].
///
/// Removing a range only sets `deleted_at`, so [restore] can undo it.
class CutRangeRepository {
  CutRangeRepository(
    this._db, {
    this._clock = systemUtcClock,
    this._newId = uuidV4,
  });

  final AppDatabase _db;
  final UtcClock _clock;
  final IdGenerator _newId;

  Future<CutRange> add(
    String activityId, {
    required int startOffsetMs,
    required int endOffsetMs,
    String? reason,
  }) async {
    if (startOffsetMs < 0 || endOffsetMs <= startOffsetMs) {
      throw ArgumentError(
        'A cut range needs 0 <= start < end, '
        'got $startOffsetMs to $endOffsetMs',
      );
    }
    final now = _clock();
    final id = _newId();
    await _db
        .into(_db.cutRanges)
        .insert(
          CutRangesCompanion.insert(
            id: id,
            activityId: activityId,
            startOffsetMs: startOffsetMs,
            endOffsetMs: endOffsetMs,
            reason: Value(reason),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (_db.select(
      _db.cutRanges,
    )..where((c) => c.id.equals(id))).getSingle();
  }

  /// Soft-deletes a range.
  Future<void> remove(String id) {
    final now = _clock();
    return (_db.update(_db.cutRanges)..where((c) => c.id.equals(id))).write(
      CutRangesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  /// Undoes [remove].
  Future<void> restore(String id) =>
      (_db.update(_db.cutRanges)..where((c) => c.id.equals(id))).write(
        CutRangesCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(_clock()),
        ),
      );

  /// The latest time any range of [activityId] was added, changed,
  /// removed or restored, soft-deleted ranges included; null when it has
  /// none (FR-STO-06, ADR-047) [P1-20].
  Future<DateTime?> lastChangeFor(String activityId) async {
    final rows = await (_db.select(
      _db.cutRanges,
    )..where((c) => c.activityId.equals(activityId))).get();
    DateTime? last;
    for (final r in rows) {
      for (final t in [r.createdAt, r.updatedAt, r.deletedAt].nonNulls) {
        if (last == null || t.isAfter(last)) last = t;
      }
    }
    return last;
  }

  /// Ranges in effect, in timeline order.
  Future<List<CutRange>> activeFor(String activityId) =>
      (_db.select(_db.cutRanges)
            ..where(
              (c) => c.activityId.equals(activityId) & c.deletedAt.isNull(),
            )
            ..orderBy([(c) => OrderingTerm.asc(c.startOffsetMs)]))
          .get();
}
