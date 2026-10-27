import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'free_space_probe.dart';

typedef _GetDiskFreeSpaceExWNative = Int32 Function(
  Pointer<Utf16> directoryName,
  Pointer<Uint64> freeBytesAvailableToCaller,
  Pointer<Uint64> totalNumberOfBytes,
  Pointer<Uint64> totalNumberOfFreeBytes,
);
typedef _GetDiskFreeSpaceExWDart = int Function(
  Pointer<Utf16> directoryName,
  Pointer<Uint64> freeBytesAvailableToCaller,
  Pointer<Uint64> totalNumberOfBytes,
  Pointer<Uint64> totalNumberOfFreeBytes,
);

/// Calls `GetDiskFreeSpaceExW` in kernel32 through `dart:ffi` [P0-11].
///
/// https://learn.microsoft.com/windows/win32/api/fileapi/nf-fileapi-getdiskfreespaceexw
/// We report `lpFreeBytesAvailableToCaller`, which honours per-user disk
/// quotas. Works for local drives, USB drives and UNC shares.
class WindowsFreeSpaceProbe implements FreeSpaceProbe {
  WindowsFreeSpaceProbe()
    : _getDiskFreeSpaceEx = DynamicLibrary.open('kernel32.dll')
          .lookupFunction<_GetDiskFreeSpaceExWNative, _GetDiskFreeSpaceExWDart>(
            'GetDiskFreeSpaceExW',
          );

  final _GetDiskFreeSpaceExWDart _getDiskFreeSpaceEx;

  @override
  Future<FreeSpace?> query(String path) async {
    final directory = nearestExistingDirectory(path);
    if (directory == null) return null;
    return using((arena) {
      final available = arena<Uint64>();
      final total = arena<Uint64>();
      final totalFree = arena<Uint64>();
      final ok = _getDiskFreeSpaceEx(
        directory.toNativeUtf16(allocator: arena),
        available,
        total,
        totalFree,
      );
      if (ok == 0) return null;
      return FreeSpace(
        availableBytes: available.value,
        totalBytes: total.value,
      );
    });
  }
}
