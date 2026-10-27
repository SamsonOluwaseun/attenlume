import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/profile_estimates.dart';
import 'package:attenlume/domain/services/storage_thresholds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const reserve = 100 * 1024 * 1024;

  group('FR-UI-08 profile estimates [P1-09]', () {
    test('FR-UI-08 MB per hour on phones matches build guide 5.5', () {
      final mb = {
        for (final p in RecordingProfile.values)
          p: estimateProfile(
            p,
            CapturePlatform.android,
            freeBytes: null,
          ).megabytesPerHour,
      };
      expect(mb[RecordingProfile.economy], closeTo(14.4, 1e-9));
      expect(mb[RecordingProfile.balanced], closeTo(21.6, 1e-9));
      expect(mb[RecordingProfile.enhanced], closeTo(28.8, 1e-9));
    });

    test('FR-UI-08 safe time left keeps the hard reserve free', () {
      // 45 minutes at 6 000 bytes per second, above the reserve.
      const free = reserve + 6000 * 60 * 45;
      final e = estimateProfile(
        RecordingProfile.balanced,
        CapturePlatform.ios,
        freeBytes: free,
      );
      expect(e.minutesLeft, 45);
      expect(
        estimateProfile(
          RecordingProfile.balanced,
          CapturePlatform.ios,
          freeBytes: reserve,
        ).minutesLeft,
        0,
      );
    });

    test('FR-UI-08 FR-QUAL-05 Windows estimates use the effective 96 kbps, '
        'not the profile target', () {
      const free = reserve + 6000 * 60 * 45;
      final e = estimateProfile(
        RecordingProfile.balanced,
        CapturePlatform.windows,
        freeBytes: free,
      );
      expect(e.megabytesPerHour, closeTo(43.2, 1e-9));
      expect(e.minutesLeft, 22);
    });

    test('FR-UI-08 unknown free space is never shown as plenty', () {
      final e = estimateProfile(
        RecordingProfile.economy,
        CapturePlatform.android,
        freeBytes: null,
      );
      expect(e.minutesLeft, isNull);
      expect(formatTimeLeft(e.minutesLeft), 'Space left unknown');
    });

    test('FR-UI-08 custom thresholds are honoured', () {
      const thresholds = StorageThresholds(
        warningBytes: 3000,
        urgentBytes: 2000,
        hardStopBytes: 1000,
      );
      final e = estimateProfile(
        RecordingProfile.economy,
        CapturePlatform.android,
        freeBytes: 1000 + 4000 * 60 * 3,
        thresholds: thresholds,
      );
      expect(e.minutesLeft, 3);
    });

    test('FR-UI-08 time left reads in plain UK English', () {
      expect(formatTimeLeft(0), 'No space left');
      expect(formatTimeLeft(1), 'About 1 minute left');
      expect(formatTimeLeft(45), 'About 45 minutes left');
      expect(formatTimeLeft(120), 'About 2 h left');
      expect(formatTimeLeft(370), 'About 6 h 10 min left');
      expect(formatMegabytesPerHour(21.6), '21.6 MB per hour');
    });
  });

  group('FR-QUAL-05 effective settings notice [P1-09]', () {
    test('FR-QUAL-05 no notice when the target is met', () {
      for (final p in RecordingProfile.values) {
        final s = effectiveCaptureSettings(p, CapturePlatform.android);
        expect(effectiveSettingsNotice(s, CapturePlatform.android), isNull);
      }
      final enhancedWin = effectiveCaptureSettings(
        RecordingProfile.enhanced,
        CapturePlatform.windows,
      );
      // 64 kbps still differs from 96 on Windows.
      expect(enhancedWin.differsFromTarget, isTrue);
    });

    test('FR-QUAL-05 Windows explains what will be used, without calling it '
        'equivalent', () {
      final s = effectiveCaptureSettings(
        RecordingProfile.economy,
        CapturePlatform.windows,
      );
      final notice = effectiveSettingsNotice(s, CapturePlatform.windows)!;
      expect(notice, contains('Economy records at 96 kbps instead of 32 kbps'));
      expect(notice, contains('43.2 MB per hour'));
      expect(notice.toLowerCase(), isNot(contains('equivalent')));
    });
  });

  group('FR-QUAL-07 no uncompressed audio by default [P1-09]', () {
    test('FR-QUAL-07 every profile is compressed AAC well below WAV rates', () {
      // 48 kHz 16-bit mono PCM is 768 kbps.
      const wavBps = 48000 * 16;
      for (final platform in CapturePlatform.values) {
        for (final p in RecordingProfile.values) {
          final s = effectiveCaptureSettings(p, platform);
          expect(s.bitrateBps, lessThan(wavBps ~/ 4));
        }
      }
      expect(RecordingProfile.globalDefault, RecordingProfile.balanced);
    });
  });
}
