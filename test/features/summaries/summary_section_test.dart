import 'dart:async';
import 'dart:io';

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/ai/summary_store.dart';
import 'package:attenlume/domain/ai/session_summary.dart';
import 'package:attenlume/domain/ai/text_generation_engine.dart';
import 'package:attenlume/domain/transcription/transcript.dart';
import 'package:attenlume/features/summaries/summary_providers.dart';
import 'package:attenlume/features/summaries/summary_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fake_text_generation_engine.dart';

class _Model implements SummaryModelAccess {
  _Model(this.engine);

  final FakeTextGenerationEngine? engine;

  @override
  Future<String?> unavailableReason() async =>
      engine == null ? 'No model on this device.' : null;

  @override
  Future<TextGenerationEngine> open() async => engine!;
}

TranscriptDocument _transcript() => TranscriptDocument(
  activityId: 'a1',
  segmentId: 's1',
  createdAt: DateTime.utc(2026, 11, 3),
  machineSpans: [
    TranscriptSpan(
      start: Duration.zero,
      end: const Duration(seconds: 5),
      text: 'Welcome to Samlytics Conference 2026.',
    ),
    TranscriptSpan(
      start: const Duration(seconds: 90),
      end: const Duration(seconds: 95),
      text: 'Check row counts every morning.',
    ),
  ],
);

class _OpeningModel implements SummaryModelAccess {
  final opening = Completer<TextGenerationEngine>();
  int opens = 0;

  @override
  Future<String?> unavailableReason() async => null;

  @override
  Future<TextGenerationEngine> open() {
    opens++;
    return opening.future;
  }
}

class _CountingStore extends SummaryStore {
  _CountingStore(super.root);
  int saves = 0;

  @override
  Future<void> save(SessionSummary summary) async {
    saves++;
    await super.save(summary);
  }
}

void main() {
  late Directory root;
  late _CountingStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('summary_section_test_');
    store = _CountingStore(root);
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<List<int>> pump(
    WidgetTester tester, {
    List<TranscriptDocument>? transcripts,
    FakeTextGenerationEngine? engine,
    bool recording = false,
    bool Function()? isRecording,
    SummaryModelAccess? model,
    String? instructions,
  }) async {
    final played = <int>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          summaryTranscriptsProvider.overrideWithValue(
            (_) async => transcripts ?? [_transcript()],
          ),
          summaryStoreProvider.overrideWithValue(() async => store),
          summaryModelAccessProvider.overrideWithValue(model ?? _Model(engine)),
          summaryInstructionsProvider.overrideWithValue(
            () async => instructions,
          ),
          summaryBlockedByRecordingProvider.overrideWithValue(
            isRecording ?? () => recording,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: SummarySection(
                activityId: 'a1',
                title: 'Data quality for small teams',
                notesMd: null,
                bookmarks: const [],
                cuts: const [],
                canPlay: true,
                onPlayFrom: played.add,
                onOpenTranscription: () async {},
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    return played;
  }

  testWidgets('P3-02 without a transcript it points to transcription', (
    tester,
  ) async {
    await pump(tester, transcripts: const []);
    expect(
      find.textContaining('Transcribe this session first'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('summary-open-transcription')), findsOneWidget);
    expect(find.byKey(const Key('summary-create')), findsNothing);
  });

  testWidgets('P3-02 without a model it says why and offers nothing', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('No model on this device.'), findsOneWidget);
    expect(find.byKey(const Key('summary-create')), findsNothing);
  });

  testWidgets('P3-02 creates, saves and shows a grounded summary; a point '
      'plays its moment', (tester) async {
    final engine = FakeTextGenerationEngine(
      modelId: 'gemma-test',
      respond: (_) =>
          'SUMMARY: A talk on data habits.\n'
          'POINT [01:30]: Check row counts every morning.\n'
          'POINT [12:00]: Invented point.\n'
          'QUESTION: Which tool sends the alert?',
    );
    final played = await pump(tester, engine: engine);
    expect(find.textContaining('nothing is sent anywhere'), findsOneWidget);

    await tester.tap(find.byKey(const Key('summary-create')));
    await settle(tester);

    expect(find.text('A talk on data habits.'), findsOneWidget);
    expect(
      find.textContaining('Machine-generated by gemma-test'),
      findsOneWidget,
    );
    expect(find.text('Check row counts every morning.'), findsOneWidget);
    expect(find.text('Invented point.'), findsNothing);
    expect(find.text('• Which tool sends the alert?'), findsOneWidget);
    expect(engine.disposed, isTrue);

    await tester.tap(find.bySemanticsLabel('Play from 01:30'));
    expect(played, [90000]);

    final saved = await tester.runAsync(() => store.load('a1'));
    expect(saved!.points.single.at, const Duration(seconds: 90));
    expect(saved.leftOut, 1);
  });

  testWidgets('P3-02 a saved summary shows at once and says when the '
      'transcript changed since', (tester) async {
    await tester.runAsync(
      () => store.save(
        SessionSummary(
          activityId: 'a1',
          modelId: 'gemma-test',
          createdAt: DateTime.utc(2026, 11, 3),
          materialFingerprint: 'older',
          summary: 'Saved earlier.',
          points: [SummaryItem(text: 'Welcome.', at: Duration.zero)],
        ),
      ),
    );
    await pump(tester);
    expect(find.text('Saved earlier.'), findsOneWidget);
    expect(find.byKey(const Key('summary-stale')), findsOneWidget);
    expect(find.byKey(const Key('summary-copy')), findsOneWidget);
  });

  testWidgets('P3-12 the user\'s instructions reach the model; the default '
      'otherwise', (tester) async {
    for (final custom in ['Write for a CFO. Ask about cost.', null]) {
      final engine = FakeTextGenerationEngine(
        respond: (_) => 'SUMMARY: A talk.\nPOINT [01:30]: Check row counts.',
      );
      await pump(tester, engine: engine, instructions: custom);
      await tester.tap(find.byKey(const Key('summary-create')));
      await settle(tester);
      final system = engine.requests.single.system;
      if (custom != null) {
        expect(system, contains(custom));
        expect(system, isNot(contains('executive technology')));
      } else {
        expect(system, contains('executive technology and data strategy'));
      }
      // The grounding rule and answer format are always there.
      expect(system, contains('Use only the material given.'));
      expect(system, contains('exactly 3 QUESTION lines'));
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => store.delete('a1'));
    }
  });

  testWidgets('P3-02 waits while a recording runs', (tester) async {
    final engine = FakeTextGenerationEngine(respond: (_) => 'SUMMARY: x');
    await pump(tester, engine: engine, recording: true);
    await tester.tap(find.byKey(const Key('summary-create')));
    await settle(tester);
    expect(find.textContaining('A recording is running'), findsOneWidget);
    expect(engine.requests, isEmpty);
  });

  testWidgets('FR-AI-02 recording starts during verification: no inference', (
    tester,
  ) async {
    var recording = false;
    final model = _OpeningModel();
    final engine = FakeTextGenerationEngine(respond: (_) => 'SUMMARY: x');
    await pump(tester, model: model, isRecording: () => recording);
    await tester.tap(find.byKey(const Key('summary-create')));
    await tester.pump();
    expect(find.byKey(const Key('summary-progress')), findsOneWidget);
    expect(engine.requests, isEmpty);
    recording = true;
    model.opening.complete(engine);
    await settle(tester);
    expect(find.textContaining('A recording is running'), findsOneWidget);
    expect(engine.requests, isEmpty);
    expect(engine.disposed, isTrue);
    expect(store.saves, 0);
    expect(find.byKey(const Key('summary-create')), findsOneWidget);
  });

  testWidgets('FR-AI-02 pending model opening allows one engine and one save', (
    tester,
  ) async {
    final model = _OpeningModel();
    final engine = FakeTextGenerationEngine(respond: (_) => 'SUMMARY: x');
    await pump(tester, model: model);
    final create = find.byKey(const Key('summary-create'));
    // Two taps before a frame also exercise the synchronous operation guard.
    await tester.tap(create);
    await tester.tap(create);
    await tester.pump();
    expect(model.opens, 1);
    expect(find.byKey(const Key('summary-progress')), findsOneWidget);
    expect(create, findsNothing);
    model.opening.complete(engine);
    await settle(tester);
    expect(model.opens, 1);
    expect(engine.requests, hasLength(1));
    expect(store.saves, 1);
    expect(engine.disposed, isTrue);
  });

  testWidgets('P3-02d Stop works while the model is checked; the check result '
      'is discarded', (tester) async {
    final model = _OpeningModel();
    final engine = FakeTextGenerationEngine(respond: (_) => 'SUMMARY: x');
    await pump(tester, model: model);
    await tester.tap(find.byKey(const Key('summary-create')));
    await tester.pump();
    expect(find.textContaining('Checking the AI model'), findsOneWidget);
    final stop = find.byKey(const Key('summary-cancel'));
    expect(tester.widget<TextButton>(stop).onPressed, isNotNull);

    await tester.tap(stop);
    await tester.pump();
    expect(find.byKey(const Key('summary-progress')), findsNothing);
    expect(find.byKey(const Key('summary-create')), findsOneWidget);

    model.opening.complete(engine);
    await settle(tester);
    expect(engine.requests, isEmpty);
    expect(engine.disposed, isTrue);
    expect(store.saves, 0);
    expect(find.byKey(const Key('summary-error')), findsNothing);
    expect(find.byKey(const Key('summary-create')), findsOneWidget);
  });

  testWidgets('P3-02d Create again after Stop reuses the unfinished check', (
    tester,
  ) async {
    final model = _OpeningModel();
    final engine = FakeTextGenerationEngine(respond: (_) => 'SUMMARY: x');
    await pump(tester, model: model);
    await tester.tap(find.byKey(const Key('summary-create')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('summary-cancel')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('summary-create')));
    await tester.pump();
    expect(model.opens, 1);
    expect(find.byKey(const Key('summary-progress')), findsOneWidget);

    model.opening.complete(engine);
    await settle(tester);
    expect(model.opens, 1);
    expect(engine.requests, hasLength(1));
    expect(store.saves, 1);
    expect(engine.disposed, isTrue);
    expect(find.text('x'), findsOneWidget);
  });

  testWidgets('P3-02 an unreadable answer keeps nothing and says so', (
    tester,
  ) async {
    final engine = FakeTextGenerationEngine(respond: (_) => 'Sorry, no.');
    await pump(tester, engine: engine);
    await tester.tap(find.byKey(const Key('summary-create')));
    await settle(tester);
    expect(find.textContaining('could not be read'), findsOneWidget);
    expect(await tester.runAsync(() => store.load('a1')), isNull);
  });

  test('P3-02 store round trip, replace and unreadable file', () async {
    SessionSummary make(String text) => SessionSummary(
      activityId: 'a1',
      modelId: 'm',
      createdAt: DateTime.utc(2026, 11, 3),
      materialFingerprint: 'f',
      summary: text,
      points: const [],
    );
    expect(await store.load('a1'), isNull);
    await store.save(make('one'));
    await store.save(make('two'));
    expect((await store.load('a1'))!.summary, 'two');
    File('${root.path}/summaries-v1/a1.json').writeAsStringSync('{');
    await expectLater(store.load('a1'), throwsFormatException);
    await store.delete('a1');
    expect(await store.load('a1'), isNull);
    expect(() => store.load('../x'), throwsArgumentError);
  });

  test('P3-02 copied text keeps the machine-generated label and times', () {
    final text = summaryAsText(
      'Talk',
      SessionSummary(
        activityId: 'a1',
        modelId: 'm',
        createdAt: DateTime.utc(2026, 11, 3),
        materialFingerprint: 'f',
        summary: 'S.',
        points: [SummaryItem(text: 'P', at: const Duration(seconds: 61))],
        questions: const ['Q?'],
      ),
    );
    expect(text, contains('Machine-generated by m'));
    expect(text, contains('- [01:01] P'));
    expect(text, contains('- Q?'));
  });
}

Future<void> settle(WidgetTester tester) async {
  // Saving is real file work: give it enough turns to finish.
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}
