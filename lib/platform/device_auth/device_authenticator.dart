/// Whether the device can check it is the owner (FR-PRI-06, ADR-041).
enum DeviceAuthAvailability {
  /// Biometrics, a device PIN, pattern, password or Windows Hello is set up.
  available,

  /// The device could check, but nothing is set up (no PIN, no Hello).
  notSetUp,

  /// This device or platform has no way to check at all.
  unsupported,
}

/// The outcome of one prompt (FR-PRI-06, ADR-041).
enum DeviceAuthResult {
  /// The OS confirmed the owner.
  success,

  /// The person closed the prompt, or the OS cancelled it (for example the
  /// app went to the background). Trying again is fine.
  cancelled,

  /// Too many failed tries. The OS will allow another try later.
  lockedOut,

  /// Nothing is set up any more, or the platform cannot show a prompt. App
  /// lock must not keep the person out of their recordings because of this
  /// (fail safe, ADR-041).
  unavailable,
}

/// The platform's own owner check: biometrics or device PIN on Android and
/// iOS, Windows Hello on Windows (FR-PRI-06, ADR-041).
///
/// Attenlume never sees biometric data. It receives only pass or fail
/// (PRIVACY_AND_SAFETY 3).
abstract interface class DeviceAuthenticator {
  Future<DeviceAuthAvailability> availability();

  /// Shows the OS prompt with [reason]. Never throws.
  Future<DeviceAuthResult> authenticate(String reason);
}
