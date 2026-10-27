import '../models/enums.dart';

/// Operating system family, kept separate from `dart:io` so rules stay
/// testable on any host.
enum CapturePlatform { android, ios, windows }

/// The encoder settings the app will request for a profile on a platform
/// (FR-QUAL-05, ADR-002) [P0-06].
class EffectiveCaptureSettings {
  const EffectiveCaptureSettings({
    required this.profile,
    required this.bitrateBps,
    required this.sampleRateHz,
    required this.channelCount,
  });

  final RecordingProfile profile;
  final int bitrateBps;
  final int sampleRateHz;
  final int channelCount;

  /// True when the platform cannot meet the profile target.
  bool get differsFromTarget => bitrateBps != profile.targetBitrateBps;

  /// Approximate megabytes (10^6 bytes) per hour of audio payload.
  double get megabytesPerHour => bitrateBps * 3600 / 8 / 1e6;
}

/// Lowest AAC-LC bitrate the Windows Media Foundation encoder accepts:
/// 12 000 bytes per second (ADR-002, PLATFORM_FEASIBILITY 2.3).
const int windowsAacMinimumBitrateBps = 96000;

/// Maps [profile] to what [platform] can be asked for. Phones get the
/// profile target. Windows is raised to its encoder floor.
EffectiveCaptureSettings effectiveCaptureSettings(
  RecordingProfile profile,
  CapturePlatform platform,
) => EffectiveCaptureSettings(
  profile: profile,
  bitrateBps: platform == CapturePlatform.windows
      ? (profile.targetBitrateBps < windowsAacMinimumBitrateBps
            ? windowsAacMinimumBitrateBps
            : profile.targetBitrateBps)
      : profile.targetBitrateBps,
  sampleRateHz: 48000,
  channelCount: 1,
);
