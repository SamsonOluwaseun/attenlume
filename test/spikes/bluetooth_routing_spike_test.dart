import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/platform/interruptions/audio_interruption_source.dart';
import 'package:attenlume/spikes/bluetooth_routing_spike.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fake_capture_engine.dart';
import '../fixtures/fake_route_probe.dart';
import '../fixtures/fixtures.dart';

class _FakeInterruptions implements AudioInterruptionSource {
  final controller = StreamController<AudioInterruption>.broadcast();
  bool active = false;

  @override
  Future<void> activate() async => active = true;

  @override
  Future<void> deactivate() async => active = false;

  @override
  Stream<AudioInterruption> get events => controller.stream;

  Future<void> close() => controller.close();
}

const _devicesChanged = AudioInterruption(AudioInterruptionKind.devicesChanged);

void main() {
  late TestData t;
  late Directory root;
  late FakeCaptureEngine engine;
  late FakeRouteProbe routes;
  late RecordingService service;
  late _FakeInterruptions interruptions;
  late Activity keynote;
  late DateTime startOfRun;

  /// Things to do after the n-th one-second wait (1-based), before the
  /// spike polls the inputs.
  late Map<int, void Function()> script;

  BluetoothRoutingSpike spike() {
    late BluetoothRoutingSpike spike;
    return spike = BluetoothRoutingSpike(
      service: service,
      engine: engine,
      media: t.media,
      routes: routes,
      interruptions: interruptions,
      mediaRoot: root,
      platform: CapturePlatform.ios,
      clock: t.clock.call,
      wait: (d) async {
        t.clock.advance(d);
        script.remove(t.clock.now.difference(startOfRun).inSeconds)?.call();
        await Future<void>.delayed(Duration.zero);
        await spike.settle();
      },
    );
  }

  setUp(() async {
    t = TestData();
    startOfRun = t.clock.now;
    root = await Directory.systemTemp.createTemp('attenlume_p0_07_');
    engine = FakeCaptureEngine();
    routes = FakeRouteProbe()
      ..active = builtInMic
      ..available = const [builtInMic];
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
    interruptions = _FakeInterruptions();
    script = {};
    final conference = await t.conference();
    keynote = await t.activity(conference.id, title: 'Speaker chat');
  });

  tearDown(() async {
    await service.dispose();
    await interruptions.close();
    await t.close();
    await root.delete(recursive: true);
  });

  void connectHeadset() => routes
    ..available = const [builtInMic, headset]
    ..active = headset;

  void disconnectHeadset() => routes
    ..available = const [builtInMic]
    ..active = builtInMic;

  test('P0-07 with no change, one segment and a prompt to move the '
      'headset', () async {
    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(seconds: 3),
    );

    expect(report.startOutcome, StartOutcome.started);
    expect(report.checks, hasLength(1));
    expect(report.changes, isEmpty);
    expect(report.samples, hasLength(3));
    expect(interruptions.active, isFalse, reason: 'deactivated at the end');
    expect(report.observations, contains(contains('No input change seen')));
  });

  test('P0-07 FR-REC-03 connect then disconnect gives three segments with '
      'their routes', () async {
    script = {
      2: () {
        connectHeadset();
        interruptions.controller.add(_devicesChanged);
      },
      4: () {
        disconnectHeadset();
        interruptions.controller.add(_devicesChanged);
      },
    };

    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(seconds: 6),
    );

    final segments = [for (final c in report.checks) c.segment];
    expect(segments.map((s) => s.inputRoute), [
      'builtIn: iPhone Microphone',
      'bluetooth: Lapel Mic',
      'builtIn: iPhone Microphone',
    ]);
    expect(segments.map((s) => s.endReason), [
      SegmentEndReason.routeChange,
      SegmentEndReason.routeChange,
      SegmentEndReason.userStop,
    ]);
    expect(report.changesByEvent, 2);
    expect(report.changesByPollOnly, 0);
    expect(report.activeInputReported, isTrue);
  });

  test('P0-07 FR-REC-07 a lost headset leaves a route_lost marker and '
      'recording carries on', () async {
    connectHeadset();
    script = {3: disconnectHeadset};

    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(seconds: 5),
    );

    final lost = report.interruptions
        .where((i) => i.reason == InterruptionReason.routeLost)
        .toList();
    expect(lost, hasLength(1));
    expect(lost.single.autoResumed, isTrue);
    expect(lost.single.endUtc, isNotNull);
    expect(report.changesByPollOnly, 1, reason: 'no event was sent');
    expect(
      report.observations,
      contains(contains('0 by a device event, 1 only by polling')),
    );
  });

  test('P0-07 FR-REC-07 with no mic left the recorder waits, then a '
      'reconnect resumes', () async {
    connectHeadset();
    script = {
      2: () {
        routes
          ..available = const []
          ..active = null;
        engine.startError = StateError('No audio recording device was found.');
      },
      4: () {
        engine.startError = null;
        connectHeadset();
      },
    };

    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(seconds: 6),
    );

    expect(report.resumeRequiredCount, 1);
    final lost = report.interruptions.single;
    expect(lost.reason, InterruptionReason.routeLost);
    expect(lost.autoResumed, isFalse);
    expect(lost.endUtc, isNotNull);
    expect(report.events.map((e) => e.kind), contains('resumed'));
    expect(
      report.checks.last.segment.inputRoute,
      'bluetooth: Lapel Mic',
      reason: 'the resumed segment records from the headset',
    );
    expect(
      report.observations,
      contains(contains('no microphone could take over')),
    );
  });

  test('P0-07 ADR-016 without an active input every device change cuts a '
      'boundary', () async {
    routes.active = null;
    script = {
      2: () {
        routes.available = const [builtInMic, headset];
        interruptions.controller.add(_devicesChanged);
      },
    };

    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(seconds: 4),
    );

    expect(report.activeInputReported, isFalse);
    expect(report.checks, hasLength(2));
    expect(report.checks.every((c) => c.segment.inputRoute == null), isTrue);
    expect(
      report.observations,
      contains(contains('never reported the active input')),
    );
  });

  test('P0-07 a device event with no input change is counted', () async {
    script = {2: () => interruptions.controller.add(_devicesChanged)};

    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(seconds: 3),
    );

    expect(report.eventsWithoutChange, 1);
    expect(report.checks, hasLength(1));
  });

  group('AT-QUAL-03 codec and channel labels', () {
    test('AT-QUAL-03 rows match their files after route changes', () async {
      script = {2: connectHeadset, 4: disconnectHeadset};

      final report = await spike().run(
        activityId: keynote.id,
        length: const Duration(seconds: 5),
      );

      expect(report.checks, hasLength(3));
      expect(report.checks.every((c) => c.labelMatchesFile == true), isTrue);
      expect(report.mislabelled, isEmpty);
      expect(
        report.observations,
        contains(contains('AT-QUAL-03: 0 segment(s)')),
      );
    });

    test('AT-QUAL-03 a headset that delivers other channels and rate is '
        'labelled from the file and reported', () async {
      script = {2: connectHeadset};
      engine
        ..deliveredChannels = ((_) => routes.active == headset ? 2 : 1)
        ..deliveredSampleRateHz = ((_) =>
            routes.active == headset ? 16000 : 48000);

      final report = await spike().run(
        activityId: keynote.id,
        length: const Duration(seconds: 4),
      );

      final bt = report.checks.last;
      expect(bt.onBluetooth, isTrue);
      expect(bt.segment.channelCount, 2);
      expect(bt.segment.sampleRateHz, 16000);
      expect(bt.labelMatchesFile, isTrue);
      expect(bt.deliveredDiffers, isTrue);
      expect(
        report.observations,
        contains(contains('asked for 1 ch 48000 Hz, file has 2 ch 16000 Hz')),
      );
      expect(report.observations, contains(contains('narrowband')));
    });

    test('AT-QUAL-03 a damaged segment is not claimed as checked', () async {
      engine.finaliseValidFile = false;

      final report = await spike().run(
        activityId: keynote.id,
        length: const Duration(seconds: 2),
      );

      expect(report.checks.single.segment.state, SegmentState.damaged);
      expect(report.checks.single.labelMatchesFile, isNull);
      expect(report.toMarkdown(), contains('no file to compare'));
    });
  });

  test('P0-07 report JSON and Markdown carry routes, checks and '
      'events', () async {
    script = {2: connectHeadset};
    engine.level = -42;

    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(seconds: 4),
    );

    final json = jsonDecode(report.toPrettyJson()) as Map<String, Object?>;
    expect(json['spike'], 'P0-07');
    expect(json['mislabelled_segments'], 0);
    expect((json['segments']! as List).length, 2);
    expect((json['route_changes']! as List).length, 1);
    expect((json['max_level_by_route']! as Map)['bluetooth: Lapel Mic'], -42.0);
    final md = report.toMarkdown();
    expect(md, contains('| 2 | finalised | user_stop | bluetooth: Lapel Mic'));
    expect(md, contains('| yes |'));
  });

  test('P0-07 a failing probe is logged and recording carries on', () async {
    script = {2: () => routes.error = StateError('probe gone')};

    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(seconds: 3),
    );

    expect(report.events.map((e) => e.kind), contains('route_probe_error'));
    expect(report.startOutcome, StartOutcome.started);
    expect(report.checks.first.segment.state, SegmentState.finalised);
  });
}
