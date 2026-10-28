import 'package:local_auth/local_auth.dart';

import 'device_authenticator.dart';

/// [DeviceAuthenticator] over the `local_auth` plugin (ADR-041).
///
/// Device credentials are allowed as well as biometrics (`biometricOnly`
/// false), so a person without fingerprint or face unlock can still use
/// their PIN, and Windows Hello works (it cannot be limited to biometrics).
class LocalAuthDeviceAuthenticator implements DeviceAuthenticator {
  LocalAuthDeviceAuthenticator([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<DeviceAuthAvailability> availability() async {
    try {
      return await _auth.isDeviceSupported()
          ? DeviceAuthAvailability.available
          : DeviceAuthAvailability.notSetUp;
    } on Object {
      return DeviceAuthAvailability.unsupported;
    }
  }

  @override
  Future<DeviceAuthResult> authenticate(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
      return ok ? DeviceAuthResult.success : DeviceAuthResult.cancelled;
    } on LocalAuthException catch (e) {
      return resultForCode(e.code);
    } on Object {
      return DeviceAuthResult.unavailable;
    }
  }

  /// How each plugin error maps to what the lock screen does (ADR-041).
  static DeviceAuthResult resultForCode(LocalAuthExceptionCode code) =>
      switch (code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.timeout ||
        LocalAuthExceptionCode.authInProgress ||
        LocalAuthExceptionCode.userRequestedFallback =>
          DeviceAuthResult.cancelled,
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout => DeviceAuthResult.lockedOut,
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable ||
        LocalAuthExceptionCode.uiUnavailable ||
        LocalAuthExceptionCode.deviceError ||
        LocalAuthExceptionCode.unknownError => DeviceAuthResult.unavailable,
      };
}
