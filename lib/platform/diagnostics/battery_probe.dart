import 'dart:io';

import 'method_channel_battery_probe.dart';
import 'windows_battery_probe.dart';

/// One battery reading.
class BatteryReading {
  const BatteryReading({required this.percent, required this.charging});

  /// 0 to 100.
  final int percent;

  /// True when on mains power. A run on mains says nothing about drain.
  final bool charging;

  Map<String, Object?> toJson() => {'percent': percent, 'charging': charging};
}

/// Battery level for the P0-10 long run and, later, the low-battery
/// safety prompt (FR-REC-06, P1-13) [P0-10].
///
/// No package is adopted for this (ADR-015, ADR-032): Windows asks the OS
/// directly, Android uses `BatteryChannel.kt`, iOS answers null until its
/// channel is built on a Mac.
abstract interface class BatteryProbe {
  /// The current reading, or null when the platform cannot tell or the
  /// device has no battery. Callers must treat null as "unknown".
  Future<BatteryReading?> read();

  factory BatteryProbe.forPlatform() => Platform.isWindows
      ? WindowsBatteryProbe()
      : Platform.isAndroid
      ? const MethodChannelBatteryProbe()
      : const UnknownBatteryProbe();
}

/// Used where no native probe exists yet.
class UnknownBatteryProbe implements BatteryProbe {
  const UnknownBatteryProbe();

  @override
  Future<BatteryReading?> read() async => null;
}
