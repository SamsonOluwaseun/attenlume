import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FR-QUAL-05 effective capture settings [P0-06, ADR-002]', () {
    test('FR-QUAL-05 phones request the profile target', () {
      for (final platform in [CapturePlatform.android, CapturePlatform.ios]) {
        for (final profile in RecordingProfile.values) {
          final s = effectiveCaptureSettings(profile, platform);
          expect(s.bitrateBps, profile.targetBitrateBps);
          expect(s.differsFromTarget, isFalse);
          expect(s.channelCount, 1);
          expect(s.sampleRateHz, 48000);
        }
      }
    });

    test('FR-QUAL-05 Windows raises every profile to the 96 kbps floor', () {
      for (final profile in RecordingProfile.values) {
        final s = effectiveCaptureSettings(profile, CapturePlatform.windows);
        expect(s.bitrateBps, windowsAacMinimumBitrateBps);
        expect(s.differsFromTarget, isTrue);
      }
    });

    test('FR-QUAL-05 MB per hour matches build guide 5.5', () {
      final balanced = effectiveCaptureSettings(
        RecordingProfile.balanced,
        CapturePlatform.android,
      );
      expect(balanced.megabytesPerHour, closeTo(21.6, 0.001));
      final windows = effectiveCaptureSettings(
        RecordingProfile.balanced,
        CapturePlatform.windows,
      );
      expect(windows.megabytesPerHour, closeTo(43.2, 0.001));
    });
  });
}
