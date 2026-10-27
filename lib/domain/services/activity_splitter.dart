import 'dart:io';

import '../../data/filesystem/media_paths.dart';
import '../../data/repositories/activity_repository.dart';

/// Splits an activity at the playhead and moves its waveform summaries
/// with the segments (FR-REV-05, ADR-036) [P1-18].
///
/// Audio files and photos never move on disk: their rows keep the same
/// paths. Waveform summaries are derived files kept per activity, so a
/// moved segment's summary is renamed and a shared segment's is copied.
/// A summary that cannot be moved only means a flat waveform.
class ActivitySplitter {
  ActivitySplitter({required this.activities, required this.mediaRoot});

  final ActivityRepository activities;
  final Future<Directory> Function() mediaRoot;

  Future<ActivitySplitResult> split(
    String activityId, {
    required int splitOffsetMs,
    String? part2Title,
  }) async {
    final result = await activities.split(
      activityId,
      splitOffsetMs: splitOffsetMs,
      part2Title: part2Title,
    );
    final root = await mediaRoot();
    final conferenceId = result.part1.conferenceId;
    for (final MapEntry(key: from, value: to) in result.segmentMoves.entries) {
      final source = MediaPaths.resolve(
        root,
        MediaPaths.waveform(conferenceId, activityId, from),
      );
      final target = MediaPaths.resolve(
        root,
        MediaPaths.waveform(conferenceId, result.part2.id, to),
      );
      try {
        if (!source.existsSync()) continue;
        await target.parent.create(recursive: true);
        if (from == to) {
          await source.rename(target.path);
        } else {
          await source.copy(target.path);
        }
      } on FileSystemException {
        // Derived data only: the review screen draws a flat line instead.
      }
    }
    return result;
  }
}
