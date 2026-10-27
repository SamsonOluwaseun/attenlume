/// How close the device is to running out of space (FR-STO-02).
enum StorageLevel {
  ok,

  /// Below the warning space or minutes threshold.
  warning,

  /// Near the urgent space threshold.
  urgent,

  /// At the hard reserve: finalise the segment and stop (FR-STO-04).
  hardStop,
}

/// Storage thresholds from FR-STO-02. These are the build guide's starting
/// values. The hard reserve is our own starting point (ADR-008). All are
/// to be adjusted after device testing.
class StorageThresholds {
  const StorageThresholds({
    this.warningBytes = 1024 * 1024 * 1024,
    this.warningMinutes = 60,
    this.urgentBytes = 300 * 1024 * 1024,
    this.hardStopBytes = 100 * 1024 * 1024,
  }) : assert(hardStopBytes < urgentBytes && urgentBytes < warningBytes);

  final int warningBytes;
  final int warningMinutes;
  final int urgentBytes;

  /// Free space never used for recording, so the OS, the database and the
  /// segment finalisation always have room.
  final int hardStopBytes;
}

/// One storage check: the level and the recording time left.
class StorageAssessment {
  const StorageAssessment({required this.level, required this.minutesLeft});

  final StorageLevel level;

  /// Whole minutes of recording left before the hard reserve, at the given
  /// write rate. Null when the rate is unknown or zero.
  final int? minutesLeft;
}

/// Classifies [freeBytes] for a recording writing [bytesPerSecond]
/// (measured file growth where available, FR-STO-01) [P0-11, FR-STO-02].
StorageAssessment assessStorage({
  required int freeBytes,
  required double? bytesPerSecond,
  StorageThresholds thresholds = const StorageThresholds(),
}) {
  final usable = freeBytes - thresholds.hardStopBytes;
  final minutesLeft = bytesPerSecond == null || bytesPerSecond <= 0
      ? null
      : usable <= 0
      ? 0
      : usable ~/ (bytesPerSecond * 60);

  final StorageLevel level;
  if (usable <= 0) {
    level = StorageLevel.hardStop;
  } else if (freeBytes <= thresholds.urgentBytes) {
    level = StorageLevel.urgent;
  } else if (freeBytes < thresholds.warningBytes ||
      (minutesLeft != null && minutesLeft < thresholds.warningMinutes)) {
    level = StorageLevel.warning;
  } else {
    level = StorageLevel.ok;
  }
  return StorageAssessment(level: level, minutesLeft: minutesLeft);
}
