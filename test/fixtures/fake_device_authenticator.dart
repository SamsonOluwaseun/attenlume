import 'dart:async';

import 'package:attenlume/platform/device_auth/device_authenticator.dart';

/// A [DeviceAuthenticator] whose answers the test sets (FR-PRI-06).
class FakeDeviceAuthenticator implements DeviceAuthenticator {
  FakeDeviceAuthenticator({
    this.availabilityResult = DeviceAuthAvailability.available,
    this.result = DeviceAuthResult.success,
  });

  DeviceAuthAvailability availabilityResult;
  DeviceAuthResult result;

  /// When set, [authenticate] waits for it, so a test can act while the
  /// OS prompt is "up".
  Completer<void>? gate;

  final reasons = <String>[];

  @override
  Future<DeviceAuthAvailability> availability() async => availabilityResult;

  @override
  Future<DeviceAuthResult> authenticate(String reason) async {
    reasons.add(reason);
    final g = gate;
    if (g != null) await g.future;
    return result;
  }
}
