import 'package:drift/drift.dart';

import '../../domain/models/activity.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/media.dart';
import '../../domain/services/activity_split_service.dart';
import '../../domain/services/activity_title.dart';
import '../../domain/services/recording_profile_rules.dart';
import '../../domain/services/review_timeline.dart';
import '../../domain/services/timeline_offset.dart';
import '../local_database/app_database.dart';
import 'repository_support.dart';

/// The two activities after [ActivityRepository.split] (FR-REV-05)
/// [P1-18].
class ActivitySplitResult {
  const ActivitySplitResult({
    required this.part1,
    required this.part2,
    required this.segmentMoves,
  });

  final Activity part1;
  final Activity part2;

  /// Segment id in the first part to its id in the second part, for each
  /// segment that moved or was shared. Waveform summaries follow these.
  final Map<String, String> segmentMoves;
}

/// Activity and activity type storage (BUILD_GUIDE 9.3
/// `ActivityRepository`) [P0-09]. Split arrives with P1-18.
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

  /// Splits an activity at [splitOffsetMs] on its timeline into two
  /// activities (FR-REV-05, ADR-036) [P1-18].
  ///
  /// The original keeps everything before the split; a new activity,
  /// [part2Title] or "{title} (Part 2)", gets the rest. Segments wholly
  /// after the split move; bookmarks, photos and interruptions move by
  /// time; cut ranges are divided at the split. No audio is written: a
  /// segment the split falls inside stays with the first part and a second
  /// row for the same file goes to the new activity, each with a cut range
  /// hiding the other part's audio. Offsets in the new activity are
  /// measured from its first segment's start (BUILD_GUIDE 9.4).
  Future<ActivitySplitResult> split(
    String activityId, {
    required int splitOffsetMs,
    String? part2Title,
  }) => _db.transaction(() async {
    final activity = (await get(activityId))!;
    final segments = await (_db.select(
      _db.recordingSegments,
    )..where((s) => s.activityId.equals(activityId))).get();
    if (segments.any((s) => s.state == SegmentState.writing)) {
      throw StateError('Stop the recording before splitting it');
    }
    final timeline = ReviewTimeline.build(segments: segments);
    final cuts = await (_db.select(
      _db.cutRanges,
    )..where((c) => c.activityId.equals(activityId))).get();
    final title = part2Title?.trim();
    final plan = ActivitySplitService.planSplit(
      activity: activity,
      splitOffsetMs: splitOffsetMs,
      totalDurationMs: timeline.endMs,
      newActivityId: _newId(),
      segments: segments,
      bookmarks: const [],
      photos: const [],
      cutRanges: cuts,
      activity2TitleOverride: title == null || title.isEmpty ? null : title,
    );
    final now = _clock();
    final part2Id = plan.activity2Id;
    final firstStart = timeline.segments.first.segment.startUtc;
    int startOf(RecordingSegment s) =>
        s.startUtc.difference(firstStart).inMilliseconds;

    // The new activity's timeline starts at its first segment.
    final shared = plan.segmentToSplit;
    final originMs = shared != null
        ? startOf(shared.originalSegment)
        : plan.activity2Segments.isEmpty
        ? splitOffsetMs
        : startOf(plan.activity2Segments.first.segment);

    await _db
        .into(_db.activities)
        .insert(
          ActivitiesCompanion.insert(
            id: part2Id,
            conferenceId: activity.conferenceId,
            typeId: activity.typeId,
            title: plan.activity2Title,
            speakerNames: const [],
            organisation: Value(activity.organisation),
            room: Value(activity.room),
            tags: activity.tags,
            actualStart: Value(plan.splitUtc),
            actualEnd: Value(activity.actualEnd),
            status: activity.status,
            recordingPermissionStatus: activity.recordingPermissionStatus,
            recordingProfileOverride: Value(activity.recordingProfileOverride),
            isPrivate: activity.isPrivate,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await update(
      activityId,
      ActivitiesCompanion(actualEnd: Value(plan.splitUtc)),
    );

    final moved = <String, String>{};
    var sequence = 1;
    if (shared != null) {
      final s = shared.originalSegment;
      final copyId = _newId();
      await _db
          .into(_db.recordingSegments)
          .insert(
            RecordingSegmentsCompanion.insert(
              id: copyId,
              activityId: part2Id,
              sequence: sequence++,
              filePath: s.filePath,
              state: s.state,
              requestedProfile: s.requestedProfile,
              codec: s.codec,
              container: s.container,
              channelCount: s.channelCount,
              sampleRateHz: s.sampleRateHz,
              requestedBitrateBps: s.requestedBitrateBps,
              observedBitrateBps: Value(s.observedBitrateBps),
              inputRoute: Value(s.inputRoute),
              startUtc: s.startUtc,
              endUtc: Value(s.endUtc),
              durationMs: Value(s.durationMs),
              bytes: Value(s.bytes),
              sha256: Value(s.sha256),
              endReason: Value(s.endReason),
              createdAt: now,
              updatedAt: now,
            ),
          );
      moved[s.id] = copyId;
      final splitInSegment = shared.splitOffsetWithinSegmentMs;
      final segmentEnd = splitInSegment + shared.part2DurationMs;
      await _addCut(
        activityId,
        splitOffsetMs,
        originMs + segmentEnd,
        'Split: the rest is in "${plan.activity2Title}"',
        now,
      );
      await _addCut(
        part2Id,
        0,
        splitInSegment,
        'Split: the start is in "${plan.activity1Title}"',
        now,
      );
    }
    for (final a in plan.activity2Segments) {
      await (_db.update(
        _db.recordingSegments,
      )..where((s) => s.id.equals(a.segment.id))).write(
        RecordingSegmentsCompanion(
          activityId: Value(part2Id),
          sequence: Value(sequence++),
          updatedAt: Value(now),
        ),
      );
      moved[a.segment.id] = a.segment.id;
    }

    for (final c in plan.cutRanges) {
      if (c.targetActivityId != part2Id) {
        await (_db.update(
          _db.cutRanges,
        )..where((r) => r.id.equals(c.sourceCutRangeId))).write(
          CutRangesCompanion(
            endOffsetMs: Value(c.endOffsetMs),
            updatedAt: Value(now),
          ),
        );
        continue;
      }
      // Planned offsets count from the split; move them to the origin.
      final start = c.startOffsetMs + splitOffsetMs - originMs;
      final end = c.endOffsetMs + splitOffsetMs - originMs;
      final crosses = plan.cutRanges.any(
        (o) =>
            o.sourceCutRangeId == c.sourceCutRangeId &&
            o.targetActivityId != part2Id,
      );
      if (end <= 0) {
        if (!crosses) await _deleteCut(c.sourceCutRangeId, now);
        continue;
      }
      if (crosses) {
        await _addCut(part2Id, start < 0 ? 0 : start, end, c.reason, now);
      } else {
        await (_db.update(
          _db.cutRanges,
        )..where((r) => r.id.equals(c.sourceCutRangeId))).write(
          CutRangesCompanion(
            activityId: Value(part2Id),
            startOffsetMs: Value(start < 0 ? 0 : start),
            endOffsetMs: Value(end),
            updatedAt: Value(now),
          ),
        );
      }
    }

    int? effectiveOffset(int? stored, DateTime utc) =>
        stored ??
        timelineOffsetMs(eventUtc: utc, firstSegmentStartUtc: firstStart);
    final bookmarks = await (_db.select(
      _db.bookmarks,
    )..where((b) => b.activityId.equals(activityId))).get();
    for (final b in bookmarks) {
      final offset = effectiveOffset(b.offsetMs, b.atUtc);
      if (offset == null || offset < splitOffsetMs) continue;
      await (_db.update(_db.bookmarks)..where((r) => r.id.equals(b.id))).write(
        BookmarksCompanion(
          activityId: Value(part2Id),
          offsetMs: Value(offset - originMs),
          updatedAt: Value(now),
        ),
      );
    }
    final photos = await (_db.select(
      _db.photos,
    )..where((p) => p.activityId.equals(activityId))).get();
    for (final p in photos) {
      final offset = effectiveOffset(p.offsetMs, p.takenUtc);
      if (offset == null || offset < splitOffsetMs) continue;
      await (_db.update(_db.photos)..where((r) => r.id.equals(p.id))).write(
        PhotosCompanion(
          activityId: Value(part2Id),
          offsetMs: Value(offset - originMs),
          updatedAt: Value(now),
        ),
      );
    }
    final interruptions = await (_db.select(
      _db.interruptions,
    )..where((i) => i.activityId.equals(activityId))).get();
    for (final i in interruptions) {
      if (i.startUtc.isBefore(plan.splitUtc)) continue;
      await (_db.update(
        _db.interruptions,
      )..where((r) => r.id.equals(i.id))).write(
        InterruptionsCompanion(
          activityId: Value(part2Id),
          updatedAt: Value(now),
        ),
      );
    }

    return ActivitySplitResult(
      part1: (await get(activityId))!,
      part2: (await get(part2Id))!,
      segmentMoves: moved,
    );
  });

  Future<void> _addCut(
    String activityId,
    int start,
    int end,
    String? reason,
    DateTime now,
  ) async {
    if (end <= start) return;
    await _db
        .into(_db.cutRanges)
        .insert(
          CutRangesCompanion.insert(
            id: _newId(),
            activityId: activityId,
            startOffsetMs: start,
            endOffsetMs: end,
            reason: Value(reason),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  /// A cut wholly inside the gap before the new activity's first segment
  /// hides nothing, so it is soft-deleted rather than moved.
  Future<void> _deleteCut(String id, DateTime now) =>
      (_db.update(_db.cutRanges)..where((c) => c.id.equals(id))).write(
        CutRangesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );

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
