import 'dart:convert';
import 'dart:io';

import 'package:attenlume/data/transcription/transcript_store.dart';
import 'package:attenlume/domain/transcription/transcript.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/transcription/transcript_test.dart' show sampleDocument;

void main() {
  late Directory root;
  late TranscriptStore store;
  File documentFile() =>
      File('${root.path}/transcripts-v1/activity-1/segment-1.json');
  Future<TranscriptLoadResult> load() =>
      store.load(activityId: 'activity-1', segmentId: 'segment-1');

  setUp(() async {
    root = await Directory.systemTemp.createTemp('attenlume_transcript_test_');
    store = TranscriptStore(root);
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'FR-TRN-08 completed original and edits persist through store recreation',
    () async {
      expect((await load()).state, TranscriptLoadState.missing);
      await store.saveOriginal(sampleDocument());
      await store.saveCorrections(
        activityId: 'activity-1',
        segmentId: 'segment-1',
        corrections: {0: 'Corrected text'},
      );
      store = TranscriptStore(root);
      final saved = (await load()).document!;
      expect(saved.machineSpans[0].text, contains('Caf\u00e9'));
      expect(saved.corrections, {0: 'Corrected text'});
      expect(
        utf8.decode(await documentFile().readAsBytes()),
        contains('Caf\u00e9'),
      );
      expect(
        root
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.contains('.tmp-')),
        isEmpty,
      );
    },
  );

  test('FR-TRN-06 retry keeps completed text and corrections; different machine result cannot overwrite it', () async {
    await store.saveOriginal(sampleDocument());
    await store.saveCorrections(
      activityId: 'activity-1',
      segmentId: 'segment-1',
      corrections: {1: 'Keep this edit'},
    );
    await store.saveOriginal(sampleDocument());
    expect((await load()).document!.corrections, {1: 'Keep this edit'});
    final different = TranscriptDocument(
      activityId: 'activity-1',
      segmentId: 'segment-1',
      createdAt: DateTime.now(),
      machineSpans: [
        TranscriptSpan(
          start: Duration.zero,
          end: const Duration(seconds: 1),
          text: 'Different run',
        ),
      ],
    );
    await expectLater(store.saveOriginal(different), throwsStateError);
    expect((await load()).document!.corrections, {1: 'Keep this edit'});
  });

  test('FR-TRN-08 concurrent store instances serialize correction writes atomically', () async {
    await store.saveOriginal(sampleDocument());
    final other = TranscriptStore(root);
    await Future.wait([
      store.saveCorrections(
        activityId: 'activity-1',
        segmentId: 'segment-1',
        corrections: {0: 'first'},
      ),
      other.saveCorrections(
        activityId: 'activity-1',
        segmentId: 'segment-1',
        corrections: {1: 'second'},
      ),
    ]);
    expect((await load()).document!.corrections, {1: 'second'});
    expect((await load()).document!.machineSpans.length, 2);
  });

  test('FR-TRN-08 failed corrections preserve original bytes and unrelated media/model files', () async {
    final audio = File('${root.path}/original.m4a')
      ..writeAsBytesSync([1, 2, 3]);
    final model = File('${root.path}/model.bin')..writeAsBytesSync([4, 5]);
    await store.saveOriginal(sampleDocument());
    final previous = await documentFile().readAsBytes();
    await expectLater(
      store.saveCorrections(
        activityId: 'activity-1',
        segmentId: 'segment-1',
        corrections: {100: 'invalid'},
      ),
      throwsArgumentError,
    );
    expect(await documentFile().readAsBytes(), previous);
    expect(await audio.readAsBytes(), [1, 2, 3]);
    await model
        .delete(); // Model removal has no transcript/audio lifecycle effect.
    expect((await load()).state, TranscriptLoadState.ready);
    expect(await audio.readAsBytes(), [1, 2, 3]);
  });

  test(
    'FR-TRN-08 corrupt, wrong-identity and unsupported data remain untouched',
    () async {
      await documentFile().parent.create(recursive: true);
      final valid = sampleDocument().toJson();
      final cases = <List<int>>[
        utf8.encode('{broken'),
        [0xff],
        utf8.encode('[]'),
        utf8.encode(jsonEncode({...valid, 'version': 99})),
        utf8.encode(jsonEncode({...valid, 'activityId': 'other-activity'})),
        utf8.encode(
          jsonEncode({
            ...valid,
            'machineSpans': [
              {'startMs': -1, 'endMs': 0, 'text': 'invalid'},
            ],
          }),
        ),
      ];
      for (final bytes in cases) {
        await documentFile().writeAsBytes(bytes);
        expect((await load()).state, TranscriptLoadState.corrupt);
        await expectLater(
          store.saveOriginal(sampleDocument()),
          throwsStateError,
        );
        expect(await documentFile().readAsBytes(), bytes);
      }
    },
  );

  test(
    'FR-TRN-08 path traversal and directory substitutions cannot touch media',
    () async {
      await expectLater(
        store.load(activityId: '../escape', segmentId: 'segment-1'),
        throwsArgumentError,
      );
      await documentFile().create(recursive: true);
      await documentFile().delete();
      await Directory(documentFile().path).create();
      expect((await load()).state, TranscriptLoadState.unavailable);
      await expectLater(store.saveOriginal(sampleDocument()), throwsStateError);
    },
  );

  test('FR-TRN-08 interrupted sibling temporary file is never treated as completed output', () async {
    await documentFile().parent.create(recursive: true);
    final incomplete = File('${documentFile().path}.tmp-interrupted');
    await incomplete.writeAsString('{partial');
    expect((await load()).state, TranscriptLoadState.missing);
    await store.saveOriginal(sampleDocument());
    expect((await load()).state, TranscriptLoadState.ready);
    expect(await incomplete.readAsString(), '{partial');
  });
  test(
    'FR-TRN-08 discovery reloads ready documents and exposes corrupt entries',
    () async {
      await store.saveOriginal(sampleDocument());
      await File('${documentFile().parent.path}/corrupt.json')
          .writeAsString('{broken');
      await File('${documentFile().parent.path}/pending.json.tmp')
          .writeAsString('{partial');
      await File('${documentFile().parent.path}/not-a-record.txt')
          .writeAsString('ignored');
      store = TranscriptStore(root);
      final found = await store.listDocuments();
      expect(found.single.segmentId, 'segment-1');
      expect(await store.listDocuments(activityId: 'other-activity'), isEmpty);
      final inspected = await store.inspectDocuments(activityId: 'activity-1');
      expect(inspected.keys, ['activity-1/corrupt', 'activity-1/segment-1']);
      expect(
        inspected['activity-1/corrupt']!.state,
        TranscriptLoadState.corrupt,
      );
      expect(
        inspected['activity-1/segment-1']!.state,
        TranscriptLoadState.ready,
      );
    },
  );
}
