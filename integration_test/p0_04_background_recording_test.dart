import 'dart:async';
import 'dart:io';

import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/data/local_database/builtin_activity_types.dart';
import 'package:attenlume/data/repositories/activity_repository.dart';
import 'package:attenlume/data/repositories/conference_repository.dart';
import 'package:attenlume/data/repositories/media_asset_repository.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/platform/audio_capture/record_capture_engine.dart';
import 'package:attenlume/platform/interruptions/audio_session_interruption_source.dart';
import 'package:attenlume/spikes/background_recording_spike.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

/// Spike P0-04 on a real Android phone or iPhone [P0-04, NFR-05,
/// FR-REC-05]. Manual steps: `docs/TEST_PLAN.md` MT-17.
///
///   flutter test integration_test/p0_04_background_recording_test.dart \
///     -d DEVICE_ID --dart-define=P0_04_SECONDS=300
///
/// Records for P0_04_SECONDS (default 300) while the tester locks the
/// phone and calls it. Prints the report JSON and Markdown to the console
/// and writes them next to the audio in the app's temp folder. The test
/// only fails if nothing could be recorded at all: the observations are
/// for the tester to judge, with headphones on.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const seconds = int.fromEnvironment('P0_04_SECONDS', defaultValue: 300);

  testWidgets(
    'P0-04 records with the screen locked and through a call',
    (tester) async {
      final report = await tester.runAsync(() async {
        // Ask once, with the system prompt, before the timed run.
        await AudioRecorder().hasPermission();

        final workDir = await Directory.systemTemp.createTemp(
          'attenlume_p0_04_',
        );
        final db = AppDatabase(NativeDatabase.memory());
        final conferences = ConferenceRepository(db);
        final activities = ActivityRepository(db);
        final media = MediaAssetRepository(db);
        final conference = await conferences.create(
          name: 'P0-04 spike',
          timezone: 'Etc/UTC',
        );
        final activity = await activities.create(
          conferenceId: conference.id,
          typeId: builtinActivityTypes.first.id,
          title: 'P0-04 background run',
        );
        final engine = RecordCaptureEngine();
        final service = RecordingService(
          engine: engine,
          activities: activities,
          media: media,
          mediaRoot: () async => workDir,
          platform: currentCapturePlatform(),
        );
        final lifecycle = StreamController<AppLifecycleState>.broadcast();
        final listener = AppLifecycleListener(onStateChange: lifecycle.add);

        debugPrint(
          'P0-04: recording for $seconds s. Lock the phone now, then '
          'follow MT-17.',
        );
        final report =
            await BackgroundRecordingSpike(
              service: service,
              engine: engine,
              media: media,
              interruptions: AudioSessionInterruptionSource(),
              lifecycle: lifecycle.stream,
            ).run(
              activityId: activity.id,
              length: const Duration(seconds: seconds),
            );

        listener.dispose();
        await lifecycle.close();
        await service.dispose();
        await db.close();
        await File(p.join(workDir.path, 'report.json'))
            .writeAsString(report.toPrettyJson());
        await File(p.join(workDir.path, 'report.md'))
            .writeAsString(report.toMarkdown());
        debugPrint('P0-04 report folder: ${workDir.path}');
        return report;
      });

      debugPrint(report!.toMarkdown());
      debugPrint(report.toPrettyJson());
      expect(report.startOutcome, StartOutcome.started);
      expect(report.segments, isNotEmpty);
    },
    skip: !(Platform.isAndroid || Platform.isIOS),
    timeout: const Timeout(Duration(seconds: seconds + 120)),
  );
}
