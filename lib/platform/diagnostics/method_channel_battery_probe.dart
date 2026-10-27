import 'package:flutter/services.dart';

import 'battery_probe.dart';

/// Battery level from `BatteryChannel.kt` on Android (FR-REC-06) [P1-13].
class MethodChannelBatteryProbe implements BatteryProbe {
  const MethodChannelBatteryProbe([
    this._channel = const MethodChannel('com.samlytics.attenlume/battery'),
  ]);

  final MethodChannel _channel;

  @override
  Future<BatteryReading?> read() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'readBattery',
      );
      final percent = (res?['percent'] as num?)?.toInt();
      final charging = res?['charging'] as bool?;
      if (percent == null || charging == null) return null;
      return BatteryReading(percent: percent, charging: charging);
    } catch (_) {
      return null;
    }
  }
}
