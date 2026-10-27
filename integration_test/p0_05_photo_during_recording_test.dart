import 'dart:io';

import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/data/local_database/builtin_activity_types.dart';
import 'package:attenlume/data/repositories/activity_repository.dart';
import 'package:attenlume/data/repositories/conference_repository.dart';
import 'package:attenlume/data/repositories/media_asset_repository.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/platform/audio_capture/record_capture_engine.dart';
import 'package:attenlume/platform/camera/plugin_photo_camera.dart';
import 'package:attenlume/platform/interruptions/audio_interruption_source.dart';
import 'package:attenlume/platform/interruptions/audio_session_interruption_source.dart';
import 'package:attenlume/spikes/photo_during_recording_spike.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

/// Spike P0-05 on a real phone, iPhone or Windows laptop [P0-05,
/// FR-PHO-07, AT-PHO-01]. Manual steps: `docs/TEST_PLAN.md` MT-21.
///
///   flutter test integration_test/p0_05_photo_during_recording_test.dart \
///     -d DEVICE_ID --dart-define=P0_05_PHOTOS=20
///
/// Records while the camera takes P0_05_PHOTOS photos (default 20, as in
/// AT-PHO-01) every P0_05_INTERVAL seconds (default 3). The tester speaks
/// or plays steady speech near the phone throughout and listens to every
/// segment afterwards. Prints the report and writes it next to the audio
/// and photos in the app's temp folder. Fails if nothing was recorded, a
/// photo was not saved, a gap between segments has no interruption row, or
/// a camera interruption did not resume on its own (AT-PHO-01).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const photos = int.fromEnvironment('P0_05_PHOTOS', defaultValue: 20);
  const interval = int.fromEnvironment('P0_05_INTERVAL', defaultValue: 3);

  testWidgets('P0-05 takes photos during a recording without losing audio', (
    tester,
  ) async {
    final report = await tester.runAsync(() async {
      await AudioRecorder().hasPermission();

      final workDir = await Directory.systemTemp.createTemp('attenlume_p0_05_');
      final db = AppDatabase(NativeDatabase.memory());
      final conferences = ConferenceRepository(db);
      final activities = ActivityRepository(db);
      final media = MediaAssetRepository(db);
      final conference = await conferences.create(
        name: 'P0-05 spike',
        timezone: 'Etc/UTC',
      );
      final activity = await activities.create(
        conferenceId: conference.id,
        typeId: builtinActivityTypes.first.id,
        title: 'P0-05 photo run',
      );
      final engine = RecordCaptureEngine();
      final AudioInterruptionSource interruptions = Platform.isWindows
          ? const NoAudioInterruptions()
          : AudioSessionInterruptionSource();
      final service = RecordingService(
        engine: engine,
        activities: activities,
        media: media,
        mediaRoot: () async => workDir,
        platform: currentCapturePlatform(),
      );

      debugPrint(
        'P0-05: $photos photos, one every $interval s. Follow MT-21: '
        'keep speech playing near the device.',
      );
      final report =
          await PhotoDuringRecordingSpike(
            service: service,
            engine: engine,
            media: media,
            camera: PluginPhotoCamera(),
            interruptions: interruptions,
            mediaRoot: workDir,
          ).run(
            conferenceId: conference.id,
            activityId: activity.id,
            photoCount: photos,
            interval: const Duration(seconds: interval),
          );

      await service.dispose();
      await db.close();
      await File(p.join(workDir.path, 'report.json'))
          .writeAsString(report.toPrettyJson());
      await File(p.join(workDir.path, 'report.md'))
          .writeAsString(report.toMarkdown());
      debugPrint('P0-05 report folder: ${workDir.path}');
      return report;
    });

    debugPrint(report!.toMarkdown());
    debugPrint(report.toPrettyJson());
    expect(report.startOutcome, StartOutcome.started);
    expect(report.cameraError, isNull);
    expect(report.savedPhotos, photos);
    expect(report.unexplainedGaps, isEmpty, reason: 'AT-PHO-01');
    expect(
      report.cameraInterruptionsNotResumed,
      isEmpty,
      reason: 'AT-PHO-01, FR-PHO-07',
    );
  }, timeout: const Timeout(Duration(seconds: photos * (interval + 10) + 120)));
}
