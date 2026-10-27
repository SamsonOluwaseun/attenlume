import 'dart:io';

import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
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
  late FakeInterruptionSource session;
  late FakeTimers timers;
  late RecordingService service;
  late Activity keynote;

  setUp(() async {
    t = TestData();
    root = await Directory.systemTemp.createTemp('attenlume_interrupt_');
    engine = FakeCaptureEngine();
    routes = FakeRouteProbe()..active = builtInMic;
    session = FakeInterruptionSource();
    timers = FakeTimers();
    service = RecordingService(
      engine: engine,
      activities: t.activities,
      media: t.media,
      mediaRoot: () async => root,
      platform: CapturePlatform.ios,
      routes: routes,
      session: session,
      clock: t.clock.call,
      hashFile: (_) async => 'hash',
      rollTimer: timers.call,
      commitFile: (p, target) => p.rename(target.path),
    );
    final conference = await t.conference();
    keynote = await t.activity(conference.id, title: 'Data Mesh Keynote');
  });

  tearDown(() async {
    await service.dispose();
    await session.close();
    await t.close();
    await root.delete(recursive: true);
  });

  /// Starts recording, lets [minutes] pass and interrupts with [reason].
  Future<void> recordThenInterrupt({
    int minutes = 5,
    InterruptionReason reason = InterruptionReason.system,
  }) async {
    await service.start(keynote.id);
    t.clock.advance(Duration(minutes: minutes));
    expect(await service.interrupt(reason), InterruptOutcome.interrupted);
  }

  group('FR-REC-05 interruption ends the segment and logs a row', () {
    test('FR-REC-05 interrupt finalises the segment with reason interruption '
        'and releases the microphone', () async {
      await recordThenInterrupt();

      final segs = await t.media.segmentsFor(keynote.id);
      expect(segs.single.endReason, SegmentEndReason.interruption);
      expect(segs.single.state, SegmentState.finalised);
      expect(engine.isCapturing, isFalse);
      expect(service.status.state, RecordingState.interrupted);
      expect(service.status.interruption, InterruptionReason.system);
      expect(service.status.activityId, keynote.id);
      expect(timers.active, isEmpty);
    });

    test('FR-REC-05 the interruption row starts where the segment ended and '
        'stays open', () async {
      await recordThenInterrupt(reason: InterruptionReason.call);

      final segs = await t.media.segmentsFor(keynote.id);
      final rows = await t.media.interruptionsFor(keynote.id);
      expect(rows.single.reason, InterruptionReason.call);
      expect(rows.single.startUtc, segs.single.endUtc);
      expect(rows.single.endUtc, isNull);
      expect(rows.single.autoResumed, isFalse);
    });

    test('FR-REC-05 the call is never recorded: resume is refused while '
        'interrupted', () async {
      await recordThenInterrupt();

      expect(await service.resume(), isFalse);
      expect(engine.isCapturing, isFalse);
      expect(engine.startedPaths, hasLength(1));
      expect(service.status.state, RecordingState.interrupted);
    });

    test('FR-REC-05 a second interrupt changes nothing', () async {
      await recordThenInterrupt();

      expect(
        await service.interrupt(InterruptionReason.alarm),
        InterruptOutcome.alreadyInterrupted,
      );
      expect(await t.media.interruptionsFor(keynote.id), hasLength(1));
    });

    test('FR-REC-05 interrupt while paused or idle logs nothing', () async {
      expect(
        await service.interrupt(InterruptionReason.system),
        InterruptOutcome.notRecording,
      );
      await service.start(keynote.id);
      await service.pause();

      expect(
        await service.interrupt(InterruptionReason.system),
        InterruptOutcome.notRecording,
      );
      expect(service.status.state, RecordingState.paused);
      expect(await t.media.interruptionsFor(keynote.id), isEmpty);
    });
  });

  group('FR-REC-05 resume after an interruption', () {
    test('FR-REC-05 system-allowed resume goes interrupted, recovering, '
        'recording in a new segment', () async {
      await recordThenInterrupt();
      final seen = <RecordingState>[];
      final sub = service.statusStream.listen((s) => seen.add(s.state));
      t.clock.advance(const Duration(minutes: 2));

      final result = await service.interruptionEnded(mayResume: true);
      await sub.cancel();

      expect(result.outcome, InterruptionEndOutcome.resumed);
      expect(result.activityId, keynote.id);
      expect(seen, [RecordingState.recovering, RecordingState.recording]);
      final segs = await t.media.segmentsFor(keynote.id);
      expect(segs, hasLength(2));
      expect(segs.last.state, SegmentState.writing);
      expect(segs.last.startUtc, t.clock.now);
      expect(segs.last.requestedProfile, segs.first.requestedProfile);
      expect(engine.isCapturing, isTrue);
      expect(service.status.interruption, isNull);
      expect(timers.active, hasLength(1));
    });

    test('FR-REC-05 the row is closed as auto-resumed with start and end '
        'matching the gap', () async {
      await recordThenInterrupt();
      t.clock.advance(const Duration(minutes: 2));

      await service.interruptionEnded(mayResume: true);

      final segs = await t.media.segmentsFor(keynote.id);
      final row = (await t.media.interruptionsFor(keynote.id)).single;
      expect(row.startUtc, segs.first.endUtc);
      expect(row.endUtc, segs.last.startUtc);
      expect(row.autoResumed, isTrue);
    });

    test('FR-REC-05 the audio session is activated again before the new '
        'segment', () async {
      await recordThenInterrupt();
      final before = session.activations;

      await service.interruptionEnded(mayResume: true);

      expect(session.activations, before + 1);
    });

    test('FR-REC-05 refused resume keeps the audio and waits for the user '
        'with a plain message', () async {
      await recordThenInterrupt();
      t.clock.advance(const Duration(minutes: 2));
      final endedAt = t.clock.now;

      final result = await service.interruptionEnded(mayResume: false);

      expect(result.outcome, InterruptionEndOutcome.resumeRequired);
      expect(result.reason, contains('Tap Resume'));
      expect(result.reason, contains('audio so far is saved'));
      expect(service.status.state, RecordingState.userResumeRequired);
      expect(service.status.errorMessage, result.reason);
      expect(engine.isCapturing, isFalse);
      final segs = await t.media.segmentsFor(keynote.id);
      expect(segs.single.state, SegmentState.finalised);
      final row = (await t.media.interruptionsFor(keynote.id)).single;
      expect(row.endUtc, endedAt);
      expect(row.autoResumed, isFalse);
    });

    test('FR-REC-05 one tap on resume carries on in a new segment', () async {
      await recordThenInterrupt();
      await service.interruptionEnded(mayResume: false);
      t.clock.advance(const Duration(minutes: 1));

      expect(await service.resume(), isTrue);

      expect(service.status.state, RecordingState.recording);
      expect(await t.media.segmentsFor(keynote.id), hasLength(2));
      final row = (await t.media.interruptionsFor(keynote.id)).single;
      expect(row.autoResumed, isFalse);
    });

    test('FR-REC-05 if capture will not restart, the user is asked and '
        'earlier audio is kept', () async {
      await recordThenInterrupt();
      engine.startError = StateError('microphone busy');

      final result = await service.interruptionEnded(mayResume: true);

      expect(result.outcome, InterruptionEndOutcome.resumeRequired);
      expect(result.reason, contains('could not restart'));
      expect(service.status.state, RecordingState.userResumeRequired);
      final segs = await t.media.segmentsFor(keynote.id);
      expect(segs.first.state, SegmentState.finalised);
      expect(segs.last.state, SegmentState.damaged);
      final row = (await t.media.interruptionsFor(keynote.id)).single;
      expect(row.autoResumed, isFalse);
      expect(row.endUtc, isNotNull);
    });

    test(
      'FR-REC-05 interruptionEnded when not interrupted does nothing',
      () async {
        await service.start(keynote.id);

        final result = await service.interruptionEnded(mayResume: true);

        expect(result.outcome, InterruptionEndOutcome.notInterrupted);
        expect(await t.media.segmentsFor(keynote.id), hasLength(1));
      },
    );
  });

  group('FR-REC-05 stopping during an interruption', () {
    test('FR-REC-05 stop while interrupted saves and closes the row', () async {
      await recordThenInterrupt();
      t.clock.advance(const Duration(minutes: 3));

      expect(await service.stop(), keynote.id);

      expect(service.status.state, RecordingState.saved);
      final row = (await t.media.interruptionsFor(keynote.id)).single;
      expect(row.endUtc, t.clock.now);
      expect(row.autoResumed, isFalse);
      final activity = await t.activities.get(keynote.id);
      expect(activity!.status, ActivityStatus.completed);
      expect(session.active, isFalse);
    });

    test(
      'FR-REC-05 stop while waiting for the user keeps every segment',
      () async {
        await recordThenInterrupt();
        await service.interruptionEnded(mayResume: false);

        await service.stop();

        final segs = await t.media.segmentsFor(keynote.id);
        expect(segs.single.state, SegmentState.finalised);
        expect(segs.single.endReason, SegmentEndReason.interruption);
      },
    );
  });

  group('FR-REC-07 lost microphone marker', () {
    test('FR-REC-07 a route change with no mic left logs an open route_lost '
        'row, closed on resume', () async {
      await service.start(keynote.id);
      t.clock.advance(const Duration(minutes: 4));
      routes.active = headset;
      engine.startError = StateError('no input');

      final result = await service.routeChanged();

      expect(result.outcome, RouteChangeOutcome.resumeRequired);
      expect(service.status.interruption, InterruptionReason.routeLost);
      var row = (await t.media.interruptionsFor(keynote.id)).single;
      expect(row.reason, InterruptionReason.routeLost);
      expect(row.startUtc, t.clock.now);
      expect(row.endUtc, isNull);

      engine.startError = null;
      t.clock.advance(const Duration(minutes: 1));
      expect(await service.resume(), isTrue);

      row = (await t.media.interruptionsFor(keynote.id)).single;
      expect(row.endUtc, t.clock.now);
      expect(row.autoResumed, isFalse);
    });
  });

  group('FR-REC-05 audio session ownership', () {
    test('FR-REC-05 the session is activated before capture and released '
        'once saved', () async {
      engine.onStart = (_) async => expect(session.active, isTrue);

      await service.start(keynote.id);
      expect(session.activations, 1);
      await service.stop();

      expect(session.deactivations, 1);
      expect(session.active, isFalse);
    });

    test('FR-REC-05 a session that will not activate does not block '
        'recording', () async {
      session.activateError = StateError('session busy');

      expect(await service.start(keynote.id), StartOutcome.started);
    });
  });
}
