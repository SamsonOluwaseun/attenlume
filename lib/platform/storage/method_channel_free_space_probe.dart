import 'package:flutter/services.dart';

import 'free_space_probe.dart';

/// Free-space probe using the platform method channel on Android and iOS [P1-12, FR-STO-01].
class MethodChannelFreeSpaceProbe implements FreeSpaceProbe {
  const MethodChannelFreeSpaceProbe([
    this._channel = const MethodChannel('com.samlytics.attenlume/free_space'),
  ]);

  final MethodChannel _channel;

  @override
  Future<FreeSpace?> query(String path) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'queryFreeSpace',
        {'path': path},
      );
      if (res == null) return null;
      final available = (res['availableBytes'] as num?)?.toInt();
      final total = (res['totalBytes'] as num?)?.toInt();
      if (available == null || total == null) return null;
      return FreeSpace(availableBytes: available, totalBytes: total);
    } catch (_) {
      return null;
    }
  }
}
