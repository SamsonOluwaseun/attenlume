import 'dart:async';
import 'dart:io';

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/one_active_coordinator.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/domain/services/storage_budget_service.dart';
import 'package:attenlume/domain/services/storage_thresholds.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/features/capture/recording_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fake_capture_engine.dart';
import '../../fixtures/fake_free_space_probe.dart';
import '../../fixtures/fake_photo_camera.dart';
import '../../fixtures/fake_timers.dart';
import '../../fixtures/fixtures.dart';

void main() {
  late TestData t;
  late Directory tempDir;
  late FakeCaptureEngine fakeEngine;
  late FakePhotoCamera fakeCamera;
  late RecordingService recordingService;
  late OneActiveCoordinator oneActiveCoordinator;
  late FakeFreeSpaceProbe fakeProbe;
  late StorageBudgetService storageBudgetService;
  var mockTime = DateTime(2026, 10, 27, 10, 0);

  DateTime getClock() => mockTime;

  void advanceTime([Duration duration = const Duration(seconds: 1)]) {
    mockTime = mockTime.add(duration);
  }

  Future<void> settleAsync(
    WidgetTester tester, [
    Duration advance = const Duration(milliseconds: 100),
  ]) async {
    advanceTime(advance);
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> disposeService(WidgetTester tester) async {
    var disposed = false;
    unawaited(recordingService.dispose().then((_) => disposed = true));
    for (var i = 0; i < 200 && !disposed; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  setUp(() async {
    mockTime = DateTime(2026, 10, 27, 10, 0);
    t = TestData();
    tempDir = await Directory.systemTemp.createTemp('rec_screen_storage_test_');
    fakeEngine = FakeCaptureEngine()..level = -20.0;
    fakeCamera = FakePhotoCamera();
    fakeProbe = FakeFreeSpaceProbe(10 * 1024 * 1024 * 1024); // 10 GB free

    recordingService = RecordingService(
      engine: fakeEngine,
      activities: t.activities,
      media: t.media,
      mediaRoot: () async => tempDir,
      platform: CapturePlatform.android,
      freeSpaceProbe: fakeProbe,
      clock: () => mockTime.toUtc(),
      rollTimer: FakeTimers().call,
      hashFile: (_) async => 'hash',
    );

    oneActiveCoordinator = OneActiveCoordinator(
      recorder: recordingService,
      activities: t.activities,
      media: t.media,
      confirmations: InAppTriggerConfirmations(),
      clock: () => mockTime.toUtc(),
    );

    storageBudgetService = StorageBudgetService(
      recorder: recordingService,
      activities: t.activities,
      media: t.media,
      mediaRoot: () async => tempDir,
      freeSpaceProbe: fakeProbe,
      platform: CapturePlatform.android,
      clock: () => mockTime.toUtc(),
    );
  });

  tearDown(() async {
    await storageBudgetService.dispose();
    await recordingService.dispose();
    await t.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget buildSubject({
    required String activityId,
    required WidgetTester tester,
    StorageBudgetSnapshot? snapshotOverride,
  }) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(t.db),
        conferenceRepositoryProvider.overrideWithValue(t.conferences),
        activityRepositoryProvider.overrideWithValue(t.activities),
        mediaAssetRepositoryProvider.overrideWithValue(t.media),
        mediaRootProvider.overrideWithValue(() async => tempDir),
        audioCaptureEngineProvider.overrideWithValue(fakeEngine),
        photoCameraProvider.overrideWithValue(fakeCamera),
        freeSpaceProbeProvider.overrideWithValue(fakeProbe),
        capturePlatformProvider.overrideWithValue(CapturePlatform.android),
        recordingServiceProvider.overrideWithValue(recordingService),
        oneActiveCoordinatorProvider.overrideWithValue(oneActiveCoordinator),
        storageBudgetServiceProvider.overrideWithValue(storageBudgetService),
        if (snapshotOverride != null)
          storageBudgetSnapshotProvider.overrideWith(
            (ref) => Stream.value(snapshotOverride),
          ),
      ],
      child: MaterialApp(
        theme: AppTheme.live(),
        home: RecordingScreen(
          activityId: activityId,
          clock: getClock,
          enableTicker: false,
        ),
      ),
    );
  }

  group('FR-UI-07 RecordingScreen live storage budget UI [P1-12]', () {
    testWidgets(
      'FR-UI-07 displays single muted line under timer when storage is ok',
      (tester) async {
        final conf = await t.conference();
        final act = await t.activity(conf.id, title: 'Session 1');

        await tester.pumpWidget(
          buildSubject(
            activityId: act.id,
            tester: tester,
            snapshotOverride: StorageBudgetSnapshot(
              freeBytes: 10 * 1024 * 1024 * 1024,
              totalBytes: 128 * 1024 * 1024 * 1024,
              level: StorageLevel.ok,
              minutesLeft: 600,
              bytesPerSecond: 6000,
              isMeasuredRate: false,
              timestamp: DateTime.fromMillisecondsSinceEpoch(0),
            ),
          ),
        );
        await settleAsync(tester);

        expect(
          find.byKey(const Key('recording-screen-storage-meter')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('storage-meter-compact-ok')),
          findsOneWidget,
        );
        expect(find.textContaining('10.0 GB free'), findsOneWidget);
        await disposeService(tester);
      },
    );

    testWidgets(
      'FR-UI-07 displays warning banner when storage drops below 1 GB',
      (tester) async {
        final conf = await t.conference();
        final act = await t.activity(conf.id, title: 'Session 2');

        await tester.pumpWidget(
          buildSubject(
            activityId: act.id,
            tester: tester,
            snapshotOverride: StorageBudgetSnapshot(
              freeBytes: 750 * 1024 * 1024,
              totalBytes: 128 * 1024 * 1024 * 1024,
              level: StorageLevel.warning,
              minutesLeft: 45,
              bytesPerSecond: 6000,
              isMeasuredRate: false,
              timestamp: DateTime.fromMillisecondsSinceEpoch(0),
            ),
          ),
        );
        await settleAsync(tester);

        expect(
          find.byKey(const Key('storage-meter-banner-warning')),
          findsOneWidget,
        );
        expect(
          find.text('Running low. Export or free space soon.'),
          findsOneWidget,
        );
        await disposeService(tester);
      },
    );

    testWidgets('FR-UI-07 displays danger banner on hard stop reserve', (
      tester,
    ) async {
      final conf = await t.conference();
      final act = await t.activity(conf.id, title: 'Session 3');

      await tester.pumpWidget(
        buildSubject(
          activityId: act.id,
          tester: tester,
          snapshotOverride: StorageBudgetSnapshot(
            freeBytes: 80 * 1024 * 1024,
            totalBytes: 128 * 1024 * 1024 * 1024,
            level: StorageLevel.hardStop,
            minutesLeft: 0,
            bytesPerSecond: 6000,
            isMeasuredRate: false,
            timestamp: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        ),
      );
      await settleAsync(tester);

      expect(
        find.byKey(const Key('storage-meter-banner-hard-stop')),
        findsOneWidget,
      );
      expect(
        find.text('Storage nearly full. Recording stopped and saved.'),
        findsOneWidget,
      );
      await disposeService(tester);
    });
  });
}
