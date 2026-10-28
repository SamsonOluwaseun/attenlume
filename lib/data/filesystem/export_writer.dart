import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../domain/models/enums.dart';
import '../../domain/services/cut_range_math.dart';
import '../../platform/audio_trimmer/audio_trimmer.dart';
import '../../platform/audio_trimmer/mp4_sample_trimmer.dart';
import 'export_space.dart';
import 'folder_export.dart';

/// Where one exported file's bytes come from (FR-EXP-03) [P1-21].
sealed class ExportSource {
  const ExportSource();
}

/// A copy of a file on disk, byte for byte (original audio, photos).
class FileExportSource extends ExportSource {
  const FileExportSource(this.path);

  /// Absolute path. Read only, never changed or removed.
  final String path;
}

/// Small generated text (JSON, Markdown, CSV), held in memory.
class TextExportSource extends ExportSource {
  TextExportSource(String text) : bytes = utf8.encode(text);

  final Uint8List bytes;
}

/// A trimmed copy of an MP4/M4A file keeping only [keepRanges]
/// (milliseconds from the start of the file), written with
/// [Mp4SampleTrimmer] (ADR-037).
class TrimmedAudioExportSource extends ExportSource {
  const TrimmedAudioExportSource(this.path, this.keepRanges);

  final String path;
  final List<TimeRange> keepRanges;
}

/// One file in an export: where it goes and where it comes from.
class ExportEntry {
  const ExportEntry({
    required this.relativePath,
    required this.source,
    required this.estimatedBytes,
  });

  /// `/`-separated, relative to the export's root folder, already safe
  /// (FR-EXP-07).
  final String relativePath;
  final ExportSource source;

  /// Exact for copies and text, an upper estimate for trimmed audio.
  final int estimatedBytes;
}

/// Everything [writeExport] needs. Plain data, so it can be sent to a
/// background isolate.
class ExportWritePlan {
  const ExportWritePlan({
    required this.format,
    required this.destinationParent,
    required this.rootName,
    required this.entries,
    required this.tempDirectory,
  });

  final ExportFormat format;

  /// The folder the export folder or ZIP is created in.
  final String destinationParent;

  /// Name of the export's top folder (and of the ZIP, plus `.zip`).
  final String rootName;
  final List<ExportEntry> entries;

  /// Scratch folder for trimmed copies on their way into a ZIP. Holds
  /// copies only, so it is always safe to delete (FR-EXP-05).
  final String tempDirectory;

  /// The finished folder or ZIP.
  String get outputPath => p.join(
    destinationParent,
    format == ExportFormat.zip ? '$rootName.zip' : rootName,
  );

  /// Where the export is written until it is complete.
  String get partialPath => '$outputPath.partial';

  int get estimatedBytes => entries.fold(0, (n, e) => n + e.estimatedBytes);
}

class ExportWriteResult {
  const ExportWriteResult({required this.outputPath, required this.files});

  final String outputPath;

  /// Every exported file, excluding `checksums.sha256` itself.
  final List<ExportedFile> files;

  int get totalBytes => files.fold(0, (n, f) => n + f.bytes);
}

/// Progress after each file.
class ExportWriteProgress {
  const ExportWriteProgress({
    required this.filesDone,
    required this.filesTotal,
    required this.bytesDone,
    required this.bytesTotal,
  });

  final int filesDone;
  final int filesTotal;
  final int bytesDone;

  /// Estimated; trimmed copies may come out smaller.
  final int bytesTotal;

  double get fraction => bytesTotal <= 0
      ? (filesTotal == 0 ? 1 : filesDone / filesTotal)
      : (bytesDone / bytesTotal).clamp(0, 1).toDouble();
}

/// Thrown when the user cancelled. The partial export has been removed.
class ExportCancelledException implements Exception {
  const ExportCancelledException();

  @override
  String toString() => 'ExportCancelledException';
}

/// Writes an export as a folder or a ZIP (FR-EXP-02 to 06) [P1-21].
///
/// - Streams every file: copies and hashes go one chunk at a time, ZIP
///   members are added from file streams with no compression (audio and
///   photos are already compressed), so memory never holds a whole
///   recording or photo set (FR-EXP-04).
/// - Writes into `<output>.partial` and renames at the end, so a half
///   export never looks complete. Never overwrites an existing output.
/// - On any failure or cancellation, removes only the partial output and
///   [ExportWritePlan.tempDirectory]: both hold copies, never unique media.
///   Sources are only ever read (FR-EXP-05).
/// - Lists every file's SHA-256 in `checksums.sha256` at the export root
///   (FR-EXP-06). Folder copies are read back and compared with the hash.
///
/// [isCancelled] is checked between files, so a cancel takes effect once
/// the current file is done.
Future<ExportWriteResult> writeExport(
  ExportWritePlan plan, {
  void Function(ExportWriteProgress progress)? onProgress,
  bool Function()? isCancelled,
  AudioTrimmer trimmer = const Mp4SampleTrimmer(),
}) async {
  final output = plan.outputPath;
  final partial = plan.partialPath;
  if (FileSystemEntity.typeSync(output) != FileSystemEntityType.notFound ||
      FileSystemEntity.typeSync(partial) != FileSystemEntityType.notFound) {
    throw FileSystemException('Export already exists', output);
  }
  await Directory(plan.destinationParent).create(recursive: true);

  final total = plan.estimatedBytes;
  var bytesDone = 0;
  final files = <ExportedFile>[];
  void done(ExportedFile file, int estimate) {
    files.add(file);
    bytesDone += estimate;
    onProgress?.call(
      ExportWriteProgress(
        filesDone: files.length,
        filesTotal: plan.entries.length,
        bytesDone: bytesDone,
        bytesTotal: total,
      ),
    );
  }

  void checkCancelled() {
    if (isCancelled?.call() ?? false) throw const ExportCancelledException();
  }

  final writer = plan.format == ExportFormat.zip
      ? _ZipWriter(partial, plan.rootName)
      : _FolderWriter(partial);
  try {
    await writer.open();
    for (final entry in plan.entries) {
      checkCancelled();
      final file = switch (entry.source) {
        FileExportSource(:final path) => await writer.addFile(
          entry.relativePath,
          File(path),
        ),
        TextExportSource(:final bytes) => await writer.addBytes(
          entry.relativePath,
          bytes,
        ),
        TrimmedAudioExportSource(:final path, :final keepRanges) =>
          await writer.addTrimmed(
            entry.relativePath,
            File(path),
            keepRanges,
            trimmer,
            plan.tempDirectory,
          ),
      };
      done(file, entry.estimatedBytes);
    }
    checkCancelled();
    final checksums = files
        .map((f) => '${f.sha256}  ${f.relativePath}\n')
        .join();
    await writer.addChecksums(utf8.encode(checksums));
    await writer.close();
    if (plan.format == ExportFormat.zip) {
      await File(partial).rename(output);
    } else {
      await Directory(partial).rename(output);
    }
    return ExportWriteResult(outputPath: output, files: files);
  } catch (error) {
    await writer.abort();
    await removePartialExport(plan);
    if (error is FileSystemException && isOutOfSpaceError(error)) {
      throw ExportOutOfSpaceException(error);
    }
    rethrow;
  } finally {
    await _deleteQuietly(Directory(plan.tempDirectory));
  }
}

/// Removes what a failed or cancelled [writeExport] may have left: the
/// partial output and the temp folder. Both hold copies only.
Future<void> removePartialExport(ExportWritePlan plan) async {
  final type = FileSystemEntity.typeSync(plan.partialPath);
  if (type == FileSystemEntityType.directory) {
    await _deleteQuietly(Directory(plan.partialPath));
  } else if (type == FileSystemEntityType.file) {
    await _deleteQuietly(File(plan.partialPath));
  }
  await _deleteQuietly(Directory(plan.tempDirectory));
}

Future<void> _deleteQuietly(FileSystemEntity entity) async {
  try {
    if (entity.existsSync()) await entity.delete(recursive: true);
  } on FileSystemException {
    // Best effort: a leftover partial copy is reported by the caller's
    // error and can be cleared later; sources are never involved.
  }
}

abstract class _ExportOutput {
  Future<void> open();
  Future<ExportedFile> addFile(String relativePath, File source);
  Future<ExportedFile> addBytes(String relativePath, Uint8List bytes);
  Future<ExportedFile> addTrimmed(
    String relativePath,
    File source,
    List<TimeRange> keepRanges,
    AudioTrimmer trimmer,
    String tempDirectory,
  );
  Future<void> addChecksums(List<int> bytes);
  Future<void> close();
  Future<void> abort();
}

class _FolderWriter implements _ExportOutput {
  _FolderWriter(this.root);

  final String root;

  File _target(String relativePath) =>
      File(p.joinAll([root, ...p.posix.split(relativePath)]));

  @override
  Future<void> open() => Directory(root).create(recursive: true);

  @override
  Future<ExportedFile> addFile(String relativePath, File source) async {
    final target = _target(relativePath);
    await target.parent.create(recursive: true);
    final (bytes, digest) = await copyFileHashing(source, target);
    if (await hashFileSha256(target) != digest) {
      throw FileSystemException('Copy does not match source', target.path);
    }
    return ExportedFile(
      relativePath: relativePath,
      bytes: bytes,
      sha256: digest,
    );
  }

  @override
  Future<ExportedFile> addBytes(String relativePath, Uint8List bytes) async {
    final target = _target(relativePath);
    await target.parent.create(recursive: true);
    final temp = File('${target.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(target.path);
    return ExportedFile(
      relativePath: relativePath,
      bytes: bytes.length,
      sha256: sha256.convert(bytes).toString(),
    );
  }

  @override
  Future<ExportedFile> addTrimmed(
    String relativePath,
    File source,
    List<TimeRange> keepRanges,
    AudioTrimmer trimmer,
    String tempDirectory,
  ) async {
    final target = _target(relativePath);
    await target.parent.create(recursive: true);
    final result = await trimmer.trim(
      sourceFile: source,
      targetFile: target,
      keepRanges: keepRanges,
    );
    final check = await hashFileSha256(target);
    if (check != result.sha256) {
      throw FileSystemException('Trimmed copy does not verify', target.path);
    }
    return ExportedFile(
      relativePath: relativePath,
      bytes: result.bytes,
      sha256: check,
    );
  }

  @override
  Future<void> addChecksums(List<int> bytes) async {
    final target = File(p.join(root, checksumFileName));
    await target.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> abort() async {}
}

/// ZIP output with store compression. Members sit under `<rootName>/` so
/// unzipping gives the same folder as a folder export.
class _ZipWriter implements _ExportOutput {
  _ZipWriter(this.zipPath, this.rootName);

  final String zipPath;
  final String rootName;
  final _encoder = ZipFileEncoder();
  var _open = false;

  String _name(String relativePath) => '$rootName/$relativePath';

  @override
  Future<void> open() async {
    _encoder.create(zipPath, level: ZipFileEncoder.store);
    _open = true;
  }

  @override
  Future<ExportedFile> addFile(String relativePath, File source) async {
    final bytes = await source.length();
    final digest = await hashFileSha256(source);
    await _encoder.addFile(source, _name(relativePath), ZipFileEncoder.store);
    return ExportedFile(
      relativePath: relativePath,
      bytes: bytes,
      sha256: digest,
    );
  }

  @override
  Future<ExportedFile> addBytes(String relativePath, Uint8List bytes) async {
    final member = ArchiveFile.bytes(_name(relativePath), bytes)
      ..lastModTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _encoder.addArchiveFile(member);
    return ExportedFile(
      relativePath: relativePath,
      bytes: bytes.length,
      sha256: sha256.convert(bytes).toString(),
    );
  }

  @override
  Future<ExportedFile> addTrimmed(
    String relativePath,
    File source,
    List<TimeRange> keepRanges,
    AudioTrimmer trimmer,
    String tempDirectory,
  ) async {
    await Directory(tempDirectory).create(recursive: true);
    final temp = File(
      p.join(
        tempDirectory,
        'trim-${DateTime.now().microsecondsSinceEpoch}'
        '.m4a',
      ),
    );
    try {
      await trimmer.trim(
        sourceFile: source,
        targetFile: temp,
        keepRanges: keepRanges,
      );
      return await addFile(relativePath, temp);
    } finally {
      // A trimmed copy, never unique media.
      await _deleteQuietly(temp);
    }
  }

  @override
  Future<void> addChecksums(List<int> bytes) => addBytes(
    checksumFileName,
    bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
  );

  @override
  Future<void> close() async {
    await _encoder.close();
    _open = false;
  }

  @override
  Future<void> abort() async {
    if (!_open) return;
    _open = false;
    try {
      await _encoder.close();
    } catch (_) {
      // The partial ZIP is deleted next; a close error adds nothing.
    }
  }
}

/// Runs [writeExport] on a background isolate so hashing and ZIP encoding
/// never stall the UI (BUILD_GUIDE 9.1). [cancel] completing asks the
/// writer to stop after the current file.
Future<ExportWriteResult> writeExportInBackground(
  ExportWritePlan plan, {
  void Function(ExportWriteProgress progress)? onProgress,
  Future<void>? cancel,
}) async {
  final fromWorker = ReceivePort();
  final result = Completer<ExportWriteResult>();
  SendPort? toWorker;
  var cancelRequested = false;
  unawaited(
    cancel?.then((_) {
      cancelRequested = true;
      toWorker?.send('cancel');
    }),
  );
  fromWorker.listen((message) {
    if (message is SendPort) {
      toWorker = message;
      if (cancelRequested) message.send('cancel');
    } else if (message is ExportWriteProgress) {
      onProgress?.call(message);
    } else if (message is ExportWriteResult) {
      if (!result.isCompleted) result.complete(message);
    } else if (message is _WorkerError && !result.isCompleted) {
      result.completeError(
        message.toException(),
        StackTrace.fromString(message.stackTrace),
      );
    } else if (message is List && !result.isCompleted) {
      // An uncaught isolate error: [error, stack] as strings.
      result.completeError(
        Exception('${message.first}'),
        StackTrace.fromString('${message.last}'),
      );
    }
  });
  final isolate = await Isolate.spawn(
    _exportWorker,
    (fromWorker.sendPort, plan),
    errorsAreFatal: true,
    onError: fromWorker.sendPort,
  );
  try {
    return await result.future;
  } finally {
    fromWorker.close();
    isolate.kill();
  }
}

Future<void> _exportWorker((SendPort, ExportWritePlan) args) async {
  final (reply, plan) = args;
  final control = ReceivePort();
  var cancelled = false;
  control.listen((m) {
    if (m == 'cancel') cancelled = true;
  });
  reply.send(control.sendPort);
  try {
    final result = await writeExport(
      plan,
      onProgress: reply.send,
      isCancelled: () => cancelled,
    );
    reply.send(result);
  } catch (error, stack) {
    reply.send(_WorkerError.from(error, stack));
  } finally {
    control.close();
  }
}

/// An error from the worker, in a form that always crosses isolates.
class _WorkerError {
  _WorkerError(this.kind, this.message, StackTrace stack, [this.osCode])
    : stackTrace = stack.toString();

  factory _WorkerError.from(Object error, StackTrace stack) => switch (error) {
    ExportCancelledException() => _WorkerError('cancelled', '', stack),
    ExportOutOfSpaceException(:final cause) => _WorkerError(
      'out_of_space',
      cause.message,
      stack,
      cause.osError?.errorCode,
    ),
    AudioTrimException(:final message) => _WorkerError('trim', message, stack),
    FileSystemException(:final message) => _WorkerError(
      'file_system',
      message,
      stack,
      error.osError?.errorCode,
    ),
    _ => _WorkerError('other', error.toString(), stack),
  };

  final String kind;
  final String message;
  final String stackTrace;
  final int? osCode;

  Object toException() => switch (kind) {
    'cancelled' => const ExportCancelledException(),
    'out_of_space' => ExportOutOfSpaceException(
      FileSystemException(message, null, OSError('', osCode ?? 0)),
    ),
    'trim' => AudioTrimException(message),
    'file_system' => FileSystemException(
      message,
      null,
      osCode == null ? null : OSError('', osCode!),
    ),
    _ => Exception(message),
  };
}
