import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:attenlume/data/filesystem/media_paths.dart';
import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/models/media.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:attenlume/platform/camera/photo_camera.dart';
import 'package:attenlume/platform/interruptions/audio_interruption_source.dart';
import 'package:attenlume/spikes/photo_during_recording_spike.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fixtures/fake_capture_engine.dart';
import '../fixtures/fake_photo_camera.dart';
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

const _began = AudioInterruption(AudioInterruptionKind.began);

void main() {
  late TestData t;
  late Directory root;
  late FakeCaptureEngine engine;
  late FakePhotoCamera camera;
  late RecordingService service;
  late _FakeInterruptions interruptions;
  late Activity talk;

  /// Called after each wait has moved the clock, with the wait's number
  /// (1-based) and length.
  late void Function(int n, Duration d) onWait;

  PhotoDuringRecordingSpike spike() {
    late PhotoDuringRecordingSpike spike;
    var waits = 0;
    return spike = PhotoDuringRecordingSpike(
      service: service,
      engine: engine,
      media: t.media,
      camera: camera,
      interruptions: interruptions,
      mediaRoot: root,
      newId: t.ids.call,
      clock: t.clock.call,
      wait: (d) async {
        t.clock.advance(d);
        onWait(++waits, d);
        await Future<void>.delayed(Duration.zero);
        await spike.settle();
      },
    );
  }

  Future<PhotoDuringRecordingReport> run({int photos = 3}) => spike().run(
    conferenceId: talk.conferenceId,
    activityId: talk.id,
    photoCount: photos,
  );

  setUp(() async {
    t = TestData();
    root = await Directory.systemTemp.createTemp('attenlume_p0_05_');
    engine = FakeCaptureEngine();
    camera = FakePhotoCamera();
    service = RecordingService(
      engine: engine,
      activities: t.activities,
      media: t.media,
      mediaRoot: () async => root,
      platform: CapturePlatform.ios,
      clock: t.clock.call,
      hashFile: (_) async => 'hash',
    );
    interruptions = _FakeInterruptions();
    onWait = (_, _) {};
    final conference = await t.conference();
    talk = await t.activity(conference.id, title: 'Slides keynote');
  });

  tearDown(() async {
    await service.dispose();
    await interruptions.close();
    await t.close();
    await root.delete(recursive: true);
  });

  test('P0-05 AT-PHO-01 photos with no audio event keep one segment and '
      'land on the timeline', () async {
    camera.onShot = (_) async =>
        t.clock.advance(const Duration(milliseconds: 400));

    final report = await run();

    expect(report.startOutcome, StartOutcome.started);
    expect(report.savedPhotos, 3);
    expect(report.segments, hasLength(1));
    expect(report.gaps, isEmpty);
    expect(report.interruptions, isEmpty);
    expect(report.shots.every((s) => s.recordingAfter), isTrue);
    expect(report.shots.any((s) => s.cutSegment), isFalse);
    expect(report.shots.map((s) => s.durationMs), everyElement(400));
    expect(report.meetsAtPho01Rows, isTrue);
    expect(camera.closed, isTrue);
    expect(interruptions.active, isFalse, reason: 'deactivated at the end');
  });

  test('P0-05 FR-PHO-01 photos are stored under photos/<photo_id>.jpg with '
      'their recording offset', () async {
    final report = await run(photos: 2);

    expect(report.photos, hasLength(2));
    for (final photo in report.photos) {
      expect(
        photo.filePath,
        MediaPaths.photo(talk.conferenceId, talk.id, photo.id),
      );
      expect(MediaPaths.resolve(root, photo.filePath).existsSync(), isTrue);
      expect(photo.source, PhotoSource.inApp);
      expect(photo.bytes, 1024);
    }
    // Shot 1 at the start, shot 2 after 1 s settle and 3 s interval.
    expect(report.photos.map((p) => p.offsetMs), [0, 4000]);
  });

  test('P0-05 FR-PHO-07 a camera interruption cuts a segment and resumes '
      'after the shot', () async {
    camera.onShot = (n) async {
      if (n == 2) interruptions.controller.add(_began);
    };

    final report = await run();

    expect(report.cameraInterruptions, hasLength(1));
    expect(report.cameraInterruptions.single.autoResumed, isTrue);
    expect(report.cameraInterruptions.single.endUtc, isNotNull);
    expect(report.segments, hasLength(2));
    expect(report.segments.first.endReason, SegmentEndReason.pause);
    expect(report.shots[1].cutSegment, isTrue);
    expect(report.shots[1].recordingAfter, isTrue);
    expect(report.eventsNearCamera, 1);
    expect(report.unexplainedGaps, isEmpty);
    expect(report.meetsAtPho01Rows, isTrue);
    expect(
      report.events.where((e) => e.kind == 'resumed').single.detail['why'],
      'after_shot',
    );
  });

  test('P0-05 FR-REC-05 an interruption away from the camera is a system '
      'one and waits for the system', () async {
    onWait = (n, d) {
      // The 3 s interval after shot 1: well outside the camera window.
      if (n == 2) interruptions.controller.add(_began);
    };

    final report = await run();

    expect(report.cameraInterruptions, isEmpty);
    expect(report.interruptions.single.reason, InterruptionReason.system);
    expect(report.interruptions.single.autoResumed, isFalse);
    expect(report.shots[1].stateBefore, RecordingState.paused);
    expect(report.shots.last.recordingAfter, isFalse);
    expect(report.eventsNearCamera, 0);
    expect(report.observations, contains(contains('away from any shot')));
  });

  test('P0-05 a system resume after an interruption ends the row as auto '
      'resumed', () async {
    onWait = (n, d) {
      if (n == 2) interruptions.controller.add(_began);
      if (n == 3) {
        interruptions.controller.add(
          const AudioInterruption(
            AudioInterruptionKind.ended,
            shouldResume: true,
          ),
        );
      }
    };

    final report = await run();

    expect(report.systemOfferedResume, isTrue);
    expect(report.interruptions.single.autoResumed, isTrue);
    expect(report.segments, hasLength(2));
    expect(report.unexplainedGaps, isEmpty);
  });

  test(
    'P0-05 a camera that will not open leaves the recording intact',
    () async {
      camera.openError = const CameraUnavailableException('No camera found.');

      final report = await run();

      expect(report.cameraError, contains('No camera found'));
      expect(report.shots, isEmpty);
      expect(report.segments, hasLength(1));
      expect(report.segments.single.state, SegmentState.finalised);
      expect(report.meetsAtPho01Rows, isFalse);
      expect(
        report.observations,
        contains(contains('Camera could not be used')),
      );
    },
  );

  test(
    'P0-05 cameras are listed even when the recording cannot start',
    () async {
      engine.startError = StateError('No audio recording device was found.');
      camera.lenses = const [];

      final report = await run();

      expect(report.startOutcome, StartOutcome.failed);
      expect(report.shots, isEmpty);
      expect(report.observations, contains('No camera listed.'));
      expect(report.events.map((e) => e.kind), contains('cameras'));
    },
  );

  test('P0-05 a failed shot is logged and the next shot still runs', () async {
    camera.shotError = (n) => n == 2 ? StateError('busy') : null;

    final report = await run();

    expect(report.savedPhotos, 2);
    expect(report.shots[1].saved, isFalse);
    expect(report.shots[1].error, contains('busy'));
    expect(report.photos, hasLength(2));
    expect(report.meetsAtPho01Rows, isFalse);
    expect(report.observations, contains('2 of 3 photo(s) saved, 1 failed.'));
  });

  test('P0-05 a level drop across a shot is flagged for listening', () async {
    camera.onShot = (n) async {
      if (n == 2) engine.level = -90;
    };

    final report = await run();

    expect(report.shotsWithLevelDrop.map((s) => s.number), [2]);
    expect(report.observations, contains(contains('listen around them')));
  });

  test('P0-05 the report renders as JSON and a Markdown table', () async {
    final report = await run(photos: 2);

    final json = jsonDecode(report.toPrettyJson()) as Map<String, Object?>;
    expect(json['spike'], 'P0-05');
    expect(json['saved_photos'], 2);
    expect(json['shots'], hasLength(2));
    expect(json['meets_at_pho_01_rows'], isTrue);
    final md = report.toMarkdown();
    expect(md, contains('| Shot | Offset s |'));
    expect(md.split('\n').where((l) => l.startsWith('| 1 |')), hasLength(1));
  });

  group('P0-05 AT-PHO-01 segment gaps', () {
    test('a gap with no interruption is unexplained, one with a row is '
        'explained', () async {
      final segments = await t.segmentsWithGaps(talk.id, [
        (0, 60),
        (62, 120), // 2 s gap, no row
        (130, 180), // 10 s gap, covered below
      ]);
      final start = segments.first.startUtc;
      final row = await t.media.startInterruption(
        talk.id,
        InterruptionReason.camera,
        startUtc: start.add(const Duration(seconds: 121)),
      );
      await t.media.endInterruption(
        row.id,
        autoResumed: true,
        endUtc: start.add(const Duration(seconds: 129)),
      );

      final gaps = segmentGaps(
        segments,
        await t.media.interruptionsFor(talk.id),
      );

      expect(gaps.map((g) => g.durationMs), [2000, 10000]);
      expect(gaps.map((g) => g.explained), [false, true]);
      expect(gaps.last.explainedBy!.reason, InterruptionReason.camera);
    });

    test('an open interruption explains every later gap', () async {
      final segments = await t.segmentsWithGaps(talk.id, [(0, 10), (20, 30)]);
      await t.media.startInterruption(
        talk.id,
        InterruptionReason.call,
        startUtc: segments.first.startUtc.add(const Duration(seconds: 12)),
      );

      final gaps = segmentGaps(
        segments,
        await t.media.interruptionsFor(talk.id),
      );

      expect(gaps.single.explained, isTrue);
    });
  });

  group('P0-05 moveCapturedFile', () {
    test('moves the plugin file into place', () async {
      final from = File(p.join(root.path, 'tmp', 'CAP001.jpg'));
      await from.parent.create(recursive: true);
      await from.writeAsBytes([1, 2, 3]);
      final to = p.join(root.path, 'photos', 'a.jpg');

      final moved = await moveCapturedFile(from.path, to);

      expect(moved.path, to);
      expect(await moved.readAsBytes(), [1, 2, 3]);
      expect(from.existsSync(), isFalse);
    });

    test('never overwrites an existing photo', () async {
      final from = File(p.join(root.path, 'CAP002.jpg'));
      await from.writeAsBytes([9]);
      final existing = File(p.join(root.path, 'photos', 'b.jpg'));
      await existing.parent.create(recursive: true);
      await existing.writeAsBytes([1]);

      await expectLater(
        moveCapturedFile(from.path, existing.path),
        throwsA(isA<FileSystemException>()),
      );
      expect(await existing.readAsBytes(), [1]);
      expect(from.existsSync(), isTrue);
    });
  });
}

extension on TestData {
  /// Finalised segments at the given (start, end) seconds from the clock's
  /// current time.
  Future<List<RecordingSegment>> segmentsWithGaps(
    String activityId,
    List<(int, int)> spans,
  ) async {
    final base = clock.now;
    final out = <RecordingSegment>[];
    for (final (start, end) in spans) {
      final s = await media.startSegment(
        startUtc: base.add(Duration(seconds: start)),
        activityId: activityId,
        filePath: 'audio/segment-${out.length + 1}.m4a',
        requestedProfile: RecordingProfile.balanced,
        codec: 'aac',
        container: 'm4a',
        channelCount: 1,
        sampleRateHz: 48000,
        requestedBitrateBps: 48000,
      );
      out.add(
        await media.finaliseSegment(
          s.id,
          endUtc: base.add(Duration(seconds: end)),
          endReason: SegmentEndReason.pause,
          durationMs: (end - start) * 1000,
          bytes: 100,
        ),
      );
    }
    return out;
  }
}
