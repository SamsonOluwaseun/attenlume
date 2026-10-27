import 'dart:async';
import 'dart:io';

import 'package:attenlume/data/filesystem/media_paths.dart';
import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/conference.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:attenlume/domain/services/storage_budget_service.dart';
import 'package:attenlume/domain/services/storage_thresholds.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fixtures/fake_capture_engine.dart';
import '../fixtures/fake_free_space_probe.dart';
import '../fixtures/fixtures.dart';

void main() {
  late TestData t;
  late Directory root;
  late FakeCaptureEngine engine;
  late RecordingService recorder;
  late Conference conference;
  late Activity activity;
  late FakeFreeSpaceProbe probe;

  setUp(() async {
    t = TestData();
    root = await Directory.systemTemp.createTemp('storage_budget_test_');
    engine = FakeCaptureEngine();
    conference = await t.conference();
    activity = await t.activity(conference.id, title: 'Architecture Session');
    probe = FakeFreeSpaceProbe(10 * 1024 * 1024 * 1024); // 10 GB free
    recorder = RecordingService(
      engine: engine,
      activities: t.activities,
      media: t.media,
      mediaRoot: () async => root,
      platform: CapturePlatform.android,
      freeSpaceProbe: probe,
      clock: t.clock.call,
      hashFile: (_) async => 'hash',
    );
  });

  tearDown(() async {
    await recorder.dispose();
    await t.close();
    await root.delete(recursive: true);
  });

  StorageBudgetService buildService({
    FakeFreeSpaceProbe? customProbe,
    Duration tickInterval = const Duration(seconds: 30),
    Timer Function(Duration, void Function(Timer))? createTimer,
  }) {
    return StorageBudgetService(
      recorder: recorder,
      activities: t.activities,
      media: t.media,
      mediaRoot: () async => root,
      freeSpaceProbe: customProbe ?? probe,
      platform: CapturePlatform.android,
      tickInterval: tickInterval,
      createTimer: createTimer,
      clock: t.clock.call,
    );
  }

  group('FR-STO-01 file growth measurement [P1-12]', () {
    test('FR-STO-01 uses nominal profile bitrate when no audio has been written yet', () async {
      final service = buildService();
      final snapshot = await service.checkNow(
        activityId: activity.id,
        profile: RecordingProfile.balanced,
      );

      expect(snapshot.isMeasuredRate, isFalse);
      expect(snapshot.bytesPerSecond, isNotNull);
      // Balanced profile on Android is 48 kbps -> 6000 bytes/s
      final nominalBps =
          effectiveCaptureSettings(
            RecordingProfile.balanced,
            CapturePlatform.android,
          ).bitrateBps /
          8.0;
      expect(snapshot.bytesPerSecond, closeTo(nominalBps, 1.0));
      expect(snapshot.level, StorageLevel.ok);
      expect(snapshot.minutesLeft, greaterThan(1000));

      await service.dispose();
    });

    test(
      'FR-STO-01 measures write rate from active segment file growth',
      () async {
        final service = buildService();
        await recorder.start(activity.id);

        // Advance clock by 10 seconds and write 80,000 bytes to the open file
        t.clock.advance(const Duration(seconds: 10));
        final openFile = recorder.currentSegmentFile!;
        openFile.writeAsBytesSync(List.filled(80000, 0));

        final snapshot = await service.checkNow();
        expect(snapshot.isMeasuredRate, isTrue);
        // 80,000 bytes over 10 seconds = 8,000 bytes/s
        expect(snapshot.bytesPerSecond, closeTo(8000.0, 50.0));

        await recorder.stop();
        await service.dispose();
      },
    );

    test('FR-STO-01 measures write rate from prior completed segments if active segment is under 5s', () async {
      engine.durationSeconds = 10;
      engine.deliveredBitrateBps = (_) => 80000;
      final service = buildService();

      // Start, then pause to complete segment 1 with 10s audio at 80kbps (10,000 bytes/s)
      await recorder.start(activity.id);
      await recorder.pause();

      // Resume into segment 2 (0 seconds elapsed so far)
      await recorder.resume();

      final snapshot = await service.checkNow();
      expect(snapshot.isMeasuredRate, isTrue);
      // Segment 1 was delivered at 80,000 bps = 10,000 bytes/s
      expect(snapshot.bytesPerSecond, closeTo(10000.0, 50.0));

      await recorder.stop();
      await service.dispose();
    });
  });

  group('FR-STO-02 default thresholds and staged warnings [P1-12]', () {
    test('FR-STO-02 classifies > 1 GB free space and > 60 min as ok', () async {
      probe.availableBytes = 2 * 1024 * 1024 * 1024; // 2 GB
      final service = buildService();

      final snapshot = await service.checkNow(activityId: activity.id);
      expect(snapshot.level, StorageLevel.ok);
      expect(snapshot.isWarning, isFalse);
      expect(snapshot.isUrgent, isFalse);
      expect(snapshot.isHardStop, isFalse);

      await service.dispose();
    });

    test('FR-STO-02 classifies < 1 GB free space as warning (low)', () async {
      probe.availableBytes = 800 * 1024 * 1024; // 800 MB
      final service = buildService();

      final snapshot = await service.checkNow(activityId: activity.id);
      expect(snapshot.level, StorageLevel.warning);
      expect(snapshot.isWarning, isTrue);
      expect(snapshot.isUrgent, isFalse);

      await service.dispose();
    });

    test(
      'FR-STO-02 classifies <= 300 MB free space as urgent (critical)',
      () async {
        probe.availableBytes = 250 * 1024 * 1024; // 250 MB
        final service = buildService();

        final snapshot = await service.checkNow(activityId: activity.id);
        expect(snapshot.level, StorageLevel.urgent);
        expect(snapshot.isUrgent, isTrue);

        await service.dispose();
      },
    );

    test('FR-STO-02 classifies <= 100 MB free space as hardStop', () async {
      probe.availableBytes =
          90 * 1024 * 1024; // 90 MB (hardStopBytes default 100 MB)
      final service = buildService();

      final snapshot = await service.checkNow(activityId: activity.id);
      expect(snapshot.level, StorageLevel.hardStop);
      expect(snapshot.isHardStop, isTrue);
      expect(snapshot.minutesLeft, 0);

      await service.dispose();
    });
  });

  group('FR-STO-03 periodic ticks and recheck triggers [P1-12]', () {
    test('FR-STO-03 starts 30-second periodic timer on recording and stops on pause', () async {
      var timerStarted = false;
      void Function(Timer)? tickCallback;

      Timer customTimer(Duration interval, void Function(Timer) callback) {
        timerStarted = true;
        tickCallback = callback;
        return Timer(interval, () {});
      }

      final service = buildService(createTimer: customTimer);
      service.start();

      expect(timerStarted, isFalse);

      // Start recording
      await recorder.start(activity.id);
      expect(timerStarted, isTrue);
      expect(tickCallback, isNotNull);

      // Pause recording
      await recorder.pause();
      expect(recorder.status.state, RecordingState.paused);

      await recorder.stop();
      await service.dispose();
    });

    test(
      'FR-STO-03 onOsLowSpaceSignal rechecks free space immediately',
      () async {
        final service = buildService();
        probe.availableBytes = 5 * 1024 * 1024 * 1024;
        await service.checkNow(activityId: activity.id);
        expect(service.currentSnapshot.level, StorageLevel.ok);

        // OS sends low space signal
        probe.availableBytes = 200 * 1024 * 1024; // 200 MB
        await service.onOsLowSpaceSignal();
        expect(service.currentSnapshot.level, StorageLevel.urgent);

        await service.dispose();
      },
    );
  });

  group('FR-STO-04 hard limit stop and notification [P1-12]', () {
    test('FR-STO-04 stops recording with reason storage_low when hard stop is reached', () async {
      final service = buildService();
      service.start();

      final notices = <String>[];
      final sub = service.hardStopNoticeStream.listen(notices.add);

      await recorder.start(activity.id);
      expect(recorder.status.state, RecordingState.recording);

      // Disk fills up to 90 MB (below 100 MB hard reserve)
      probe.availableBytes = 90 * 1024 * 1024;

      await service.checkNow();

      // Recording must be finalised and stopped safely
      expect(recorder.status.state, RecordingState.saved);
      expect(notices, hasLength(1));
      expect(
        notices.single,
        contains('Storage nearly full. Recording stopped and saved.'),
      );

      final segments = await t.media.segmentsFor(activity.id);
      expect(segments, hasLength(1));
      expect(segments.single.endReason, SegmentEndReason.storageLow);

      await sub.cancel();
      await service.dispose();
    });
  });

  group('FR-UI-07 conference disk usage calculation [P1-12]', () {
    test(
      'FR-UI-07 calculates space used by this conference from disk',
      () async {
        final service = buildService();

        // Create dummy file inside conference folder
        final confDir = Directory(
          p.join(root.path, MediaPaths.conferenceFolder(conference.id)),
        );
        await confDir.create(recursive: true);
        final dummyFile = File(p.join(confDir.path, 'sample.bin'));
        dummyFile.writeAsBytesSync(List.filled(45000, 0));

        final snapshot = await service.checkNow(activityId: activity.id);
        expect(snapshot.conferenceBytes, 45000);

        await service.dispose();
      },
    );
  });
}
