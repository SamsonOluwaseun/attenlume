import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

/// The device's total memory, used only to recommend an AI model that fits
/// (P3-11). Null when unknown; nothing is ever blocked on it.
abstract interface class DeviceMemoryProbe {
  Future<int?> totalBytes();

  /// The probe for the running platform: Windows reads it directly, Android
  /// asks the app's native code, others (iOS, where AI is off) do not know.
  factory DeviceMemoryProbe.platform() {
    if (Platform.isWindows) return const WindowsDeviceMemoryProbe();
    if (Platform.isAndroid) return const MethodChannelDeviceMemoryProbe();
    return const UnknownDeviceMemoryProbe();
  }
}

class UnknownDeviceMemoryProbe implements DeviceMemoryProbe {
  const UnknownDeviceMemoryProbe();

  @override
  Future<int?> totalBytes() async => null;
}

/// Android: ActivityManager.MemoryInfo.totalMem through a method channel.
/// An app build without the native side answers null, not an error.
class MethodChannelDeviceMemoryProbe implements DeviceMemoryProbe {
  const MethodChannelDeviceMemoryProbe([
    this._channel = const MethodChannel(
      'com.samlytics.attenlume/device_memory',
    ),
  ]);

  final MethodChannel _channel;

  @override
  Future<int?> totalBytes() async {
    try {
      final bytes = await _channel.invokeMethod<num>('totalBytes');
      return bytes == null || bytes <= 0 ? null : bytes.toInt();
    } catch (_) {
      return null;
    }
  }
}

/// Windows: GlobalMemoryStatusEx, whose MEMORYSTATUSEX starts with
/// dwLength (4 bytes), dwMemoryLoad (4 bytes) then ullTotalPhys (8 bytes).
class WindowsDeviceMemoryProbe implements DeviceMemoryProbe {
  const WindowsDeviceMemoryProbe();

  static const _structSize = 64;

  @override
  Future<int?> totalBytes() async {
    try {
      final query = DynamicLibrary.open('kernel32.dll')
          .lookupFunction<
            Int32 Function(Pointer<Uint8>),
            int Function(Pointer<Uint8>)
          >('GlobalMemoryStatusEx');
      final status = calloc<Uint8>(_structSize);
      try {
        status.cast<Uint32>().value = _structSize;
        if (query(status) == 0) return null;
        final total = (status + 8).cast<Uint64>().value;
        return total > 0 ? total : null;
      } finally {
        calloc.free(status);
      }
    } on Object {
      return null;
    }
  }
}
