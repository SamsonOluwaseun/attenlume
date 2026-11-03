import 'dart:io';

import 'package:attenlume/data/filesystem/media_paths.dart';
import 'package:attenlume/data/transcription/transcript_store.dart';
import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/models/media.dart';
import 'package:attenlume/domain/services/activity_splitter.dart';
import 'package:attenlume/domain/services/cut_range_math.dart';
import 'package:attenlume/domain/services/permanent_trim_service.dart';
import 'package:attenlume/domain/services/transcript_carrier.dart';
import 'package:attenlume/domain/transcription/transcript.dart';
import 'package:attenlume/domain/transcription/transcript_carry.dart';
import 'package:attenlume/platform/audio_trimmer/mp4_sample_trimmer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fixtures.dart';
import '../fixtures/mp4_fixture.dart';

const _min = 60000;

/// Reads like the real store but cannot move anything.
class _FailingStore extends TranscriptStore {
  _FailingStore(super.root);

  @override
  Future<void> carry({
    required List<TranscriptDocument> documents,
    required List<(String, String)> retire,
  }) async => throw const FileSystemException('disk full');
}

TranscriptSpan _span(int startMs, int endMs, String text) => TranscriptSpan(
  start: Duration(milliseconds: startMs),
  end: Duration(milliseconds: endMs),
  text: text,
);

TranscriptDocument _doc(
  String activityId,
  String segmentId,
  List<TranscriptSpan> spans, {
  Map<int, String> corrections = const {},
  Duration offset = Duration.zero,
}) => TranscriptDocument(
  activityId: activityId,
  segmentId: segmentId,
  machineSpans: spans,
  corrections: corrections,
  createdAt: DateTime.utc(2026, 11, 4, 12),
  segmentOffset: offset,
  modelId: 'pilot-model',
);

List<(int, int, String)> _lines(TranscriptDocument d) => [
  for (var i = 0; i < d.machineSpans.length; i++)
    (
      d.machineSpans[i].start.inMilliseconds,
      d.machineSpans[i].end.inMilliseconds,
      d.textAt(i),
    ),
];

List<File> _superseded(Directory root, String activityId) {
  final folder = Directory('${root.path}/transcripts-v1/$activityId');
  if (!folder.existsSync()) return const [];
  return [
    for (final f in folder.listSync().whereType<File>())
      if (f.path.contains('.json.superseded-')) f,
  ];
}

void main() {
  group('FR-TRN-08 P2-09b transcript line maths', () {
    final source = _doc(
      'act',
      'seg',
      [
        _span(500, 1500, 'intro'),
        _span(1800, 2500, 'across the start cut'),
        _span(2500, 3500, 'kept a'),
        _span(4500, 5500, 'middle'),
        _span(6200, 7000, 'kept b'),
        _span(7800, 8200, 'across the end cut'),
        _span(9000, 9500, 'outro'),
      ],
      corrections: {2: 'Kept A', 3: 'Middle (fixed)', 4: 'Kept B'},
    );

    test('FR-TRN-08 P2-09b a trimmed piece keeps only lines wholly in its '
        'audio, timed from the piece start, with corrections', () {
      final first = transcriptForTrimmedPiece(
        source,
        activityId: 'act',
        segmentId: 'piece1',
        keep: const TimeRange(2000, 4000),
        segmentOffset: Duration.zero,
      )!;
      expect(_lines(first), [(500, 1500, 'Kept A')]);
      expect(first.textAt(0, useCorrections: false), 'kept a');
      expect(first.corrections, {0: 'Kept A'});
      expect(first.segmentId, 'piece1');
      expect(first.createdAt, source.createdAt);
      expect(first.modelId, 'pilot-model');

      final second = transcriptForTrimmedPiece(
        source,
        activityId: 'act',
        segmentId: 'piece2',
        keep: const TimeRange(6000, 8000),
        segmentOffset: const Duration(seconds: 4),
      )!;
      expect(_lines(second), [(200, 1000, 'Kept B')]);
      expect(second.segmentOffset, const Duration(seconds: 4));
    });

    test('FR-TRN-08 P2-09b a piece with no whole line gives no transcript', () {
      expect(
        transcriptForTrimmedPiece(
          source,
          activityId: 'act',
          segmentId: 'p',
          keep: const TimeRange(4000, 6000),
          segmentOffset: Duration.zero,
        )?.machineSpans.map((s) => s.text),
        ['middle'],
      );
      expect(
        transcriptForTrimmedPiece(
          source,
          activityId: 'act',
          segmentId: 'p',
          keep: const TimeRange(8200, 8900),
          segmentOffset: Duration.zero,
        ),
        isNull,
      );
    });

    test('FR-TRN-08 P2-09b a split inside a line gives it to the side that '
        'holds most of its audio; times do not change', () {
      final first = transcriptForSplitPart(
        source,
        activityId: 'act',
        segmentId: 'seg',
        segmentOffset: Duration.zero,
        toMs: 1900,
      )!;
      final second = transcriptForSplitPart(
        source,
        activityId: 'part2',
        segmentId: 'copy',
        segmentOffset: Duration.zero,
        fromMs: 1900,
      )!;
      // 1800 to 2500 has its middle (2150) after the split.
      expect(_lines(first), [(500, 1500, 'intro')]);
      expect(_lines(second).first, (1800, 2500, 'across the start cut'));
      expect(second.machineSpans, hasLength(6));
      expect(second.corrections, {
        1: 'Kept A',
        2: 'Middle (fixed)',
        3: 'Kept B',
      });
      expect(
        first.machineSpans.length + second.machineSpans.length,
        source.machineSpans.length,
      );
    });
  });

  group('FR-TRN-08 P2-09b transcript store carry', () {
    late Directory root;
    late TranscriptStore store;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('transcript_carry_');
      store = TranscriptStore(root);
    });

    tearDown(() => root.delete(recursive: true));

    test('FR-TRN-08 P2-09b retired transcripts are renamed, not deleted, '
        'and leave the listing', () async {
      final old = _doc('act', 'old', [_span(0, 1000, 'hello')]);
      await store.saveOriginal(old);
      await store.carry(
        documents: [
          _doc('act', 'new', [_span(0, 1000, 'hello')]),
        ],
        retire: const [('act', 'old')],
      );
      final listed = await store.listDocuments(activityId: 'act');
      expect(listed.map((d) => d.segmentId), ['new']);
      final kept = _superseded(root, 'act').single;
      expect(kept.readAsStringSync(), contains('hello'));
    });

    test('FR-TRN-08 P2-09b never overwrites a transcript it was not told '
        'to replace', () async {
      await store.saveOriginal(_doc('act', 'other', [_span(0, 1, 'mine')]));
      await store.saveOriginal(_doc('act', 'old', [_span(0, 1, 'old')]));
      await expectLater(
        store.carry(
          documents: [
            _doc('act', 'other', [_span(0, 1, 'theirs')]),
          ],
          retire: const [('act', 'old')],
        ),
        throwsStateError,
      );
      final other = await store.load(activityId: 'act', segmentId: 'other');
      expect(other.document!.textAt(0), 'mine');
      final old = await store.load(activityId: 'act', segmentId: 'old');
      expect(old.state, TranscriptLoadState.ready);
    });
  });

  group('FR-TRN-08 P2-09b transcripts survive a permanent trim', () {
    late TestData t;
    late Directory root;
    late Activity activity;
    late RecordingSegment seg1;
    late RecordingSegment seg2;
    final start = DateTime.utc(2026, 11, 4, 9, 30);

    Future<RecordingSegment> addSegment(
      int sequence,
      int startMs,
      int samples,
    ) async {
      final path = MediaPaths.segment(
        activity.conferenceId,
        activity.id,
        sequence,
      );
      final file = MediaPaths.resolve(root, path);
      await file.parent.create(recursive: true);
      await writeMp4Fixture(file, samples: samples);
      final at = start.add(Duration(milliseconds: startMs));
      final s = await t.media.startSegment(
        activityId: activity.id,
        filePath: path,
        requestedProfile: RecordingProfile.balanced,
        codec: 'aac_lc',
        container: 'm4a',
        channelCount: 1,
        sampleRateHz: 48000,
        requestedBitrateBps: 64000,
        startUtc: at,
      );
      final ms = (samples * 1024 * 1000 / 48000).round();
      return t.media.finaliseSegment(
        s.id,
        endUtc: at.add(Duration(milliseconds: ms)),
        endReason: SegmentEndReason.userStop,
        durationMs: ms,
        bytes: file.lengthSync(),
        sha256: 'f' * 64,
      );
    }

    PermanentTrimService service(TranscriptStore store) => PermanentTrimService(
      activities: t.activities,
      media: t.media,
      cuts: t.cuts,
      trimmer: const Mp4SampleTrimmer(),
      mediaRoot: () async => root,
      newId: t.ids.call,
      transcripts: TranscriptCarrier(store: () async => store, media: t.media),
    );

    late TranscriptDocument original;

    setUp(() async {
      t = TestData(start: start);
      root = await Directory.systemTemp.createTemp('transcript_trim_');
      final conference = await t.conference();
      activity = await t.activity(conference.id, title: 'Keynote');
      // 0 to 10.03 s, a 2 s gap, then 12 to 18.0 s.
      seg1 = await addSegment(1, 0, 470);
      seg2 = await addSegment(2, 12000, 282);
      original = _doc(activity.id, seg1.id, [
        _span(500, 1500, 'intro'),
        _span(1800, 2500, 'across the start cut'),
        _span(2500, 3500, 'kept a'),
        _span(4500, 5500, 'middle'),
        _span(6200, 7000, 'kept b'),
        _span(7800, 8200, 'across the end cut'),
        _span(9000, 9500, 'outro'),
      ]);
      final store = TranscriptStore(root);
      await store.saveOriginal(original);
      await store.saveCorrections(
        activityId: activity.id,
        segmentId: seg1.id,
        corrections: {2: 'Kept A', 4: 'Kept B', 6: 'Outro'},
      );
      await store.saveOriginal(
        _doc(activity.id, seg2.id, [
          _span(1000, 2000, 'second recording'),
        ], offset: const Duration(seconds: 12)),
      );
      // Cuts at the start, in the middle and at the end of the first
      // recording.
      await t.cuts.add(activity.id, startOffsetMs: 0, endOffsetMs: 2000);
      await t.cuts.add(activity.id, startOffsetMs: 4000, endOffsetMs: 6000);
      await t.cuts.add(activity.id, startOffsetMs: 8000, endOffsetMs: 10100);
    });

    tearDown(() async {
      await t.close();
      await root.delete(recursive: true);
    });

    test(
      'FR-TRN-08 P2-09b cuts at the start, middle and end: lines in '
      'removed audio go, the rest follow their piece with corrections',
      () async {
        final store = TranscriptStore(root);
        final result = await service(store).apply(activity.id);

        expect(result.transcripts.carried, 1);
        expect(result.transcripts.hasProblem, isFalse);
        final rows = await t.media.segmentsFor(activity.id);
        expect(rows, hasLength(3));
        final (piece1, piece2) = (rows[0], rows[1]);
        expect(rows[2].id, seg2.id);

        final first = (await store.load(
          activityId: activity.id,
          segmentId: piece1.id,
        )).document!;
        expect(_lines(first), [(500, 1500, 'Kept A')]);
        expect(first.textAt(0, useCorrections: false), 'kept a');
        expect(first.segmentOffset, Duration.zero);
        final second = (await store.load(
          activityId: activity.id,
          segmentId: piece2.id,
        )).document!;
        expect(_lines(second), [(200, 1000, 'Kept B')]);
        expect(second.textAt(0, useCorrections: false), 'kept b');
        // Piece 2 starts at 6 s; the timeline now starts at 2 s.
        expect(second.segmentOffset, const Duration(seconds: 4));

        // The untouched recording keeps its text and moves 2 s earlier.
        final later = (await store.load(
          activityId: activity.id,
          segmentId: seg2.id,
        )).document!;
        expect(_lines(later), [(1000, 2000, 'second recording')]);
        expect(later.segmentOffset, const Duration(seconds: 10));

        // The old transcript is kept aside, not deleted, and is not listed.
        expect(
          (await store.load(activityId: activity.id, segmentId: seg1.id)).state,
          TranscriptLoadState.missing,
        );
        final kept = _superseded(root, activity.id).single;
        expect(kept.readAsStringSync(), contains('across the start cut'));
        expect(kept.readAsStringSync(), contains('Outro'));
        expect(
          (await store.listDocuments(activityId: activity.id))
              .map((d) => d.segmentId)
              .toSet(),
          {piece1.id, piece2.id, seg2.id},
        );
      },
    );

    test('FR-TRN-08 P2-09b when the transcript cannot be moved the trim '
        'still succeeds and the old transcript stays as it was', () async {
      final result = await service(_FailingStore(root)).apply(activity.id);

      expect(result.filesWritten, 2);
      expect(result.transcripts.notCarried, 1);
      expect(result.transcripts.hasProblem, isTrue);
      expect(await t.media.segmentsFor(activity.id), hasLength(3));
      final store = TranscriptStore(root);
      final old = (await store.load(
        activityId: activity.id,
        segmentId: seg1.id,
      )).document!;
      expect(_lines(old), _lines(original.withCorrections(old.corrections)));
      expect(old.corrections, {2: 'Kept A', 4: 'Kept B', 6: 'Outro'});
      expect(_superseded(root, activity.id), isEmpty);
    });

    test('FR-TRN-08 P2-09b an unreadable transcript store never blocks the '
        'trim', () async {
      final svc = PermanentTrimService(
        activities: t.activities,
        media: t.media,
        cuts: t.cuts,
        trimmer: const Mp4SampleTrimmer(),
        mediaRoot: () async => root,
        newId: t.ids.call,
        transcripts: TranscriptCarrier(
          store: () async => throw const FileSystemException('no folder'),
          media: t.media,
        ),
      );
      final result = await svc.apply(activity.id);
      expect(result.filesWritten, 2);
      expect(result.transcripts.unchecked, isTrue);
      expect(
        (await TranscriptStore(
          root,
        ).load(activityId: activity.id, segmentId: seg1.id)).state,
        TranscriptLoadState.ready,
      );
    });
  });

  group('FR-TRN-08 P2-09b transcripts survive a split', () {
    late TestData t;
    late SampleConference sample;
    late Directory root;
    late TranscriptStore store;
    late List<RecordingSegment> segments;

    ActivitySplitter splitter() => ActivitySplitter(
      activities: t.activities,
      mediaRoot: () async => root,
      transcripts: TranscriptCarrier(store: () async => store, media: t.media),
    );

    setUp(() async {
      t = TestData();
      // Keynote: 0:00 to 10:00, call 10:00 to 13:00, 13:00 to 20:00.
      sample = await SampleConference.build(t);
      root = await Directory.systemTemp.createTemp('transcript_split_');
      store = TranscriptStore(root);
      segments = await t.media.segmentsFor(sample.keynote.id);
      final id = sample.keynote.id;
      await store.saveOriginal(
        _doc(id, segments[0].id, [
          _span(1 * _min, 1 * _min + 2000, 'opening'),
          _span(5 * _min - 2000, 5 * _min + 1000, 'before the split'),
          _span(5 * _min - 500, 5 * _min + 2000, 'after the split'),
          _span(7 * _min, 7 * _min + 2000, 'data mesh'),
        ]),
      );
      await store.saveCorrections(
        activityId: id,
        segmentId: segments[0].id,
        corrections: {0: 'Opening', 3: 'Data Mesh'},
      );
      await store.saveOriginal(
        _doc(id, segments[1].id, [
          _span(10000, 12000, 'questions'),
        ], offset: const Duration(minutes: 13)),
      );
    });

    tearDown(() async {
      await t.close();
      await root.delete(recursive: true);
    });

    test('FR-TRN-08 P2-09b a split inside a line divides the shared '
        'recording\'s lines by where their audio is', () async {
      final id = sample.keynote.id;
      final result = await splitter().split(id, splitOffsetMs: 5 * _min);
      expect(result.transcripts.carried, 2);
      expect(result.transcripts.hasProblem, isFalse);
      final copy = result.segmentMoves[segments[0].id]!;

      final first = (await store.load(
        activityId: id,
        segmentId: segments[0].id,
      )).document!;
      expect(_lines(first), [
        (1 * _min, 1 * _min + 2000, 'Opening'),
        (5 * _min - 2000, 5 * _min + 1000, 'before the split'),
      ]);
      expect(first.textAt(0, useCorrections: false), 'opening');

      final second = (await store.load(
        activityId: result.part2.id,
        segmentId: copy,
      )).document!;
      expect(_lines(second), [
        (5 * _min - 500, 5 * _min + 2000, 'after the split'),
        (7 * _min, 7 * _min + 2000, 'Data Mesh'),
      ]);
      expect(second.textAt(1, useCorrections: false), 'data mesh');
      expect(second.segmentOffset, Duration.zero);

      // The later recording moved whole, with its place in the new activity.
      final moved = (await store.load(
        activityId: result.part2.id,
        segmentId: segments[1].id,
      )).document!;
      expect(_lines(moved), [(10000, 12000, 'questions')]);
      expect(moved.segmentOffset, const Duration(minutes: 13));
      expect(
        (await store.load(activityId: id, segmentId: segments[1].id)).state,
        TranscriptLoadState.missing,
      );

      // Both old versions are kept aside.
      expect(_superseded(root, id), hasLength(2));
    });

    test('FR-TRN-08 P2-09b a split between lines, in the gap, moves only '
        'the later recording\'s transcript', () async {
      final id = sample.keynote.id;
      final result = await splitter().split(id, splitOffsetMs: 11 * _min);
      expect(result.transcripts.carried, 1);

      final first = (await store.load(
        activityId: id,
        segmentId: segments[0].id,
      )).document!;
      expect(first.machineSpans, hasLength(4));
      expect(first.corrections, {0: 'Opening', 3: 'Data Mesh'});

      final moved = (await store.load(
        activityId: result.part2.id,
        segmentId: segments[1].id,
      )).document!;
      expect(_lines(moved), [(10000, 12000, 'questions')]);
      // The new activity's timeline starts at this recording.
      expect(moved.segmentOffset, Duration.zero);
      expect(_superseded(root, id), hasLength(1));
    });

    test('FR-TRN-08 P2-09b when the transcript cannot be moved the split '
        'still succeeds and the old transcript stays', () async {
      final id = sample.keynote.id;
      final result = await ActivitySplitter(
        activities: t.activities,
        mediaRoot: () async => root,
        transcripts: TranscriptCarrier(
          store: () async => _FailingStore(root),
          media: t.media,
        ),
      ).split(id, splitOffsetMs: 5 * _min);

      expect(result.transcripts.notCarried, 2);
      expect(await t.media.segmentsFor(result.part2.id), hasLength(2));
      final first = (await store.load(
        activityId: id,
        segmentId: segments[0].id,
      )).document!;
      expect(first.machineSpans, hasLength(4));
      expect(
        (await store.load(activityId: id, segmentId: segments[1].id)).state,
        TranscriptLoadState.ready,
      );
    });
  });
}
