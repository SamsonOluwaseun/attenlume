import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;

import '../../data/filesystem/m4a_inspector.dart';
import '../../data/filesystem/media_paths.dart';
import '../../data/filesystem/segment_commit.dart';
import '../../data/local_database/app_database.dart';
import '../../data/repositories/activity_repository.dart';
import '../../data/repositories/media_asset_repository.dart';
import '../models/enums.dart';
import '../models/media.dart';
import 'recording_service.dart';
import 'recording_state.dart';

/// What recovery found for one activity left open by a crash
/// (FR-REC-08, AT-REC-03) [P1-08].
class RecoveredActivity {
  const RecoveredActivity({
    required this.activityId,
    required this.conferenceId,
    required this.title,
    required this.wasRecording,
    this.recovered = 0,
    this.damaged = 0,
    this.missing = 0,
    this.interruptionsClosed = 0,
  });

  final String activityId;
  final String conferenceId;
  final String title;

  /// The activity was still marked active, so the app stopped while it
  /// was recording, paused or interrupted.
  final bool wasRecording;

  /// Unfinished parts whose file parsed. Marked `recovered`.
  final int recovered;

  /// Unfinished parts whose file exists but does not parse. Marked
  /// `damaged`, file kept under its partial name.
  final int damaged;

  /// Unfinished parts with no file under either name. Marked `damaged`.
  final int missing;

  /// Interruptions left open by the crash, now closed.
  final int interruptionsClosed;

  RecoveredActivity _add({
    int recovered = 0,
    int damaged = 0,
    int missing = 0,
    int interruptionsClosed = 0,
  }) => RecoveredActivity(
    activityId: activityId,
    conferenceId: conferenceId,
    title: title,
    wasRecording: wasRecording,
    recovered: this.recovered + recovered,
    damaged: this.damaged + damaged,
    missing: this.missing + missing,
    interruptionsClosed: this.interruptionsClosed + interruptionsClosed,
  );

  /// Plain UK English summary for the recovery prompt.
  String get message {
    final lines = <String>[
      wasRecording
          ? "Attenlume closed while '$title' was recording."
          : "Attenlume closed before '$title' finished saving.",
      if (recovered > 0)
        recovered == 1
            ? 'The unfinished part was saved.'
            : '$recovered unfinished parts were saved.',
      if (damaged > 0)
        damaged == 1
            ? 'One unfinished part could not be read. The file is kept.'
            : '$damaged unfinished parts could not be read. The files are '
                  'kept.',
      if (missing > 0)
        missing == 1
            ? 'One unfinished part has no audio file and shows as a gap.'
            : '$missing unfinished parts have no audio file and show as '
                  'gaps.',
      'Everything recorded before that is safe.',
    ];
    return lines.join(' ');
  }

  @override
  String toString() =>
      'RecoveredActivity($title, recovered: $recovered, damaged: $damaged, '
      'missing: $missing, interruptions: $interruptionsClosed)';
}

/// Result of [CrashRecoveryService.reconcile].
class RecoveryReport {
  const RecoveryReport({
    this.activities = const [],
    this.unlinkedFiles = const [],
  });

  static const empty = RecoveryReport();

  final List<RecoveredActivity> activities;

  /// Audio files in an activity folder that no segment row names. Kept and
  /// listed, never deleted or linked automatically.
  final List<String> unlinkedFiles;

  /// True when there is something to tell the user.
  bool get needsPrompt => activities.isNotEmpty || unlinkedFiles.isNotEmpty;
}

/// Reconciles the database with segment files on app start (FR-REC-08,
/// AT-REC-03, ARCHITECTURE 3) [P1-08].
///
/// For every segment still `writing` it looks for the file under the
/// row's path and, for a partial path, under the final name too, because
/// the rename comes before the row update (ADR-019). A file that parses is
/// marked `recovered` and given its final name. Anything else is marked
/// `damaged` and kept: a damaged file is never marked good, and nothing is
/// deleted or overwritten (NFR-07). Interruptions and activities left open
/// by the crash are closed.
///
/// Rows of the activity the recorder holds are left alone, so it is safe
/// to run while a recording has already started.
class CrashRecoveryService {
  CrashRecoveryService({
    required this._activities,
    required this._media,
    required this._mediaRoot,
    this._recorderStatus = _idle,
    this._inspector = const M4aInspector(),
    this._hashFile = sha256OfFileInIsolate,
    this._commitFile = commitSegmentFile,
  });

  final ActivityRepository _activities;
  final MediaAssetRepository _media;
  final Future<Directory> Function() _mediaRoot;
  final RecordingStatus Function() _recorderStatus;
  final M4aInspector _inspector;
  final Future<String> Function(File) _hashFile;
  final SegmentCommit _commitFile;

  static RecordingStatus _idle() => RecordingStatus.idle;

  bool _held(String activityId) {
    final status = _recorderStatus();
    return status.state.holdsActivity && status.activityId == activityId;
  }

  Future<RecoveryReport> reconcile() async {
    final root = await _mediaRoot();
    final found = <String, RecoveredActivity>{};

    Future<RecoveredActivity?> entry(String activityId) async {
      final known = found[activityId];
      if (known != null) return known;
      final activity = await _activities.get(activityId);
      if (activity == null) return null;
      return found[activityId] = RecoveredActivity(
        activityId: activityId,
        conferenceId: activity.conferenceId,
        title: activity.title,
        wasRecording: activity.status == ActivityStatus.active,
      );
    }

    for (final segment in await _media.unfinalisedSegments()) {
      if (_held(segment.activityId)) continue;
      final outcome = await _reconcileSegment(root, segment);
      final current = await entry(segment.activityId);
      if (current == null) continue;
      found[segment.activityId] = switch (outcome) {
        SegmentState.recovered => current._add(recovered: 1),
        null => current._add(missing: 1),
        _ => current._add(damaged: 1),
      };
    }

    for (final interruption in await _media.openInterruptions()) {
      if (_held(interruption.activityId)) continue;
      await _closeInterruption(interruption);
      final current = await entry(interruption.activityId);
      if (current == null) continue;
      found[interruption.activityId] = current._add(interruptionsClosed: 1);
    }

    for (final activity in await _activities.listByStatus(
      ActivityStatus.active,
    )) {
      if (_held(activity.id)) continue;
      await entry(activity.id);
      await _closeActivity(activity.id);
    }

    return RecoveryReport(
      activities: found.values.toList(),
      unlinkedFiles: await _unlinkedFiles(root),
    );
  }

  /// Returns the state given, or null when no file was found.
  Future<SegmentState?> _reconcileSegment(
    Directory root,
    RecordingSegment segment,
  ) async {
    var path = segment.filePath;
    var file = MediaPaths.resolve(root, path);
    if (!file.existsSync() && MediaPaths.isPartial(path)) {
      // Renamed before the row was updated (ADR-019 point 3).
      final renamed = MediaPaths.finalName(path);
      final renamedFile = MediaPaths.resolve(root, renamed);
      if (renamedFile.existsSync()) {
        path = renamed;
        file = renamedFile;
      }
    }
    if (!file.existsSync()) {
      await _markDamaged(segment, path: path);
      return null;
    }

    final AudioFileInfo info;
    try {
      info = await _inspector.inspect(file);
    } on MediaInspectionException {
      await _markDamaged(segment, path: path, bytes: file.lengthSync());
      return SegmentState.damaged;
    } on FileSystemException {
      await _markDamaged(segment, path: path);
      return SegmentState.damaged;
    }

    String? digest;
    try {
      digest = await _hashFile(file);
    } on Object {
      // Left null: export re-hashes, and a missing hash is honest.
    }
    if (MediaPaths.isPartial(path)) {
      final target = MediaPaths.finalName(path);
      try {
        await _commitFile(file, MediaPaths.resolve(root, target));
        path = target;
      } on Object {
        // Kept under the partial name. The row still finds it.
      }
    }
    await _media.finaliseSegment(
      segment.id,
      endUtc: segment.startUtc.add(Duration(milliseconds: info.durationMs)),
      endReason: SegmentEndReason.error,
      filePath: path,
      durationMs: info.durationMs,
      bytes: info.bytes,
      sha256: digest,
      observedBitrateBps: info.observedBitrateBps,
      codec: info.codec,
      container: info.container,
      channelCount: info.channelCount,
      sampleRateHz: info.sampleRateHz,
      state: SegmentState.recovered,
    );
    return SegmentState.recovered;
  }

  /// A damaged part spans no time, so the timeline shows a gap where it
  /// was (ADR-016).
  Future<void> _markDamaged(
    RecordingSegment segment, {
    required String path,
    int? bytes,
  }) => _media.finaliseSegment(
    segment.id,
    endUtc: segment.startUtc,
    endReason: SegmentEndReason.error,
    filePath: path,
    bytes: bytes,
    state: SegmentState.damaged,
  );

  /// Ends an interruption at the last moment known: the start of the next
  /// segment if recording carried on, otherwise its own start, since
  /// nothing says how long it lasted.
  Future<void> _closeInterruption(Interruption interruption) async {
    final segments = await _media.segmentsFor(interruption.activityId);
    final next = segments
        .map((s) => s.startUtc)
        .where((start) => !start.isBefore(interruption.startUtc))
        .fold<DateTime?>(
          null,
          (earliest, start) =>
              earliest == null || start.isBefore(earliest) ? start : earliest,
        );
    await _media.endInterruption(
      interruption.id,
      autoResumed: false,
      endUtc: next ?? interruption.startUtc,
    );
  }

  /// An activity with audio becomes completed, ending where its audio
  /// ends. One with none goes back to draft so it can be started again.
  Future<void> _closeActivity(String activityId) async {
    final segments = await _media.segmentsFor(activityId);
    if (segments.isEmpty) {
      await _activities.update(
        activityId,
        const ActivitiesCompanion(status: Value(ActivityStatus.draft)),
      );
      return;
    }
    final lastEnd = segments
        .map((s) => s.endUtc ?? s.startUtc)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    await _activities.update(
      activityId,
      ActivitiesCompanion(
        status: const Value(ActivityStatus.completed),
        actualEnd: Value(lastEnd),
      ),
    );
  }

  /// `.m4a` files under `conferences/*/activities/*/audio/` that no row
  /// names, as relative paths.
  Future<List<String>> _unlinkedFiles(Directory root) async {
    final conferences = Directory(p.join(root.path, 'conferences'));
    if (!conferences.existsSync()) return const [];
    final known = await _media.segmentPaths();
    final unlinked = <String>[];
    await for (final entity in conferences.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.posix.joinAll(
        p.split(p.relative(entity.path, from: root.path)),
      );
      final parts = p.posix.split(relative);
      final inAudio =
          parts.length == 6 &&
          parts[2] == 'activities' &&
          parts[4] == 'audio' &&
          p.posix.extension(relative) == '.m4a';
      if (inAudio && !known.contains(relative)) unlinked.add(relative);
    }
    return unlinked..sort();
  }
}
