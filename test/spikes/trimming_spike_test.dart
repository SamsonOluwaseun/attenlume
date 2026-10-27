import 'dart:io';

import 'package:attenlume/spikes/trimming_spike.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('trimming_spike_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('P0-14 trimming spike runner [P0-14, FR-REV-04, FR-REV-05, FR-REV-06, FR-REV-07, FR-EXP-03, NFR-07]', () {
    test('P0-14 runs trimming spike with verified maths, splitting, manifest, and atomic trim', () async {
      final spike = TrimmingSpike(workDir: tempDir);
      final report = await spike.run();

      expect(report.mathPassed, isTrue);
      expect(report.splitLogicPassed, isTrue);
      expect(report.cutsManifestPassed, isTrue);
      expect(report.trimmedDurationMs, 7000);
      expect(report.trimmedFileInspectedValid, isTrue);
      expect(report.failureRecoveryVerified, isTrue);
      expect(report.trimExecutionMs, greaterThanOrEqualTo(0));
      expect(report.trimmedFileBytes, greaterThan(0));

      // Bounded RAM: RSS delta should remain tiny (well under 50 MB)
      expect(report.trimDeltaRssBytes, lessThan(50 * 1024 * 1024));

      final json = report.toJson();
      expect(json['trimmed_duration_ms'], 7000);
      expect(json['math_passed'], isTrue);
      expect(json['failure_recovery_verified'], isTrue);
    });
  });
}
