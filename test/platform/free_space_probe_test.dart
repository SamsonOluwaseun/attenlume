import 'dart:io';

import 'package:attenlume/platform/storage/free_space_probe.dart';
import 'package:attenlume/platform/storage/windows_free_space_probe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('free_space_probe_test');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  group('FR-STO-01 free-space probe [P0-11]', () {
    test('FR-STO-01 nearestExistingDirectory walks up to a folder that '
        'exists', () {
      final missing = p.join(root.path, 'not', 'yet', 'made');
      expect(nearestExistingDirectory(missing), root.absolute.path);
      expect(nearestExistingDirectory(root.path), root.absolute.path);
    });

    test('FR-STO-01 the unknown probe answers null, never "plenty"', () async {
      expect(await const UnknownFreeSpaceProbe().query(root.path), isNull);
    });

    test(
      'FR-STO-01 forPlatform picks the Windows probe on Windows',
      () {
        expect(FreeSpaceProbe.forPlatform(), isA<WindowsFreeSpaceProbe>());
      },
      skip: Platform.isWindows ? false : 'Windows only',
    );

    test(
      'FR-STO-01 Windows probe reports the volume of a folder and of a path '
      'not created yet',
      () async {
        final probe = WindowsFreeSpaceProbe();
        final here = await probe.query(root.path);
        final later = await probe.query(p.join(root.path, 'a', 'b'));
        expect(here, isNotNull);
        expect(here!.totalBytes, greaterThan(0));
        expect(here.availableBytes, greaterThan(0));
        expect(here.availableBytes, lessThanOrEqualTo(here.totalBytes));
        expect(later!.totalBytes, here.totalBytes);
      },
      skip: Platform.isWindows ? false : 'Windows only',
    );

    test(
      'FR-STO-01 Windows probe agrees with the OS figure for the drive',
      () async {
        final drive = p.rootPrefix(root.absolute.path).substring(0, 1);
        final ps = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          '(Get-PSDrive $drive).Free',
        ]);
        final osFree = int.parse((ps.stdout as String).trim());
        final ours = await WindowsFreeSpaceProbe().query(root.path);
        // Other processes write meanwhile, so allow 512 MiB of drift.
        expect((ours!.availableBytes - osFree).abs(), lessThan(512 << 20));
      },
      skip: Platform.isWindows ? false : 'Windows only',
    );

    test(
      'FR-STO-01 Windows probe answers null for a drive that does not exist',
      () async {
        final unused = 'BCDEFGHIJKLMNOPQRSTUVWXYZ'
            .split('')
            .firstWhere((d) => !Directory('$d:\\').existsSync());
        expect(await WindowsFreeSpaceProbe().query('$unused:\\x'), isNull);
      },
      skip: Platform.isWindows ? false : 'Windows only',
    );
  });
}
