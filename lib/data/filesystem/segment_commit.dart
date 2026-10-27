import 'dart:io';

/// Makes a finished segment durable, then gives it its final name
/// [P1-05, FR-REC-03].
///
/// Returns the file under its new name. Throws if the data cannot be
/// flushed or [target] already exists, leaving [partial] where it was.
typedef SegmentCommit = Future<File> Function(File partial, File target);

/// Flushes [partial] to disk (fsync on Android and iOS, `FlushFileBuffers`
/// on Windows), then renames it to [target] in the same folder. An
/// existing [target] is never overwritten (NFR-07).
Future<File> commitSegmentFile(File partial, File target) async {
  // Opening for append would create a missing file.
  if (!partial.existsSync()) {
    throw FileSystemException('Segment file is missing', partial.path);
  }
  final handle = await partial.open(mode: FileMode.append);
  try {
    await handle.flush();
  } finally {
    await handle.close();
  }
  if (target.existsSync()) {
    throw FileSystemException('Will not overwrite a segment', target.path);
  }
  return partial.rename(target.path);
}
