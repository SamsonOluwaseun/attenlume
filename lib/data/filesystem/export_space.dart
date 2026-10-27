import 'dart:io';

import '../../platform/storage/free_space_probe.dart';

/// Space kept free on the destination after an export finishes, so the
/// export never runs a disk to zero (FR-STO-04, FR-EXP-05). A starting value
/// until device testing (FR-STO-02 says thresholds are adjusted then).
const defaultExportReserveBytes = 256 * 1024 * 1024;

/// Per-file allowance on top of the file's own size: allocation slack (one
/// 4 KiB cluster) and its line in `checksums.sha256`.
const _perFileOverheadBytes = 4096 + 512;

/// Bytes a folder export of files with these [sizes] needs on the
/// destination. Each file is written once (temp name then rename), so no
/// double space is needed.
int estimateFolderExportBytes(Iterable<int> sizes) =>
    sizes.fold(0, (sum, s) => sum + s + _perFileOverheadBytes) +
    _perFileOverheadBytes;

enum PreflightStatus {
  /// Enough space, with the reserve left over.
  ok,

  /// Not enough space. Nothing has been written.
  insufficient,

  /// The platform cannot report free space. The caller decides, and the UI
  /// must say the check was not possible.
  unknown,
}

/// Result of checking free space before an export (FR-EXP-05, AT-STO-03).
class ExportPreflight {
  const ExportPreflight({
    required this.requiredBytes,
    required this.availableBytes,
    required this.reserveBytes,
  });

  final int requiredBytes;
  final int? availableBytes;
  final int reserveBytes;

  PreflightStatus get status {
    final available = availableBytes;
    if (available == null) return PreflightStatus.unknown;
    return available - reserveBytes >= requiredBytes
        ? PreflightStatus.ok
        : PreflightStatus.insufficient;
  }

  /// How much more space is needed, or 0 when there is enough.
  int get shortfallBytes {
    final available = availableBytes;
    if (available == null) return 0;
    final short = requiredBytes + reserveBytes - available;
    return short > 0 ? short : 0;
  }

  Map<String, Object?> toJson() => {
    'status': status.name,
    'required_bytes': requiredBytes,
    'available_bytes': availableBytes,
    'reserve_bytes': reserveBytes,
    'shortfall_bytes': shortfallBytes,
  };
}

/// Asks [probe] about the volume holding [destination] and compares it
/// with [requiredBytes] plus [reserveBytes].
Future<ExportPreflight> preflightExport({
  required int requiredBytes,
  required String destination,
  required FreeSpaceProbe probe,
  int reserveBytes = defaultExportReserveBytes,
}) async {
  final space = await probe.query(destination);
  return ExportPreflight(
    requiredBytes: requiredBytes,
    availableBytes: space?.availableBytes,
    reserveBytes: reserveBytes,
  );
}

/// Thrown before anything is written when the destination is too small
/// (AT-STO-03).
class InsufficientSpaceException implements Exception {
  const InsufficientSpaceException(this.preflight);

  final ExportPreflight preflight;

  @override
  String toString() =>
      'InsufficientSpaceException: needs ${preflight.requiredBytes} bytes '
      'plus a ${preflight.reserveBytes} byte reserve, '
      '${preflight.availableBytes} available';
}

/// Thrown when the disk fills during an export, despite the preflight (for
/// example another app wrote to it meanwhile). The partial copy has been
/// removed and the sources are untouched.
class ExportOutOfSpaceException implements Exception {
  const ExportOutOfSpaceException(this.cause);

  final FileSystemException cause;

  @override
  String toString() => 'ExportOutOfSpaceException: $cause';
}

/// Whether [error] means the disk is full. Windows reports
/// `ERROR_DISK_FULL` (112) or `ERROR_HANDLE_DISK_FULL` (39), Android, iOS
/// and other POSIX systems `ENOSPC` (28).
bool isOutOfSpaceError(FileSystemException error, {bool? windows}) {
  final code = error.osError?.errorCode;
  if (code == null) return false;
  return (windows ?? Platform.isWindows)
      ? code == 112 || code == 39
      : code == 28;
}
