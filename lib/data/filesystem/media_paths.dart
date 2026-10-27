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

  /// The name a segment is written under until it is finalised
  /// (`segment-001.partial.m4a` for `segment-001.m4a`) [P1-05, FR-REC-03].
  /// The extension stays last because encoders pick the container from it.
  static String partial(String relativePath) {
    final ext = p.posix.extension(relativePath);
    return '${relativePath.substring(0, relativePath.length - ext.length)}'
        '$partialMarker$ext';
  }

  /// True for a path made by [partial].
  static bool isPartial(String relativePath) =>
      p.posix.basenameWithoutExtension(relativePath).endsWith(partialMarker);

  static const partialMarker = '.partial';

  /// The final name of a path made by [partial] (`segment-001.m4a` for
  /// `segment-001.partial.m4a`). Other paths come back unchanged
  /// [P1-08, FR-REC-08].
  static String finalName(String relativePath) {
    if (!isPartial(relativePath)) return relativePath;
    final ext = p.posix.extension(relativePath);
    final stem = relativePath.substring(0, relativePath.length - ext.length);
    return '${stem.substring(0, stem.length - partialMarker.length)}$ext';
  }

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
