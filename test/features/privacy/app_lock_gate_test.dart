import 'dart:async';
import 'dart:io';

import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/features/privacy/app_lock_controller.dart';
import 'package:attenlume/features/privacy/app_lock_gate.dart';
import 'package:attenlume/platform/device_auth/device_authenticator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fake_capture_engine.dart';
import '../../fixtures/fake_device_authenticator.dart';
import '../../fixtures/fake_timers.dart';
import '../../fixtures/fixtures.dart';

void main() {
  late TestData t;
  late FakeDeviceAuthenticator auth;
  late FakeCaptureEngine engine;
  late RecordingService recorder;
  late Directory tempDir;
  late DateTime now;
  late AppLockController lock;

  setUp(() async {
    t = TestData();
    auth = FakeDeviceAuthenticator();
    engine = FakeCaptureEngine();
    now = DateTime.utc(2026, 11, 4, 9);
    tempDir = await Directory.systemTemp.createTemp('app_lock_gate_test_');
    recorder = RecordingService(
      engine: engine,
      activities: t.activities,
      media: t.media,
      mediaRoot: () async => tempDir,
      platform: CapturePlatform.android,
      clock: () => now,
      rollTimer: FakeTimers().call,
      hashFile: (_) async => 'hash',
    );
    lock = AppLockController(
      settings: t.settings,
      authenticator: auth,
      clock: () => now,
    );
  });

  tearDown(() async {
    await recorder.dispose();
    await t.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Disposes the recorder with real async, as the recording screen tests
  /// do: its status stream cannot close inside fake async in tearDown.
  Future<void> disposeRecorder(WidgetTester tester) async {
    var done = false;
    unawaited(recorder.dispose().then((_) => done = true));
    for (var i = 0; i < 200 && !done; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(t.db),
          settingsRepositoryProvider.overrideWithValue(t.settings),
          deviceAuthenticatorProvider.overrideWithValue(auth),
          appLockControllerProvider.overrideWithValue(lock),
          recordingServiceProvider.overrideWithValue(recorder),
        ],
        child: MaterialApp(
          builder: (context, child) => AppLockGate(child: child!),
          home: const Scaffold(body: Center(child: Text('Secret summit'))),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> lockOn({Duration grace = Duration.zero}) async {
    await t.settings.setAppLockEnabled(true);
    await t.settings.setAppLockGrace(grace);
  }

  Future<String> startRecording(WidgetTester tester) async {
    late String activityId;
    await tester.runAsync(() async {
      final conf = await t.conference(policyAcknowledged: true);
      final act = await t.activity(conf.id, title: 'Keynote');
      activityId = act.id;
      expect(await recorder.start(act.id), StartOutcome.started);
    });
    return activityId;
  }

  testWidgets('FR-PRI-06 with the lock off the app opens straight in', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.byKey(const Key('app-lock-cover')), findsNothing);
    expect(find.text('Secret summit'), findsOneWidget);
    expect(auth.reasons, isEmpty);
    await disposeRecorder(tester);
  });

  testWidgets('FR-PRI-06 with the lock on the app starts locked, asks the OS '
      'at once, and hides the screens underneath', (tester) async {
    await tester.runAsync(lockOn);
    auth.gate = Completer<void>();
    await pumpApp(tester);

    expect(find.byKey(const Key('app-lock-cover')), findsOneWidget);
    expect(find.text('Attenlume is locked'), findsOneWidget);
    expect(auth.reasons, [AppLockController.unlockReason]);
    // Screen readers cannot reach the content under the cover.
    expect(find.bySemanticsLabel('Secret summit'), findsNothing);

    auth.gate!.complete();
    await settle(tester);
    expect(find.byKey(const Key('app-lock-cover')), findsNothing);
    expect(find.bySemanticsLabel('Secret summit'), findsOneWidget);
    await disposeRecorder(tester);
  });

  testWidgets('FR-PRI-06 a cancelled prompt stays locked with a plain '
      'message and an Unlock button that asks again', (tester) async {
    await tester.runAsync(lockOn);
    auth.result = DeviceAuthResult.cancelled;
    await pumpApp(tester);

    expect(find.byKey(const Key('app-lock-message')), findsOneWidget);
    expect(find.byKey(const Key('app-lock-turn-off')), findsNothing);

    auth.result = DeviceAuthResult.success;
    await tester.tap(find.byKey(const Key('app-lock-unlock')));
    await settle(tester);
    expect(find.byKey(const Key('app-lock-cover')), findsNothing);
    expect(auth.reasons, hasLength(2));
    await disposeRecorder(tester);
  });

  testWidgets('FR-PRI-06 fail safe: when the device cannot check, the cover '
      'explains and offers to turn the lock off', (tester) async {
    await tester.runAsync(lockOn);
    auth.result = DeviceAuthResult.unavailable;
    await pumpApp(tester);

    expect(
      find.textContaining('cannot check it is you right now'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('app-lock-turn-off')));
    await settle(tester);

    expect(find.byKey(const Key('app-lock-cover')), findsNothing);
    expect(find.text('Secret summit'), findsOneWidget);
    late bool stored;
    await tester.runAsync(
      () async => stored = await t.settings.appLockEnabled(),
    );
    expect(stored, isFalse);
    await disposeRecorder(tester);
  });

  testWidgets('FR-PRI-06 returning from the background after the grace '
      'period locks; returning sooner does not', (tester) async {
    await tester.runAsync(() => lockOn(grace: const Duration(minutes: 1)));
    await pumpApp(tester);
    expect(find.byKey(const Key('app-lock-cover')), findsNothing);

    // Inactive alone (notification shade, OS prompt) never locks.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    now = now.add(const Duration(minutes: 10));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(find.byKey(const Key('app-lock-cover')), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(seconds: 30));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(find.byKey(const Key('app-lock-cover')), findsNothing);

    auth.gate = Completer<void>();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(find.byKey(const Key('app-lock-cover')), findsOneWidget);
    auth.gate!.complete();
    await settle(tester);
    await disposeRecorder(tester);
  });

  testWidgets('FR-PRI-06 FR-PRI-02 locking never stops or pauses a '
      'recording, and the cover says it is still on with Stop', (tester) async {
    await tester.runAsync(lockOn);
    await pumpApp(tester);
    expect(find.byKey(const Key('app-lock-cover')), findsNothing);
    await startRecording(tester);
    await settle(tester);
    final segmentsBefore = engine.startedPaths.length;

    auth.result = DeviceAuthResult.cancelled;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 3));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);

    expect(find.byKey(const Key('app-lock-cover')), findsOneWidget);
    expect(recorder.status.state, RecordingState.recording);
    expect(engine.isCapturing, isTrue);
    expect(engine.stopCalls, 0);
    expect(engine.startedPaths.length, segmentsBefore);
    expect(find.byKey(const Key('app-lock-recording-strip')), findsOneWidget);
    expect(
      find.text('Recording is still on. Locking does not stop it.'),
      findsOneWidget,
    );
    // The cover names nothing about what is being recorded.
    expect(find.textContaining('Keynote'), findsNothing);

    // Unlocking leaves the recording exactly as it was.
    auth.result = DeviceAuthResult.success;
    await tester.tap(find.byKey(const Key('app-lock-unlock')));
    await settle(tester);
    expect(find.byKey(const Key('app-lock-cover')), findsNothing);
    expect(recorder.status.state, RecordingState.recording);
    expect(engine.stopCalls, 0);
    await disposeRecorder(tester);
  });

  testWidgets('FR-PRI-02 Stop on the lock cover saves the recording without '
      'unlocking', (tester) async {
    await tester.runAsync(lockOn);
    auth.result = DeviceAuthResult.cancelled;
    await pumpApp(tester);
    await startRecording(tester);
    await settle(tester);
    expect(find.byKey(const Key('app-lock-cover')), findsOneWidget);

    await tester.tap(find.byKey(const Key('app-lock-stop-recording')));
    await settle(tester);
    await settle(tester);

    expect(recorder.status.state, RecordingState.saved);
    expect(engine.stopCalls, 1);
    expect(find.byKey(const Key('app-lock-cover')), findsOneWidget);
    expect(find.byKey(const Key('app-lock-recording-strip')), findsNothing);
    await disposeRecorder(tester);
  });
}
