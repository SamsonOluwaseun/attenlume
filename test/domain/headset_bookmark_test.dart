import 'dart:io';

import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/foreground_service_coordinator.dart';
import 'package:attenlume/domain/services/interruption_coordinator.dart';
import 'package:attenlume/domain/services/one_active_coordinator.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:attenlume/platform/foreground_service/foreground_service_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fake_capture_engine.dart';
import '../fixtures/fake_foreground_service_bridge.dart';
import '../fixtures/fake_interruption_source.dart';
import '../fixtures/fake_route_probe.dart';
import '../fixtures/fake_timers.dart';
import '../fixtures/fixtures.dart';

void main() {
  late TestData t;
  late Directory root;
  late FakeCaptureEngine engine;
  late FakeInterruptionSource source;
  late FakeForegroundServiceBridge bridge;
  late InAppInterruptionNotices inAppNotices;
  late InAppTriggerConfirmations confirmations;
  late RecordingService service;
  late Activity keynote;
  ForegroundServiceCoordinator? coordinator;

  Future<void> waitFor(bool Function() condition) async {
    final deadline = Stopwatch()..start();
    while (deadline.elapsed < const Duration(seconds: 5)) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('Condition was not reached within five seconds.');
  }

  ForegroundServiceCoordinator start({required bool enabled}) =>
      coordinator = ForegroundServiceCoordinator(
        recorder: service,
        activities: t.activities,
        media: t.media,
        bridge: bridge,
        inAppNotices: inAppNotices,
        clock: t.clock.call,
        headsetBookmarksEnabled: () async => enabled,
        confirmations: confirmations,
      )..start();

  setUp(() async {
    t = TestData();
    root = await Directory.systemTemp.createTemp('attenlume_headset_');
    engine = FakeCaptureEngine();
    source = FakeInterruptionSource();
    bridge = FakeForegroundServiceBridge();
    inAppNotices = InAppInterruptionNotices();
    confirmations = InAppTriggerConfirmations();
    service = RecordingService(
      engine: engine,
      activities: t.activities,
      media: t.media,
      mediaRoot: () async => root,
      platform: CapturePlatform.android,
      routes: FakeRouteProbe()..active = builtInMic,
      session: source,
      clock: t.clock.call,
      hashFile: (_) async => 'hash',
      rollTimer: FakeTimers().call,
      commitFile: (p, target) => p.rename(target.path),
    );
    final conference = await t.conference(name: 'Samlytics Conference 2026');
    keynote = await t.activity(conference.id, title: 'Keynote Talk');
  });

  tearDown(() async {
    await coordinator?.dispose();
    coordinator = null;
    await service.dispose();
    await inAppNotices.dispose();
    await confirmations.dispose();
    await bridge.close();
    await source.close();
    await t.close();
    await root.delete(recursive: true);
  });

  group('P2-06 headset button adds a bookmark', () {
    test(
      'P2-06 the setting is passed to the service when recording starts',
      () async {
        start(enabled: true);
        await service.start(keynote.id);
        await waitFor(() => bridge.startCalls.isNotEmpty);

        expect(bridge.startCalls.single.headsetBookmarks, isTrue);
        expect(bridge.startCalls.single.toMap()['headsetBookmarks'], isTrue);
      },
    );

    test('P2-06 off by default: the service is told not to listen', () async {
      start(enabled: false);
      await service.start(keynote.id);
      await waitFor(() => bridge.startCalls.isNotEmpty);

      expect(bridge.startCalls.single.headsetBookmarks, isFalse);
    });

    test('P2-06 a press adds a headset bookmark and confirms it', () async {
      start(enabled: true);
      final messages = <String>[];
      final sub = confirmations.messages.listen(messages.add);
      await service.start(keynote.id);
      // The native listener exists only once the service has started.
      await waitFor(() => bridge.startCalls.isNotEmpty);
      t.clock.advance(const Duration(minutes: 2));

      bridge.sendAction(ForegroundServiceAction.headsetBookmark);
      await waitFor(() => messages.isNotEmpty);

      final bookmarks = await t.media.bookmarksFor(keynote.id);
      expect(bookmarks, hasLength(1));
      expect(bookmarks.single.source, BookmarkSource.headset);
      expect(messages.single, 'Bookmark added from headset');
      expect(bridge.updateCalls.last.message, 'Bookmark added from headset');
      // Later notification updates keep the listener on.
      expect(bridge.updateCalls.last.headsetBookmarks, isTrue);
      await sub.cancel();
    });

    test('P2-06 a press is ignored when the setting is off', () async {
      start(enabled: false);
      await service.start(keynote.id);
      await waitFor(() => service.status.state == RecordingState.recording);

      bridge.sendAction(ForegroundServiceAction.headsetBookmark);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(await t.media.bookmarksFor(keynote.id), isEmpty);
    });

    test('P2-06 a press with nothing recording adds nothing', () async {
      start(enabled: true);
      bridge.sendAction(ForegroundServiceAction.headsetBookmark);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(await t.media.bookmarksFor(keynote.id), isEmpty);
    });

    test('P2-06 the native action key parses', () {
      expect(
        ForegroundServiceAction.fromKey('headset_bookmark'),
        ForegroundServiceAction.headsetBookmark,
      );
      expect(BookmarkSource.values.byName('headset').key, 'headset');
    });

    test('P2-06 setting is off until turned on', () async {
      expect(await t.settings.headsetBookmark(), isFalse);
      await t.settings.setHeadsetBookmark(true);
      expect(await t.settings.headsetBookmark(), isTrue);
    });
  });
}
