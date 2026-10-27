import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/platform/interruptions/audio_interruption_source.dart';
import 'package:attenlume/spikes/background_recording_spike.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fake_capture_engine.dart';
import '../fixtures/fixtures.dart';

class _FakeInterruptions implements AudioInterruptionSource {
  final controller = StreamController<AudioInterruption>.broadcast();
  bool active = false;
  Object? activateError;

  @override
  Future<void> activate() async {
    if (activateError != null) throw activateError!;
    active = true;
  }

  @override
  Future<void> deactivate() async => active = false;

  @override
  Stream<AudioInterruption> get events => controller.stream;

  Future<void> close() => controller.close();
}

void main() {
  late TestData t;
  late Directory root;
  late FakeCaptureEngine engine;
  late RecordingService service;
  late _FakeInterruptions interruptions;
  late StreamController<AppLifecycleState> lifecycle;
  late Activity keynote;

  /// Things to do after the n-th one-second wait (1-based).
  late Map<int, void Function()> script;

  BackgroundRecordingSpike spike() {
    late BackgroundRecordingSpike spike;
    return spike = BackgroundRecordingSpike(
      service: service,
      engine: engine,
      media: t.media,
      interruptions: interruptions,
      lifecycle: lifecycle.stream,
      clock: t.clock.call,
      wait: (d) async {
        t.clock.advance(d);
        script.remove(t.clock.now.difference(startOfRun).inSeconds)?.call();
        // Deliver the stream events, then let the commands they queued run
        // before the next sample.
        await Future<void>.delayed(Duration.zero);
        await spike.settle();
      },
    );
  }

  setUp(() async {
    t = TestData();
    startOfRun = t.clock.now;
    root = await Directory.systemTemp.createTemp('attenlume_p0_04_');
    engine = FakeCaptureEngine();
    service = RecordingService(
      engine: engine,
      activities: t.activities,
      media: t.media,
      mediaRoot: () async => root,
      platform: CapturePlatform.android,
      clock: t.clock.call,
      hashFile: (_) async => 'hash',
    );
    interruptions = _FakeInterruptions();
    lifecycle = StreamController<AppLifecycleState>.broadcast();
    script = {};
    final conference = await t.conference();
    keynote = await t.activity(conference.id, title: 'Data Mesh Keynote');
  });

  tearDown(() async {
    await service.dispose();
    await lifecycle.close();
    await interruptions.close();
    await t.close();
    await root.delete(recursive: true);
  });

  test('P0-04 records for the requested time and saves one segment', () async {
    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(seconds: 5),
    );

    expect(report.startOutcome, StartOutcome.started);
    expect(report.samples, hasLength(5));
    expect(report.segments, hasLength(1));
    expect(report.segments.single.state, SegmentState.finalised);
    expect(report.segments.single.endReason, SegmentEndReason.userStop);
    expect(interruptions.active, isFalse, reason: 'deactivated at the end');
    expect(
      report.observations,
      contains(contains('never left the foreground')),
    );
  });

  test('P0-04 NFR-05 splits level samples by app state and flags a flat '
      'background signal', () async {
    script = {
      2: () {
        lifecycle.add(AppLifecycleState.inactive);
        engine.level = -160;
      },
      3: () => lifecycle.add(AppLifecycleState.paused),
      6: () {
        lifecycle.add(AppLifecycleState.resumed);
        engine.level = -30;
      },
    };

    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(seconds: 8),
    );

    expect(report.wentToBackground, isTrue);
    expect(report.background.count, 4);
    expect(report.background.flat, isTrue);
    expect(report.foreground.flat, isFalse);
    expect(report.foreground.maxDbfs, -30);
    expect(report.observations, contains(contains('flat')));
  });

  test('P0-04 NFR-05 reports background signal when the mic keeps '
      'working', () async {
    script = {2: () => lifecycle.add(AppLifecycleState.paused)};

    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(seconds: 4),
    );

    expect(report.background.count, greaterThan(0));
    expect(report.background.flat, isFalse);
    expect(
      report.observations,
      contains(contains('Background signal present')),
    );
  });

  test('P0-04 FR-REC-05 interruption ends the segment, logs it and '
      'resumes when the system allows', () async {
    script = {
      2: () => interruptions.controller.add(
        const AudioInterruption(AudioInterruptionKind.began),
      ),
      4: () => interruptions.controller.add(
        const AudioInterruption(
          AudioInterruptionKind.ended,
          shouldResume: true,
        ),
      ),
    };

    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(seconds: 6),
    );

    expect(report.segments, hasLength(2));
    expect(report.segments.first.endReason, SegmentEndReason.pause);
    expect(report.segments.last.endReason, SegmentEndReason.userStop);
    expect(report.interruptions, hasLength(1));
    expect(report.interruptions.single.autoResumed, isTrue);
    expect(report.interruptions.single.endUtc, isNotNull);
    expect(report.systemOfferedResume, isTrue);
    // No samples while paused for the interruption (the call is never
    // recorded).
    expect(report.samples, hasLength(4));
  });

  test('P0-04 FR-REC-05 without a system resume, resumes when the app is '
      'visible again', () async {
    script = {
      1: () => lifecycle.add(AppLifecycleState.paused),
      2: () => interruptions.controller.add(
        const AudioInterruption(AudioInterruptionKind.began),
      ),
      3: () => interruptions.controller.add(
        const AudioInterruption(AudioInterruptionKind.ended),
      ),
      5: () => lifecycle.add(AppLifecycleState.resumed),
    };

    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(seconds: 7),
    );

    expect(report.systemOfferedResume, isFalse);
    expect(report.segments, hasLength(2));
    expect(report.interruptions.single.autoResumed, isFalse);
    expect(
      report.events.where((e) => e.kind == 'resumed').single.detail['why'],
      'app_visible',
    );
    expect(report.observations, contains(contains('user-resume path')));
  });

  test('P0-04 a duck request does not interrupt the recording', () async {
    script = {
      2: () => interruptions.controller.add(
        const AudioInterruption(AudioInterruptionKind.began, mayDuck: true),
      ),
    };

    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(seconds: 4),
    );

    expect(report.segments, hasLength(1));
    expect(report.interruptions, isEmpty);
  });

  test('P0-04 an interruption still open at the end is closed and the '
      'audio kept', () async {
    script = {
      2: () => interruptions.controller.add(
        const AudioInterruption(AudioInterruptionKind.began),
      ),
    };

    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(seconds: 4),
    );

    expect(report.segments, hasLength(1));
    expect(report.segments.single.state, SegmentState.finalised);
    expect(report.interruptions.single.endUtc, isNotNull);
    expect(report.interruptions.single.autoResumed, isFalse);
  });

  test('P0-04 a denied microphone is reported, nothing recorded', () async {
    engine.permission = false;

    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(seconds: 3),
    );

    expect(report.startOutcome, StartOutcome.microphoneDenied);
    expect(report.samples, isEmpty);
    expect(report.segments, isEmpty);
    expect(report.events.first.detail['microphone'], isFalse);
  });

  test('P0-04 an audio session error is logged and recording goes '
      'ahead', () async {
    interruptions.activateError = StateError('no session');

    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(seconds: 2),
    );

    expect(report.events.map((e) => e.kind), contains('audio_session_error'));
    expect(report.segments, hasLength(1));
  });

  test('P0-04 report JSON and Markdown carry segments and events', () async {
    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(seconds: 2),
    );

    final json = jsonDecode(report.toPrettyJson()) as Map<String, Object?>;
    expect(json['spike'], 'P0-04');
    expect(json['segments'], hasLength(1));
    expect(json['events'], isNotEmpty);
    expect(report.toMarkdown(), contains('| 1 | finalised | user_stop |'));
  });
}

late DateTime startOfRun;
