import 'dart:convert';
import 'dart:io';

import 'package:attenlume/data/filesystem/export_writer.dart';
import 'package:attenlume/data/filesystem/folder_export.dart';
import 'package:attenlume/data/filesystem/media_paths.dart';
import 'package:attenlume/data/transcription/transcript_store.dart';
import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/models/media.dart';
import 'package:attenlume/domain/services/export_documents.dart';
import 'package:attenlume/domain/services/export_import_service.dart';
import 'package:attenlume/domain/services/export_service.dart';
import 'package:attenlume/domain/services/export_transcript.dart';
import 'package:attenlume/domain/transcription/transcript.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fixtures/fake_free_space_probe.dart';
import '../fixtures/fixtures.dart';
import '../fixtures/mp4_fixture.dart';

Future<ExportWriteResult> _inlineWriter(
  ExportWritePlan plan, {
  void Function(ExportWriteProgress progress)? onProgress,
  Future<void>? cancel,
}) => writeExport(plan, onProgress: onProgress);

TranscriptSpan _span(int startMs, int endMs, String text) => TranscriptSpan(
  start: Duration(milliseconds: startMs),
  end: Duration(milliseconds: endMs),
  text: text,
);

void main() {
  late TestData t;
  late Directory temp;
  late Directory mediaRoot;
  late Directory dest;
  late TranscriptStore store;
  late ExportService service;

  setUp(() async {
    t = TestData();
    temp = await Directory.systemTemp.createTemp('export_transcript_test');
    mediaRoot = Directory(p.join(temp.path, 'old', 'media'))
      ..createSync(recursive: true);
    dest = Directory(p.join(temp.path, 'dest'))..createSync();
    store = TranscriptStore(Directory(p.join(temp.path, 'old')));
    service = ExportService(
      conferences: t.conferences,
      activities: t.activities,
      media: t.media,
      cuts: t.cuts,
      jobs: t.exports,
      mediaRoot: () async => mediaRoot,
      tempRoot: () async => Directory(p.join(temp.path, 'cache')),
      freeSpace: FakeFreeSpaceProbe(64 << 30),
      reserveBytes: 0,
      writer: _inlineWriter,
      clock: t.clock.call,
      transcriptStore: () async => store,
    );
  });

  tearDown(() async {
    await t.close();
    await temp.delete(recursive: true);
  });

  /// A finalised segment whose file exists; [mp4] writes a real AAC-in-MP4
  /// fixture (10 027 ms) so a trimmed copy can be made.
  Future<RecordingSegment> segment(
    Activity a,
    DateTime start, {
    bool mp4 = false,
  }) async {
    final s = await t.media.startSegment(
      activityId: a.id,
      filePath: 'pending.m4a',
      requestedProfile: RecordingProfile.balanced,
      codec: 'aac_lc',
      container: 'm4a',
      channelCount: 1,
      sampleRateHz: 48000,
      requestedBitrateBps: 48000,
      startUtc: start,
    );
    final rel = MediaPaths.segment(a.conferenceId, a.id, s.sequence);
    final file = MediaPaths.resolve(mediaRoot, rel);
    await file.parent.create(recursive: true);
    if (mp4) {
      await writeMp4Fixture(file);
    } else {
      await file.writeAsBytes(
        List.generate(4000 + s.sequence, (i) => (i * 7 + s.sequence) % 251),
      );
    }
    return t.media.finaliseSegment(
      s.id,
      endUtc: start.add(const Duration(seconds: 10)),
      endReason: SegmentEndReason.userStop,
      filePath: rel,
      durationMs: mp4 ? 10027 : 10000,
      bytes: file.lengthSync(),
    );
  }

  /// Saves the machine output for [s], then the owner's [corrections].
  Future<void> transcribe(
    Activity a,
    RecordingSegment s,
    List<TranscriptSpan> spans, {
    Map<int, String> corrections = const {},
    Duration offset = Duration.zero,
  }) async {
    await store.saveOriginal(
      TranscriptDocument(
        activityId: a.id,
        segmentId: s.id,
        machineSpans: spans,
        createdAt: DateTime.utc(2026, 11, 4, 12),
        segmentOffset: offset,
        modelId: 'tiny-en',
      ),
    );
    if (corrections.isNotEmpty) {
      await store.saveCorrections(
        activityId: a.id,
        segmentId: s.id,
        corrections: corrections,
      );
    }
  }

  Future<ExportOutcome> export(
    String conferenceId, {
    ExportContent content = ExportContent.everything,
    ExportAudioMode audioMode = ExportAudioMode.original,
    bool includePrivate = false,
    ExportFormat format = ExportFormat.folder,
    String sub = 'out',
  }) => service.run(
    ExportRequest(
      conferenceId: conferenceId,
      content: content,
      audioMode: audioMode,
      includePrivate: includePrivate,
      format: format,
    ),
    destinationParent: (Directory(
      p.join(dest.path, sub),
    )..createSync(recursive: true)).path,
  );

  /// Paths of every file in a folder export, relative to its root.
  List<String> files(ExportOutcome out) => [
    for (final f in Directory(
      out.outputPath,
    ).listSync(recursive: true).whereType<File>())
      p.posix.joinAll(p.split(p.relative(f.path, from: out.outputPath))),
  ]..sort();

  String read(ExportOutcome out, String rel) =>
      File(p.join(out.outputPath, rel)).readAsStringSync();

  /// Every text file of the export, joined.
  String textOf(ExportOutcome out) => [
    for (final f in files(out))
      if (!f.endsWith('.m4a') && !f.endsWith('.jpg')) read(out, f),
  ].join();

  String folderOf(ExportOutcome out, String title) =>
      files(out)
          .firstWhere((f) => f.contains(title) && f.endsWith('activity.json'))
          .replaceFirst('/activity.json', '');

  /// A talk recorded in two parts with a 20 s gap between them, both
  /// transcribed; one line was corrected by the owner.
  Future<(String, Activity, RecordingSegment, RecordingSegment)>
  twoPartTalk() async {
    final c = await t.conference();
    final a = await t.activity(c.id, title: 'Data products');
    final start = DateTime.utc(2026, 11, 4, 9);
    final s1 = await segment(a, start);
    final s2 = await segment(a, start.add(const Duration(seconds: 30)));
    await transcribe(
      a,
      s1,
      [
        _span(0, 2000, 'Welcome to Samlytics Conference 2026.'),
        _span(2500, 4000, 'Samlytics Data Services builds data prodcts.'),
      ],
      corrections: {1: 'Samlytics Data Services builds data products.'},
    );
    await transcribe(a, s2, [
      _span(1000, 2500, 'After the break we continue.'),
    ], offset: const Duration(seconds: 30));
    return (c.id, a, s1, s2);
  }

  group('FR-TRN-08 transcripts in exports', () {
    test('FR-TRN-08 FR-EXP-06 transcript.txt, transcript.md and '
        'transcript.json are written and listed in checksums.sha256', () async {
      final (id, _, _, _) = await twoPartTalk();
      final out = await export(id);
      final folder = folderOf(out, 'data-products');
      final all = files(out);
      for (final name in [
        transcriptTextFileName,
        transcriptMarkdownFileName,
        transcriptJsonFileName,
      ]) {
        expect(all, contains('$folder/$name'));
        expect(read(out, checksumFileName), contains('  $folder/$name\n'));
      }
      expect(await verifyChecksums(Directory(out.outputPath)), isEmpty);

      // UTF-8 plain text with CRLF, the corrected text and the label.
      final bytes = File(p.join(out.outputPath, folder, transcriptTextFileName))
          .readAsBytesSync();
      final txt = utf8.decode(bytes);
      expect(txt, contains(transcriptMachineLabel));
      expect(
        txt,
        contains('Samlytics Data Services builds data products.\r\n'),
      );
      expect(txt, isNot(contains('prodcts')));
      expect(txt.replaceAll('\r\n', ''), isNot(contains('\n')));

      // The original machine output stays available (FR-TRN-08).
      final md = read(out, '$folder/$transcriptMarkdownFileName');
      expect(md, contains('Machine-generated'));
      expect(md, contains('*(corrected)*'));
      expect(
        md,
        contains(
          'Original machine text: Samlytics Data Services '
          'builds data prodcts.',
        ),
      );
      final json =
          jsonDecode(read(out, '$folder/$transcriptJsonFileName')) as Map;
      expect(json['machine_generated'], isTrue);
      final lines = [
        for (final part in json['parts'] as List)
          ...(part as Map)['lines'] as List,
      ];
      expect(
        lines[1],
        containsPair(
          'machine_text',
          'Samlytics Data Services builds data prodcts.',
        ),
      );
      expect(lines[1], containsPair('corrected', true));
    });

    test('FR-TRN-08 FR-EXP-08 the manifest, timeline, README, activity.md '
        'and prompts list the transcript without embedding it', () async {
      final (id, a, _, _) = await twoPartTalk();
      final out = await export(id);
      final folder = folderOf(out, 'data-products');
      final manifest = jsonDecode(read(out, 'conference.json')) as Map;
      final entry = (manifest['activities'] as List).single as Map;
      expect(entry['files'], containsPair('transcript_md', 'transcript.md'));
      expect(entry['files'], containsPair('transcript_txt', 'transcript.txt'));
      expect(entry['transcript'], containsPair('machine_generated', true));
      expect(entry['transcript'], containsPair('line_count', 3));
      expect(entry['transcript'], containsPair('corrected_count', 1));

      final timeline = read(out, 'timeline.csv');
      expect(
        timeline,
        contains('${a.id},Data products,transcript,$folder/transcript.md,'),
      );
      expect(read(out, 'README_START_HERE.md'), contains('`transcript.md`'));
      expect(read(out, '$folder/activity.md'), contains('## Transcript'));
      final prompt = read(out, 'analysis_prompt.md');
      expect(prompt, contains('machine-generated'));
      expect(out.analysisPrompt, prompt);
      // Copy AI prompt refers to the transcript; it does not carry it.
      expect(prompt, isNot(contains('builds data products')));
    });

    test('FR-TRN-08 gaps: times count from the first recording on the '
        'activity timeline and from each file in the audio', () async {
      final (id, _, _, _) = await twoPartTalk();
      final out = await export(id);
      final folder = folderOf(out, 'data-products');
      final md = read(out, '$folder/$transcriptMarkdownFileName');
      expect(md, contains('## Part 1: `audio/segment-001.m4a`'));
      expect(md, contains('## Part 2: `audio/segment-002.m4a`'));
      expect(
        md,
        contains(
          '*Gap: nothing recorded from activity 00:00:10 to '
          '00:00:30.*',
        ),
      );
      // 1 s into part 2, which starts 30 s after part 1.
      expect(
        md,
        contains(
          '- **[00:00:01 - 00:00:02]** (activity 00:00:31) '
          'After the break we continue.',
        ),
      );
      final json =
          jsonDecode(read(out, '$folder/$transcriptJsonFileName')) as Map;
      final part2 = (json['parts'] as List)[1] as Map;
      expect(part2['audio_file'], 'audio/segment-002.m4a');
      final line = (part2['lines'] as List).single as Map;
      expect(line['audio_start_ms'], 1000);
      expect(line['activity_start_ms'], 31000);
      expect(json['gaps'], [
        {'start_ms': 10000, 'end_ms': 30000},
      ]);
    });

    test(
      'FR-TRN-08 FR-EXP-01 audio-only and photos-only exports hold no '
      'transcript; notes-and-details exports hold it with activity times',
      () async {
        final (id, a, _, _) = await twoPartTalk();
        final photoId = t.ids();
        final photoRel = MediaPaths.photo(id, a.id, photoId);
        final photo = MediaPaths.resolve(mediaRoot, photoRel);
        await photo.parent.create(recursive: true);
        await photo.writeAsBytes(List.filled(900, 5));
        await t.media.addPhoto(
          id: photoId,
          activityId: a.id,
          filePath: photoRel,
          takenUtc: DateTime.utc(2026, 11, 4, 9, 0, 3),
          source: PhotoSource.inApp,
        );
        for (final content in [
          ExportContent.audioOnly,
          ExportContent.photosOnly,
        ]) {
          final out = await export(id, content: content, sub: content.key);
          expect(
            files(out).where((f) => f.contains('transcript')),
            isEmpty,
            reason: content.key,
          );
          expect(read(out, 'timeline.csv'), isNot(contains(',transcript,')));
        }
        final out = await export(id, content: ExportContent.textOnly);
        final folder = folderOf(out, 'data-products');
        final md = read(out, '$folder/$transcriptMarkdownFileName');
        expect(md, contains('This export has no audio.'));
        expect(md, contains('## Part 2 (audio not in this export)'));
        expect(md, contains('- **[00:00:31 - 00:00:32]** After the break'));
      },
    );

    test('FR-TRN-09 FR-EXP-10 a private activity\'s transcript is left out '
        'unless private items are included', () async {
      final c = await t.conference();
      final private = await t.activities.create(
        conferenceId: c.id,
        typeId: builtinTypeId('business_conversation'),
        title: 'Supplier chat',
        isPrivate: true,
      );
      final s = await segment(private, DateTime.utc(2026, 11, 4, 13));
      await transcribe(private, s, [_span(0, 1000, 'Private pricing words.')]);
      final public = await t.activity(c.id, title: 'Open session');
      await segment(public, DateTime.utc(2026, 11, 4, 14));

      final out = await export(c.id);
      final everything = textOf(out);
      expect(files(out).where((f) => f.contains('transcript')), isEmpty);
      expect(everything, isNot(contains('Private pricing words')));

      final withPrivate = await export(
        c.id,
        includePrivate: true,
        sub: 'private',
      );
      final folder = folderOf(withPrivate, 'supplier-chat');
      expect(
        read(withPrivate, '$folder/$transcriptTextFileName'),
        contains('Private pricing words.'),
      );
      expect(await verifyChecksums(Directory(withPrivate.outputPath)), isEmpty);
    });

    test(
      'FR-TRN-08 a transcript of a replaced recording is not exported',
      () async {
        final c = await t.conference();
        final a = await t.activity(c.id, title: 'Replaced');
        await segment(a, DateTime.utc(2026, 11, 4, 9));
        // Saved against a recording ID the activity no longer has.
        await store.saveOriginal(
          TranscriptDocument(
            activityId: a.id,
            segmentId: 'aaaaaaaa-0000-4000-8000-0000000fffff',
            machineSpans: [_span(0, 1000, 'Old audio words.')],
            createdAt: DateTime.utc(2026, 11, 4, 12),
          ),
        );
        final out = await export(c.id);
        expect(files(out).where((f) => f.contains('transcript')), isEmpty);
      },
    );
  });

  group('FR-TRN-08 FR-EXP-03 transcripts follow cuts', () {
    /// One 10 027 ms recording with a cut from 2 s to 4 s and four lines:
    /// before the cut, touching it, inside it and after it.
    Future<(String, Activity, RecordingSegment)> cutTalk() async {
      final c = await t.conference();
      final a = await t.activity(c.id, title: 'Cut talk');
      final s = await segment(a, DateTime.utc(2026, 11, 4, 9), mp4: true);
      await t.cuts.add(a.id, startOffsetMs: 2000, endOffsetMs: 4000);
      await transcribe(a, s, [
        _span(0, 1500, 'Before the cut.'),
        _span(1800, 2500, 'Touches the cut.'),
        _span(2500, 3500, 'Inside the cut.'),
        _span(5000, 6000, 'After the cut.'),
      ]);
      return (c.id, a, s);
    }

    test('FR-TRN-08 trimmed copies: cut text is removed and later times '
        'shift to match the trimmed file', () async {
      final (id, _, _) = await cutTalk();
      final out = await export(id, audioMode: ExportAudioMode.trimmed);
      final folder = folderOf(out, 'cut-talk');
      final all = textOf(out);
      expect(all, isNot(contains('Touches the cut')));
      expect(all, isNot(contains('Inside the cut')));

      final md = read(out, '$folder/$transcriptMarkdownFileName');
      expect(
        md,
        contains('## Part 1: `audio/segment-001-trimmed.m4a` (trimmed copy)'),
      );
      expect(
        md,
        contains(
          '- **[00:00:00 - 00:00:01]** (activity 00:00:00) '
          'Before the cut.',
        ),
      );
      // 5 s on the original, 3 s into the trimmed copy (2 s cut).
      expect(
        md,
        contains(
          '- **[00:00:03 - 00:00:04]** (activity 00:00:05) '
          'After the cut.',
        ),
      );
      expect(md, contains('2 lines removed'));
      expect(
        read(out, '$folder/$transcriptTextFileName'),
        contains('[2 lines removed'),
      );

      final json =
          jsonDecode(read(out, '$folder/$transcriptJsonFileName')) as Map;
      final part = (json['parts'] as List).single as Map;
      expect(part['trimmed'], isTrue);
      expect(part['removed_count'], 2);
      final after = (part['lines'] as List).last as Map;
      expect(after['audio_start_ms'], 3000);
      expect(after['audio_end_ms'], 4000);
      expect(after['activity_start_ms'], 5000);

      // The trimmed file is the source minus the cut, so the shifted time
      // is inside it.
      final activityJson =
          jsonDecode(read(out, '$folder/activity.json')) as Map;
      final seg = (activityJson['segments'] as List).single as Map;
      expect(seg['kept_ranges_ms'], [
        [0, 2000],
        [4000, 10027],
      ]);
      expect(seg['duration_ms'] as int, greaterThan(4000));
      expect(await verifyChecksums(Directory(out.outputPath)), isEmpty);
    });

    test('FR-TRN-08 originals keep every line at its original time and mark '
        'the parts marked to skip', () async {
      final (id, _, _) = await cutTalk();
      for (final mode in [
        ExportAudioMode.original,
        ExportAudioMode.originalWithCuts,
      ]) {
        final out = await export(id, audioMode: mode, sub: mode.key);
        final folder = folderOf(out, 'cut-talk');
        final md = read(out, '$folder/$transcriptMarkdownFileName');
        expect(
          md,
          contains('## Part 1: `audio/segment-001.m4a`'),
          reason: mode.key,
        );
        expect(
          md,
          contains(
            'Parts marked to skip (activity times): 00:00:02 '
            'to 00:00:04.',
          ),
        );
        expect(
          md,
          contains(
            '- **[00:00:02 - 00:00:03]** (activity 00:00:02) '
            'Inside the cut. *(in a part marked to skip)*',
          ),
        );
        expect(
          md,
          contains(
            '- **[00:00:05 - 00:00:06]** (activity 00:00:05) '
            'After the cut.\n',
          ),
        );
        final json =
            jsonDecode(read(out, '$folder/$transcriptJsonFileName')) as Map;
        final lines = ((json['parts'] as List).single as Map)['lines'] as List;
        expect(lines, hasLength(4));
        expect(
          [for (final l in lines) (l as Map)['in_cut']],
          [false, true, true, false],
        );
      }
    });

    test('FR-TRN-08 notes-and-details exports leave cut speech out', () async {
      final (id, _, _) = await cutTalk();
      final out = await export(id, content: ExportContent.textOnly);
      final folder = folderOf(out, 'cut-talk');
      final txt = read(out, '$folder/$transcriptTextFileName');
      expect(txt, contains('Before the cut.'));
      expect(txt, contains('After the cut.'));
      expect(txt, isNot(contains('Inside the cut')));
      expect(txt, isNot(contains('Touches the cut')));
    });

    test('FR-TRN-08 a recording wholly cut from a trimmed export has no '
        'transcript text', () async {
      final c = await t.conference();
      final a = await t.activity(c.id, title: 'All cut');
      final s = await segment(a, DateTime.utc(2026, 11, 4, 9), mp4: true);
      await t.cuts.add(a.id, startOffsetMs: 0, endOffsetMs: 10027);
      await transcribe(a, s, [_span(0, 1000, 'Never shared words.')]);
      final out = await export(c.id, audioMode: ExportAudioMode.trimmed);
      final all = textOf(out);
      expect(all, isNot(contains('Never shared words')));
    });
  });

  group('FR-EXP-11 re-import of exports with transcripts', () {
    late TestData u;
    late Directory newMediaRoot;
    late TranscriptStore newStore;

    setUp(() {
      u = TestData();
      newMediaRoot = Directory(p.join(temp.path, 'new', 'media'))
        ..createSync(recursive: true);
      newStore = TranscriptStore(Directory(p.join(temp.path, 'new')));
    });

    tearDown(() => u.close());

    ExportImportService importer({bool withStore = true}) =>
        ExportImportService(
          db: u.db,
          activities: u.activities,
          mediaRoot: () async => newMediaRoot,
          freeSpace: FakeFreeSpaceProbe(64 << 30),
          reserveBytes: 0,
          clock: () => DateTime.utc(2026, 12, 1, 10),
          transcriptStore: withStore ? () async => newStore : null,
        );

    test('FR-EXP-11 FR-TRN-08 an export with transcripts restores them with '
        'the corrections and original machine text', () async {
      final (id, a, s1, s2) = await twoPartTalk();
      final out = await export(id);
      final service = importer();
      final prepared = await service.prepare(out.outputPath);
      expect(prepared.preview.canImport, isTrue);
      expect(prepared.preview.activities.single.transcriptLines, 3);
      final summary = await service.commit(prepared);
      expect(summary.transcripts, 2);
      expect(summary.warnings, isEmpty);

      // Nothing existed on the new device, so the IDs are kept.
      final restored = await newStore.listDocuments(activityId: a.id);
      expect(restored.map((d) => d.segmentId), [s1.id, s2.id]);
      final first = restored.first;
      expect(first.machineSpans.map((x) => x.text), [
        'Welcome to Samlytics Conference 2026.',
        'Samlytics Data Services builds data prodcts.',
      ]);
      expect(first.corrections, {
        1: 'Samlytics Data Services builds data products.',
      });
      expect(restored.last.segmentOffset, const Duration(seconds: 30));
      expect(
        restored.last.machineSpans.single.start,
        const Duration(seconds: 1),
      );
    });

    test('FR-EXP-11 FR-TRN-08 a trimmed export restores the transcript '
        'against the trimmed recording', () async {
      final c = await t.conference();
      final a = await t.activity(c.id, title: 'Cut talk');
      final s = await segment(a, DateTime.utc(2026, 11, 4, 9), mp4: true);
      await t.cuts.add(a.id, startOffsetMs: 2000, endOffsetMs: 4000);
      await transcribe(a, s, [
        _span(0, 1500, 'Before the cut.'),
        _span(2500, 3500, 'Inside the cut.'),
        _span(5000, 6000, 'After the cut.'),
      ]);
      final out = await export(c.id, audioMode: ExportAudioMode.trimmed);
      final service = importer();
      final summary = await service.commit(
        await service.prepare(out.outputPath),
      );
      expect(summary.transcripts, 1);
      final doc = (await newStore.listDocuments(activityId: a.id)).single;
      expect(doc.machineSpans.map((x) => x.text), [
        'Before the cut.',
        'After the cut.',
      ]);
      expect(doc.machineSpans.last.start, const Duration(seconds: 3));
    });

    test('FR-EXP-11 a notes-and-details export with transcripts imports '
        'without errors and says the transcript was not restored', () async {
      final (id, a, _, _) = await twoPartTalk();
      final out = await export(id, content: ExportContent.textOnly);
      final service = importer();
      final prepared = await service.prepare(out.outputPath);
      expect(prepared.preview.canImport, isTrue);
      expect(
        prepared.preview.warnings,
        contains(contains('transcript belongs to recordings that are not')),
      );
      final summary = await service.commit(prepared);
      expect(summary.activities, 1);
      expect(summary.transcripts, 0);
      expect(await newStore.listDocuments(activityId: a.id), isEmpty);
    });

    test('FR-EXP-11 an import without a transcript store still imports the '
        'recordings and reports the transcript', () async {
      final (id, _, _, _) = await twoPartTalk();
      final out = await export(id, format: ExportFormat.zip);
      final service = importer(withStore: false);
      final summary = await service.commit(
        await service.prepare(out.outputPath),
      );
      expect(summary.segments, 2);
      expect(summary.transcripts, 0);
      expect(summary.warnings, contains(contains('2 transcripts were not')));
    });

    test(
      'FR-EXP-11 a damaged transcript.json never blocks the import',
      () async {
        final (id, _, _, _) = await twoPartTalk();
        final out = await export(id);
        final folder = folderOf(out, 'data-products');
        // Replace it and fix its checksum, as a hand-edited export would.
        final file = File(
          p.join(out.outputPath, folder, transcriptJsonFileName),
        )..writeAsStringSync('{not json');
        final sums = File(p.join(out.outputPath, checksumFileName));
        final hash = await hashFileSha256(file);
        final lines = [
          for (final line in sums.readAsLinesSync())
            line.endsWith('  $folder/$transcriptJsonFileName')
                ? '$hash  $folder/$transcriptJsonFileName'
                : line,
        ];
        sums.writeAsStringSync('${lines.join('\n')}\n');
        final service = importer();
        final prepared = await service.prepare(out.outputPath);
        expect(prepared.preview.canImport, isTrue);
        expect(
          prepared.preview.warnings,
          contains(contains('transcript could not be read')),
        );
        final summary = await service.commit(prepared);
        expect(summary.segments, 2);
        expect(summary.transcripts, 0);
      },
    );
  });

  test('FR-TRN-08 the export schema version is unchanged, so older apps '
      'still import exports that hold transcripts', () {
    expect(exportSchemaVersion, 2);
    expect(transcriptJsonSchemaVersion, 1);
  });
}
