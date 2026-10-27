import 'package:drift/drift.dart';

import '../../domain/models/enums.dart';
import '../../domain/models/export_job.dart';
import '../local_database/app_database.dart';
import 'repository_support.dart';

/// Export job records (BUILD_GUIDE 9.4 `export_jobs`) [P0-09]. The export
/// itself is P1-21.
class ExportJobRepository {
  ExportJobRepository(
    this._db, {
    this._clock = systemUtcClock,
    this._newId = uuidV4,
  });

  final AppDatabase _db;
  final UtcClock _clock;
  final IdGenerator _newId;

  Future<ExportJob> create({
    required String conferenceId,
    required Map<String, Object?> scope,
    required ExportFormat format,
    required ExportAudioMode audioMode,
    ExportDestination destination = ExportDestination.local,
    int? bytesTotal,
  }) async {
    final now = _clock();
    final id = _newId();
    await _db
        .into(_db.exportJobs)
        .insert(
          ExportJobsCompanion.insert(
            id: id,
            conferenceId: conferenceId,
            scope: scope,
            destination: destination,
            format: format,
            audioMode: audioMode,
            state: ExportJobState.pending,
            bytesTotal: Value(bytesTotal),
            bytesDone: 0,
            verificationLevel: VerificationLevel.none,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (await get(id))!;
  }

  Future<ExportJob?> get(String id) => (_db.select(
    _db.exportJobs,
  )..where((j) => j.id.equals(id))).getSingleOrNull();

  Future<List<ExportJob>> forConference(String conferenceId) =>
      (_db.select(_db.exportJobs)
            ..where((j) => j.conferenceId.equals(conferenceId))
            ..orderBy([(j) => OrderingTerm.desc(j.createdAt)]))
          .get();

  Future<void> markRunning(String id) {
    final now = _clock();
    return _write(
      id,
      ExportJobsCompanion(
        state: const Value(ExportJobState.running),
        startedAt: Value(now),
      ),
    );
  }

  Future<void> reportProgress(String id, int bytesDone) =>
      _write(id, ExportJobsCompanion(bytesDone: Value(bytesDone)));

  Future<void> complete(String id, VerificationLevel verificationLevel) =>
      _write(
        id,
        ExportJobsCompanion(
          state: const Value(ExportJobState.completed),
          completedAt: Value(_clock()),
          verificationLevel: Value(verificationLevel),
        ),
      );

  /// Records a failure. [error] must not contain personal data or secrets.
  Future<void> fail(String id, String error) => _write(
    id,
    ExportJobsCompanion(
      state: const Value(ExportJobState.failed),
      lastError: Value(error),
    ),
  );

  Future<void> cancel(String id) => _write(
    id,
    const ExportJobsCompanion(state: Value(ExportJobState.cancelled)),
  );

  Future<void> _write(String id, ExportJobsCompanion changes) =>
      (_db.update(_db.exportJobs)..where((j) => j.id.equals(id))).write(
        changes.copyWith(updatedAt: Value(_clock())),
      );
}
