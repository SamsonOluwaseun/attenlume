import 'dart:io';

import 'windows_free_space_probe.dart';

/// Free and total space on the volume that holds a path.
class FreeSpace {
  const FreeSpace({required this.availableBytes, required this.totalBytes});

  /// Bytes this app may still write. On Windows this honours disk quotas,
  /// so it can be lower than the volume's raw free space.
  final int availableBytes;
  final int totalBytes;

  Map<String, Object?> toJson() => {
    'available_bytes': availableBytes,
    'total_bytes': totalBytes,
  };
}

/// Platform-neutral free-space query (ADR-002 item 4, ADR-008) [P0-11,
/// FR-STO-01, FR-EXP-05].
///
/// No maintained package covers Android, iOS and Windows, so each platform
/// gets its own small implementation behind this interface.
abstract interface class FreeSpaceProbe {
  /// Space on the volume holding [path]. [path] need not exist yet: the
  /// nearest existing parent folder is asked instead. Returns null when the
  /// platform cannot tell.
  Future<FreeSpace?> query(String path);

  /// The probe for the running platform. Android and iOS answer null until
  /// their method channels land in P1-12.
  factory FreeSpaceProbe.forPlatform() => Platform.isWindows
      ? WindowsFreeSpaceProbe()
      : const UnknownFreeSpaceProbe();
}

/// Used where no native probe exists yet. Callers must treat null as
/// "unknown", never as "plenty".
class UnknownFreeSpaceProbe implements FreeSpaceProbe {
  const UnknownFreeSpaceProbe();

  @override
  Future<FreeSpace?> query(String path) async => null;
}

/// [path] itself if it is a folder, otherwise its nearest existing parent.
/// Returns null if not even the root exists (for example an unplugged USB
/// drive).
String? nearestExistingDirectory(String path) {
  var current = Directory(path).absolute;
  while (true) {
    if (current.existsSync()) return current.path;
    final parent = current.parent;
    if (parent.path == current.path) return null;
    current = parent;
  }
}
