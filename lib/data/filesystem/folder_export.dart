import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../platform/storage/free_space_probe.dart';
import 'export_space.dart';

/// One file written by [exportFolder].
class ExportedFile {
  const ExportedFile({
    required this.relativePath,
    required this.bytes,
    required this.sha256,
  });

  /// Forward slashes, relative to the export folder.
  final String relativePath;
  final int bytes;
  final String sha256;

  Map<String, Object?> toJson() => {
    'path': relativePath,
    'bytes': bytes,
    'sha256': sha256,
  };
}

class FolderExportResult {
  const FolderExportResult({required this.folder, required this.files});

  final Directory folder;

  /// Every copied file, excluding `checksums.sha256` itself.
  final List<ExportedFile> files;

  int get totalBytes => files.fold(0, (sum, f) => sum + f.bytes);
}

/// Name of the checksum list written into every export (FR-EXP-06).
const checksumFileName = 'checksums.sha256';

/// Copies every file under [source] into a new folder [folderName] inside
/// [destinationParent], streaming and hashing as it goes [P0-06, FR-EXP-04,
/// FR-EXP-05, FR-EXP-06].
///
/// - Never overwrites: fails if the destination folder already exists.
/// - Never touches [source].
/// - Writes into `<folderName>.partial` and renames at the end, so a half
///   export never looks complete. On failure only that partial folder is
///   removed: it holds copies, never unique media.
/// - Each copy is read back and its SHA-256 compared with the source hash.
///
/// - With [freeSpace], checks the destination first and throws
///   [InsufficientSpaceException] before writing anything if the export and
///   [reserveBytes] do not fit [P0-11, AT-STO-03].
/// - If the disk fills mid-export, throws [ExportOutOfSpaceException] after
///   removing the partial folder.
///
/// [onFileDone] is called after each verified copy, for progress reporting.
/// [openSink] replaces the file writer, for failure tests.
Future<FolderExportResult> exportFolder({
  required Directory source,
  required Directory destinationParent,
  required String folderName,
  void Function(ExportedFile file)? onFileDone,
  FreeSpaceProbe? freeSpace,
  int reserveBytes = defaultExportReserveBytes,
  ExportSinkOpener openSink = openFileExportSink,
}) async {
  final finalDir = Directory(p.join(destinationParent.path, folderName));
  final partialDir = Directory('${finalDir.path}.partial');
  if (finalDir.existsSync() || partialDir.existsSync()) {
    throw FileSystemException('Export folder already exists', finalDir.path);
  }
  final sourceFiles =
      source
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  if (freeSpace != null) {
    final preflight = await preflightExport(
      requiredBytes: estimateFolderExportBytes(
        sourceFiles.map((f) => f.lengthSync()),
      ),
      destination: destinationParent.path,
      probe: freeSpace,
      reserveBytes: reserveBytes,
    );
    if (preflight.status == PreflightStatus.insufficient) {
      throw InsufficientSpaceException(preflight);
    }
  }

  await partialDir.create(recursive: true);
  try {
    final exported = <ExportedFile>[];
    for (final file in sourceFiles) {
      final relative = p.relative(file.path, from: source.path);
      final target = File(p.join(partialDir.path, relative));
      await target.parent.create(recursive: true);
      final (bytes, digest) = await copyFileHashing(file, target, openSink);
      final check = await hashFileSha256(target);
      if (check != digest) {
        throw FileSystemException('Copy does not match source', target.path);
      }
      final done = ExportedFile(
        relativePath: p.posix.joinAll(p.split(relative)),
        bytes: bytes,
        sha256: digest,
      );
      exported.add(done);
      onFileDone?.call(done);
    }
    await File(p.join(partialDir.path, checksumFileName)).writeAsString(
      exported.map((f) => '${f.sha256}  ${f.relativePath}\n').join(),
      flush: true,
    );
    await partialDir.rename(finalDir.path);
    return FolderExportResult(folder: finalDir, files: exported);
  } catch (error) {
    if (partialDir.existsSync()) await partialDir.delete(recursive: true);
    if (error is FileSystemException && isOutOfSpaceError(error)) {
      throw ExportOutOfSpaceException(error);
    }
    rethrow;
  }
}

/// Where [exportFolder] writes one file's bytes.
abstract interface class ExportSink {
  Future<void> add(List<int> chunk);

  /// Flushes to disk and closes.
  Future<void> close();
}

typedef ExportSinkOpener = Future<ExportSink> Function(File target);

/// The real writer: a [RandomAccessFile], flushed on close.
Future<ExportSink> openFileExportSink(File target) async =>
    _FileExportSink(await target.open(mode: FileMode.writeOnly));

class _FileExportSink implements ExportSink {
  _FileExportSink(this._file);

  final RandomAccessFile _file;

  @override
  Future<void> add(List<int> chunk) => _file.writeFrom(chunk);

  @override
  Future<void> close() async {
    try {
      await _file.flush();
    } finally {
      await _file.close();
    }
  }
}

/// Streams [from] into [to] (temp name, flush, rename) and hashes in the
/// same pass. Memory use is one read chunk. Returns the byte count and the
/// SHA-256 hex digest. Used by [exportFolder] and the P1-21 export writer.
Future<(int, String)> copyFileHashing(
  File from,
  File to, [
  ExportSinkOpener openSink = openFileExportSink,
]) async {
  final temp = File('${to.path}.tmp');
  final digestSink = _DigestSink();
  final hasher = sha256.startChunkedConversion(digestSink);
  final out = await openSink(temp);
  var bytes = 0;
  var written = false;
  try {
    await for (final chunk in from.openRead()) {
      hasher.add(chunk);
      await out.add(chunk);
      bytes += chunk.length;
    }
    written = true;
  } finally {
    if (written) {
      await out.close();
    } else {
      // Keep the write error, not a second one from closing.
      try {
        await out.close();
      } catch (_) {}
    }
  }
  hasher.close();
  await temp.rename(to.path);
  return (bytes, digestSink.value.toString());
}

/// SHA-256 hex digest of [file], streamed (FR-EXP-04, FR-EXP-06).
Future<String> hashFileSha256(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Reads `checksums.sha256` in [folder] and re-hashes every listed file.
/// Returns the relative paths that are missing or do not match.
Future<List<String>> verifyChecksums(Directory folder) async {
  final lines = await File(p.join(folder.path, checksumFileName)).readAsLines();
  final failures = <String>[];
  for (final line in lines.where((l) => l.trim().isNotEmpty)) {
    final split = line.indexOf('  ');
    final expected = line.substring(0, split);
    final relative = line.substring(split + 2);
    final file = File(p.joinAll([folder.path, ...p.posix.split(relative)]));
    if (!file.existsSync() || await hashFileSha256(file) != expected) {
      failures.add(relative);
    }
  }
  return failures;
}
