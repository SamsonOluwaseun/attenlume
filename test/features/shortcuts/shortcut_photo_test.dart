import 'dart:io';

import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/features/capture/camera_screen.dart';
import 'package:attenlume/features/shortcuts/shortcut_coordinator.dart';
import 'package:attenlume/platform/shortcuts/shortcut_command.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fake_capture_engine.dart';
import '../../fixtures/fake_timers.dart';
import '../../fixtures/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('P2-03 photo shortcut opens camera for the held recording', () async {
    final data = TestData();
    final root = await Directory.systemTemp.createTemp('shortcut_photo_');
    final recorder = RecordingService(
      engine: FakeCaptureEngine(),
      activities: data.activities,
      media: data.media,
      mediaRoot: () async => root,
      platform: CapturePlatform.android,
      clock: data.clock.call,
      rollTimer: FakeTimers().call,
      hashFile: (_) async => 'hash',
    );
    addTearDown(() async {
      await recorder.dispose();
      await data.close();
      await root.delete(recursive: true);
    });
    final conference = await data.conference();
    final activity = await data.activity(conference.id);
    await recorder.start(activity.id);
    Widget? destination;
    final coordinator = ShortcutCoordinator(
      navigatorKey: GlobalKey<NavigatorState>(),
      conferenceRepository: data.conferences,
      activityRepository: data.activities,
      mediaRepository: data.media,
      recordingService: recorder,
      onNavigate: (screen) => destination = screen,
    );

    await coordinator.handleCommand(
      ShortcutCommand.parse(Uri.parse('attenlume://photo'))!,
    );

    expect(destination, isA<CameraScreen>());
    expect((destination as CameraScreen).activityId, activity.id);
    expect(recorder.status.state.holdsActivity, isTrue);
  });
}
