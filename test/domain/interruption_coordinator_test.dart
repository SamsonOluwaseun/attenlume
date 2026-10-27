import 'dart:async';
import 'dart:io';

import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/interruption_coordinator.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fake_capture_engine.dart';
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
  late RecordingService service;
  late InAppInterruptionNotices notices;
  late List<InterruptionNotice> shown;
  late StreamSubscription<InterruptionNotice> noticeSub;
  late InterruptionCoordinator coordinator;
  late Activity keynote;

  InterruptionCoordinator build({bool forceRouteRoll = false}) =>
      InterruptionCoordinator(
        recorder: service,
        source: source,
        notices: notices,
        forceRouteRoll: forceRouteRoll,
        clock: t.clock.call,
      )..start();

  setUp(() async {
    t = TestData();
    root = await Directory.systemTemp.createTemp('attenlume_coord_');
    engine = FakeCaptureEngine();
    routes = FakeRouteProbe()..active = builtInMic;
    source = FakeInterruptionSource();
    service = RecordingService(
      engine: engine,
      activities: t.activities,
      media: t.media,
      mediaRoot: () async => root,
      platform: CapturePlatform.ios,
      routes: routes,
      session: source,
      clock: t.clock.call,
      hashFile: (_) async => 'hash',
      rollTimer: FakeTimers().call,
      commitFile: (p, target) => p.rename(target.path),
    );
    notices = InAppInterruptionNotices();
    shown = [];
    noticeSub = notices.notices.listen(shown.add);
    coordinator = build();
    final conference = await t.conference();
    keynote = await t.activity(conference.id, title: 'Data Mesh Keynote');
  });

  tearDown(() async {
    await coordinator.dispose();
    await service.dispose();
    await noticeSub.cancel();
    await notices.dispose();
    await source.close();
    await t.close();
    await root.delete(recursive: true);
  });

  /// Lets queued events reach the coordinator and finish.
  Future<void> settle() async {
    await pumpEventQueue();
    await coordinator.settled;
    await pumpEventQueue();
  }

  Future<void> record() async {
    await service.start(keynote.id);
    t.clock.advance(const Duration(minutes: 5));
  }

  group('FR-REC-05 calls and audio interruptions', () {
    test(
      'FR-REC-05 an interruption ends the segment and logs a system row',
      () async {
        await record();

        source.began();
        await settle();

        expect(service.status.state, RecordingState.interrupted);
        expect(engine.isCapturing, isFalse);
        final segs = await t.media.segmentsFor(keynote.id);
        expect(segs.single.endReason, SegmentEndReason.interruption);
        final row = (await t.media.interruptionsFor(keynote.id)).single;
        expect(row.reason, InterruptionReason.system);
      },
    );

    test('FR-REC-05 a duck request keeps recording', () async {
      await record();

      source.began(mayDuck: true);
      await settle();

      expect(service.status.state, RecordingState.recording);
      expect(await t.media.interruptionsFor(keynote.id), isEmpty);
    });

    test('FR-REC-05 when the system allows it, recording resumes and says '
        '"Recording resumed"', () async {
      await record();
      source.began();
      await settle();
      t.clock.advance(const Duration(minutes: 2));

      source.ended(shouldResume: true);
      await settle();

      expect(service.status.state, RecordingState.recording);
      expect(await t.media.segmentsFor(keynote.id), hasLength(2));
      final row = (await t.media.interruptionsFor(keynote.id)).single;
      expect(row.autoResumed, isTrue);
      expect(shown.single.kind, InterruptionNoticeKind.resumed);
      expect(shown.single.message, 'Recording resumed');
      expect(shown.single.activityId, keynote.id);
    });

    test('FR-REC-05 when the system does not allow resume, a one-tap resume '
        'notice is shown', () async {
      await record();
      source.began();
      await settle();

      source.ended(shouldResume: false);
      await settle();

      expect(service.status.state, RecordingState.userResumeRequired);
      expect(shown.single.kind, InterruptionNoticeKind.resumeRequired);
      expect(shown.single.message, contains('Tap Resume'));
      expect(await service.resume(), isTrue);
      expect(service.status.state, RecordingState.recording);
    });

    test('FR-REC-05 began and ended in quick succession are handled in '
        'order', () async {
      await record();

      source
        ..began()
        ..ended(shouldResume: true);
      await settle();

      expect(service.status.state, RecordingState.recording);
      final segs = await t.media.segmentsFor(keynote.id);
      expect(segs.map((s) => s.endReason), [
        SegmentEndReason.interruption,
        null,
      ]);
    });

    test(
      'FR-REC-05 an ended event with nothing interrupted does nothing',
      () async {
        await record();

        source.ended(shouldResume: true);
        await settle();

        expect(service.status.state, RecordingState.recording);
        expect(await t.media.segmentsFor(keynote.id), hasLength(1));
        expect(shown, isEmpty);
      },
    );

    test('FR-REC-05 an interruption while paused does not resume the '
        'recording', () async {
      await record();
      await service.pause();

      source
        ..began()
        ..ended(shouldResume: true);
      await settle();

      expect(service.status.state, RecordingState.paused);
      expect(await t.media.interruptionsFor(keynote.id), isEmpty);
    });

    test('FR-REC-05 AT-REC-01 three calls give four segments and three '
        'auto-resumed rows with no unexplained gap', () async {
      await record();
      for (var i = 0; i < 3; i++) {
        source.began();
        await settle();
        t.clock.advance(const Duration(minutes: 1));
        source.ended(shouldResume: true);
        await settle();
        t.clock.advance(const Duration(minutes: 5));
      }
      await service.stop();

      final segs = await t.media.segmentsFor(keynote.id);
      final rows = await t.media.interruptionsFor(keynote.id);
      expect(segs, hasLength(4));
      expect(rows, hasLength(3));
      for (var i = 0; i < rows.length; i++) {
        expect(rows[i].startUtc, segs[i].endUtc);
        expect(rows[i].endUtc, segs[i + 1].startUtc);
        expect(rows[i].autoResumed, isTrue);
      }
      expect(segs.every((s) => s.state == SegmentState.finalised), isTrue);
    });
  });

  group('FR-PHO-07 camera interruptions', () {
    test('FR-PHO-07 an interruption during a shot is logged as camera and '
        'resumes straight after the shot', () async {
      await record();

      await coordinator.duringCameraUse(() async {
        source.began();
        await settle();
        expect(service.status.state, RecordingState.interrupted);
        expect(service.status.interruption, InterruptionReason.camera);
      });
      await settle();

      expect(service.status.state, RecordingState.recording);
      final row = (await t.media.interruptionsFor(keynote.id)).single;
      expect(row.reason, InterruptionReason.camera);
      expect(row.autoResumed, isTrue);
      expect(shown.single.message, 'Recording resumed');
    });

    test('FR-PHO-07 a camera interruption resumes even when the system says '
        'it may not', () async {
      await record();
      await coordinator.duringCameraUse(() async {});

      source.began();
      await settle();
      source.ended(shouldResume: false);
      await settle();

      expect(service.status.state, RecordingState.recording);
      final row = (await t.media.interruptionsFor(keynote.id)).single;
      expect(row.reason, InterruptionReason.camera);
    });

    test('FR-PHO-07 an ended event during the shot waits for the shot to '
        'finish', () async {
      await record();

      await coordinator.duringCameraUse(() async {
        source
          ..began()
          ..ended(shouldResume: true);
        await settle();
        expect(service.status.state, RecordingState.interrupted);
        expect(engine.isCapturing, isFalse);
      });
      await settle();

      expect(service.status.state, RecordingState.recording);
      expect(await t.media.segmentsFor(keynote.id), hasLength(2));
    });

    test('FR-PHO-07 an interruption within 2 s after a shot is still put '
        'down to the camera', () async {
      await record();
      await coordinator.duringCameraUse(() async {});
      t.clock.advance(const Duration(milliseconds: 1500));

      source.began();
      await settle();

      expect(service.status.interruption, InterruptionReason.camera);
    });

    test(
      'FR-PHO-07 an interruption well after a shot is not the camera',
      () async {
        await record();
        await coordinator.duringCameraUse(() async {});
        t.clock.advance(const Duration(seconds: 3));

        source.began();
        await settle();

        expect(service.status.interruption, InterruptionReason.system);
        expect(service.status.state, RecordingState.interrupted);
      },
    );

    test('FR-PHO-07 a shot with no interruption leaves the recording '
        'alone', () async {
      await record();

      final result = await coordinator.duringCameraUse(() async => 'photo');
      await settle();

      expect(result, 'photo');
      expect(service.status.state, RecordingState.recording);
      expect(await t.media.segmentsFor(keynote.id), hasLength(1));
      expect(shown, isEmpty);
    });

    test('FR-PHO-07 a failed shot still ends the camera use', () async {
      await record();

      await expectLater(
        coordinator.duringCameraUse(() async {
          source.began();
          await settle();
          throw StateError('camera failed');
        }),
        throwsStateError,
      );
      await settle();

      expect(service.status.state, RecordingState.recording);
    });
  });

  group('FR-REC-03 FR-REC-07 route events', () {
    test('FR-REC-07 a device change to a new input cuts a route_change '
        'segment', () async {
      await record();
      routes.active = headset;

      source.devicesChanged();
      await settle();

      final segs = await t.media.segmentsFor(keynote.id);
      expect(segs.first.endReason, SegmentEndReason.routeChange);
      expect(segs.last.inputRoute, headset.key);
      expect(service.status.state, RecordingState.recording);
    });

    test('FR-REC-03 the same input is not cut unless forced', () async {
      await record();

      source.becomingNoisy();
      await settle();
      expect(await t.media.segmentsFor(keynote.id), hasLength(1));

      await coordinator.dispose();
      coordinator = build(forceRouteRoll: true);
      source.devicesChanged();
      await settle();
      expect(await t.media.segmentsFor(keynote.id), hasLength(2));
    });

    test('FR-REC-07 no mic left shows a resume notice', () async {
      await record();
      routes.active = headset;
      engine.startError = StateError('no input');

      source.devicesChanged();
      await settle();

      expect(service.status.state, RecordingState.userResumeRequired);
      expect(shown.single.kind, InterruptionNoticeKind.resumeRequired);
      expect(shown.single.message, contains('No microphone'));
      final row = (await t.media.interruptionsFor(keynote.id)).single;
      expect(row.reason, InterruptionReason.routeLost);
    });
  });

  test('FR-REC-05 dispose stops listening', () async {
    await record();
    await coordinator.dispose();

    source.began();
    await pumpEventQueue();

    expect(service.status.state, RecordingState.recording);
  });
}
