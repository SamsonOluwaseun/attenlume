import 'dart:io';

import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/services/foreground_service_coordinator.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/platform/foreground_service/foreground_service_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fake_capture_engine.dart';
import '../../fixtures/fake_foreground_service_bridge.dart';
import '../../fixtures/fixtures.dart';

void main() {
  late TestData t;
  late Directory tempDir;
  late FakeCaptureEngine fakeEngine;
  late FakeForegroundServiceBridge fakeBridge;
  late ProviderContainer container;
  late Activity keynote;

  setUp(() async {
    t = TestData();
    tempDir = await Directory.systemTemp.createTemp('attenlume_prov_');
    fakeEngine = FakeCaptureEngine();
    fakeBridge = FakeForegroundServiceBridge();

    container = ProviderContainer(
      overrides: [
        // The safety prompt thresholds come from Settings (P1-25).
        settingsRepositoryProvider.overrideWithValue(t.settings),
        activityRepositoryProvider.overrideWithValue(t.activities),
        mediaAssetRepositoryProvider.overrideWithValue(t.media),
        audioCaptureEngineProvider.overrideWithValue(fakeEngine),
        mediaRootProvider.overrideWithValue(() async => tempDir),
        foregroundServiceBridgeProvider.overrideWithValue(fakeBridge),
      ],
    );

    final conf = await t.conference();
    keynote = await t.activity(conf.id, title: 'Opening Keynote');
  });

  tearDown(() async {
    container.dispose();
    await fakeBridge.close();
    await t.close();
    await tempDir.delete(recursive: true);
  });

  group('FR-REC-10 Riverpod foreground service provider wiring', () {
    test('FR-REC-10 foregroundServiceBridgeProvider defaults to no-op on non-Android', () {
      final defaultContainer = ProviderContainer(
        overrides: [
          activityRepositoryProvider.overrideWithValue(t.activities),
          mediaAssetRepositoryProvider.overrideWithValue(t.media),
        ],
      );
      final bridge = defaultContainer.read(foregroundServiceBridgeProvider);
      expect(bridge, isA<ForegroundServiceBridge>());
      if (!Platform.isAndroid) {
        expect(bridge, isA<NoopForegroundServiceBridge>());
      }
      defaultContainer.dispose();
    });

    test('FR-REC-10 oneActiveCoordinatorProvider initializes foregroundServiceCoordinatorProvider', () {
      final oneActive = container.read(oneActiveCoordinatorProvider);
      expect(oneActive, isNotNull);
      final coordinator = container.read(foregroundServiceCoordinatorProvider);
      expect(coordinator, isNotNull);
      expect(coordinator, isA<ForegroundServiceCoordinator>());
    });

    test('FR-REC-10 calculateElapsed correctly sums finished segments and active segment duration', () async {
      final coordinator = container.read(foregroundServiceCoordinatorProvider);

      // Insert two finished segments using fixture helper
      final start1 = DateTime.utc(2026, 10, 27, 9, 0);
      await t.segment(
        keynote.id,
        start: start1,
        length: const Duration(minutes: 10),
      );

      final start2 = DateTime.utc(2026, 10, 27, 9, 10);
      await t.segment(
        keynote.id,
        start: start2,
        length: const Duration(minutes: 10),
      );

      // Status in paused state (no open segment span added)
      const pausedStatus = RecordingStatus(
        state: RecordingState.paused,
        activityId: 'act-1',
      );
      final pausedElapsed = await coordinator.calculateElapsed(
        keynote.id,
        pausedStatus,
      );
      expect(pausedElapsed, const Duration(minutes: 20));

      // Status in recording state (open segment span 2 minutes added)
      final recordingStatus = RecordingStatus(
        state: RecordingState.recording,
        activityId: keynote.id,
        segmentStartUtc: DateTime.now().toUtc().subtract(
          const Duration(minutes: 2),
        ),
      );
      final recordingElapsed = await coordinator.calculateElapsed(
        keynote.id,
        recordingStatus,
      );
      expect(recordingElapsed.inMinutes, closeTo(22, 1));
    });
  });
}
