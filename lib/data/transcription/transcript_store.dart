// Disk operations stay asynchronous so persistence cannot block recording UI.
// ignore_for_file: avoid_slow_async_io

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/transcription/transcript.dart';

enum TranscriptLoadState { missing, ready, corrupt, unavailable }

class TranscriptLoadResult {
  const TranscriptLoadResult(this.state, {this.document, this.message});

  final TranscriptLoadState state;
  final TranscriptDocument? document;
  final String? message;
}

/// Atomic, UTF-8 local persistence for completed segments (FR-TRN-06/08/09).
///
/// Owns only `root/transcripts-v1/<activity>/<segment>.json`. There is deliberately
/// no delete operation and no relationship to model removal or audio writes.
/// Atomic replacement uses a sibling temporary file, flushed before rename.
/// App-process writers serialize, including separate store instances; arbitrary
/// external writers/processes are not supported. A failed write keeps old text.
class TranscriptStore {
  TranscriptStore(Directory root) : _root = root.absolute;

  final Directory _root;
  static final Map<String, Future<void>> _writers = {};
  static int _temporaryId = 0;
  static const maxDocumentBytes = 16 * 1024 * 1024;

  Directory get _directory =>
      Directory.fromUri(_root.uri.resolve('transcripts-v1/'));

  File _file(String activityId, String segmentId) {
    validateTranscriptId(activityId);
    validateTranscriptId(segmentId);
    return File.fromUri(_directory.uri.resolve('$activityId/$segmentId.json'));
  }

  Future<void> _checkPath(File file, {bool create = false}) async {
    for (final directory in [_root, _directory, file.parent]) {
      final type = await FileSystemEntity.type(
        directory.path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.directory) {
        throw const FileSystemException(
          'Transcript directories must not be links or files',
        );
      }
      if (create && type == FileSystemEntityType.notFound) {
        await directory.create(recursive: true);
      }
    }
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw const FileSystemException(
        'Transcript document must be a regular file',
      );
    }
  }

  Future<TranscriptLoadResult> load({
    required String activityId,
    required String segmentId,
  }) async {
    final file = _file(activityId, segmentId);
    try {
      await _checkPath(file);
      if (!await file.exists()) {
        return const TranscriptLoadResult(TranscriptLoadState.missing);
      }
      if (await file.length() > maxDocumentBytes) {
        return const TranscriptLoadResult(
          TranscriptLoadState.corrupt,
          message: 'Transcript exceeds the supported size.',
        );
      }
      final json = jsonDecode(utf8.decode(await file.readAsBytes()));
      if (json is! Map<String, dynamic>) {
        throw const FormatException('Expected transcript object');
      }
      final document = TranscriptDocument.fromJson(json);
      if (document.activityId != activityId ||
          document.segmentId != segmentId) {
        throw const FormatException(
          'Transcript identifiers do not match its file',
        );
      }
      return TranscriptLoadResult(
        TranscriptLoadState.ready,
        document: document,
      );
    } on FileSystemException {
      return const TranscriptLoadResult(
        TranscriptLoadState.unavailable,
        message: 'Transcript could not be read safely.',
      );
    } on FormatException {
      return const TranscriptLoadResult(
        TranscriptLoadState.corrupt,
        message: 'Saved transcript is not valid. Original audio is unchanged.',
      );
    } on ArgumentError {
      return const TranscriptLoadResult(
        TranscriptLoadState.corrupt,
        message: 'Saved transcript contains invalid values. Original audio is unchanged.',
      );
    }
  }

  /// Discovers completed local records after restart. For diagnostics, use
  /// [inspectDocuments], which retains corrupt/unavailable entries as states.
  Future<List<TranscriptDocument>> listDocuments({String? activityId}) async =>
      [
        for (final result in (await inspectDocuments(
          activityId: activityId,
        )).values)
          if (result.state == TranscriptLoadState.ready) result.document!,
      ];

  /// Keys are safe activity/segment identifiers; temporary files are ignored.
  Future<Map<String, TranscriptLoadResult>> inspectDocuments({
    String? activityId,
  }) async {
    if (activityId != null) validateTranscriptId(activityId);
    await _checkPath(_file(activityId ?? 'scan', 'scan'));
    if (!await _directory.exists()) return {};
    final results = <String, TranscriptLoadResult>{};
    final directories = await _directory.list(followLinks: false).toList();
    directories.sort((a, b) => a.path.compareTo(b.path));
    for (final directory in directories) {
      if (directory is! Directory) continue;
      final id = directory.uri.pathSegments.lastWhere(
        (part) => part.isNotEmpty,
      );
      try {
        validateTranscriptId(id);
      } on ArgumentError {
        continue;
      }
      if (activityId != null && activityId != id) continue;
      final entries = await directory.list(followLinks: false).toList();
      entries.sort((a, b) => a.path.compareTo(b.path));
      for (final entry in entries) {
        final name = entry.uri.pathSegments.lastWhere(
          (part) => part.isNotEmpty,
        );
        if (!name.endsWith('.json')) continue;
        final segment = name.substring(0, name.length - 5);
        try {
          validateTranscriptId(segment);
        } on ArgumentError {
          continue;
        }
        results['$id/$segment'] = await load(
          activityId: id,
          segmentId: segment,
        );
      }
    }
    return results;
  }

  /// Records the first machine result, never replacing it with a later run.
  /// Repeating the exact original result is idempotent and preserves edits.
  Future<TranscriptDocument> saveOriginal(TranscriptDocument document) {
    if (document.corrections.isNotEmpty) {
      throw ArgumentError('Save original output before applying corrections');
    }
    final file = _file(document.activityId, document.segmentId);
    return _serialized(file, () async {
      final loaded = await load(
        activityId: document.activityId,
        segmentId: document.segmentId,
      );
      if (loaded.state == TranscriptLoadState.ready) {
        final existing = loaded.document!;
        if (_originalKey(existing) != _originalKey(document)) {
          throw StateError('Original machine transcript already exists');
        }
        return existing;
      }
      if (loaded.state != TranscriptLoadState.missing) {
        throw StateError('Existing transcript cannot be safely replaced');
      }
      await _write(file, document);
      return document;
    });
  }

  /// Replaces the correction map only; omitted keys revert to machine text.
  Future<TranscriptDocument> saveCorrections({
    required String activityId,
    required String segmentId,
    required Map<int, String> corrections,
  }) {
    final values = Map<int, String>.of(corrections);
    final file = _file(activityId, segmentId);
    return _serialized(file, () async {
      final loaded = await load(activityId: activityId, segmentId: segmentId);
      if (loaded.state != TranscriptLoadState.ready) {
        throw StateError('No readable original transcript to correct');
      }
      final updated = loaded.document!.withCorrections(values);
      await _write(file, updated);
      return updated;
    });
  }

  String _originalKey(TranscriptDocument document) => jsonEncode({
    'spans': document.machineSpans.map((span) => span.toJson()).toList(),
    'offset': document.segmentOffset.inMilliseconds,
    'model': document.modelId,
  });

  Future<T> _serialized<T>(File file, Future<T> Function() action) async {
    final key = Platform.isWindows
        ? file.absolute.path.toLowerCase()
        : file.absolute.path;
    final previous = _writers[key] ?? Future<void>.value();
    final complete = Completer<void>();
    _writers[key] = complete.future;
    await previous;
    try {
      return await action();
    } finally {
      complete.complete();
      if (identical(_writers[key], complete.future)) {
        _writers.remove(key)?.ignore();
      }
    }
  }

  Future<void> _write(File file, TranscriptDocument document) async {
    final bytes = utf8.encode(jsonEncode(document.toJson()));
    if (bytes.length > maxDocumentBytes) {
      throw ArgumentError('Transcript exceeds the supported size');
    }
    await _checkPath(file, create: true);
    // Unique sibling prevents an interrupted/stale write from being read as final.
    final temp = File('${file.path}.tmp-$pid-${_temporaryId++}');
    RandomAccessFile? handle;
    var owned = false;
    try {
      if (await FileSystemEntity.type(temp.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const FileSystemException(
          'Temporary transcript path already exists',
        );
      }
      await temp.create(exclusive: true);
      owned = true;
      handle = await temp.open(mode: FileMode.writeOnly);
      await handle.writeFrom(bytes);
      await handle.flush();
      await handle.close();
      handle = null;
      await _checkPath(file);
      await temp.rename(file.path);
    } finally {
      if (handle != null) await handle.close();
      if (owned && await temp.exists()) await temp.delete();
    }
  }
}
