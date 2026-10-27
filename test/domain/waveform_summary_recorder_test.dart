import 'dart:async';
import 'dart:io';

import 'package:attenlume/data/filesystem/media_paths.dart';
import 'package:attenlume/data/filesystem/waveform_summary.dart';
import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/domain/services/waveform_summary_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fake_capture_engine.dart';
import '../fixtures/fixtures.dart';

void main() {
  late TestData t;
  late Directory root;
  late RecordingService recorder;
  late Activity activity;
  late WaveformSummaryRecorder summaries;
  double level = -30;

  setUp(() async {
    t = TestData();
    root = await Directory.systemTemp.createTemp('waveform_recorder_test_');
    final conf = await t.conference();
    activity = await t.activity(conf.id, title: 'Keynote');
    recorder = RecordingService(
      engine: FakeCaptureEngine(),
      activities: t.activities,
      media: t.media,
      mediaRoot: () async => root,
      platform: CapturePlatform.android,
      clock: t.clock.call,
      hashFile: (_) async => 'hash',
    );
    level = -30;
    summaries = WaveformSummaryRecorder(
      recorder: recorder,
      activities: t.activities,
      mediaRoot: () async => root,
      level: () async => level,
      // Samples are driven by calling sample(); the timer never fires.
      createTimer: (d, cb) => Timer(const Duration(days: 365), () {}),
    )..start();
  });

  tearDown(() async {
    await summaries.dispose();
    await recorder.dispose();
    await t.close();
    await root.delete(recursive: true);
  });

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  File summaryOf(String segmentId) => MediaPaths.resolve(
    root,
    MediaPaths.waveform(activity.conferenceId, activity.id, segmentId),
  );

  group('FR-REV-03 summaries written while recording [P1-17]', () {
    test(
      'FR-REV-03 one level per sample, saved when the segment ends',
      () async {
        await recorder.start(activity.id);
        await settle();
        final segmentId = recorder.status.segmentId!;

        for (var i = 0; i < 30; i++) {
          level = i.isEven ? -30 : -90;
          await summaries.sample();
        }
        await recorder.stop();
        await settle();
        await summaries.flushed();

        final slice = await const WaveformSummaryReader().read(
          summaryOf(segmentId),
        );
        expect(slice!.levels, hasLength(30));
        expect(slice.levels.take(2), [128, 0]);
      },
    );

    test(
      'FR-REV-03 each segment gets its own summary, none while paused',
      () async {
        await recorder.start(activity.id);
        await settle();
        final first = recorder.status.segmentId!;
        await summaries.sample();
        await summaries.sample();

        await recorder.pause();
        await settle();
        await summaries.sample(); // Paused: not written anywhere.

        await recorder.resume();
        await settle();
        final second = recorder.status.segmentId!;
        expect(second, isNot(first));
        await summaries.sample();
        await recorder.stop();
        await settle();
        await summaries.flushed();

        const reader = WaveformSummaryReader();
        expect((await reader.read(summaryOf(first)))!.levels, hasLength(2));
        expect((await reader.read(summaryOf(second)))!.levels, hasLength(1));
      },
    );

    test('FR-REV-03 a failing level reading is skipped', () async {
      var fail = true;
      final flaky = WaveformSummaryRecorder(
        recorder: recorder,
        activities: t.activities,
        mediaRoot: () async => root,
        level: () async => fail ? throw StateError('no level') : -30,
        createTimer: (d, cb) => Timer(const Duration(days: 365), () {}),
      );
      await summaries.dispose();
      flaky.start();
      addTearDown(flaky.dispose);

      await recorder.start(activity.id);
      await settle();
      final segmentId = recorder.status.segmentId!;
      await flaky.sample();
      fail = false;
      await flaky.sample();
      await recorder.stop();
      await settle();
      await flaky.flushed();

      final slice = await const WaveformSummaryReader().read(
        summaryOf(segmentId),
      );
      expect(slice!.levels, [128]);
    });
  });
}
