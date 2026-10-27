import 'dart:io';

import 'package:attenlume/domain/services/storage_thresholds.dart';
import 'package:attenlume/spikes/storage_export_spike.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fake_free_space_probe.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'storage_export_spike_test',
    );
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('P0-11 storage export spike [P0-11]', () {
    test(
      'P0-11 runs export spike with bounded RAM and verified checksums',
      () async {
        final probe = FakeFreeSpaceProbe(
          10 * 1024 * 1024 * 1024,
        ); // 10 GiB free
        final spike = StorageExportSpike(workDir: tempDir, probe: probe);

        const testBytes = 5 * 1024 * 1024; // 5 MiB
        final report = await spike.run(syntheticFileBytes: testBytes);

        expect(report.deviceFreeBytes, 10 * 1024 * 1024 * 1024);
        expect(report.thresholdAssessment.level, StorageLevel.ok);
        expect(report.testFileBytes, testBytes);
        expect(report.folderChecksumsValid, isTrue);
        expect(report.zipSizeBytes, greaterThan(testBytes));
        // Bounded RAM: RSS delta stays well within a normal process variation (under 50 MiB)
        expect(report.folderExportDeltaRssBytes, lessThan(50 * 1024 * 1024));
        expect(report.zipExportDeltaRssBytes, lessThan(50 * 1024 * 1024));

        final json = report.toJson();
        expect(json['storage_level'], 'ok');
        expect(json['folder_checksums_valid'], true);
      },
    );
  });
}
