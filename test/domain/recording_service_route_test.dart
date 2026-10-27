import 'dart:io';

import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fake_capture_engine.dart';
import '../fixtures/fake_route_probe.dart';
import '../fixtures/fixtures.dart';

void main() {
  late TestData t;
  late Directory root;
  late FakeCaptureEngine engine;
  late FakeRouteProbe routes;
  late RecordingService service;
  late Activity keynote;

  setUp(() async {
    t = TestData();
    root = await Directory.systemTemp.createTemp('attenlume_route_');
    engine = FakeCaptureEngine();
    routes = FakeRouteProbe()..active = builtInMic;
    service = RecordingService(
      engine: engine,
      activities: t.activities,
      media: t.media,
      mediaRoot: () async => root,
      platform: CapturePlatform.ios,
      routes: routes,
      clock: t.clock.call,
      hashFile: (_) async => 'hash',
    );
    final conference = await t.conference();
    keynote = await t.activity(conference.id, title: 'Data Mesh Keynote');
  });

  tearDown(() async {
    await service.dispose();
    await t.close();
    await root.delete(recursive: true);
  });

  group('FR-QUAL-06 input route stored per segment', () {
    test('FR-QUAL-06 a segment stores the input in use when it '
        'starts', () async {
      await service.start(keynote.id);

      final segment = (await t.media.segmentsFor(keynote.id)).single;
      expect(segment.inputRoute, 'builtIn: iPhone Microphone');
      expect(service.status.inputRoute, 'builtIn: iPhone Microphone');
    });

    test('FR-QUAL-06 the route is left empty, not guessed, when the '
        'platform does not say', () async {
      routes.active = null;
      await service.start(keynote.id);

      expect((await t.media.segmentsFor(keynote.id)).single.inputRoute, isNull);
    });

    test('FR-QUAL-06 a failing probe does not stop the recording', () async {
      routes.error = StateError('channel gone');

      expect(await service.start(keynote.id), StartOutcome.started);
      expect((await t.media.segmentsFor(keynote.id)).single.inputRoute, isNull);
    });
  });

  group('FR-REC-03 new segment on input route change', () {
    test('FR-REC-03 a new active input ends the segment with '
        'route_change and the next one stores the new input', () async {
      await service.start(keynote.id);
      t.clock.advance(const Duration(minutes: 2));
      routes.active = headset;

      final result = await service.routeChanged();

      expect(result.outcome, RouteChangeOutcome.switched);
      expect(result.from, builtInMic);
      expect(result.to, headset);
      expect(service.status.state, RecordingState.recording);
      expect(service.status.segmentSequence, 2);
      final segments = await t.media.segmentsFor(keynote.id);
      expect(segments, hasLength(2));
      expect(segments[0].endReason, SegmentEndReason.routeChange);
      expect(segments[0].state, SegmentState.finalised);
      expect(segments[1].inputRoute, 'bluetooth: Lapel Mic');
      expect(engine.startedPaths, hasLength(2));
    });

    test('FR-REC-03 the same input leaves the segment alone', () async {
      await service.start(keynote.id);

      final result = await service.routeChanged();

      expect(result.outcome, RouteChangeOutcome.unchanged);
      expect(await t.media.segmentsFor(keynote.id), hasLength(1));
      expect(engine.stopCalls, 0);
    });

    test('FR-REC-03 force cuts a boundary when the active input is not '
        'reported', () async {
      routes.active = null;
      await service.start(keynote.id);

      expect(
        (await service.routeChanged()).outcome,
        RouteChangeOutcome.unchanged,
      );
      final result = await service.routeChanged(force: true);

      expect(result.outcome, RouteChangeOutcome.switched);
      expect(await t.media.segmentsFor(keynote.id), hasLength(2));
    });

    test('FR-REC-03 nothing happens while paused or idle', () async {
      expect(
        (await service.routeChanged(force: true)).outcome,
        RouteChangeOutcome.notRecording,
      );
      await service.start(keynote.id);
      await service.pause();
      routes.active = headset;

      expect(
        (await service.routeChanged(force: true)).outcome,
        RouteChangeOutcome.notRecording,
      );
      await service.resume();
      final segments = await t.media.segmentsFor(keynote.id);
      expect(segments.last.inputRoute, 'bluetooth: Lapel Mic');
    });
  });

  group('FR-REC-07 fallback or pause with a prompt', () {
    test('FR-REC-07 when no input can start, the segment is kept and the '
        'recorder waits for the user', () async {
      await service.start(keynote.id);
      routes.active = null;
      engine.startError = StateError('No audio recording device was found.');

      final result = await service.routeChanged(force: true);

      expect(result.outcome, RouteChangeOutcome.resumeRequired);
      expect(result.reason, contains('tap resume'));
      expect(service.status.state, RecordingState.userResumeRequired);
      expect(service.status.errorMessage, contains('No microphone'));
      final segments = await t.media.segmentsFor(keynote.id);
      expect(segments[0].state, SegmentState.finalised);
      expect(segments[0].endReason, SegmentEndReason.routeChange);
      expect(segments[1].state, SegmentState.damaged);
    });

    test('FR-REC-07 resume after reconnecting records again, and stop '
        'still saves', () async {
      await service.start(keynote.id);
      engine.startError = StateError('no device');
      await service.routeChanged(force: true);

      engine.startError = null;
      routes.active = headset;
      expect(await service.resume(), isTrue);
      expect(service.status.inputRoute, 'bluetooth: Lapel Mic');

      expect(await service.stop(), keynote.id);
      expect(service.status.state, RecordingState.saved);
    });

    test('FR-REC-07 stop from waiting for the user saves what was '
        'written', () async {
      await service.start(keynote.id);
      engine.startError = StateError('no device');
      await service.routeChanged(force: true);

      expect(await service.stop(), keynote.id);
      final segments = await t.media.segmentsFor(keynote.id);
      expect(segments.first.state, SegmentState.finalised);
    });
  });
}
