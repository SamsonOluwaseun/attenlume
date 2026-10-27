import 'package:attenlume/domain/services/storage_thresholds.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fake_free_space_probe.dart';

void main() {
  const mib = 1024 * 1024;
  // 96 kbps, the Windows floor (ADR-002), in bytes per second.
  const windowsRate = 96000 / 8;

  group('FR-STO-02 storage thresholds [P0-11]', () {
    test('FR-STO-02 plenty of space is ok', () {
      final a = assessStorage(freeBytes: 50 << 30, bytesPerSecond: windowsRate);
      expect(a.level, StorageLevel.ok);
      expect(a.minutesLeft, greaterThan(60));
    });

    test('FR-STO-02 below 1 GB free warns', () {
      final a = assessStorage(freeBytes: 1000 * mib, bytesPerSecond: null);
      expect(a.level, StorageLevel.warning);
      expect(a.minutesLeft, isNull);
    });

    test('FR-STO-02 under 60 minutes left warns even above 1 GB', () {
      // 1.5 GB free at 1 MB/s: about 24 minutes before the reserve.
      final a = assessStorage(freeBytes: 1536 * mib, bytesPerSecond: 1e6);
      expect(a.level, StorageLevel.warning);
      expect(a.minutesLeft, lessThan(60));
    });

    test('FR-STO-02 near 300 MB is urgent', () {
      final a = assessStorage(freeBytes: 300 * mib, bytesPerSecond: null);
      expect(a.level, StorageLevel.urgent);
    });

    test('FR-STO-04 at the hard reserve stops with no minutes left', () {
      final a = assessStorage(
        freeBytes: 100 * mib,
        bytesPerSecond: windowsRate,
      );
      expect(a.level, StorageLevel.hardStop);
      expect(a.minutesLeft, 0);
    });

    test(
      'AT-STO-02 simulated recording on a filling disk warns, then urges, '
      'then stops before the disk is empty',
      () async {
        // A disk with 10 GiB free, recording at 96 kbps while another app
        // writes 2 MiB per tick (30 s), checked every 30 seconds (FR-STO-03).
        // The assessment uses only the recording rate to estimate minutes
        // left; the other app's drain makes the real decline faster.
        final probe = FakeFreeSpaceProbe(10240 * mib);
        const otherAppPerTick = 60 * mib;
        const recordingPerTick = (windowsRate * 30) ~/ 1;
        final seen = <StorageLevel>[];
        var ticks = 0;
        while (true) {
          final space = await probe.query('C:\\media');
          final a = assessStorage(
            freeBytes: space!.availableBytes,
            bytesPerSecond: windowsRate,
          );
          if (seen.isEmpty || seen.last != a.level) seen.add(a.level);
          if (a.level == StorageLevel.hardStop) break;
          probe.availableBytes =
              probe.availableBytes! - recordingPerTick - otherAppPerTick;
          ticks++;
          expect(ticks, lessThan(1000));
        }
        expect(seen, [
          StorageLevel.ok,
          StorageLevel.warning,
          StorageLevel.urgent,
          StorageLevel.hardStop,
        ]);
        // The stop happens with space still free, never at zero.
        expect(probe.availableBytes, greaterThan(0));
        expect(
          probe.availableBytes,
          greaterThan(100 * mib - otherAppPerTick - recordingPerTick),
        );
      },
    );
  });
}
