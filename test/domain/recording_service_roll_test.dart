import 'dart:io';

import 'package:attenlume/data/filesystem/media_paths.dart';
import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fake_capture_engine.dart';
import '../fixtures/fake_route_probe.dart';
import '../fixtures/fake_timers.dart';
import '../fixtures/fixtures.dart';

void main() {
  late TestData t;
  late Directory root;
  late FakeCaptureEngine engine;
  late FakeRouteProbe routes;
  late FakeTimers timers;
  late RecordingService service;
  late Activity keynote;

  RecordingService build({
    Duration segmentMaxDuration = defaultSegmentMaxDuration,
    Future<File> Function(File partial, File target)? commit,
  }) => RecordingService(
    engine: engine,
    activities: t.activities,
    media: t.media,
    mediaRoot: () async => root,
    platform: CapturePlatform.android,
    routes: routes,
    clock: t.clock.call,
    hashFile: (_) async => 'hash',
    rollTimer: timers.call,
    segmentMaxDuration: segmentMaxDuration,
    commitFile: commit ?? (p, target) => p.rename(target.path),
  );

  setUp(() async {
    t = TestData();
    root = await Directory.systemTemp.createTemp('attenlume_roll_');
    engine = FakeCaptureEngine();
    routes = FakeRouteProbe()..active = builtInMic;
    timers = FakeTimers();
    service = build();
    final conference = await t.conference();
    keynote = await t.activity(conference.id, title: 'Data Mesh Keynote');
  });

  tearDown(() async {
    await service.dispose();
    await t.close();
    await root.delete(recursive: true);
  });

  /// Fires the newest roll timer after [minutes] and waits until the roll
  /// has settled.
  Future<void> rollAfter(int minutes) async {
    t.clock.advance(Duration(minutes: minutes));
    final settled = service.statusStream.firstWhere(
      (s) =>
          s.state == RecordingState.recording ||
          s.state == RecordingState.errorRecoverable,
    );
    timers.created.last.fire();
    await settled;
  }

  File fileOf(String relative) => MediaPaths.resolve(root, relative);

  List<String> audioFiles() =>
      fileOf(MediaPaths.segment(keynote.conferenceId, keynote.id, 1)).parent
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .toList()
        ..sort();

  group('FR-REC-03 rolling segments every 10 minutes', () {
    test('FR-REC-03 a started segment arms a 10-minute roll', () async {
      await service.start(keynote.id);

      expect(timers.created.single.duration, const Duration(minutes: 10));
      expect(timers.created.single.isActive, isTrue);
    });

    test('FR-REC-03 the roll ends the segment with reason roll and starts '
        'the next with the same profile and input', () async {
      await service.start(keynote.id);
      final seen = <RecordingState>[];
      final sub = service.statusStream.listen((s) => seen.add(s.state));

      await rollAfter(10);
      await sub.cancel();

      final segs = await t.media.segmentsFor(keynote.id);
      expect(segs, hasLength(2));
      expect(segs.first.endReason, SegmentEndReason.roll);
      expect(segs.first.state, SegmentState.finalised);
      expect(segs.first.endUtc, t.clock.now);
      expect(segs.last.state, SegmentState.writing);
      expect(segs.last.startUtc, t.clock.now);
      expect(segs.last.requestedProfile, segs.first.requestedProfile);
      expect(segs.last.inputRoute, segs.first.inputRoute);
      expect(seen, [RecordingState.switchingSegment, RecordingState.recording]);
      expect(service.status.segmentSequence, 2);
      expect(timers.active, hasLength(1));
    });

    test('FR-REC-03 35 minutes give four segments on one timeline with no '
        'gaps', () async {
      await service.start(keynote.id);
      await rollAfter(10);
      await rollAfter(10);
      await rollAfter(10);
      t.clock.advance(const Duration(minutes: 5));
      await service.stop();

      final segs = await t.media.segmentsFor(keynote.id);
      expect(segs.map((s) => s.sequence), [1, 2, 3, 4]);
      expect(segs.map((s) => s.endReason), [
        SegmentEndReason.roll,
        SegmentEndReason.roll,
        SegmentEndReason.roll,
        SegmentEndReason.userStop,
      ]);
      for (var i = 1; i < segs.length; i++) {
        expect(segs[i].startUtc, segs[i - 1].endUtc);
      }
      expect(segs.every((s) => s.state == SegmentState.finalised), isTrue);
      expect(timers.active, isEmpty);
    });

    test('FR-REC-03 the roll interval can be set', () async {
      await service.dispose();
      service = build(segmentMaxDuration: const Duration(minutes: 5));

      await service.start(keynote.id);

      expect(timers.created.single.duration, const Duration(minutes: 5));
    });

    test('FR-REC-03 pause, stop and dispose cancel the roll', () async {
      await service.start(keynote.id);
      await service.pause();
      expect(timers.active, isEmpty);

      await service.resume();
      expect(timers.active, hasLength(1));
      await service.stop();
      expect(timers.active, isEmpty);

      await service.start(keynote.id);
      await service.dispose();
      expect(timers.active, isEmpty);
    });

    test('FR-REC-03 a quality or route change restarts the 10 '
        'minutes', () async {
      await service.start(keynote.id);
      final first = timers.created.last;

      await service.changeProfile(RecordingProfile.enhanced);
      expect(first.isActive, isFalse);
      final second = timers.created.last;
      expect(second.isActive, isTrue);

      routes.active = headset;
      await service.routeChanged();
      expect(second.isActive, isFalse);
      expect(timers.active, hasLength(1));
    });

    test('FR-REC-03 a late timer for an ended segment does nothing', () async {
      await service.start(keynote.id);
      final stale = timers.created.last;
      await service.changeProfile(RecordingProfile.economy);

      stale.fireLate();
      await service.stop();

      final segs = await t.media.segmentsFor(keynote.id);
      expect(segs.map((s) => s.endReason), [
        SegmentEndReason.qualityChange,
        SegmentEndReason.userStop,
      ]);
    });

    test('FR-REC-03 a late timer while paused does nothing', () async {
      await service.start(keynote.id);
      final stale = timers.created.last;
      await service.pause();

      stale.fireLate();
      await service.stop();

      expect(await t.media.segmentsFor(keynote.id), hasLength(1));
    });

    test('FR-REC-03 if the next segment cannot start, earlier audio is '
        'kept and the recorder waits for the user', () async {
      await service.start(keynote.id);
      engine.startError = StateError('mic taken');

      await rollAfter(10);

      final segs = await t.media.segmentsFor(keynote.id);
      expect(segs.first.state, SegmentState.finalised);
      expect(fileOf(segs.first.filePath).existsSync(), isTrue);
      expect(segs.last.state, SegmentState.damaged);
      expect(service.status.state, RecordingState.errorRecoverable);
      expect(service.status.errorMessage, contains('mic taken'));
      expect(timers.active, isEmpty);

      expect(await service.stop(), keynote.id);
    });
  });

  group('FR-REC-03 atomic finalisation', () {
    test('FR-REC-03 the encoder writes a partial file and the row points '
        'at it', () async {
      await service.start(keynote.id);

      final seg = (await t.media.segmentsFor(keynote.id)).single;
      expect(seg.filePath, endsWith('audio/segment-001.partial.m4a'));
      expect(engine.startedPaths.single, fileOf(seg.filePath).path);
      expect(fileOf(seg.filePath).existsSync(), isTrue);
      expect(audioFiles(), ['segment-001.partial.m4a']);
    });

    test('FR-REC-03 a finalised segment has its final name and no partial '
        'file is left', () async {
      await service.start(keynote.id);
      await rollAfter(10);
      await service.stop();

      final segs = await t.media.segmentsFor(keynote.id);
      expect(segs.map((s) => s.filePath.split('/').last), [
        'segment-001.m4a',
        'segment-002.m4a',
      ]);
      expect(audioFiles(), ['segment-001.m4a', 'segment-002.m4a']);
      for (final s in segs) {
        expect(s.bytes, fileOf(s.filePath).lengthSync());
      }
    });

    test('FR-REC-03 the file is inspected and hashed before it is renamed, '
        'and the row is updated after', () async {
      final order = <String>[];
      await service.dispose();
      service = RecordingService(
        engine: engine,
        activities: t.activities,
        media: t.media,
        mediaRoot: () async => root,
        platform: CapturePlatform.android,
        clock: t.clock.call,
        rollTimer: timers.call,
        hashFile: (f) async {
          order.add('hash ${f.path.split(Platform.pathSeparator).last}');
          return 'hash';
        },
        commitFile: (partial, target) async {
          final rows = await t.media.segmentsFor(keynote.id);
          order.add('commit, row ${rows.single.state.key}');
          return partial.rename(target.path);
        },
      );

      await service.start(keynote.id);
      await service.stop();

      expect(order, ['hash segment-001.partial.m4a', 'commit, row writing']);
      final seg = (await t.media.segmentsFor(keynote.id)).single;
      expect(seg.state, SegmentState.finalised);
      expect(seg.filePath, endsWith('segment-001.m4a'));
    });

    test('FR-REC-03 if the rename fails the good file keeps its partial '
        'name and the row still finds it', () async {
      await service.dispose();
      service = build(
        commit: (_, target) =>
            throw FileSystemException('disk said no', target.path),
      );

      await service.start(keynote.id);
      await service.stop();

      final seg = (await t.media.segmentsFor(keynote.id)).single;
      expect(seg.state, SegmentState.finalised);
      expect(seg.filePath, endsWith('segment-001.partial.m4a'));
      expect(fileOf(seg.filePath).existsSync(), isTrue);
      expect(service.status.state, RecordingState.saved);
    });

    test('FR-REC-03 a damaged file keeps its partial name, never a final '
        'one', () async {
      engine.finaliseValidFile = false;
      await service.start(keynote.id);
      await service.stop();

      final seg = (await t.media.segmentsFor(keynote.id)).single;
      expect(seg.state, SegmentState.damaged);
      expect(seg.filePath, endsWith('segment-001.partial.m4a'));
      expect(audioFiles(), ['segment-001.partial.m4a']);
    });

    test('FR-REC-03 a leftover partial file is never overwritten', () async {
      final leftover = fileOf(
        MediaPaths.partial(
          MediaPaths.segment(keynote.conferenceId, keynote.id, 1),
        ),
      );
      await leftover.parent.create(recursive: true);
      await leftover.writeAsString('audio from a crash');

      await service.start(keynote.id);
      await service.stop();

      expect(leftover.readAsStringSync(), 'audio from a crash');
      final seg = (await t.media.segmentsFor(keynote.id)).single;
      expect(seg.filePath, endsWith('segment-001-2.m4a'));
    });
  });
}
