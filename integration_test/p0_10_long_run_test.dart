import 'dart:io';

import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/data/local_database/builtin_activity_types.dart';
import 'package:attenlume/data/repositories/activity_repository.dart';
import 'package:attenlume/data/repositories/conference_repository.dart';
import 'package:attenlume/data/repositories/media_asset_repository.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/platform/audio_capture/record_capture_engine.dart';
import 'package:attenlume/platform/diagnostics/battery_probe.dart';
import 'package:attenlume/spikes/long_run_spike.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

/// Spike P0-10 on a real low-spec phone or Windows PC [P0-10, AT-REC-01,
/// AT-MEM-01]. Manual steps: `docs/TEST_PLAN.md` MT-19.
///
///   flutter test integration_test/p0_10_long_run_test.dart \
///     -d DEVICE_ID --dart-define=P0_10_MINUTES=90
///
/// Records for P0_10_MINUTES (default 90), sampling RSS, open-file size,
/// level and battery every P0_10_SAMPLE_SECONDS (default 60). Each sample
/// is printed as it is taken, so a run the OS kills still leaves a trail
/// in the console. The report JSON, CSV and Markdown are written next to
/// the audio. The test only fails if nothing could be recorded: the
/// figures are for the tester to judge and record.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const minutes = int.fromEnvironment('P0_10_MINUTES', defaultValue: 90);
  const sampleSeconds = int.fromEnvironment(
    'P0_10_SAMPLE_SECONDS',
    defaultValue: 60,
  );

  testWidgets(
    'P0-10 records for a long run and logs memory, file size and battery',
    (tester) async {
      final report = await tester.runAsync(() async {
        // Ask once, with the system prompt, before the timed run.
        await AudioRecorder().hasPermission();

        final workDir = await Directory.systemTemp.createTemp(
          'attenlume_p0_10_',
        );
        final db = AppDatabase(NativeDatabase.memory());
        final conferences = ConferenceRepository(db);
        final activities = ActivityRepository(db);
        final media = MediaAssetRepository(db);
        final conference = await conferences.create(
          name: 'P0-10 spike',
          timezone: 'Etc/UTC',
        );
        final activity = await activities.create(
          conferenceId: conference.id,
          typeId: builtinActivityTypes.first.id,
          title: 'P0-10 long run',
        );
        final engine = RecordCaptureEngine();
        final service = RecordingService(
          engine: engine,
          activities: activities,
          media: media,
          mediaRoot: () async => workDir,
          platform: currentCapturePlatform(),
        );

        debugPrint(
          'P0-10: recording for $minutes min. Note the battery now, then '
          'lock the screen and follow MT-19.',
        );
        debugPrint('P0-10 ${LongRunSample.csvHeader}');
        final report =
            await LongRunSpike(
              service: service,
              engine: engine,
              media: media,
              mediaRoot: workDir,
              battery: BatteryProbe.forPlatform(),
              sampleInterval: const Duration(seconds: sampleSeconds),
              onSample: (s) => debugPrint('P0-10 ${s.toCsvRow()}'),
            ).run(
              activityId: activity.id,
              length: const Duration(minutes: minutes),
            );

        await service.dispose();
        await db.close();
        await File(p.join(workDir.path, 'report.json'))
            .writeAsString(report.toPrettyJson());
        await File(p.join(workDir.path, 'report.csv'))
            .writeAsString(report.toCsv());
        await File(p.join(workDir.path, 'report.md'))
            .writeAsString(report.toMarkdown());
        debugPrint('P0-10 report folder: ${workDir.path}');
        return report;
      });

      debugPrint(report!.toMarkdown());
      expect(report.startOutcome, StartOutcome.started);
      expect(report.segments, isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: minutes + 5)),
  );
}
