import 'dart:async';
import 'dart:io';

import 'package:attenlume/data/filesystem/media_paths.dart';
import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/conference.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fake_capture_engine.dart';
import '../fixtures/fixtures.dart';

void main() {
  late TestData t;
  late Directory root;
  late FakeCaptureEngine engine;
  late RecordingService service;
  late Conference conference;
  late Activity keynote;

  RecordingService build({
    CapturePlatform platform = CapturePlatform.android,
  }) => RecordingService(
    engine: engine,
    activities: t.activities,
    media: t.media,
    mediaRoot: () async => root,
    platform: platform,
    clock: t.clock.call,
  );

  setUp(() async {
    t = TestData();
    root = await Directory.systemTemp.createTemp('attenlume_rec_');
    engine = FakeCaptureEngine();
    service = build();
    conference = await t.conference();
    keynote = await t.activity(conference.id, title: 'Data Mesh Keynote');
  });

  tearDown(() async {
    await service.dispose();
    await t.close();
    await root.delete(recursive: true);
  });

  group('FR-REC-01 one-tap start, metadata before audio', () {
    test('FR-REC-01 start writes the segment row before the encoder '
        'starts', () async {
      List<String>? statesSeenByEngine;
      var fileExistedAtStart = true;
      engine.onStart = (path) async {
        fileExistedAtStart = File(path).existsSync();
        statesSeenByEngine = [
          for (final s in await t.media.segmentsFor(keynote.id)) s.state.key,
        ];
      };

      expect(await service.start(keynote.id), StartOutcome.started);

      expect(statesSeenByEngine, ['writing']);
      expect(fileExistedAtStart, isFalse);
    });

    test('FR-REC-01 one call leaves the activity recording', () async {
      final seen = <RecordingState>[];
      final sub = service.statusStream.listen((s) => seen.add(s.state));

      await service.start(keynote.id);
      await Future<void>.delayed(Duration.zero);

      expect(seen, [RecordingState.starting, RecordingState.recording]);
      expect(service.status.state, RecordingState.recording);
      expect(service.status.activityId, keynote.id);
      expect(service.status.segmentSequence, 1);
      final activity = (await t.activities.get(keynote.id))!;
      expect(activity.status, ActivityStatus.active);
      expect(activity.actualStart, t.clock.now);
      await sub.cancel();
    });

    test('FR-REC-01 segment requests the effective profile for the '
        'platform', () async {
      await t.activities.update(
        keynote.id,
        const ActivitiesCompanion(
          recordingProfileOverride: Value(RecordingProfile.economy),
        ),
      );
      await service.dispose();
      engine = FakeCaptureEngine();
      service = build(platform: CapturePlatform.windows);

      await service.start(keynote.id);

      final seg = (await t.media.segmentsFor(keynote.id)).single;
      expect(seg.requestedProfile, RecordingProfile.economy);
      expect(seg.requestedBitrateBps, windowsAacMinimumBitrateBps);
      expect(engine.requests.single.bitrateBps, windowsAacMinimumBitrateBps);
      expect(service.status.profile, RecordingProfile.economy);
    });

    test('FR-REC-01 refuses an activity marked not recording audio', () async {
      await t.activities.update(
        keynote.id,
        const ActivitiesCompanion(
          recordingPermissionStatus: Value(
            RecordingPermissionStatus.notPermitted,
          ),
        ),
      );

      expect(
        await service.start(keynote.id),
        StartOutcome.recordingNotPermitted,
      );
      expect(await t.media.segmentsFor(keynote.id), isEmpty);
      expect(engine.startedPaths, isEmpty);
      expect(service.status.state, RecordingState.idle);
    });

    test(
      'FR-REC-01 without microphone permission nothing is written',
      () async {
        engine.permission = false;

        expect(await service.start(keynote.id), StartOutcome.microphoneDenied);
        expect(await t.media.segmentsFor(keynote.id), isEmpty);
        expect(service.status.state, RecordingState.idle);
      },
    );

    test('FR-REC-01 unknown activity', () async {
      expect(
        await service.start('aaaaaaaa-0000-4000-8000-ffffffffffff'),
        StartOutcome.activityNotFound,
      );
    });
  });

  group('FR-REC-02 record straight to disk', () {
    test('FR-REC-02 encoder writes to a file under the media root and the '
        'row stores the relative path', () async {
      await service.start(keynote.id);

      final seg = (await t.media.segmentsFor(keynote.id)).single;
      expect(
        seg.filePath,
        'conferences/${conference.id}/activities/${keynote.id}/'
        'audio/segment-001.m4a',
      );
      expect(
        engine.startedPaths.single,
        MediaPaths.resolve(root, seg.filePath).path,
      );
    });

    test('FR-REC-02 stop records what the file really holds', () async {
      await service.start(keynote.id);
      t.clock.advance(const Duration(seconds: 3));

      expect(await service.stop(), keynote.id);

      final seg = (await t.media.segmentsFor(keynote.id)).single;
      final file = MediaPaths.resolve(root, seg.filePath);
      final bytes = file.lengthSync();
      expect(seg.state, SegmentState.finalised);
      expect(seg.endReason, SegmentEndReason.userStop);
      expect(seg.durationMs, 3000);
      expect(seg.bytes, bytes);
      expect(seg.observedBitrateBps, (bytes * 8 * 1000 / 3000).round());
      expect(seg.sha256, sha256.convert(file.readAsBytesSync()).toString());
      expect(seg.codec, 'aac_lc');
      expect(seg.channelCount, 1);
      expect(seg.endUtc, t.clock.now);

      final activity = (await t.activities.get(keynote.id))!;
      expect(activity.status, ActivityStatus.completed);
      expect(activity.actualEnd, t.clock.now);
      expect(service.status.state, RecordingState.saved);
      expect(service.status.activityId, keynote.id);
    });

    test('FR-REC-02 a file cut off without moov is kept and marked '
        'damaged, never good', () async {
      engine.finaliseValidFile = false;
      await service.start(keynote.id);
      await service.stop();

      final seg = (await t.media.segmentsFor(keynote.id)).single;
      expect(seg.state, SegmentState.damaged);
      expect(seg.sha256, isNull);
      expect(MediaPaths.resolve(root, seg.filePath).existsSync(), isTrue);
      expect(seg.bytes, MediaPaths.resolve(root, seg.filePath).lengthSync());
    });

    test('FR-REC-02 an existing file is never overwritten', () async {
      final taken = MediaPaths.resolve(
        root,
        MediaPaths.segment(conference.id, keynote.id, 1),
      );
      await taken.parent.create(recursive: true);
      await taken.writeAsString('older audio');

      await service.start(keynote.id);
      await service.stop();

      expect(taken.readAsStringSync(), 'older audio');
      final seg = (await t.media.segmentsFor(keynote.id)).single;
      expect(seg.filePath, endsWith('audio/segment-001-2.m4a'));
    });

    test('FR-REC-02 start failure keeps a damaged row and allows retry or '
        'save', () async {
      engine.startError = StateError('mic busy');

      expect(await service.start(keynote.id), StartOutcome.failed);
      expect(service.status.state, RecordingState.errorRecoverable);
      expect(service.status.errorMessage, contains('mic busy'));
      final failed = (await t.media.segmentsFor(keynote.id)).single;
      expect(failed.state, SegmentState.damaged);
      expect(failed.endReason, SegmentEndReason.error);

      engine.startError = null;
      expect(await service.start(keynote.id), StartOutcome.started);
      expect(service.status.segmentSequence, 2);
      await service.stop();
      expect(service.status.state, RecordingState.saved);
    });
  });

  group('FR-REC-09 idempotent, mutex-protected commands', () {
    test('FR-REC-09 rapid start taps create one recording', () async {
      engine.startGate = Completer<void>();
      final taps = [for (var i = 0; i < 5; i++) service.start(keynote.id)];
      await Future<void>.delayed(const Duration(milliseconds: 10));
      engine.startGate!.complete();

      final outcomes = await Future.wait(taps);

      expect(outcomes.first, StartOutcome.started);
      expect(outcomes.skip(1), everyElement(StartOutcome.alreadyRecording));
      expect(engine.startedPaths, hasLength(1));
      expect(await t.media.segmentsFor(keynote.id), hasLength(1));
    });

    test('FR-REC-09 rapid stop taps save once', () async {
      await service.start(keynote.id);

      final results = await Future.wait([
        for (var i = 0; i < 4; i++) service.stop(),
      ]);

      expect(results, [keynote.id, null, null, null]);
      expect(engine.stopCalls, 1);
      expect(service.status.state, RecordingState.saved);
    });

    test('FR-REC-09 start then stop tapped together run in order', () async {
      engine.startGate = Completer<void>();
      final started = service.start(keynote.id);
      final stopped = service.stop();
      engine.startGate!.complete();

      expect(await started, StartOutcome.started);
      expect(await stopped, keynote.id);
      expect(engine.isCapturing, isFalse);
      final seg = (await t.media.segmentsFor(keynote.id)).single;
      expect(seg.state, SegmentState.finalised);
    });

    test('FR-REC-09 stop with nothing recording does nothing', () async {
      expect(await service.stop(), isNull);
      expect(engine.stopCalls, 0);
      expect(service.status.state, RecordingState.idle);
    });

    test('FR-REC-09 a second activity never starts a second recording '
        '(NFR-04)', () async {
      final other = await t.activity(conference.id, title: 'Panel');
      await service.start(keynote.id);

      expect(await service.start(other.id), StartOutcome.conflict);
      expect(engine.startedPaths, hasLength(1));
      expect(await t.media.segmentsFor(other.id), isEmpty);
      expect(service.status.activityId, keynote.id);

      await service.stop();
      expect(await service.start(other.id), StartOutcome.started);
    });

    test('FR-REC-09 pause and resume are idempotent and roll the '
        'segment (FR-REC-03)', () async {
      await service.start(keynote.id);
      t.clock.advance(const Duration(minutes: 5));

      expect(await Future.wait([service.pause(), service.pause()]), [
        true,
        false,
      ]);
      expect(service.status.state, RecordingState.paused);
      expect(engine.isCapturing, isFalse);

      t.clock.advance(const Duration(minutes: 2));
      expect(await Future.wait([service.resume(), service.resume()]), [
        true,
        false,
      ]);
      expect(service.status.state, RecordingState.recording);
      expect(service.status.segmentSequence, 2);

      await service.stop();
      final segs = await t.media.segmentsFor(keynote.id);
      expect(segs.map((s) => s.endReason), [
        SegmentEndReason.pause,
        SegmentEndReason.userStop,
      ]);
      expect(segs.last.filePath, endsWith('segment-002.m4a'));
      expect(segs.every((s) => s.state == SegmentState.finalised), isTrue);
    });

    test('FR-REC-09 stop while paused saves without touching the '
        'encoder again', () async {
      await service.start(keynote.id);
      await service.pause();

      expect(await service.stop(), keynote.id);
      expect(engine.stopCalls, 1);
      expect(service.status.state, RecordingState.saved);
    });

    test('FR-REC-09 pause or resume with nothing held returns false', () async {
      expect(await service.pause(), isFalse);
      expect(await service.resume(), isFalse);
    });

    test('FR-REC-09 dispose saves an open recording and releases the '
        'microphone', () async {
      await service.start(keynote.id);

      await service.dispose();

      expect(engine.isCapturing, isFalse);
      expect(engine.disposed, isTrue);
      final seg = (await t.media.segmentsFor(keynote.id)).single;
      expect(seg.state, SegmentState.finalised);
    });
  });
}
