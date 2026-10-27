import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'battery_probe.dart';

/// `SYSTEM_POWER_STATUS` from winbase.h.
final class _SystemPowerStatus extends Struct {
  @Uint8()
  external int acLineStatus;

  @Uint8()
  external int batteryFlag;

  @Uint8()
  external int batteryLifePercent;

  @Uint8()
  external int systemStatusFlag;

  @Uint32()
  external int batteryLifeTime;

  @Uint32()
  external int batteryFullLifeTime;
}

typedef _GetSystemPowerStatusNative = Int32 Function(
  Pointer<_SystemPowerStatus> status,
);
typedef _GetSystemPowerStatusDart = int Function(
  Pointer<_SystemPowerStatus> status,
);

/// Calls `GetSystemPowerStatus` in kernel32 through `dart:ffi` [P0-10].
///
/// https://learn.microsoft.com/windows/win32/api/winbase/nf-winbase-getsystempowerstatus
/// A percent of 255 means unknown and battery flag 128 means no system
/// battery (a desktop PC or most virtual machines): both answer null.
class WindowsBatteryProbe implements BatteryProbe {
  WindowsBatteryProbe()
    : _getSystemPowerStatus = DynamicLibrary.open('kernel32.dll')
          .lookupFunction<
            _GetSystemPowerStatusNative,
            _GetSystemPowerStatusDart
          >('GetSystemPowerStatus');

  final _GetSystemPowerStatusDart _getSystemPowerStatus;

  @override
  Future<BatteryReading?> read() async => using((arena) {
    final status = arena<_SystemPowerStatus>();
    if (_getSystemPowerStatus(status) == 0) return null;
    return windowsBatteryReading(
      acLineStatus: status.ref.acLineStatus,
      batteryFlag: status.ref.batteryFlag,
      batteryLifePercent: status.ref.batteryLifePercent,
    );
  });
}

/// Maps the raw `SYSTEM_POWER_STATUS` fields to a reading. Separate so
/// the mapping is testable without a battery.
BatteryReading? windowsBatteryReading({
  required int acLineStatus,
  required int batteryFlag,
  required int batteryLifePercent,
}) {
  const noSystemBattery = 128;
  const unknownStatus = 255;
  if (batteryFlag == unknownStatus || batteryFlag & noSystemBattery != 0) {
    return null;
  }
  if (batteryLifePercent > 100) return null;
  return BatteryReading(
    percent: batteryLifePercent,
    charging: acLineStatus == 1,
  );
}
