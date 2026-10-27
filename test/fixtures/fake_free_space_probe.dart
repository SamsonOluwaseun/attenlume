import 'package:attenlume/platform/storage/free_space_probe.dart';

/// A [FreeSpaceProbe] whose answer the test sets, for low-storage
/// simulation [P0-11].
class FakeFreeSpaceProbe implements FreeSpaceProbe {
  FakeFreeSpaceProbe(this.availableBytes, {this.totalBytes = 64 << 30});

  /// Null simulates a platform that cannot tell.
  int? availableBytes;
  int totalBytes;
  final queriedPaths = <String>[];

  @override
  Future<FreeSpace?> query(String path) async {
    queriedPaths.add(path);
    final available = availableBytes;
    return available == null
        ? null
        : FreeSpace(availableBytes: available, totalBytes: totalBytes);
  }
}
