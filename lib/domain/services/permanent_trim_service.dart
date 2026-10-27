import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../../data/filesystem/media_paths.dart';
import '../../data/filesystem/waveform_summary.dart';
import '../../data/repositories/activity_repository.dart';
import '../../data/repositories/cut_range_repository.dart';
import '../../data/repositories/media_asset_repository.dart';
import '../../data/repositories/repository_support.dart';
import '../../platform/audio_trimmer/audio_trimmer.dart';
import '../../platform/storage/free_space_probe.dart';
import '../models/enums.dart';
import '../models/media.dart';
import 'cut_range_math.dart';
import 'review_timeline.dart';

/// What a permanent trim does to one segment (FR-REV-06) [P1-19].
class SegmentTrimChange {
  const SegmentTrimChange({
    required this.segment,
    required this.segmentStartMs,
    required this.keep,
  });

  final RecordingSegment segment;

  /// Offset of the segment start on the activity timeline.
  final int segmentStartMs;

  /// Parts of the segment to keep, in ms from its start. Each becomes its
  /// own file, so the gaps left by cuts keep the timeline in place. Empty
  /// when the whole segment is cut.
  final List<TimeRange> keep;

  bool get dropped => keep.isEmpty;
}

/// A permanent trim worked out from an activity's cuts.
class PermanentTrimPlan {
  const PermanentTrimPlan({
    required this.activityId,
    required this.changes,
    required this.removedMs,
    required this.keptMs,
    required this.estimatedBytes,
  });

  final String activityId;
  final List<SegmentTrimChange> changes;

  /// Audio the trim removes and the audio left afterwards.
  final int removedMs;
  final int keptMs;

  /// About how much the new files take (kept share of each source file).
  final int estimatedBytes;

  bool get hasWork => changes.isNotEmpty;

  int get filesToWrite => changes.fold(0, (n, c) => n + c.keep.length);
}

/// A recording a permanent trim replaced, now in `audio/originals/`.
class KeptOriginal {
  const KeptOriginal({required this.relativePath, required this.bytes});

  final String relativePath;
  final int bytes;
}

class PermanentTrimResult {
  const PermanentTrimResult({
    required this.filesWritten,
    required this.originals,
    required this.sharedOriginals,
  });

  final int filesWritten;

  /// Originals no row names any more, offered for removal.
  final List<KeptOriginal> originals;

  /// Originals another activity still uses (after a split), left in place.
  final int sharedOriginals;

  int get originalBytes => originals.fold(0, (n, o) => n + o.bytes);
}

/// Refusals and failures. Nothing on disk or in the database changed.
class PermanentTrimException implements Exception {
  const PermanentTrimException(this.message);

  /// Plain UK English, ready to show.
  final String message;

  @override
  String toString() => 'PermanentTrimException: $message';
}

/// "Apply trims permanently" (FR-REV-06, FR-REV-07, ADR-037) [P1-19].
///
/// New files are written and verified first; only then does one database
/// transaction point the activity at them. Originals are never deleted
/// here: they move to `audio/originals/` and [removeOriginals] deletes them
/// only when the user asks (NFR-07). Cut ranges stay in place: after the
/// trim they cover gaps, so playback and offsets do not change.
class PermanentTrimService {
  PermanentTrimService({
    required this.activities,
    required this.media,
    required this.cuts,
    required this.trimmer,
    required this.mediaRoot,
    this.freeSpace = const UnknownFreeSpaceProbe(),
    this.reserveBytes = 100 * 1024 * 1024,
    this.minimumMs = 100,
    this.newId = uuidV4,
  });

  final ActivityRepository activities;
  final MediaAssetRepository media;
  final CutRangeRepository cuts;
  final AudioTrimmer trimmer;
  final Future<Directory> Function() mediaRoot;
  final FreeSpaceProbe freeSpace;

  /// Space that must stay free after writing (the recording hard stop).
  final int reserveBytes;

  /// Cuts and kept pieces shorter than this are ignored: cuts land on
  /// audio frames, so a re-trim must not chase a few milliseconds.
  final int minimumMs;
  final IdGenerator newId;

  Future<PermanentTrimPlan> plan(String activityId) async {
    final segments = await media.segmentsFor(activityId);
    if (segments.any((s) => s.state == SegmentState.writing)) {
      throw const PermanentTrimException(
        'Stop the recording before applying trims.',
      );
    }
    final timeline = ReviewTimeline.build(segments: segments);
    final merged = CutRangeMath.mergeOverlappingCutRanges(
      await cuts.activeFor(activityId),
    );
    final changes = <SegmentTrimChange>[];
    var removed = 0;
    var kept = 0;
    var bytes = 0;
    for (final t in timeline.segments) {
      if (!t.playable) continue;
      final local = <TimeRange>[
        for (final c in merged)
          if (math.max(c.startMs, t.startMs) < math.min(c.endMs, t.endMs) &&
              math.min(c.endMs, t.endMs) - math.max(c.startMs, t.startMs) >=
                  minimumMs)
            TimeRange(
              math.max(c.startMs, t.startMs) - t.startMs,
              math.min(c.endMs, t.endMs) - t.startMs,
            ),
      ];
      if (local.isEmpty) {
        kept += t.durationMs;
        continue;
      }
      final keep = <TimeRange>[];
      var at = 0;
      for (final c in local) {
        if (c.startMs - at >= minimumMs) keep.add(TimeRange(at, c.startMs));
        at = c.endMs;
      }
      if (t.durationMs - at >= minimumMs) {
        keep.add(TimeRange(at, t.durationMs));
      }
      final keepMs = keep.fold(0, (n, r) => n + r.durationMs);
      kept += keepMs;
      removed += t.durationMs - keepMs;
      bytes += ((t.segment.bytes ?? 0) * keepMs / t.durationMs).round();
      changes.add(
        SegmentTrimChange(
          segment: t.segment,
          segmentStartMs: t.startMs,
          keep: keep,
        ),
      );
    }
    return PermanentTrimPlan(
      activityId: activityId,
      changes: changes,
      removedMs: removed,
      keptMs: kept,
      estimatedBytes: bytes,
    );
  }

  /// Writes the trimmed files, then switches the activity to them.
  Future<PermanentTrimResult> apply(String activityId) async {
    final plan = await this.plan(activityId);
    if (!plan.hasWork) {
      throw const PermanentTrimException('There are no cuts to apply.');
    }
    if (plan.keptMs < minimumMs) {
      throw const PermanentTrimException(
        'The cuts cover all of the audio. Remove a cut, or delete the '
        'activity instead.',
      );
    }
    final activity = await activities.get(activityId);
    if (activity == null) {
      throw const PermanentTrimException('This activity no longer exists.');
    }
    final root = await mediaRoot();
    final space = await freeSpace.query(root.path);
    if (space != null &&
        space.availableBytes - plan.estimatedBytes < reserveBytes) {
      throw const PermanentTrimException(
        'Not enough free space to write the trimmed files. Free some '
        'space and try again.',
      );
    }

    // 1. Write and verify every new file. Any failure removes them all.
    final written = <TrimmedSegment>[];
    final waveforms = <(String, String, TimeRange)>[];
    try {
      for (final change in plan.changes) {
        final s = change.segment;
        final source = MediaPaths.resolve(root, s.filePath);
        for (var k = 0; k < change.keep.length; k++) {
          final range = change.keep[k];
          var attempt = 0;
          String relative;
          do {
            relative = MediaPaths.trimmedSegment(
              activity.conferenceId,
              activityId,
              s.sequence,
              k + 1,
              attempt: attempt++,
            );
          } while (MediaPaths.resolve(root, relative).existsSync() ||
              File('${MediaPaths.resolve(root, relative).path}.partial')
                  .existsSync());
          final result = await trimmer.trim(
            sourceFile: source,
            targetFile: MediaPaths.resolve(root, relative),
            keepRanges: [range],
          );
          final id = newId();
          written.add(
            TrimmedSegment(
              id: id,
              source: s,
              filePath: relative,
              startUtc: s.startUtc.add(Duration(milliseconds: range.startMs)),
              durationMs: result.durationMs,
              bytes: result.bytes,
              sha256: result.sha256,
              observedBitrateBps: result.durationMs <= 0
                  ? 0
                  : (result.bytes * 8 * 1000 / result.durationMs).round(),
            ),
          );
          waveforms.add((s.id, id, range));
        }
      }
    } on Object catch (e) {
      await _deleteQuietly([
        for (final w in written) MediaPaths.resolve(root, w.filePath),
      ]);
      if (e is PermanentTrimException) rethrow;
      throw PermanentTrimException(
        'The trimmed files could not be written, so nothing was changed. '
                'You can still export the originals with the cuts listed '
                '(cuts.json). ${e is AudioTrimException ? e.message : ''}'
            .trim(),
      );
    }

    // 2. Point the activity at the new files.
    try {
      await media.replaceWithTrimmed(
        activityId,
        replacedIds: {for (final c in plan.changes) c.segment.id},
        added: written,
      );
    } on Object {
      await _deleteQuietly([
        for (final w in written) MediaPaths.resolve(root, w.filePath),
      ]);
      throw const PermanentTrimException(
        'The trim could not be saved, so nothing was changed.',
      );
    }

    // 3. Derived waveform summaries follow (ADR-034). Failures only mean
    // a flat line on the review screen.
    await _sliceWaveforms(
      root,
      activity.conferenceId,
      activityId,
      waveforms,
      replaced: {for (final c in plan.changes) c.segment.id},
    );

    // 4. Move originals nothing names any more out of `audio/`.
    final named = await media.segmentPaths();
    final originals = <KeptOriginal>[];
    var shared = 0;
    for (final path in {for (final c in plan.changes) c.segment.filePath}) {
      if (named.contains(path)) {
        shared++;
        continue;
      }
      final kept = await _keepOriginal(
        root,
        activity.conferenceId,
        activityId,
        path,
      );
      if (kept != null) originals.add(kept);
    }
    return PermanentTrimResult(
      filesWritten: written.length,
      originals: originals,
      sharedOriginals: shared,
    );
  }

  /// Deletes kept originals the user chose to remove. Skips any file a
  /// segment row names, or that is not in an `audio/originals/` folder.
  /// Returns how many were removed.
  Future<int> removeOriginals(List<KeptOriginal> originals) async {
    final root = await mediaRoot();
    final named = await media.segmentPaths();
    var removed = 0;
    for (final o in originals) {
      if (!MediaPaths.isKeptOriginal(o.relativePath)) continue;
      if (named.contains(o.relativePath)) continue;
      final file = MediaPaths.resolve(root, o.relativePath);
      try {
        if (file.existsSync()) {
          await file.delete();
          removed++;
        }
      } on FileSystemException {
        // Left on disk; the Storage Manager can try again (P1-20).
      }
    }
    return removed;
  }

  Future<KeptOriginal?> _keepOriginal(
    Directory root,
    String conferenceId,
    String activityId,
    String path,
  ) async {
    final source = MediaPaths.resolve(root, path);
    if (!source.existsSync()) return null;
    final folder = MediaPaths.originalsFolder(conferenceId, activityId);
    final name = p.posix.basenameWithoutExtension(path);
    final ext = p.posix.extension(path);
    var attempt = 1;
    var target = p.posix.join(folder, '$name$ext');
    while (MediaPaths.resolve(root, target).existsSync()) {
      target = p.posix.join(folder, '$name-${++attempt}$ext');
    }
    final bytes = source.lengthSync();
    try {
      final file = MediaPaths.resolve(root, target);
      await file.parent.create(recursive: true);
      await source.rename(file.path);
      return KeptOriginal(relativePath: target, bytes: bytes);
    } on FileSystemException {
      // Still safe where it was. Crash recovery will list it as unlinked.
      return null;
    }
  }

  Future<void> _sliceWaveforms(
    Directory root,
    String conferenceId,
    String activityId,
    List<(String, String, TimeRange)> pieces, {
    required Set<String> replaced,
  }) async {
    const reader = WaveformSummaryReader();
    for (final (from, to, range) in pieces) {
      final source = MediaPaths.resolve(
        root,
        MediaPaths.waveform(conferenceId, activityId, from),
      );
      try {
        final slice = await reader.read(
          source,
          fromMs: range.startMs,
          toMs: range.endMs,
        );
        if (slice == null) continue;
        final target = MediaPaths.resolve(
          root,
          MediaPaths.waveform(conferenceId, activityId, to),
        );
        await target.parent.create(recursive: true);
        await target.writeAsBytes([
          ...WaveformSummary.header(slice.bucketMs),
          ...slice.levels,
        ], flush: true);
      } on FileSystemException {
        continue;
      }
    }
    await _deleteQuietly([
      for (final id in replaced)
        MediaPaths.resolve(
          root,
          MediaPaths.waveform(conferenceId, activityId, id),
        ),
    ]);
  }

  static Future<void> _deleteQuietly(List<File> files) async {
    for (final f in files) {
      try {
        if (f.existsSync()) await f.delete();
      } on FileSystemException {
        // Nothing points at it; the Storage Manager can find it (P1-20).
      }
    }
  }
}
