import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../platform/storage/free_space_probe.dart';
import 'export_space.dart';
import 'folder_export.dart';

/// Result of an [exportZip] run.
class ZipExportResult {
  const ZipExportResult({
    required this.zipFile,
    required this.checksumFile,
    required this.files,
  });

  /// The completed ZIP file.
  final File zipFile;

  /// Companion `<zipName>.sha256` written alongside the ZIP file.
  final File checksumFile;

  /// Every copied source file, excluding `checksums.sha256` itself.
  final List<ExportedFile> files;

  /// Total uncompressed size of source media files.
  int get totalContentBytes => files.fold(0, (sum, f) => sum + f.bytes);
}

/// Archives every file under [source] into a new ZIP file [zipName].zip
/// inside [destinationParent], streaming members with store (no compression)
/// for audio and photos, and writing SHA-256 checksums [FR-EXP-02, FR-EXP-04,
/// FR-EXP-05, FR-EXP-06, P0-11].
///
/// - Never overwrites: fails if the destination ZIP already exists.
/// - Never touches [source].
/// - Writes into `<zipName>.zip.partial` and renames at the end. On failure,
///   only that partial ZIP is removed: it holds copies, never unique media.
/// - Embeds `checksums.sha256` inside the ZIP archive and writes a companion
///   `<zipName>.sha256` alongside the ZIP.
/// - Checks free space using [freeSpace] before writing anything and throws
///   [InsufficientSpaceException] if there is not enough room.
/// - If the disk fills mid-export, throws [ExportOutOfSpaceException] after
///   removing the partial ZIP.
///
/// [onFileDone] is called after each archived member, for progress reporting.
Future<ZipExportResult> exportZip({
  required Directory source,
  required Directory destinationParent,
  required String zipName,
  void Function(ExportedFile file)? onFileDone,
  FreeSpaceProbe? freeSpace,
  int reserveBytes = defaultExportReserveBytes,
  int level = ZipFileEncoder.store,
}) async {
  final finalZip = File(p.join(destinationParent.path, '$zipName.zip'));
  final partialZip = File(
    p.join(destinationParent.path, '$zipName.zip.partial'),
  );
  final finalChecksum = File(p.join(destinationParent.path, '$zipName.sha256'));
  final partialChecksum = File(
    p.join(destinationParent.path, '$zipName.sha256.partial'),
  );

  if (finalZip.existsSync() || partialZip.existsSync()) {
    throw FileSystemException('Export zip already exists', finalZip.path);
  }

  final sourceFiles =
      source
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  if (freeSpace != null) {
    final preflight = await preflightExport(
      requiredBytes: estimateZipExportBytes(
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

  await destinationParent.create(recursive: true);
  final encoder = ZipFileEncoder();
  encoder.create(partialZip.path, level: level);

  try {
    final exported = <ExportedFile>[];
    for (final file in sourceFiles) {
      final relative = p.relative(file.path, from: source.path);
      final posixRelative = p.posix.joinAll(p.split(relative));
      final bytes = await file.length();
      final digest = await _hashFile(file);

      await encoder.addFile(file, posixRelative, level);

      final done = ExportedFile(
        relativePath: posixRelative,
        bytes: bytes,
        sha256: digest,
      );
      exported.add(done);
      onFileDone?.call(done);
    }

    // Embed checksums.sha256 inside the ZIP
    final checksumContent = exported
        .map((f) => '${f.sha256}  ${f.relativePath}\n')
        .join();
    final checksumArchive = ArchiveFile.string(
      checksumFileName,
      checksumContent,
    );
    checksumArchive.lastModTime =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    encoder.addArchiveFile(checksumArchive);

    await encoder.close();

    // Write companion checksum file
    await partialChecksum.writeAsString(checksumContent, flush: true);

    // Atomically rename
    await partialZip.rename(finalZip.path);
    if (partialChecksum.existsSync()) {
      await partialChecksum.rename(finalChecksum.path);
    }

    return ZipExportResult(
      zipFile: finalZip,
      checksumFile: finalChecksum,
      files: exported,
    );
  } catch (error) {
    try {
      await encoder.close();
    } catch (_) {}
    if (partialZip.existsSync()) await partialZip.delete();
    if (partialChecksum.existsSync()) await partialChecksum.delete();
    if (error is FileSystemException && isOutOfSpaceError(error)) {
      throw ExportOutOfSpaceException(error);
    }
    rethrow;
  }
}

Future<String> _hashFile(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();
