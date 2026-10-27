import 'dart:io';

import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/data/local_database/builtin_activity_types.dart';
import 'package:attenlume/data/repositories/activity_repository.dart';
import 'package:attenlume/data/repositories/conference_repository.dart';
import 'package:attenlume/data/repositories/media_asset_repository.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/platform/audio_capture/record_capture_engine.dart';
import 'package:attenlume/spikes/profile_switch_spike.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

/// Spike P0-12 on a real phone or Windows PC [P0-12, FR-QUAL-01,
/// FR-QUAL-04, FR-QUAL-06]. Manual steps: `docs/TEST_PLAN.md` MT-18.
///
///   flutter test integration_test/p0_12_profile_switch_test.dart \
///     -d DEVICE_ID --dart-define=P0_12_SECONDS=20
///
/// Records Economy, Balanced, Enhanced, then Economy again, P0_12_SECONDS
/// (default 20) each, switching with `RecordingService.changeProfile`.
/// Prints the report JSON and Markdown and writes them next to the audio.
/// The test only fails if nothing could be recorded: the tester listens
/// at each switch and records the result.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const seconds = int.fromEnvironment('P0_12_SECONDS', defaultValue: 20);

  testWidgets(
    'P0-12 switches profile per segment and reports observed bitrate',
    (tester) async {
      final report = await tester.runAsync(() async {
        // Ask once, with the system prompt, before the timed run.
        await AudioRecorder().hasPermission();

        final workDir = await Directory.systemTemp.createTemp(
          'attenlume_p0_12_',
        );
        final db = AppDatabase(NativeDatabase.memory());
        final conferences = ConferenceRepository(db);
        final activities = ActivityRepository(db);
        final media = MediaAssetRepository(db);
        final conference = await conferences.create(
          name: 'P0-12 spike',
          timezone: 'Etc/UTC',
        );
        final activity = await activities.create(
          conferenceId: conference.id,
          typeId: builtinActivityTypes.first.id,
          title: 'P0-12 profile switch run',
        );
        final platform = currentCapturePlatform();
        final service = RecordingService(
          engine: RecordCaptureEngine(),
          activities: activities,
          media: media,
          mediaRoot: () async => workDir,
          platform: platform,
        );

        debugPrint(
          'P0-12: four segments of $seconds s. Talk or play speech near '
          'the microphone throughout.',
        );
        final report =
            await ProfileSwitchSpike(
              service: service,
              activities: activities,
              media: media,
              mediaRoot: workDir,
              platform: platform,
            ).run(
              activityId: activity.id,
              segmentLength: const Duration(seconds: seconds),
            );

        await service.dispose();
        await db.close();
        await File(p.join(workDir.path, 'report.json'))
            .writeAsString(report.toPrettyJson());
        await File(p.join(workDir.path, 'report.md'))
            .writeAsString(report.toMarkdown());
        debugPrint('P0-12 report folder: ${workDir.path}');
        return report;
      });

      debugPrint(report!.toMarkdown());
      debugPrint(report.toPrettyJson());
      expect(report.startOutcome, StartOutcome.started);
      expect(report.segments, isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: seconds * 4 + 120)),
  );
}
