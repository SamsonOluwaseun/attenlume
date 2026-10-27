import 'dart:io';

import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/conference.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fake_capture_engine.dart';
import '../fixtures/fake_free_space_probe.dart';
import '../fixtures/fixtures.dart';

void main() {
  late TestData t;
  late Directory root;
  late FakeCaptureEngine engine;
  late Conference conference;
  late Activity keynote;

  setUp(() async {
    t = TestData();
    root = await Directory.systemTemp.createTemp('rec_storage_test_');
    engine = FakeCaptureEngine();
    conference = await t.conference();
    keynote = await t.activity(conference.id, title: 'Keynote');
  });

  tearDown(() async {
    await t.close();
    await root.delete(recursive: true);
  });

  group('FR-STO-04 & FR-STO-01 RecordingService storage checks [P1-12]', () {
    test('FR-STO-04 preflight refuses to start recording if space is below hard reserve', () async {
      // 50 MB free, while hard reserve is 100 MB default.
      final probe = FakeFreeSpaceProbe(50 * 1024 * 1024);
      final service = RecordingService(
        engine: engine,
        activities: t.activities,
        media: t.media,
        mediaRoot: () async => root,
        platform: CapturePlatform.android,
        freeSpaceProbe: probe,
        clock: t.clock.call,
      );

      final outcome = await service.start(keynote.id);
      expect(outcome, StartOutcome.storageFull);
      expect(service.status.state, RecordingState.idle);

      await service.dispose();
    });

    test(
      'FR-STO-04 preflight starts normally if space is above hard reserve',
      () async {
        final probe = FakeFreeSpaceProbe(500 * 1024 * 1024);
        final service = RecordingService(
          engine: engine,
          activities: t.activities,
          media: t.media,
          mediaRoot: () async => root,
          platform: CapturePlatform.android,
          freeSpaceProbe: probe,
          clock: t.clock.call,
        );

        final outcome = await service.start(keynote.id);
        expect(outcome, StartOutcome.started);
        expect(service.status.state, RecordingState.recording);

        await service.dispose();
      },
    );

    test(
      'FR-STO-04 stop with reason storageLow records storage_low on segment',
      () async {
        final service = RecordingService(
          engine: engine,
          activities: t.activities,
          media: t.media,
          mediaRoot: () async => root,
          platform: CapturePlatform.android,
          clock: t.clock.call,
        );

        expect(await service.start(keynote.id), StartOutcome.started);
        expect(service.status.state, RecordingState.recording);

        final stoppedId = await service.stop(
          reason: SegmentEndReason.storageLow,
        );
        expect(stoppedId, keynote.id);
        expect(service.status.state, RecordingState.saved);

        final segments = await t.media.segmentsFor(keynote.id);
        expect(segments, hasLength(1));
        expect(segments.single.endReason, SegmentEndReason.storageLow);

        await service.dispose();
      },
    );

    test(
      'FR-STO-01 exposes currentSegmentFile and startUtc while recording',
      () async {
        final service = RecordingService(
          engine: engine,
          activities: t.activities,
          media: t.media,
          mediaRoot: () async => root,
          platform: CapturePlatform.android,
          clock: t.clock.call,
        );

        expect(service.currentSegmentFile, isNull);
        expect(service.currentSegmentStartUtc, isNull);

        await service.start(keynote.id);
        expect(service.currentSegmentFile, isNotNull);
        expect(service.currentSegmentStartUtc, isNotNull);

        await service.stop();
        expect(service.currentSegmentFile, isNull);
        expect(service.currentSegmentStartUtc, isNull);

        await service.dispose();
      },
    );
  });
}
