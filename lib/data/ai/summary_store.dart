// File-system checks here guard paths before reads and writes, as in
// TranscriptStore.
// ignore_for_file: avoid_slow_async_io
import 'dart:convert';
import 'dart:io';

import '../../domain/ai/session_summary.dart';
import '../../domain/transcription/transcript.dart' show validateTranscriptId;

/// Saved session summaries (P3-02): `summaries-v1/<activityId>.json` under
/// the app data folder, beside `transcripts-v1/`. One summary per session;
/// a new one replaces the old. Writes go to a sibling temporary file first,
/// so a failed write keeps the previous summary.
class SummaryStore {
  SummaryStore(Directory root) : _root = root.absolute;

  final Directory _root;
  static int _temporaryId = 0;
  static const maxBytes = 1024 * 1024;

  Directory get _directory =>
      Directory.fromUri(_root.uri.resolve('summaries-v1/'));

  File _file(String activityId) => File.fromUri(
    _directory.uri.resolve('${validateTranscriptId(activityId)}.json'),
  );

  /// Null when there is none. Throws [FormatException] when the file
  /// cannot be read as a summary; saving a new one replaces it.
  Future<SessionSummary?> load(String activityId) async {
    final file = _file(activityId);
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    if (await file.length() > maxBytes) {
      throw const FormatException('Saved summary is too large');
    }
    final json = jsonDecode(await file.readAsString());
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Saved summary is not an object');
    }
    final summary = SessionSummary.fromJson(json);
    if (summary.activityId != activityId) {
      throw const FormatException('Saved summary belongs to another session');
    }
    return summary;
  }

  Future<void> save(SessionSummary summary) async {
    final bytes = utf8.encode(jsonEncode(summary.toJson()));
    if (bytes.length > maxBytes) throw ArgumentError('Summary is too large');
    final file = _file(summary.activityId);
    await _checkDirectory(create: true);
    final temp = File('${file.path}.tmp-$pid-${_temporaryId++}');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<void> delete(String activityId) async {
    final file = _file(activityId);
    if (await file.exists()) await file.delete();
  }

  Future<void> _checkDirectory({bool create = false}) async {
    for (final directory in [_root, _directory]) {
      final type = await FileSystemEntity.type(
        directory.path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.directory) {
        throw const FileSystemException(
          'Summary folders must not be links or files',
        );
      }
      if (create && type == FileSystemEntityType.notFound) {
        await directory.create(recursive: true);
      }
    }
  }
}
