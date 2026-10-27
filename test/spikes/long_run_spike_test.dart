import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:attenlume/platform/diagnostics/battery_probe.dart';
import 'package:attenlume/platform/diagnostics/memory_probe.dart';
import 'package:attenlume/platform/diagnostics/windows_battery_probe.dart';
import 'package:attenlume/spikes/long_run_spike.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fake_capture_engine.dart';
import '../fixtures/fixtures.dart';

const _mb = 1024 * 1024;

class _ScriptedMemory implements MemoryProbe {
  int rss = 100 * _mb;
  int peak = 100 * _mb;

  @override
  int currentRssBytes() {
    if (rss > peak) peak = rss;
    return rss;
  }

  @override
  int peakRssBytes() => peak;
}

class _ScriptedBattery implements BatteryProbe {
  _ScriptedBattery(this.readings);

  final List<BatteryReading?> readings;
  var _next = 0;

  @override
  Future<BatteryReading?> read() async =>
      readings[_next < readings.length ? _next++ : readings.length - 1];
}

void main() {
  late TestData t;
  late Directory root;
  late FakeCaptureEngine engine;
  late RecordingService service;
  late _ScriptedMemory memory;
  late Activity keynote;
  late DateTime startOfRun;

  /// Called after each wait with the minutes since the start.
  late FutureOr<void> Function(int minute) everyMinute;

  LongRunSpike spike({BatteryProbe battery = const UnknownBatteryProbe()}) =>
      LongRunSpike(
        service: service,
        engine: engine,
        media: t.media,
        mediaRoot: root,
        memory: memory,
        battery: battery,
        clock: t.clock.call,
        wait: (d) async {
          t.clock.advance(d);
          await everyMinute(t.clock.now.difference(startOfRun).inMinutes);
        },
      );

  /// Grows the file the fake encoder is writing, as a real one would.
  void grow(int bytes) {
    final file = File(engine.startedPaths.last);
    file.writeAsBytesSync(List.filled(bytes, 0), mode: FileMode.append);
  }

  setUp(() async {
    t = TestData();
    startOfRun = t.clock.now;
    root = await Directory.systemTemp.createTemp('attenlume_p0_10_');
    engine = FakeCaptureEngine()
      ..durationSeconds = 10 * 60
      ..deliveredBitrateBps = ((r) => r.bitrateBps);
    service = RecordingService(
      engine: engine,
      activities: t.activities,
      media: t.media,
      mediaRoot: () async => root,
      platform: CapturePlatform.android,
      clock: t.clock.call,
      hashFile: (_) async => 'hash',
    );
    memory = _ScriptedMemory();
    everyMinute = (_) {};
    final conference = await t.conference();
    keynote = await t.activity(conference.id, title: 'Data Mesh Keynote');
  });

  tearDown(() async {
    await service.dispose();
    await t.close();
    await root.delete(recursive: true);
  });

  test(
    'P0-10 FR-REC-02 samples once a minute and saves the recording',
    () async {
      everyMinute = (_) => grow(360000);

      final report = await spike().run(
        activityId: keynote.id,
        length: const Duration(minutes: 10),
      );

      expect(report.startOutcome, StartOutcome.started);
      expect(report.samples, hasLength(10));
      expect(report.samples.map((s) => s.offsetMs ~/ 60000), [
        for (var m = 1; m <= 10; m++) m,
      ]);
      expect(
        report.samples.every((s) => s.state == RecordingState.recording),
        isTrue,
      );
      expect(report.notRecordingSamples, 0);
      expect(
        [for (final s in report.samples) s.openFileBytes],
        [for (var m = 1; m <= 10; m++) m * 360000],
        reason: 'file size read from disk while recording',
      );
      expect(report.stalledIntervals, 0);
      expect(report.segments, hasLength(1));
      expect(report.segments.single.state, SegmentState.finalised);
      expect(report.segments.single.endReason, SegmentEndReason.userStop);
      expect(service.status.state, RecordingState.saved);
    },
  );

  test('P0-10 shortens the last wait so the run ends on time', () async {
    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(seconds: 150),
    );

    expect(
      [for (final s in report.samples) s.offsetMs],
      [60000, 120000, 150000],
    );
  });

  test('P0-10 AT-MEM-01 reports a flat memory trend as zero growth', () async {
    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(minutes: 30),
    );

    expect(report.rssSlopeMbPerHour, closeTo(0, 1e-9));
    expect(report.rssThirdsMb, (100.0, 100.0));
    expect(report.observations, contains(contains('0.00 MB per hour')));
  });

  test('P0-10 AT-MEM-01 measures steady growth after the warm-up and '
      'ignores start-up allocation', () async {
    everyMinute = (minute) {
      // A jump during warm-up, then 1 MB a minute: 60 MB per hour.
      memory.rss = minute < 5 ? 180 * _mb : (200 + minute) * _mb;
    };

    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(minutes: 90),
    );

    expect(report.samples, hasLength(90));
    expect(report.rssSlopeMbPerHour, closeTo(60, 1e-6));
    expect(report.rssBeforeBytes, 100 * _mb);
    expect(report.peakRssBytes, 290 * _mb);
    final (first, last) = report.rssThirdsMb!;
    expect(last, greaterThan(first));
    expect(report.observations, contains(contains('60.00 MB per hour')));
  });

  test('P0-10 leaves the trend unknown with too few samples after the '
      'warm-up', () async {
    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(minutes: 6),
    );

    expect(report.rssSlopeMbPerHour, isNull);
    expect(report.observations, contains(contains('unknown MB per hour')));
  });

  test('P0-10 FR-QUAL-06 reports whole-file rate and disk use per hour from '
      'the saved files', () async {
    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(minutes: 10),
    );

    final segment = report.segments.single;
    expect(report.recordedMs, segment.durationMs);
    expect(report.recordedBytes, segment.bytes);
    expect(report.requestedBitrateBps, segment.requestedBitrateBps);
    final kbps = segment.bytes! * 8 / segment.durationMs!;
    expect(report.fileKbps, closeTo(kbps, 1e-9));
    expect(report.mbPerHour, closeTo(kbps * 1000 / 8 * 3600 / 1e6, 1e-9));
    expect(report.observations, contains(contains('MB per 8 hours')));
  });

  test('P0-10 counts intervals where the open file stopped growing', () async {
    everyMinute = (minute) {
      if (minute <= 3) grow(1000);
    };

    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(minutes: 6),
    );

    expect(report.stalledIntervals, 3);
    expect(report.observations, contains(contains('did not grow in 3')));
  });

  test('P0-10 counts flat-signal samples', () async {
    everyMinute = (minute) => engine.level = minute > 2 ? -160 : -30;

    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(minutes: 4),
    );

    expect(report.flatSamples, 2);
    expect(report.observations, contains(contains('listen for silence')));
  });

  test('P0-10 counts samples taken while not recording', () async {
    everyMinute = (minute) async {
      if (minute == 2) await service.pause();
      if (minute == 4) await service.resume();
    };

    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(minutes: 5),
    );

    expect(report.notRecordingSamples, 2);
    expect(report.samples[2].openFileBytes, isNull);
    expect(report.samples[2].dbfs, isNull);
    expect(report.segments, hasLength(2));
    expect(
      report.events
          .where((e) => e.kind == 'state')
          .map((e) => e.detail['state']),
      containsAllInOrder(['recording', 'paused', 'recording', 'saved']),
    );
  });

  test('P0-10 FR-REC-06 works out battery drain per hour on battery', () async {
    final battery = _ScriptedBattery([
      const BatteryReading(percent: 80, charging: false),
      for (var i = 0; i < 90; i++)
        const BatteryReading(percent: 79, charging: false),
      const BatteryReading(percent: 68, charging: false),
    ]);

    final report = await spike(battery: battery)
        .run(activityId: keynote.id, length: const Duration(minutes: 90));

    expect(report.batteryBefore!.percent, 80);
    expect(report.batteryAfter!.percent, 68);
    expect(report.batteryDrainPercentPerHour, closeTo(8, 1e-9));
    expect(report.observations, contains(contains('8.0% per hour')));
  });

  test(
    'P0-10 gives no drain figure while charging or when unreadable',
    () async {
      final charging = await spike(
        battery: _ScriptedBattery([
          const BatteryReading(percent: 50, charging: true),
        ]),
      ).run(activityId: keynote.id, length: const Duration(minutes: 2));
      expect(charging.batteryDrainPercentPerHour, isNull);
      expect(charging.observations, contains(contains('charging')));

      final unknown = await spike().run(
        activityId: keynote.id,
        length: const Duration(minutes: 2),
      );
      expect(unknown.batteryBefore, isNull);
      expect(unknown.observations, contains(contains('note it by hand')));
    },
  );

  test('P0-10 reports a refused start without sampling', () async {
    engine.startError = StateError('No audio recording device was found.');

    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(minutes: 90),
    );

    expect(report.startOutcome, StartOutcome.failed);
    expect(report.samples, isEmpty);
    expect(report.recordedMs, 0);
    expect(report.fileKbps, isNull);
    expect(report.observations.first, 'Start: failed.');
  });

  test('P0-10 report JSON, CSV and Markdown carry the measurements', () async {
    everyMinute = (_) => grow(1000);

    final report = await spike().run(
      activityId: keynote.id,
      length: const Duration(minutes: 3),
    );

    final json = jsonDecode(report.toPrettyJson()) as Map<String, Object?>;
    expect(json['spike'], 'P0-10');
    expect(json['samples'], hasLength(3));
    expect((json['memory']! as Map)['peak_rss_bytes'], 100 * _mb);
    expect((json['files']! as Map)['recorded_bytes'], report.recordedBytes);

    final csv = report.toCsv().split('\n');
    expect(csv.first, LongRunSample.csvHeader);
    expect(csv, hasLength(4));
    expect(csv[1], startsWith('60,recording,1,100.0,1000,-30.0,,'));

    final md = report.toMarkdown();
    expect(md, contains('P0-10 run'));
    expect(md, contains('| 1 | finalised | user_stop |'));
  });

  test('P0-10 least-squares slope', () {
    expect(leastSquaresSlope([0, 1, 2], [1, 3, 5]), closeTo(2, 1e-12));
    expect(leastSquaresSlope([0, 1], [0, 1]), isNull);
    expect(leastSquaresSlope([1, 1, 1], [0, 1, 2]), isNull);
  });

  group('P0-10 Windows battery mapping', () {
    test('reads percent and mains power', () {
      final r = windowsBatteryReading(
        acLineStatus: 0,
        batteryFlag: 1,
        batteryLifePercent: 72,
      )!;
      expect(r.percent, 72);
      expect(r.charging, isFalse);
      expect(
        windowsBatteryReading(
          acLineStatus: 1,
          batteryFlag: 8,
          batteryLifePercent: 40,
        )!.charging,
        isTrue,
      );
    });

    test('answers null with no battery or an unknown status', () {
      expect(
        windowsBatteryReading(
          acLineStatus: 1,
          batteryFlag: 128,
          batteryLifePercent: 255,
        ),
        isNull,
      );
      expect(
        windowsBatteryReading(
          acLineStatus: 255,
          batteryFlag: 255,
          batteryLifePercent: 255,
        ),
        isNull,
      );
      expect(
        windowsBatteryReading(
          acLineStatus: 0,
          batteryFlag: 2,
          batteryLifePercent: 255,
        ),
        isNull,
      );
    });

    test('the real probe answers without throwing on this PC', () async {
      final reading = await WindowsBatteryProbe().read();
      if (reading != null) {
        expect(reading.percent, inInclusiveRange(0, 100));
      }
    }, skip: !Platform.isWindows);
  });

  test('P0-10 process memory probe reads a positive RSS', () {
    const probe = ProcessMemoryProbe();
    expect(probe.currentRssBytes(), greaterThan(0));
    expect(probe.peakRssBytes(), greaterThanOrEqualTo(probe.currentRssBytes()));
  });
}
