import 'package:drift/drift.dart';

import '../../domain/models/enums.dart';
import '../../domain/models/media.dart';
import '../../domain/services/timeline_offset.dart';
import '../local_database/app_database.dart';
import 'repository_support.dart';

/// Segments, interruptions, photos and bookmarks (BUILD_GUIDE 9.3
/// `MediaAssetRepository`) [P0-09].
///
/// Offsets follow the 9.4 offset rule (see [timelineOffsetMs]). Rows are
/// written before any audio, so a crash leaves a `writing` row that
/// recovery can reconcile (FR-REC-01, FR-REC-08).
class MediaAssetRepository {
  MediaAssetRepository(
    this._db, {
    this._clock = systemUtcClock,
    this._newId = uuidV4,
  });

  final AppDatabase _db;
  final UtcClock _clock;
  final IdGenerator _newId;

  // Segments (FR-REC-03, FR-QUAL-06).

  /// Adds the next segment of an activity in state `writing`.
  ///
  /// The first segment also sets the activity's actual start and fills in
  /// offsets for photos and bookmarks added before recording began.
  Future<RecordingSegment> startSegment({
    required String activityId,
    required String filePath,
    required RecordingProfile requestedProfile,
    required String codec,
    required String container,
    required int channelCount,
    required int sampleRateHz,
    required int requestedBitrateBps,
    String? inputRoute,
    DateTime? startUtc,
  }) => _db.transaction(() async {
    final start = (startUtc ?? _clock()).toUtc();
    final sequence = await nextSegmentSequence(activityId);
    final now = _clock();
    final id = _newId();
    await _db
        .into(_db.recordingSegments)
        .insert(
          RecordingSegmentsCompanion.insert(
            id: id,
            activityId: activityId,
            sequence: sequence,
            filePath: filePath,
            state: SegmentState.writing,
            requestedProfile: requestedProfile,
            codec: codec,
            container: container,
            channelCount: channelCount,
            sampleRateHz: sampleRateHz,
            requestedBitrateBps: requestedBitrateBps,
            inputRoute: Value(inputRoute),
            startUtc: start,
            createdAt: now,
            updatedAt: now,
          ),
        );
    if (sequence == 1) await _onFirstSegment(activityId, start, now);
    return _segment(id);
  });

  Future<void> _onFirstSegment(
    String activityId,
    DateTime start,
    DateTime now,
  ) async {
    await (_db.update(
      _db.activities,
    )..where((a) => a.id.equals(activityId) & a.actualStart.isNull())).write(
      ActivitiesCompanion(actualStart: Value(start), updatedAt: Value(now)),
    );
    final photos =
        await (_db.select(_db.photos)..where(
              (p) => p.activityId.equals(activityId) & p.offsetMs.isNull(),
            ))
            .get();
    for (final p in photos) {
      await (_db.update(_db.photos)..where((t) => t.id.equals(p.id))).write(
        PhotosCompanion(
          offsetMs: Value(
            timelineOffsetMs(eventUtc: p.takenUtc, firstSegmentStartUtc: start),
          ),
          updatedAt: Value(now),
        ),
      );
    }
    final bookmarks =
        await (_db.select(_db.bookmarks)..where(
              (b) => b.activityId.equals(activityId) & b.offsetMs.isNull(),
            ))
            .get();
    for (final b in bookmarks) {
      await (_db.update(_db.bookmarks)..where((t) => t.id.equals(b.id))).write(
        BookmarksCompanion(
          offsetMs: Value(
            timelineOffsetMs(eventUtc: b.atUtc, firstSegmentStartUtc: start),
          ),
          updatedAt: Value(now),
        ),
      );
    }
  }

  /// The sequence [startSegment] will give the next segment of an
  /// activity, so callers can name its file first [P1-04].
  Future<int> nextSegmentSequence(String activityId) async {
    final maxSeq = _db.recordingSegments.sequence.max();
    final last =
        await (_db.selectOnly(_db.recordingSegments)
              ..addColumns([maxSeq])
              ..where(_db.recordingSegments.activityId.equals(activityId)))
            .map((r) => r.read(maxSeq))
            .getSingle();
    return (last ?? 0) + 1;
  }

  /// Marks a segment finished with what was actually written.
  ///
  /// Format fields left null keep the values requested at start. Pass the
  /// ones read from the finished file (FR-QUAL-06). Pass [filePath] when
  /// the file was renamed on finalisation (P1-05).
  Future<RecordingSegment> finaliseSegment(
    String id, {
    required DateTime endUtc,
    required SegmentEndReason endReason,
    String? filePath,
    int? durationMs,
    int? bytes,
    String? sha256,
    int? observedBitrateBps,
    String? codec,
    String? container,
    int? channelCount,
    int? sampleRateHz,
    SegmentState state = SegmentState.finalised,
  }) async {
    await (_db.update(
      _db.recordingSegments,
    )..where((s) => s.id.equals(id))).write(
      RecordingSegmentsCompanion(
        state: Value(state),
        filePath: Value.absentIfNull(filePath),
        endUtc: Value(endUtc.toUtc()),
        endReason: Value(endReason),
        durationMs: Value(durationMs),
        bytes: Value(bytes),
        sha256: Value(sha256),
        observedBitrateBps: Value(observedBitrateBps),
        codec: Value.absentIfNull(codec),
        container: Value.absentIfNull(container),
        channelCount: Value.absentIfNull(channelCount),
        sampleRateHz: Value.absentIfNull(sampleRateHz),
        updatedAt: Value(_clock()),
      ),
    );
    return _segment(id);
  }

  /// Sets a segment's state, for crash recovery (FR-REC-08).
  Future<void> setSegmentState(String id, SegmentState state) =>
      (_db.update(_db.recordingSegments)..where((s) => s.id.equals(id))).write(
        RecordingSegmentsCompanion(
          state: Value(state),
          updatedAt: Value(_clock()),
        ),
      );

  /// Swaps segments for the trimmed files written from them, in one
  /// transaction (FR-REV-06, ADR-037) [P1-19].
  ///
  /// Rows in [replacedIds] are deleted (their files are not touched) and
  /// [added] are inserted. Sequences are renumbered by start time. When the
  /// first segment now starts later, stored photo, bookmark and cut offsets
  /// move back by the same amount, so everything keeps its wall-clock place
  /// (BUILD_GUIDE 9.4). Returns the inserted rows.
  Future<List<RecordingSegment>> replaceWithTrimmed(
    String activityId, {
    required Set<String> replacedIds,
    required List<TrimmedSegment> added,
  }) => _db.transaction(() async {
    final now = _clock();
    final before = await segmentsFor(activityId);
    if (before.any((s) => s.state == SegmentState.writing)) {
      throw StateError('Stop the recording before trimming it');
    }
    DateTime? originOf(Iterable<RecordingSegment> rows) => rows.isEmpty
        ? null
        : rows.map((s) => s.startUtc).reduce((a, b) => a.isBefore(b) ? a : b);
    final oldOrigin = originOf(before);

    await (_db.delete(
      _db.recordingSegments,
    )..where((s) => s.id.isIn(replacedIds))).go();
    var temp = 1000000;
    for (final t in added) {
      final s = t.source;
      await _db
          .into(_db.recordingSegments)
          .insert(
            RecordingSegmentsCompanion.insert(
              id: t.id,
              activityId: activityId,
              sequence: temp++,
              filePath: t.filePath,
              state: s.state,
              requestedProfile: s.requestedProfile,
              codec: s.codec,
              container: s.container,
              channelCount: s.channelCount,
              sampleRateHz: s.sampleRateHz,
              requestedBitrateBps: s.requestedBitrateBps,
              observedBitrateBps: Value(t.observedBitrateBps),
              inputRoute: Value(s.inputRoute),
              startUtc: t.startUtc.toUtc(),
              endUtc: Value(
                t.startUtc.toUtc().add(Duration(milliseconds: t.durationMs)),
              ),
              durationMs: Value(t.durationMs),
              bytes: Value(t.bytes),
              sha256: Value(t.sha256),
              endReason: Value(s.endReason),
              createdAt: now,
              updatedAt: now,
            ),
          );
    }

    // Renumber in two passes so the unique (activity, sequence) key holds.
    final rows = await segmentsFor(activityId)
      ..sort((a, b) {
        final byStart = a.startUtc.compareTo(b.startUtc);
        return byStart != 0 ? byStart : a.sequence.compareTo(b.sequence);
      });
    for (final first in const [2000000, 1]) {
      for (var k = 0; k < rows.length; k++) {
        await (_db.update(
          _db.recordingSegments,
        )..where((s) => s.id.equals(rows[k].id))).write(
          RecordingSegmentsCompanion(
            sequence: Value(first + k),
            updatedAt: Value(now),
          ),
        );
      }
    }

    final newOrigin = originOf(rows);
    final shift = oldOrigin == null || newOrigin == null
        ? 0
        : newOrigin.difference(oldOrigin).inMilliseconds;
    if (shift != 0) await _shiftOffsets(activityId, shift, now);

    final ids = {for (final t in added) t.id};
    return [
      for (final s in await segmentsFor(activityId))
        if (ids.contains(s.id)) s,
    ];
  });

  Future<void> _shiftOffsets(String activityId, int shift, DateTime now) async {
    final photos = await (_db.select(
      _db.photos,
    )..where((p) => p.activityId.equals(activityId))).get();
    for (final p in photos) {
      if (p.offsetMs == null) continue;
      await (_db.update(_db.photos)..where((r) => r.id.equals(p.id))).write(
        PhotosCompanion(
          offsetMs: Value(p.offsetMs! - shift),
          updatedAt: Value(now),
        ),
      );
    }
    final bookmarks = await (_db.select(
      _db.bookmarks,
    )..where((b) => b.activityId.equals(activityId))).get();
    for (final b in bookmarks) {
      if (b.offsetMs == null) continue;
      await (_db.update(_db.bookmarks)..where((r) => r.id.equals(b.id))).write(
        BookmarksCompanion(
          offsetMs: Value(b.offsetMs! - shift),
          updatedAt: Value(now),
        ),
      );
    }
    final cuts = await (_db.select(
      _db.cutRanges,
    )..where((c) => c.activityId.equals(activityId))).get();
    for (final c in cuts) {
      final start = c.startOffsetMs - shift;
      final end = c.endOffsetMs - shift;
      await (_db.update(_db.cutRanges)..where((r) => r.id.equals(c.id))).write(
        end <= 0
            // Wholly before the new start: it hides nothing now.
            ? CutRangesCompanion(
                deletedAt: Value(c.deletedAt ?? now),
                updatedAt: Value(now),
              )
            : CutRangesCompanion(
                startOffsetMs: Value(start < 0 ? 0 : start),
                endOffsetMs: Value(end),
                updatedAt: Value(now),
              ),
      );
    }
  }

  Future<List<RecordingSegment>> segmentsFor(String activityId) =>
      (_db.select(_db.recordingSegments)
            ..where((s) => s.activityId.equals(activityId))
            ..orderBy([(s) => OrderingTerm.asc(s.sequence)]))
          .get();

  /// Segments still `writing`, across all activities (FR-REC-08).
  Future<List<RecordingSegment>> unfinalisedSegments() => (_db.select(
    _db.recordingSegments,
  )..where((s) => s.state.equalsValue(SegmentState.writing))).get();

  /// Every stored segment path, to find audio files no row names
  /// (FR-REC-08) [P1-08].
  Future<Set<String>> segmentPaths() async {
    final path = _db.recordingSegments.filePath;
    final rows = await (_db.selectOnly(
      _db.recordingSegments,
    )..addColumns([path])).map((r) => r.read(path)!).get();
    return rows.toSet();
  }

  Future<DateTime?> firstSegmentStart(String activityId) async {
    final first =
        await (_db.select(_db.recordingSegments)
              ..where((s) => s.activityId.equals(activityId))
              ..orderBy([(s) => OrderingTerm.asc(s.sequence)])
              ..limit(1))
            .getSingleOrNull();
    return first?.startUtc;
  }

  Future<RecordingSegment> _segment(String id) => (_db.select(
    _db.recordingSegments,
  )..where((s) => s.id.equals(id))).getSingle();

  // Interruptions (FR-REC-05).

  Future<Interruption> startInterruption(
    String activityId,
    InterruptionReason reason, {
    DateTime? startUtc,
  }) async {
    final now = _clock();
    final id = _newId();
    await _db
        .into(_db.interruptions)
        .insert(
          InterruptionsCompanion.insert(
            id: id,
            activityId: activityId,
            reason: reason,
            startUtc: (startUtc ?? now).toUtc(),
            autoResumed: false,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (_db.select(
      _db.interruptions,
    )..where((i) => i.id.equals(id))).getSingle();
  }

  Future<void> endInterruption(
    String id, {
    required bool autoResumed,
    DateTime? endUtc,
  }) => (_db.update(_db.interruptions)..where((i) => i.id.equals(id))).write(
    InterruptionsCompanion(
      endUtc: Value((endUtc ?? _clock()).toUtc()),
      autoResumed: Value(autoResumed),
      updatedAt: Value(_clock()),
    ),
  );

  /// Interruptions with no end, across all activities (FR-REC-08) [P1-08].
  Future<List<Interruption>> openInterruptions() =>
      (_db.select(_db.interruptions)..where((i) => i.endUtc.isNull())).get();

  Future<List<Interruption>> interruptionsFor(String activityId) =>
      (_db.select(_db.interruptions)
            ..where((i) => i.activityId.equals(activityId))
            ..orderBy([(i) => OrderingTerm.asc(i.startUtc)]))
          .get();

  // Photos (FR-PHO-01, FR-PHO-06).

  /// [id] lets the caller name the file after the row before the row
  /// exists (`photos/<photo_id>.jpg`).
  Future<Photo> addPhoto({
    String? id,
    required String activityId,
    required String filePath,
    required DateTime takenUtc,
    required PhotoSource source,
    String? thumbnailPath,
    String? caption,
    String? label,
    int? width,
    int? height,
    int? bytes,
    String? sha256,
    bool originalKept = false,
  }) => _db.transaction(() async {
    final now = _clock();
    final photoId = id ?? _newId();
    await _db
        .into(_db.photos)
        .insert(
          PhotosCompanion.insert(
            id: photoId,
            activityId: activityId,
            filePath: filePath,
            thumbnailPath: Value(thumbnailPath),
            takenUtc: takenUtc.toUtc(),
            offsetMs: Value(
              timelineOffsetMs(
                eventUtc: takenUtc,
                firstSegmentStartUtc: await firstSegmentStart(activityId),
              ),
            ),
            caption: Value(caption),
            label: Value(label),
            source: source,
            width: Value(width),
            height: Value(height),
            bytes: Value(bytes),
            sha256: Value(sha256),
            originalKept: originalKept,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (_db.select(
      _db.photos,
    )..where((p) => p.id.equals(photoId))).getSingle();
  });

  Future<List<Photo>> photosFor(String activityId) =>
      (_db.select(_db.photos)
            ..where((p) => p.activityId.equals(activityId))
            ..orderBy([(p) => OrderingTerm.asc(p.takenUtc)]))
          .get();

  /// Sets a photo's caption and label (FR-PHO-06) [P1-14]. Blank text
  /// clears the field.
  Future<Photo> updatePhotoText(
    String photoId, {
    String? caption,
    String? label,
  }) async {
    String? clean(String? s) =>
        (s == null || s.trim().isEmpty) ? null : s.trim();
    await (_db.update(_db.photos)..where((p) => p.id.equals(photoId))).write(
      PhotosCompanion(
        caption: Value(clean(caption)),
        label: Value(clean(label)),
        updatedAt: Value(_clock()),
      ),
    );
    return (_db.select(
      _db.photos,
    )..where((p) => p.id.equals(photoId))).getSingle();
  }

  // Bookmarks (FR-BMK-01).

  Future<Bookmark> addBookmark({
    required String activityId,
    required BookmarkSource source,
    DateTime? atUtc,
    String? label,
    String? note,
  }) => _db.transaction(() async {
    final now = _clock();
    final at = (atUtc ?? now).toUtc();
    final id = _newId();
    await _db
        .into(_db.bookmarks)
        .insert(
          BookmarksCompanion.insert(
            id: id,
            activityId: activityId,
            atUtc: at,
            offsetMs: Value(
              timelineOffsetMs(
                eventUtc: at,
                firstSegmentStartUtc: await firstSegmentStart(activityId),
              ),
            ),
            label: Value(label),
            note: Value(note),
            source: source,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (_db.select(
      _db.bookmarks,
    )..where((b) => b.id.equals(id))).getSingle();
  });

  Future<List<Bookmark>> bookmarksFor(String activityId) =>
      (_db.select(_db.bookmarks)
            ..where((b) => b.activityId.equals(activityId))
            ..orderBy([(b) => OrderingTerm.asc(b.atUtc)]))
          .get();

  /// Sets a bookmark's label and note (FR-BMK-01) [P1-16]. Blank text
  /// clears the field. Time and offset never change.
  Future<Bookmark> updateBookmarkText(
    String bookmarkId, {
    String? label,
    String? note,
  }) async {
    String? clean(String? s) =>
        (s == null || s.trim().isEmpty) ? null : s.trim();
    await (_db.update(
      _db.bookmarks,
    )..where((b) => b.id.equals(bookmarkId))).write(
      BookmarksCompanion(
        label: Value(clean(label)),
        note: Value(clean(note)),
        updatedAt: Value(_clock()),
      ),
    );
    return (_db.select(
      _db.bookmarks,
    )..where((b) => b.id.equals(bookmarkId))).getSingle();
  }

  /// Removes one bookmark [P1-16]. Audio and photos are not touched.
  Future<void> deleteBookmark(String bookmarkId) =>
      (_db.delete(_db.bookmarks)..where((b) => b.id.equals(bookmarkId))).go();

  /// Every file a segment or photo row names (audio, photo and thumbnail),
  /// leaving out the rows of [excludingActivities] (ADR-036, FR-STO-06)
  /// [P1-20]. A file in this set must not be deleted.
  Future<Set<String>> namedFilePaths({
    Iterable<String> excludingActivities = const [],
  }) async {
    final excluded = excludingActivities.toList();
    final segPath = _db.recordingSegments.filePath;
    final segQuery = _db.selectOnly(_db.recordingSegments)
      ..addColumns([segPath]);
    final photoPath = _db.photos.filePath;
    final thumbPath = _db.photos.thumbnailPath;
    final photoQuery = _db.selectOnly(_db.photos)
      ..addColumns([photoPath, thumbPath]);
    if (excluded.isNotEmpty) {
      segQuery.where(_db.recordingSegments.activityId.isNotIn(excluded));
      photoQuery.where(_db.photos.activityId.isNotIn(excluded));
    }
    final named = <String>{
      ...await segQuery.map((r) => r.read(segPath)!).get(),
    };
    for (final row in await photoQuery.get()) {
      named.add(row.read(photoPath)!);
      final thumb = row.read(thumbPath);
      if (thumb != null) named.add(thumb);
    }
    return named;
  }

  /// Every segment id, to find waveform summaries whose segment is gone
  /// (ADR-034, FR-STO-06) [P1-20].
  Future<Set<String>> segmentIds() async {
    final id = _db.recordingSegments.id;
    final rows = await (_db.selectOnly(
      _db.recordingSegments,
    )..addColumns([id])).map((r) => r.read(id)!).get();
    return rows.toSet();
  }
}

/// A file written by a permanent trim from part of [source] (FR-REV-06)
/// [P1-19]. Format fields and the end reason come from [source].
class TrimmedSegment {
  const TrimmedSegment({
    required this.id,
    required this.source,
    required this.filePath,
    required this.startUtc,
    required this.durationMs,
    required this.bytes,
    required this.sha256,
    required this.observedBitrateBps,
  });

  final String id;
  final RecordingSegment source;
  final String filePath;
  final DateTime startUtc;
  final int durationMs;
  final int bytes;
  final String sha256;
  final int observedBitrateBps;
}
