import 'dart:io';

import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/foreground_service_coordinator.dart';
import 'package:attenlume/domain/services/interruption_coordinator.dart';
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
  late FakeRouteProbe routes;
  late FakeInterruptionSource source;
  late FakeForegroundServiceBridge bridge;
  late InAppInterruptionNotices inAppNotices;
  late RecordingService service;
  late ForegroundServiceCoordinator coordinator;
  late Activity keynote;

  Future<void> waitFor(bool Function() condition) async {
    for (var i = 0; i < 50; i++) {
      if (condition()) return;
      await pumpEventQueue();
    }
  }

  setUp(() async {
    t = TestData();
    root = await Directory.systemTemp.createTemp('attenlume_fg_');
    engine = FakeCaptureEngine();
    routes = FakeRouteProbe()..active = builtInMic;
    source = FakeInterruptionSource();
    bridge = FakeForegroundServiceBridge();
    inAppNotices = InAppInterruptionNotices();

    service = RecordingService(
      engine: engine,
      activities: t.activities,
      media: t.media,
      mediaRoot: () async => root,
      platform: CapturePlatform.android,
      routes: routes,
      session: source,
      clock: t.clock.call,
      hashFile: (_) async => 'hash',
      rollTimer: FakeTimers().call,
      commitFile: (p, target) => p.rename(target.path),
    );

    coordinator = ForegroundServiceCoordinator(
      recorder: service,
      activities: t.activities,
      media: t.media,
      bridge: bridge,
      inAppNotices: inAppNotices,
      clock: t.clock.call,
    )..start();

    final conference = await t.conference();
    keynote = await t.activity(conference.id, title: 'Keynote Talk');
  });

  tearDown(() async {
    await coordinator.dispose();
    await service.dispose();
    await inAppNotices.dispose();
    await bridge.close();
    await source.close();
    await t.close();
    await root.delete(recursive: true);
  });

  group('FR-REC-10 Foreground service lifecycle and notification updates', () {
    test('FR-REC-10 starts foreground service when recording starts', () async {
      final startOutcome = await service.start(keynote.id);
      expect(startOutcome, StartOutcome.started);

      await waitFor(() => bridge.isRunning && bridge.startCalls.isNotEmpty);

      expect(bridge.isRunning, isTrue);
      expect(bridge.startCalls, hasLength(1));
      final call = bridge.startCalls.first;
      expect(call.activityId, keynote.id);
      expect(call.title, 'Keynote Talk');
      expect(call.state, RecordingState.recording);
      expect(call.baseTimeUtc, isNotNull);
    });

    test('FR-REC-10 updates notification on pause and resume', () async {
      await service.start(keynote.id);
      await waitFor(() => bridge.isRunning && bridge.startCalls.isNotEmpty);
      bridge.startCalls.clear();

      t.clock.advance(const Duration(minutes: 3));

      // Pause recording
      await service.pause();
      await waitFor(
        () => bridge.updateCalls.any((c) => c.state == RecordingState.paused),
      );

      expect(bridge.updateCalls, isNotEmpty);
      final pauseUpdate = bridge.updateCalls.last;
      expect(pauseUpdate.state, RecordingState.paused);
      expect(pauseUpdate.baseTimeUtc, isNull); // chronometer stopped
      expect(pauseUpdate.message, contains('Recording paused'));

      // Resume recording
      bridge.updateCalls.clear();
      t.clock.advance(const Duration(seconds: 30));
      await service.resume();
      await waitFor(
        () =>
            bridge.updateCalls.any((c) => c.state == RecordingState.recording),
      );

      expect(bridge.updateCalls, isNotEmpty);
      final resumeUpdate = bridge.updateCalls.last;
      expect(resumeUpdate.state, RecordingState.recording);
      expect(resumeUpdate.baseTimeUtc, isNotNull); // chronometer running
      expect(resumeUpdate.message, 'Recording');
    });

    test(
      'FR-REC-10 updates notification on interruption and user resume required',
      () async {
        await service.start(keynote.id);
        await waitFor(() => bridge.isRunning && bridge.startCalls.isNotEmpty);
        bridge.updateCalls.clear();

        // Interruption begins
        await service.interrupt(InterruptionReason.system);
        await waitFor(
          () => bridge.updateCalls.any(
            (c) => c.state == RecordingState.interrupted,
          ),
        );

        expect(bridge.updateCalls, isNotEmpty);
        final intUpdate = bridge.updateCalls.last;
        expect(intUpdate.state, RecordingState.interrupted);
        expect(intUpdate.message, contains('interrupted'));

        // Interruption ends with no auto-resume allowed -> userResumeRequired
        bridge.updateCalls.clear();
        await service.interruptionEnded(mayResume: false);
        await waitFor(
          () => bridge.updateCalls.any(
            (c) => c.state == RecordingState.userResumeRequired,
          ),
        );

        expect(bridge.updateCalls, isNotEmpty);
        final reqUpdate = bridge.updateCalls.last;
        expect(reqUpdate.state, RecordingState.userResumeRequired);
        expect(reqUpdate.message, contains('Resume'));
      },
    );

    test('FR-REC-10 stops foreground service when recording stops', () async {
      await service.start(keynote.id);
      await waitFor(() => bridge.isRunning && bridge.startCalls.isNotEmpty);
      expect(bridge.isRunning, isTrue);

      await service.stop();
      await waitFor(() => !bridge.isRunning && bridge.stopCallCount > 0);

      expect(bridge.isRunning, isFalse);
      expect(bridge.stopCallCount, greaterThanOrEqualTo(1));
    });
  });

  group('FR-REC-10 Notification action handlers', () {
    test('FR-REC-10 pause action pauses the active recording', () async {
      await service.start(keynote.id);
      await waitFor(() => service.status.state == RecordingState.recording);

      bridge.sendAction(ForegroundServiceAction.pause);
      await waitFor(() => service.status.state == RecordingState.paused);

      expect(service.status.state, RecordingState.paused);
    });

    test('FR-REC-10 resume action resumes paused recording', () async {
      await service.start(keynote.id);
      await service.pause();
      await waitFor(() => service.status.state == RecordingState.paused);

      bridge.sendAction(ForegroundServiceAction.resume);
      await waitFor(() => service.status.state == RecordingState.recording);

      expect(service.status.state, RecordingState.recording);
    });

    test(
      'FR-REC-10 resume action resumes userResumeRequired recording',
      () async {
        await service.start(keynote.id);
        await service.interrupt(InterruptionReason.system);
        await service.interruptionEnded(mayResume: false);
        await waitFor(
          () => service.status.state == RecordingState.userResumeRequired,
        );

        bridge.sendAction(ForegroundServiceAction.resume);
        await waitFor(() => service.status.state == RecordingState.recording);

        expect(service.status.state, RecordingState.recording);
      },
    );

    test('FR-REC-10 stop action stops and saves the recording', () async {
      await service.start(keynote.id);
      await waitFor(() => service.status.state == RecordingState.recording);

      bridge.sendAction(ForegroundServiceAction.stop);
      await waitFor(() => service.status.state == RecordingState.saved);

      expect(service.status.state, RecordingState.saved);
      expect(bridge.isRunning, isFalse);
    });

    test('FR-REC-10 bookmark action adds bookmark with source notification and updates notification', () async {
      await service.start(keynote.id);
      await waitFor(() => service.status.state == RecordingState.recording);

      t.clock.advance(const Duration(minutes: 2));

      bridge.sendAction(ForegroundServiceAction.bookmark);
      await waitFor(
        () => bridge.updateCalls.any((c) => c.message == 'Bookmark added'),
      );

      final bookmarks = await t.media.bookmarksFor(keynote.id);
      expect(bookmarks, hasLength(1));
      expect(bookmarks.first.source, BookmarkSource.notification);

      // Notification is updated with "Bookmark added"
      expect(bridge.updateCalls, isNotEmpty);
      expect(bridge.updateCalls.last.message, 'Bookmark added');
    });
  });

  group('FR-REC-10 Interruption notice forwarding', () {
    test(
      'FR-REC-10 show notice forwards to inAppNotices and updates notification',
      () async {
        final shownNotices = <InterruptionNotice>[];
        final sub = inAppNotices.notices.listen(shownNotices.add);

        await service.start(keynote.id);
        await waitFor(() => bridge.isRunning && bridge.startCalls.isNotEmpty);
        bridge.updateCalls.clear();

        await coordinator.show(
          InterruptionNotice(
            InterruptionNoticeKind.resumeRequired,
            'Call interrupted recording. Tap Resume.',
            activityId: keynote.id,
          ),
        );
        await waitFor(() => shownNotices.isNotEmpty);

        expect(shownNotices, hasLength(1));
        expect(
          shownNotices.first.message,
          'Call interrupted recording. Tap Resume.',
        );

        expect(bridge.updateCalls, isNotEmpty);
        expect(
          bridge.updateCalls.last.message,
          'Call interrupted recording. Tap Resume.',
        );

        await sub.cancel();
      },
    );
  });
}
