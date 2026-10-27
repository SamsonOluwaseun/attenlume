import 'dart:io';

import 'package:path/path.dart' as p;

/// On-device media layout (BUILD_GUIDE 9.5) [P1-04].
///
/// Database paths are relative to the media root and always use `/`, so
/// they survive iOS container moves and read the same on every platform.
abstract final class MediaPaths {
  /// Folder name of the media root inside the app documents folder.
  static const rootFolderName = 'media';

  static String activityFolder(String conferenceId, String activityId) =>
      p.posix.join('conferences', conferenceId, 'activities', activityId);

  /// `segment-001.m4a` for sequence 1. A non-zero [attempt] adds a suffix
  /// (`segment-001-2.m4a`) so an existing file is never overwritten.
  static String segmentFileName(int sequence, {int attempt = 0}) {
    final base = 'segment-${sequence.toString().padLeft(3, '0')}';
    return attempt == 0 ? '$base.m4a' : '$base-${attempt + 1}.m4a';
  }

  static String segment(
    String conferenceId,
    String activityId,
    int sequence, {
    int attempt = 0,
  }) => p.posix.join(
    activityFolder(conferenceId, activityId),
    'audio',
    segmentFileName(sequence, attempt: attempt),
  );

  /// `photos/<photo_id>.jpg` in the activity folder (BUILD_GUIDE 9.5)
  /// [P0-05].
  static String photo(String conferenceId, String activityId, String photoId) =>
      p.posix.join(
        activityFolder(conferenceId, activityId),
        'photos',
        '$photoId.jpg',
      );

  /// The absolute file for a stored relative path.
  static File resolve(Directory mediaRoot, String relativePath) =>
      File(p.joinAll([mediaRoot.path, ...p.posix.split(relativePath)]));
}
