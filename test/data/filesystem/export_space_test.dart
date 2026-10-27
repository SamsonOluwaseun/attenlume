import 'dart:io';

import 'package:attenlume/data/filesystem/export_space.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fake_free_space_probe.dart';

void main() {
  const mib = 1024 * 1024;

  group('FR-EXP-05 export preflight [P0-11]', () {
    test('FR-EXP-05 estimate covers every byte plus per-file overhead', () {
      final estimate = estimateFolderExportBytes([10 * mib, 5 * mib, 0]);
      expect(estimate, greaterThan(15 * mib));
      // Overhead stays small: under 32 KiB for three files.
      expect(estimate - 15 * mib, lessThan(32 * 1024));
    });

    test('FR-EXP-05 enough space with the reserve left over is ok', () async {
      final result = await preflightExport(
        requiredBytes: 100 * mib,
        destination: 'D:\\exports',
        probe: FakeFreeSpaceProbe(356 * mib),
        reserveBytes: 256 * mib,
      );
      expect(result.status, PreflightStatus.ok);
      expect(result.shortfallBytes, 0);
    });

    test('AT-STO-03 eating into the reserve is insufficient', () async {
      final result = await preflightExport(
        requiredBytes: 100 * mib,
        destination: 'D:\\exports',
        probe: FakeFreeSpaceProbe(356 * mib - 1),
        reserveBytes: 256 * mib,
      );
      expect(result.status, PreflightStatus.insufficient);
      expect(result.shortfallBytes, 1);
      expect(result.toJson()['status'], 'insufficient');
    });

    test('FR-EXP-05 a platform without a probe gives unknown', () async {
      final result = await preflightExport(
        requiredBytes: 1,
        destination: '/data/exports',
        probe: FakeFreeSpaceProbe(null),
      );
      expect(result.status, PreflightStatus.unknown);
      expect(result.shortfallBytes, 0);
    });

    test('FR-EXP-05 the probe is asked about the destination', () async {
      final probe = FakeFreeSpaceProbe(1 << 40);
      await preflightExport(
        requiredBytes: 1,
        destination: 'E:\\usb\\exports',
        probe: probe,
      );
      expect(probe.queriedPaths, ['E:\\usb\\exports']);
    });
  });

  group('FR-STO-04 disk-full errors are recognised [P0-11]', () {
    FileSystemException withCode(int code) =>
        FileSystemException('write failed', 'x', OSError('full', code));

    test('FR-STO-04 Windows ERROR_DISK_FULL and ERROR_HANDLE_DISK_FULL', () {
      expect(isOutOfSpaceError(withCode(112), windows: true), isTrue);
      expect(isOutOfSpaceError(withCode(39), windows: true), isTrue);
      expect(isOutOfSpaceError(withCode(5), windows: true), isFalse);
      expect(isOutOfSpaceError(withCode(28), windows: true), isFalse);
    });

    test('FR-STO-04 POSIX ENOSPC on Android and iOS', () {
      expect(isOutOfSpaceError(withCode(28), windows: false), isTrue);
      expect(isOutOfSpaceError(withCode(39), windows: false), isFalse);
    });

    test('FR-STO-04 an error without an OS code is not disk full', () {
      expect(
        isOutOfSpaceError(const FileSystemException('x'), windows: true),
        isFalse,
      );
    });
  });
}
