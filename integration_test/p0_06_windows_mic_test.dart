import 'dart:io';

import 'package:attenlume/platform/audio_capture/record_capture_engine.dart';
import 'package:attenlume/spikes/windows_mic_spike.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

/// Spike P0-06 on a real Windows machine [P0-06, FR-QUAL-01, FR-EXP-06].
///
/// Run on the Windows host:
///   flutter test integration_test/p0_06_windows_mic_test.dart -d windows
///
/// Records about 3 seconds of room audio per bitrate into the system temp
/// folder (not the repo), then writes `report.json` and `report.md` next to
/// it and prints the path. Listen to the files before trusting them.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'P0-06 records AAC-LC from the Windows mic, inspects and exports',
    (tester) async {
      final workDir = await Directory.systemTemp.createTemp('attenlume_p0_06_');
      final report = await tester.runAsync(
        () => WindowsMicSpike(
          engine: RecordCaptureEngine(),
          workDir: workDir,
        ).run(),
      );
      await File(p.join(workDir.path, 'report.json'))
          .writeAsString(report!.toPrettyJson());
      await File(p.join(workDir.path, 'report.md'))
          .writeAsString(report.toMarkdownTable());
      debugPrint('P0-06 report: ${workDir.path}');
      debugPrint(report.toPrettyJson());

      expect(report.aacLcSupported, isTrue, reason: 'AAC-LC encoder');
      for (final segment in report.segments) {
        expect(segment.error, isNull, reason: segment.file);
        expect(segment.info!.codec, 'aac_lc', reason: segment.file);
        expect(segment.info!.channelCount, 1, reason: segment.file);
        expect(segment.info!.durationMs, greaterThan(2000));
      }
      expect(report.exportVerified, isTrue);
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
