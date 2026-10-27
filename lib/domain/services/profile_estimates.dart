import '../models/enums.dart';
import 'capture_settings.dart';
import 'storage_thresholds.dart';

/// What one profile will use on this device, and how long the free space
/// lasts at that rate (FR-UI-08, FR-QUAL-05) [P1-09].
class ProfileEstimate {
  const ProfileEstimate({required this.settings, required this.minutesLeft});

  /// The settings that will actually be requested (ADR-002).
  final EffectiveCaptureSettings settings;

  /// Whole minutes until the hard reserve, at the requested bitrate. Null
  /// when free space is unknown: never shown as "plenty".
  final int? minutesLeft;

  RecordingProfile get profile => settings.profile;

  /// Megabytes per hour at the bitrate that will be requested, not the
  /// profile target.
  double get megabytesPerHour => settings.megabytesPerHour;
}

/// Estimates [profile] on [platform] with [freeBytes] free (null when the
/// platform cannot tell). Uses the nominal bitrate, since nothing has been
/// recorded yet to measure (FR-STO-01 measures during recording, P1-12).
ProfileEstimate estimateProfile(
  RecordingProfile profile,
  CapturePlatform platform, {
  required int? freeBytes,
  StorageThresholds thresholds = const StorageThresholds(),
}) {
  final settings = effectiveCaptureSettings(profile, platform);
  final minutesLeft = freeBytes == null
      ? null
      : assessStorage(
          freeBytes: freeBytes,
          bytesPerSecond: settings.bitrateBps / 8,
          thresholds: thresholds,
        ).minutesLeft;
  return ProfileEstimate(settings: settings, minutesLeft: minutesLeft);
}

/// "21.6 MB per hour".
String formatMegabytesPerHour(double megabytesPerHour) =>
    '${megabytesPerHour.toStringAsFixed(1)} MB per hour';

/// "About 45 minutes left", "About 6 h 10 min left", "Space left unknown".
String formatTimeLeft(int? minutes) {
  if (minutes == null) return 'Space left unknown';
  if (minutes <= 0) return 'No space left';
  if (minutes < 60) {
    return 'About $minutes ${minutes == 1 ? 'minute' : 'minutes'} left';
  }
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? 'About $hours h left' : 'About $hours h $rest min left';
}

/// The plain explanation shown before recording when [settings] differ
/// from the profile target (FR-QUAL-05), or null when they match. Says
/// what will be used; never calls the fallback equivalent.
String? effectiveSettingsNotice(
  EffectiveCaptureSettings settings,
  CapturePlatform platform,
) {
  if (!settings.differsFromTarget) return null;
  final profile = settings.profile;
  final target = profile.targetBitrateBps ~/ 1000;
  final actual = settings.bitrateBps ~/ 1000;
  final reason = platform == CapturePlatform.windows
      ? "Windows' audio encoder cannot go below $actual kbps"
      : 'This device cannot record at $target kbps';
  return '$reason, so ${profile.label} records at $actual kbps instead of '
      '$target kbps (${formatMegabytesPerHour(settings.megabytesPerHour)}). '
      'Each recording notes the setting it used.';
}
