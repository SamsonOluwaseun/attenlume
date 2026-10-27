import 'dart:io';

import 'package:attenlume/data/filesystem/media_paths.dart';
import 'package:attenlume/data/filesystem/segment_commit.dart';
import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/models/media.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/crash_recovery_service.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fake_capture_engine.dart';
import '../fixtures/fake_timers.dart';
import '../fixtures/fixtures.dart';
import '../fixtures/m4a_builder.dart';

void main() {
  late TestData t;
  late Directory root;
  late Activity keynote;
  late List<String> hashed;

  CrashRecoveryService build({
    RecordingStatus Function()? recorderStatus,
    SegmentCommit commit = commitSegmentFile,
    Future<String> Function(File)? hashFile,
  }) => CrashRecoveryService(
    activities: t.activities,
    media: t.media,
    mediaRoot: () async => root,
    recorderStatus: recorderStatus ?? () => RecordingStatus.idle,
    hashFile:
        hashFile ??
        (file) async {
          hashed.add(file.path);
          return 'hash';
        },
    commitFile: commit,
  );

  setUp(() async {
    t = TestData();
    root = await Directory.systemTemp.createTemp('attenlume_recovery_');
    hashed = [];
    final conference = await t.conference();
    keynote = await t.activity(conference.id, title: 'Data Mesh Keynote');
  });

  tearDown(() async {
    await t.close();
    await root.delete(recursive: true);
  });

  String finalPath(int sequence, {Activity? of}) {
    final a = of ?? keynote;
    return MediaPaths.segment(a.conferenceId, a.id, sequence);
  }

  File fileOf(String relative) => MediaPaths.resolve(root, relative);

  void writeFile(String relative, List<int> bytes) {
    fileOf(relative)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes);
  }

  /// A row left `writing` by a crash, pointing at the partial name.
  Future<RecordingSegment> writingRow({
    Activity? of,
    DateTime? start,
    int sequence = 1,
  }) async {
    final a = of ?? keynote;
    await t.activities.update(
      a.id,
      const ActivitiesCompanion(status: Value(ActivityStatus.active)),
    );
    return t.media.startSegment(
      activityId: a.id,
      filePath: MediaPaths.partial(finalPath(sequence, of: a)),
      requestedProfile: RecordingProfile.balanced,
      codec: 'aac_lc',
      container: 'm4a',
      channelCount: 1,
      sampleRateHz: 48000,
      requestedBitrateBps: 48000,
      startUtc: start ?? t.clock.now,
    );
  }

  Future<RecordingSegment> rowOf(String id) async =>
      (await t.media.segmentsFor(keynote.id)).singleWhere((s) => s.id == id);

  group('FR-REC-08 unfinished segments', () {
    test('FR-REC-08 a partial file that parses is marked recovered, given '
        'its final name and described from the file', () async {
      final row = await writingRow();
      writeFile(
        row.filePath,
        buildM4a(channels: 2, sampleRateHz: 44100, durationUnits: 48000 * 5),
      );

      final report = await build().reconcile();

      final seg = await rowOf(row.id);
      expect(seg.state, SegmentState.recovered);
      expect(seg.filePath, finalPath(1));
      expect(fileOf(finalPath(1)).existsSync(), isTrue);
      expect(fileOf(row.filePath).existsSync(), isFalse);
      expect(seg.durationMs, 5000);
      expect(seg.endUtc, row.startUtc.add(const Duration(seconds: 5)));
      expect(seg.channelCount, 2);
      expect(seg.sampleRateHz, 44100);
      expect(seg.bytes, fileOf(finalPath(1)).lengthSync());
      expect(seg.sha256, 'hash');
      expect(seg.observedBitrateBps, greaterThan(0));
      expect(seg.endReason, SegmentEndReason.error);
      expect(report.activities.single.recovered, 1);
    });

    test('FR-REC-08 renamed before the row update: the final name is found '
        'and recovered (ADR-019)', () async {
      final row = await writingRow();
      writeFile(finalPath(1), buildM4a());

      final report = await build().reconcile();

      final seg = await rowOf(row.id);
      expect(seg.state, SegmentState.recovered);
      expect(seg.filePath, finalPath(1));
      expect(seg.durationMs, 3000);
      expect(fileOf(finalPath(1)).existsSync(), isTrue);
      expect(report.activities.single.recovered, 1);
      expect(report.activities.single.missing, 0);
    });

    test('FR-REC-08 a file cut off before its moov box is damaged, never '
        'marked good, and kept under its partial name', () async {
      final row = await writingRow();
      final bytes = buildM4a(includeMoov: false);
      writeFile(row.filePath, bytes);

      final report = await build().reconcile();

      final seg = await rowOf(row.id);
      expect(seg.state, SegmentState.damaged);
      expect(seg.filePath, row.filePath);
      expect(fileOf(row.filePath).readAsBytesSync(), bytes);
      expect(fileOf(finalPath(1)).existsSync(), isFalse);
      expect(seg.bytes, bytes.length);
      expect(seg.sha256, isNull);
      expect(seg.durationMs, isNull);
      expect(hashed, isEmpty);
      expect(report.activities.single.damaged, 1);
    });

    test('FR-REC-08 an empty file is damaged and kept', () async {
      final row = await writingRow();
      writeFile(row.filePath, const []);

      await build().reconcile();

      final seg = await rowOf(row.id);
      expect(seg.state, SegmentState.damaged);
      expect(seg.bytes, 0);
      expect(fileOf(row.filePath).existsSync(), isTrue);
    });

    test('FR-REC-08 no file under either name: damaged, spans no time so '
        'the timeline shows a gap (ADR-016)', () async {
      final row = await writingRow();

      final report = await build().reconcile();

      final seg = await rowOf(row.id);
      expect(seg.state, SegmentState.damaged);
      expect(seg.endUtc, seg.startUtc);
      expect(seg.bytes, isNull);
      expect(seg.filePath, row.filePath);
      expect(report.activities.single.missing, 1);
      expect(report.activities.single.damaged, 0);
    });

    test('NFR-07 a good partial file whose final name is taken is recovered '
        'under its partial name and the other file is untouched', () async {
      final row = await writingRow();
      writeFile(row.filePath, buildM4a());
      writeFile(finalPath(1), const [1, 2, 3]);

      await build().reconcile();

      final seg = await rowOf(row.id);
      expect(seg.state, SegmentState.recovered);
      expect(seg.filePath, row.filePath);
      expect(fileOf(row.filePath).existsSync(), isTrue);
      expect(fileOf(finalPath(1)).readAsBytesSync(), [1, 2, 3]);
    });

    test('FR-REC-08 a failed rename keeps the file under its partial name, '
        'still recovered', () async {
      final row = await writingRow();
      writeFile(row.filePath, buildM4a());

      await build(
        commit: (partial, target) async =>
            throw FileSystemException('locked', partial.path),
      ).reconcile();

      final seg = await rowOf(row.id);
      expect(seg.state, SegmentState.recovered);
      expect(seg.filePath, row.filePath);
      expect(fileOf(row.filePath).existsSync(), isTrue);
    });

    test(
      'FR-REC-08 a hash failure leaves the hash empty, not invented',
      () async {
        final row = await writingRow();
        writeFile(row.filePath, buildM4a());

        await build(
          hashFile: (_) async => throw const FileSystemException('busy'),
        ).reconcile();

        final seg = await rowOf(row.id);
        expect(seg.state, SegmentState.recovered);
        expect(seg.sha256, isNull);
      },
    );

    test('FR-REC-08 finalised and damaged rows, including the zero-length '
        'row of a failed fallback, are left alone', () async {
      final good = await t.segment(
        keynote.id,
        start: t.clock.now,
        length: const Duration(minutes: 10),
      );
      final failed = await t.media.startSegment(
        activityId: keynote.id,
        filePath: MediaPaths.partial(finalPath(2)),
        requestedProfile: RecordingProfile.balanced,
        codec: 'aac_lc',
        container: 'm4a',
        channelCount: 1,
        sampleRateHz: 48000,
        requestedBitrateBps: 48000,
      );
      await t.media.finaliseSegment(
        failed.id,
        endUtc: failed.startUtc,
        endReason: SegmentEndReason.error,
        state: SegmentState.damaged,
      );
      final before = await t.media.segmentsFor(keynote.id);

      final report = await build().reconcile();

      expect(report.needsPrompt, isFalse);
      final after = await t.media.segmentsFor(keynote.id);
      expect(after.map((s) => s.toString()), before.map((s) => s.toString()));
      expect(after.first.id, good.id);
    });

    test('FR-REC-08 a second run finds nothing more to do', () async {
      final row = await writingRow();
      writeFile(row.filePath, buildM4a());

      await build().reconcile();
      final again = await build().reconcile();

      expect(again.needsPrompt, isFalse);
      expect((await rowOf(row.id)).state, SegmentState.recovered);
    });

    test('FR-REC-08 nothing to recover gives an empty report', () async {
      final report = await build().reconcile();

      expect(report.activities, isEmpty);
      expect(report.unlinkedFiles, isEmpty);
      expect(report.needsPrompt, isFalse);
    });
  });

  group('FR-REC-08 activities and interruptions left open', () {
    test('FR-REC-08 an active activity with audio is completed, ending '
        'where its audio ends', () async {
      final start = t.clock.now;
      await t.segment(
        keynote.id,
        start: start,
        length: const Duration(minutes: 10),
        endReason: SegmentEndReason.roll,
      );
      final row = await writingRow(
        start: start.add(const Duration(minutes: 10)),
        sequence: 2,
      );
      writeFile(row.filePath, buildM4a(durationUnits: 48000 * 60));

      final report = await build().reconcile();

      final activity = (await t.activities.get(keynote.id))!;
      expect(activity.status, ActivityStatus.completed);
      expect(activity.actualEnd, start.add(const Duration(minutes: 11)));
      expect(report.activities.single.wasRecording, isTrue);
      expect(report.activities.single.recovered, 1);
    });

    test('FR-REC-08 an active activity with no audio goes back to draft so '
        'it can be started again', () async {
      await t.activities.update(
        keynote.id,
        const ActivitiesCompanion(status: Value(ActivityStatus.active)),
      );

      final report = await build().reconcile();

      expect(
        (await t.activities.get(keynote.id))!.status,
        ActivityStatus.draft,
      );
      expect(report.activities.single.wasRecording, isTrue);
    });

    test('FR-REC-05 an interruption open at the crash ends at its own start '
        'when nothing was recorded after it', () async {
      final start = t.clock.now;
      await t.segment(
        keynote.id,
        start: start,
        length: const Duration(minutes: 4),
        endReason: SegmentEndReason.interruption,
      );
      await t.activities.update(
        keynote.id,
        const ActivitiesCompanion(status: Value(ActivityStatus.active)),
      );
      final call = await t.media.startInterruption(
        keynote.id,
        InterruptionReason.system,
        startUtc: start.add(const Duration(minutes: 4)),
      );

      final report = await build().reconcile();

      final closed = (await t.media.interruptionsFor(keynote.id)).single;
      expect(closed.id, call.id);
      expect(closed.endUtc, call.startUtc);
      expect(closed.autoResumed, isFalse);
      expect(report.activities.single.interruptionsClosed, 1);
      expect(await t.media.openInterruptions(), isEmpty);
    });

    test('FR-REC-05 an interruption followed by more audio ends where the '
        'next segment starts', () async {
      final start = t.clock.now;
      final lost = await t.media.startInterruption(
        keynote.id,
        InterruptionReason.routeLost,
        startUtc: start,
      );
      await t.segment(
        keynote.id,
        start: start.add(const Duration(minutes: 2)),
        length: const Duration(minutes: 1),
      );

      await build().reconcile();

      final closed = (await t.media.interruptionsFor(keynote.id)).single;
      expect(closed.id, lost.id);
      expect(closed.endUtc, start.add(const Duration(minutes: 2)));
    });

    test('FR-REC-08 the activity the recorder holds is left alone', () async {
      final row = await writingRow();
      writeFile(row.filePath, const []);
      await t.media.startInterruption(keynote.id, InterruptionReason.system);
      final status = RecordingStatus(
        state: RecordingState.recording,
        activityId: keynote.id,
        segmentId: row.id,
      );

      final report = await build(recorderStatus: () => status).reconcile();

      expect(report.needsPrompt, isFalse);
      expect((await rowOf(row.id)).state, SegmentState.writing);
      expect(await t.media.openInterruptions(), hasLength(1));
      expect(
        (await t.activities.get(keynote.id))!.status,
        ActivityStatus.active,
      );
    });

    test(
      'FR-REC-08 other activities are recovered while one records',
      () async {
        final other = await t.activity(keynote.conferenceId, title: 'Panel');
        final held = await writingRow();
        final crashed = await writingRow(of: other);
        writeFile(crashed.filePath, buildM4a());
        final status = RecordingStatus(
          state: RecordingState.recording,
          activityId: keynote.id,
          segmentId: held.id,
        );

        final report = await build(recorderStatus: () => status).reconcile();

        expect(report.activities.single.activityId, other.id);
        expect(
          (await t.media.segmentsFor(other.id)).single.state,
          SegmentState.recovered,
        );
        expect((await rowOf(held.id)).state, SegmentState.writing);
      },
    );
  });

  group('FR-REC-08 unlinked files', () {
    test('NFR-07 audio files no row names are listed and kept', () async {
      await t.segment(
        keynote.id,
        start: t.clock.now,
        length: const Duration(minutes: 1),
      );
      final known = (await t.media.segmentsFor(keynote.id)).single;
      await (t.db.update(t.db.recordingSegments)
            ..where((s) => s.id.equals(known.id)))
          .write(RecordingSegmentsCompanion(filePath: Value(finalPath(1))));
      writeFile(finalPath(1), buildM4a());
      final stray = MediaPaths.partial(finalPath(7));
      writeFile(stray, const [0]);
      final photo = MediaPaths.photo(keynote.conferenceId, keynote.id, 'x');
      writeFile(photo, const [0]);

      final report = await build().reconcile();

      expect(report.unlinkedFiles, [stray]);
      expect(report.needsPrompt, isTrue);
      expect(fileOf(stray).existsSync(), isTrue);
      expect(fileOf(finalPath(1)).existsSync(), isTrue);
    });
  });

  group('FR-REC-08 messages', () {
    RecoveredActivity sample({
      bool wasRecording = true,
      int recovered = 0,
      int damaged = 0,
      int missing = 0,
    }) => RecoveredActivity(
      activityId: 'a',
      conferenceId: 'c',
      title: 'Data Mesh Keynote',
      wasRecording: wasRecording,
      recovered: recovered,
      damaged: damaged,
      missing: missing,
    );

    test('FR-REC-08 says what was saved and what was kept, in plain words', () {
      expect(
        sample(recovered: 1).message,
        "Attenlume closed while 'Data Mesh Keynote' was recording. The "
        'unfinished part was saved. Everything recorded before that is safe.',
      );
      expect(
        sample(damaged: 2, missing: 1).message,
        "Attenlume closed while 'Data Mesh Keynote' was recording. 2 "
        'unfinished parts could not be read. The files are kept. One '
        'unfinished part has no audio file and shows as a gap. Everything '
        'recorded before that is safe.',
      );
      expect(
        sample(wasRecording: false, damaged: 1).message,
        startsWith(
          "Attenlume closed before 'Data Mesh Keynote' finished "
          'saving.',
        ),
      );
    });
  });

  group('AT-REC-03 force-kill mid-recording', () {
    test('AT-REC-03 a kill loses at most the open segment and recovery is '
        'offered on the next launch', () async {
      final engine = FakeCaptureEngine();
      final timers = FakeTimers();
      final recorder = RecordingService(
        engine: engine,
        activities: t.activities,
        media: t.media,
        mediaRoot: () async => root,
        platform: CapturePlatform.android,
        clock: t.clock.call,
        hashFile: (_) async => 'hash',
        rollTimer: timers.call,
      );
      expect(await recorder.start(keynote.id), StartOutcome.started);
      t.clock.advance(const Duration(minutes: 10));
      final rolled = recorder.statusStream.firstWhere(
        (s) => s.state == RecordingState.recording,
      );
      timers.created.last.fire();
      await rolled;
      t.clock.advance(const Duration(minutes: 3));
      // Killed here: the encoder never wrote its moov box and no stop ran.

      final report = await build().reconcile();

      final segments = await t.media.segmentsFor(keynote.id);
      expect(segments.map((s) => s.state), [
        SegmentState.finalised,
        SegmentState.damaged,
      ]);
      expect(fileOf(segments.first.filePath).existsSync(), isTrue);
      expect(fileOf(segments.last.filePath).existsSync(), isTrue);
      expect(report.needsPrompt, isTrue);
      expect(report.activities.single.wasRecording, isTrue);
      expect(report.activities.single.damaged, 1);
      expect(
        (await t.activities.get(keynote.id))!.status,
        ActivityStatus.completed,
      );
      await engine.dispose();
    });
  });
}
