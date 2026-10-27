import 'dart:io';

import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/data/local_database/builtin_activity_types.dart';
import 'package:attenlume/data/repositories/activity_repository.dart';
import 'package:attenlume/data/repositories/conference_repository.dart';
import 'package:attenlume/data/repositories/media_asset_repository.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/platform/audio_capture/record_capture_engine.dart';
import 'package:attenlume/platform/audio_route/audio_route_probe.dart';
import 'package:attenlume/platform/audio_route/audio_session_route_probe.dart';
import 'package:attenlume/platform/audio_route/engine_route_probe.dart';
import 'package:attenlume/platform/interruptions/audio_interruption_source.dart';
import 'package:attenlume/platform/interruptions/audio_session_interruption_source.dart';
import 'package:attenlume/spikes/bluetooth_routing_spike.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

/// Spike P0-07 on a real phone, iPhone or Windows laptop [P0-07,
/// FR-REC-07, AT-QUAL-03]. Manual steps: `docs/TEST_PLAN.md` MT-20.
///
///   flutter test integration_test/p0_07_bluetooth_routing_test.dart \
///     -d DEVICE_ID --dart-define=P0_07_SECONDS=180
///
/// Records for P0_07_SECONDS (default 180) while the tester connects,
/// disconnects and switches off a Bluetooth headset or lapel mic. Prints
/// the report to the console and writes it next to the audio in the
/// app's temp folder. Fails only if nothing could be recorded at all or a
/// segment's stored format differs from its file (AT-QUAL-03).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const seconds = int.fromEnvironment('P0_07_SECONDS', defaultValue: 180);

  testWidgets(
    'P0-07 follows Bluetooth mic changes and labels every segment from its '
    'file',
    (tester) async {
      final report = await tester.runAsync(() async {
        await AudioRecorder().hasPermission();

        final workDir = await Directory.systemTemp.createTemp(
          'attenlume_p0_07_',
        );
        final db = AppDatabase(NativeDatabase.memory());
        final conferences = ConferenceRepository(db);
        final activities = ActivityRepository(db);
        final media = MediaAssetRepository(db);
        final conference = await conferences.create(
          name: 'P0-07 spike',
          timezone: 'Etc/UTC',
        );
        final activity = await activities.create(
          conferenceId: conference.id,
          typeId: builtinActivityTypes.first.id,
          title: 'P0-07 Bluetooth run',
        );
        final engine = RecordCaptureEngine();
        final AudioRouteProbe routes = Platform.isWindows
            ? EngineRouteProbe(engine)
            : AudioSessionRouteProbe();
        final AudioInterruptionSource interruptions = Platform.isWindows
            ? const NoAudioInterruptions()
            : AudioSessionInterruptionSource();
        final platform = currentCapturePlatform();
        final service = RecordingService(
          engine: engine,
          activities: activities,
          media: media,
          mediaRoot: () async => workDir,
          platform: platform,
          routes: routes,
        );

        debugPrint(
          'P0-07: recording for $seconds s. Follow MT-20: connect, '
          'disconnect and switch off the headset.',
        );
        final report =
            await BluetoothRoutingSpike(
              service: service,
              engine: engine,
              media: media,
              routes: routes,
              interruptions: interruptions,
              mediaRoot: workDir,
              platform: platform,
            ).run(
              activityId: activity.id,
              length: const Duration(seconds: seconds),
            );

        await service.dispose();
        await db.close();
        await File(p.join(workDir.path, 'report.json'))
            .writeAsString(report.toPrettyJson());
        await File(p.join(workDir.path, 'report.md'))
            .writeAsString(report.toMarkdown());
        debugPrint('P0-07 report folder: ${workDir.path}');
        return report;
      });

      debugPrint(report!.toMarkdown());
      debugPrint(report.toPrettyJson());
      expect(report.startOutcome, StartOutcome.started);
      expect(report.checks, isNotEmpty);
      expect(report.mislabelled, isEmpty, reason: 'AT-QUAL-03');
    },
    timeout: const Timeout(Duration(seconds: seconds + 120)),
  );
}
