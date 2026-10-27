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
import 'package:attenlume/platform/shortcuts/shortcut_bridge.dart';
import 'package:attenlume/spikes/shortcut_trigger_spike.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

/// Spike P0-13 on a real Android phone or iPhone [P0-13, FR-HF-01,
/// FR-HF-04, FR-HF-05, AT-HF-01]. Manual steps: `docs/TEST_PLAN.md` MT-22.
///
///   flutter test integration_test/p0_13_shortcut_trigger_test.dart \
///     -d DEVICE_ID --dart-define=P0_13_SECONDS=300 \
///     --dart-define=P0_13_TILE_DIRECT=false
///
/// Listens for P0_13_SECONDS (default 300) while the tester uses the Quick
/// Settings tile, launcher shortcuts, Siri or Shortcuts intents and
/// `attenlume://` links with the app in front, in the background and with
/// the phone locked. With P0_13_TILE_DIRECT=true the Android tile sends
/// commands to the running app without opening it. Prints the report and
/// writes it to the app's temp folder.
///
/// Fails only if no trigger arrived at all: the report records what each
/// OS allowed, and a refused or silent background start is a finding, not
/// a test fault. Cold starts from a killed app cannot be driven by this
/// test (killing the app ends it); MT-22 covers them by hand.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const seconds = int.fromEnvironment('P0_13_SECONDS', defaultValue: 300);
  const tileDirect = bool.fromEnvironment('P0_13_TILE_DIRECT');

  testWidgets('P0-13 shortcuts and intents trigger recordings', (tester) async {
    final report = await tester.runAsync(() async {
      await AudioRecorder().hasPermission();

      final workDir = await Directory.systemTemp.createTemp('attenlume_p0_13_');
      final db = AppDatabase(NativeDatabase.memory());
      final conferences = ConferenceRepository(db);
      final activities = ActivityRepository(db);
      final media = MediaAssetRepository(db);
      final conference = await conferences.create(
        name: 'P0-13 spike',
        timezone: 'Etc/UTC',
      );
      final activity = await activities.create(
        conferenceId: conference.id,
        typeId: builtinActivityTypes.first.id,
        title: 'P0-13 shortcut run',
      );
      final engine = RecordCaptureEngine();
      final service = RecordingService(
        engine: engine,
        activities: activities,
        media: media,
        mediaRoot: () async => workDir,
        platform: currentCapturePlatform(),
      );
      final bridge = Platform.isWindows
          ? null
          : MethodChannelShortcutBridge(
              onMalformed: (a) => debugPrint('P0-13 malformed: $a'),
            );
      final lifecycle = StreamController<AppLifecycleState>.broadcast();
      final listener = AppLifecycleListener(onStateChange: lifecycle.add);

      debugPrint(
        'P0-13: listening for $seconds s, tile direct: $tileDirect. '
        'Follow MT-22.',
      );
      final report =
          await ShortcutTriggerSpike(
            service: service,
            engine: engine,
            media: media,
            bridge: bridge ?? const NoShortcutBridge(),
            lifecycle: lifecycle.stream,
            initialLifecycle:
                binding.lifecycleState ?? AppLifecycleState.resumed,
          ).run(
            activityId: activity.id,
            duration: const Duration(seconds: seconds),
            tileDirect: tileDirect,
          );

      listener.dispose();
      await lifecycle.close();
      await bridge?.dispose();
      await service.dispose();
      await db.close();
      await File(p.join(workDir.path, 'report.json'))
          .writeAsString(report.toPrettyJson());
      await File(p.join(workDir.path, 'report.md'))
          .writeAsString(report.toMarkdown());
      debugPrint('P0-13 report folder: ${workDir.path}');
      return report;
    });

    debugPrint(report!.toMarkdown());
    debugPrint(report.toPrettyJson());
    expect(report.triggers, isNotEmpty, reason: 'MT-22: no trigger arrived');
  }, timeout: const Timeout(Duration(seconds: seconds + 120)));
}
