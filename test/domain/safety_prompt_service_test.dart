import 'dart:async';
import 'dart:io';

import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/domain/services/safety_prompt_service.dart';
import 'package:attenlume/platform/diagnostics/battery_probe.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fake_capture_engine.dart';
import '../fixtures/fixtures.dart';

class _Battery implements BatteryProbe {
  BatteryReading? reading;
  int reads = 0;

  @override
  Future<BatteryReading?> read() async {
    reads++;
    return reading;
  }
}

void main() {
  late TestData t;
  late Directory root;
  late FakeCaptureEngine engine;
  late RecordingService recorder;
  late Activity activity;
  late _Battery battery;
  late SafetyPromptService service;
  late List<SafetyPrompt> prompts;
  double level = -20;

  setUp(() async {
    t = TestData();
    root = await Directory.systemTemp.createTemp('safety_prompt_test_');
    engine = FakeCaptureEngine();
    final conf = await t.conference();
    activity = await t.activity(conf.id, title: 'Keynote');
    recorder = RecordingService(
      engine: engine,
      activities: t.activities,
      media: t.media,
      mediaRoot: () async => root,
      platform: CapturePlatform.android,
      clock: t.clock.call,
      hashFile: (_) async => 'hash',
    );
    battery = _Battery();
    level = -20;
    prompts = [];
    service = SafetyPromptService(
      recorder: recorder,
      level: () async => level,
      battery: battery,
      // Ticks are driven by calling check(); the timer never fires.
      createTimer: (d, cb) => Timer(const Duration(days: 365), () {}),
      clock: t.clock.call,
    )..start();
    service.prompts.listen(prompts.add);
  });

  tearDown(() async {
    await service.dispose();
    await recorder.dispose();
    await t.close();
    await root.delete(recursive: true);
  });

  Future<void> tick([Duration by = const Duration(seconds: 5)]) async {
    t.clock.advance(by);
    await service.check();
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'FR-REC-06 prompts once a recording passes 2 hours, then every 2 hours',
    () async {
      await recorder.start(activity.id);
      await Future<void>.delayed(Duration.zero);

      await tick(const Duration(hours: 1, minutes: 59));
      expect(prompts, isEmpty);

      await tick(const Duration(minutes: 2));
      expect(prompts.map((p) => p.kind), [SafetyPromptKind.longRecording]);
      expect(prompts.single.activityId, activity.id);

      await tick(const Duration(minutes: 30));
      expect(prompts, hasLength(1), reason: 'not again until 4 hours');

      await tick(const Duration(hours: 2));
      expect(prompts, hasLength(2));
      expect(recorder.status.state.name, 'recording');
    },
  );

  test('FR-REC-06 paused time does not count towards 2 hours', () async {
    await recorder.start(activity.id);
    await Future<void>.delayed(Duration.zero);
    await tick(const Duration(hours: 1));
    await recorder.pause();
    await Future<void>.delayed(Duration.zero);
    t.clock.advance(const Duration(hours: 3));
    await recorder.resume();
    await Future<void>.delayed(Duration.zero);

    await tick(const Duration(minutes: 30));
    expect(prompts, isEmpty);
    await tick(const Duration(minutes: 31));
    expect(prompts.map((p) => p.kind), [SafetyPromptKind.longRecording]);
  });

  test(
    'FR-REC-06 10 minutes of near-silence prompts once, recording continues',
    () async {
      await recorder.start(activity.id);
      await Future<void>.delayed(Duration.zero);
      level = -70;

      for (var i = 0; i < 9; i++) {
        await tick(const Duration(minutes: 1));
      }
      expect(prompts, isEmpty);

      await tick(const Duration(minutes: 1, seconds: 5));
      expect(prompts.map((p) => p.kind), [SafetyPromptKind.silence]);

      await tick(const Duration(minutes: 15));
      expect(prompts, hasLength(1), reason: 'once until sound returns');
      expect(recorder.status.state.name, 'recording');

      level = -30;
      await tick();
      level = -70;
      await tick(const Duration(minutes: 10, seconds: 5));
      expect(prompts, hasLength(2), reason: 're-armed after sound returned');
    },
  );

  test('FR-REC-06 sound keeps resetting the silence timer', () async {
    await recorder.start(activity.id);
    await Future<void>.delayed(Duration.zero);

    for (var i = 0; i < 30; i++) {
      level = i.isEven ? -70 : -35;
      await tick(const Duration(minutes: 1));
    }
    expect(prompts, isEmpty);
  });

  test('FR-REC-06 battery below 15 % and not charging prompts once', () async {
    await recorder.start(activity.id);
    await Future<void>.delayed(Duration.zero);
    battery.reading = const BatteryReading(percent: 14, charging: false);

    await tick();
    expect(prompts.map((p) => p.kind), [SafetyPromptKind.lowBattery]);
    expect(prompts.single.batteryPercent, 14);

    for (var i = 0; i < 30; i++) {
      await tick();
    }
    expect(prompts, hasLength(1));
  });

  test('FR-REC-06 no battery prompt while charging or when unknown', () async {
    await recorder.start(activity.id);
    await Future<void>.delayed(Duration.zero);

    battery.reading = null;
    await tick();
    battery.reading = const BatteryReading(percent: 5, charging: true);
    for (var i = 0; i < 13; i++) {
      await tick();
    }
    expect(prompts, isEmpty);
    expect(battery.reads, greaterThanOrEqualTo(2));
  });

  test('FR-REC-06 nothing is checked when not recording', () async {
    level = -90;
    battery.reading = const BatteryReading(percent: 1, charging: false);
    await tick(const Duration(hours: 3));
    expect(prompts, isEmpty);
    expect(battery.reads, 0);
  });

  test('FR-REC-06 a new recording starts with fresh prompts', () async {
    await recorder.start(activity.id);
    await Future<void>.delayed(Duration.zero);
    await tick(const Duration(hours: 2, minutes: 1));
    expect(prompts, hasLength(1));
    await recorder.stop();
    await Future<void>.delayed(Duration.zero);

    await recorder.start(activity.id);
    await Future<void>.delayed(Duration.zero);
    await tick(const Duration(minutes: 5));
    expect(prompts, hasLength(1));
    expect(service.recordedTime, const Duration(minutes: 5));
  });
}
