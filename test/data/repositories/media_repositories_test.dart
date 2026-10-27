import 'package:attenlume/domain/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fixtures.dart';

void main() {
  late TestData t;

  setUp(() => t = TestData());
  tearDown(() => t.close());

  group('FR-REC-03 segments', () {
    test('FR-REC-03 segments are numbered in order per activity', () async {
      final c = await t.conference();
      final a = await t.activity(c.id);
      final b = await t.activity(c.id);
      final start = DateTime.utc(2026, 11, 4, 10);
      await t.segment(a.id, start: start, length: const Duration(minutes: 10));
      await t.segment(b.id, start: start, length: const Duration(minutes: 1));
      await t.segment(
        a.id,
        start: start.add(const Duration(minutes: 10)),
        length: const Duration(minutes: 2),
      );
      expect((await t.media.segmentsFor(a.id)).map((s) => s.sequence), [1, 2]);
      expect((await t.media.segmentsFor(b.id)).single.sequence, 1);
    });

    test('FR-REC-01 a segment row exists in state writing first', () async {
      final c = await t.conference();
      final a = await t.activity(c.id);
      final seg = await t.media.startSegment(
        activityId: a.id,
        filePath: 'audio/segment-001.m4a',
        requestedProfile: RecordingProfile.balanced,
        codec: 'aac_lc',
        container: 'm4a',
        channelCount: 1,
        sampleRateHz: 48000,
        requestedBitrateBps: 48000,
      );
      expect(seg.state, SegmentState.writing);
      expect(seg.endUtc, isNull);
      expect((await t.media.unfinalisedSegments()).single.id, seg.id);
      expect((await t.activities.get(a.id))!.actualStart, seg.startUtc);
    });

    test('FR-QUAL-06 a segment keeps requested and observed quality', () async {
      final c = await t.conference();
      final a = await t.activity(c.id);
      final seg = await t.media.startSegment(
        activityId: a.id,
        filePath: 'audio/segment-001.m4a',
        requestedProfile: RecordingProfile.economy,
        codec: 'aac_lc',
        container: 'm4a',
        channelCount: 1,
        sampleRateHz: 48000,
        requestedBitrateBps: 32000,
        inputRoute: 'bluetooth_hfp',
        startUtc: DateTime.utc(2026, 11, 4, 10),
      );
      final done = await t.media.finaliseSegment(
        seg.id,
        endUtc: DateTime.utc(2026, 11, 4, 10, 10),
        endReason: SegmentEndReason.roll,
        durationMs: 600000,
        bytes: 7200000,
        sha256: 'a' * 64,
        observedBitrateBps: 96000,
      );
      expect(done.state, SegmentState.finalised);
      expect(done.requestedProfile, RecordingProfile.economy);
      expect(done.requestedBitrateBps, 32000);
      expect(done.observedBitrateBps, 96000);
      expect(done.inputRoute, 'bluetooth_hfp');
      expect(done.endReason, SegmentEndReason.roll);
      expect(done.bytes, 7200000);
      expect(await t.media.unfinalisedSegments(), isEmpty);
    });

    test('FR-REC-08 a segment can be marked damaged or recovered', () async {
      final c = await t.conference();
      final a = await t.activity(c.id);
      final seg = await t.media.startSegment(
        activityId: a.id,
        filePath: 'audio/segment-001.m4a',
        requestedProfile: RecordingProfile.balanced,
        codec: 'aac_lc',
        container: 'm4a',
        channelCount: 1,
        sampleRateHz: 48000,
        requestedBitrateBps: 48000,
      );
      await t.media.setSegmentState(seg.id, SegmentState.damaged);
      expect(
        (await t.media.segmentsFor(a.id)).single.state,
        SegmentState.damaged,
      );
    });

    test('P0-09 duplicate sequence numbers are refused', () async {
      final c = await t.conference();
      final a = await t.activity(c.id);
      await t.segment(a.id, start: t.clock.now, length: Duration.zero);
      expect(
        () => t.db.customStatement(
          'INSERT INTO recording_segments (id, activity_id, sequence, '
          'file_path, state, requested_profile, codec, container, '
          'channel_count, sample_rate_hz, requested_bitrate_bps, start_utc, '
          "created_at, updated_at) VALUES ('dup', '${a.id}', 1, 'x', "
          "'writing', 'balanced', 'aac_lc', 'm4a', 1, 48000, 48000, "
          "'2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', "
          "'2026-01-01T00:00:00.000Z')",
        ),
        throwsA(anything),
      );
    });
  });

  group('P0-09 offset rule across gaps', () {
    test('P0-09 photos and bookmarks use wall clock across a call', () async {
      final sample = await SampleConference.build(t);
      final id = sample.keynote.id;
      // Recorded 09:30 to 09:40, call 09:40 to 09:43, recorded 09:43 to
      // 09:50. The photo at 09:44 and bookmark at 09:45 sit 14 and 15
      // minutes in, not 11 and 12.
      expect((await t.media.photosFor(id)).single.offsetMs, 14 * 60000);
      final bookmark = (await t.media.bookmarksFor(id)).single;
      expect(bookmark.offsetMs, 15 * 60000);
      expect(bookmark.label, 'Key slide');
      final call = (await t.media.interruptionsFor(id)).single;
      expect(call.reason, InterruptionReason.call);
      expect(call.autoResumed, isTrue);
      expect(call.endUtc!.difference(call.startUtc).inMinutes, 3);
    });

    test('P0-09 events before recording get offsets later', () async {
      final c = await t.conference();
      final a = await t.activity(c.id);
      final start = DateTime.utc(2026, 11, 4, 10);
      final photo = await t.media.addPhoto(
        activityId: a.id,
        filePath: 'photos/p.jpg',
        takenUtc: start.subtract(const Duration(seconds: 20)),
        source: PhotoSource.inApp,
      );
      final mark = await t.media.addBookmark(
        activityId: a.id,
        source: BookmarkSource.notification,
        atUtc: start.subtract(const Duration(seconds: 5)),
      );
      expect(photo.offsetMs, isNull);
      expect(mark.offsetMs, isNull);

      await t.segment(a.id, start: start, length: const Duration(minutes: 1));

      expect((await t.media.photosFor(a.id)).single.offsetMs, -20000);
      expect((await t.media.bookmarksFor(a.id)).single.offsetMs, -5000);
    });
  });

  group('FR-REV-04 cut ranges', () {
    test('FR-REV-04 remove and restore give undo', () async {
      final sample = await SampleConference.build(t);
      final id = sample.keynote.id;
      final cut = (await t.cuts.activeFor(id)).single;
      expect(cut.reason, 'Intro music');
      await t.cuts.remove(cut.id);
      expect(await t.cuts.activeFor(id), isEmpty);
      await t.cuts.restore(cut.id);
      expect((await t.cuts.activeFor(id)).single.isDeleted, isFalse);
    });

    test('FR-REV-04 empty or reversed ranges are rejected', () async {
      final c = await t.conference();
      final a = await t.activity(c.id);
      for (final (start, end) in [(10, 10), (10, 5), (-1, 5)]) {
        expect(
          () => t.cuts.add(a.id, startOffsetMs: start, endOffsetMs: end),
          throwsArgumentError,
        );
      }
      expect(
        () => t.db.customStatement(
          'INSERT INTO cut_ranges (id, activity_id, start_offset_ms, '
          "end_offset_ms, created_at, updated_at) VALUES ('c', '${a.id}', "
          "10, 5, '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')",
        ),
        throwsA(anything),
      );
    });

    test('FR-REV-04 multiple ranges list in timeline order', () async {
      final c = await t.conference();
      final a = await t.activity(c.id);
      await t.cuts.add(a.id, startOffsetMs: 60000, endOffsetMs: 90000);
      await t.cuts.add(a.id, startOffsetMs: 0, endOffsetMs: 5000);
      expect((await t.cuts.activeFor(a.id)).map((r) => r.startOffsetMs), [
        0,
        60000,
      ]);
    });
  });

  group('P0-09 export jobs', () {
    test('P0-09 a job moves pending, running, completed', () async {
      final c = await t.conference();
      final job = await t.exports.create(
        conferenceId: c.id,
        scope: const {
          'kind': 'activities',
          'activity_ids': ['a', 'b'],
        },
        format: ExportFormat.folder,
        audioMode: ExportAudioMode.originalWithCuts,
        bytesTotal: 1000,
      );
      expect(job.state, ExportJobState.pending);
      expect(job.destination, ExportDestination.local);
      expect(job.scope['activity_ids'], ['a', 'b']);

      await t.exports.markRunning(job.id);
      await t.exports.reportProgress(job.id, 500);
      t.clock.advance(const Duration(seconds: 30));
      await t.exports.complete(job.id, VerificationLevel.checksum);

      final done = (await t.exports.get(job.id))!;
      expect(done.state, ExportJobState.completed);
      expect(done.bytesDone, 500);
      expect(done.verificationLevel, VerificationLevel.checksum);
      expect(done.completedAt!.difference(done.startedAt!).inSeconds, 30);
    });

    test('P0-09 a failed job keeps its error', () async {
      final c = await t.conference();
      final job = await t.exports.create(
        conferenceId: c.id,
        scope: const {'kind': 'conference'},
        format: ExportFormat.zip,
        audioMode: ExportAudioMode.original,
      );
      await t.exports.fail(job.id, 'insufficient_space');
      final failed = (await t.exports.forConference(c.id)).single;
      expect(failed.state, ExportJobState.failed);
      expect(failed.lastError, 'insufficient_space');
    });
  });

  group('P0-09 UTC storage', () {
    test('P0-09 every stored instant is UTC ISO 8601 text', () async {
      await SampleConference.build(t);
      await t.conferences.acknowledgePolicy(
        (await t.conferences.watchAll().first).single.id,
      );
      final columns = {
        'conferences': ['created_at', 'updated_at', 'policy_acknowledged_at'],
        'goals': ['created_at', 'updated_at'],
        'activity_types': ['created_at', 'updated_at'],
        'activities': ['created_at', 'updated_at', 'actual_start'],
        'recording_segments': ['start_utc', 'end_utc', 'created_at'],
        'interruptions': ['start_utc', 'end_utc'],
        'photos': ['taken_utc'],
        'bookmarks': ['at_utc'],
        'cut_ranges': ['created_at'],
      };
      final iso = RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+)?Z$');
      for (final MapEntry(key: table, value: cols) in columns.entries) {
        for (final col in cols) {
          final rows = await t.db
              .customSelect('SELECT $col AS v FROM $table WHERE $col NOT NULL')
              .get();
          expect(rows, isNotEmpty, reason: '$table.$col');
          for (final row in rows) {
            expect(row.read<String>('v'), matches(iso), reason: '$table.$col');
          }
        }
      }
    });

    test('P0-09 local input is stored and read back as UTC', () async {
      final c = await t.conference();
      final a = await t.activity(c.id);
      final local = DateTime(2026, 11, 4, 10, 15);
      final b = await t.media.addBookmark(
        activityId: a.id,
        source: BookmarkSource.hotkey,
        atUtc: local,
      );
      expect(b.atUtc.isUtc, isTrue);
      expect(b.atUtc, local.toUtc());
    });
  });
}
