import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/ai/summary_store.dart';
import 'package:attenlume/domain/transcription/transcript.dart';
import 'package:attenlume/features/summaries/summary_providers.dart';
import 'package:attenlume/features/summaries/summary_section.dart';
import 'package:attenlume/platform/ai/language_model_store.dart';
import 'package:attenlume/platform/ai/llama_text_generation_engine.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

TranscriptDocument _testTranscript() => TranscriptDocument(
  activityId: 'a1',
  segmentId: 's1',
  createdAt: DateTime.utc(2026, 11, 5),
  machineSpans: [
    TranscriptSpan(
      start: Duration.zero,
      end: const Duration(seconds: 10),
      text: 'Welcome to Samlytics Conference 2026.',
    ),
    TranscriptSpan(
      start: const Duration(seconds: 20),
      end: const Duration(seconds: 30),
      text: 'Samlytics Data Services provides on-device AI capabilities.',
    ),
  ],
);

void main() {
  late Directory tempDir;
  late LanguageModelStore modelStore;
  late SummaryStore summaryStore;
  late LanguageModelDescriptor testDescriptor;

  const fakeModelContent = 'dummy gguf model bytes 12345678';
  final fakeModelBytes = utf8.encode(fakeModelContent);
  final fakeModelSha256 = sha256.convert(fakeModelBytes).toString();

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('p3_02b_test_');
    modelStore = LanguageModelStore(baseDirectory: tempDir);
    summaryStore = SummaryStore(tempDir);
    testDescriptor = LanguageModelDescriptor(
      id: 'test_model',
      name: 'Test Gemma Model',
      sizeBytes: fakeModelBytes.length,
      sha256: fakeModelSha256,
      downloadUrl: 'https://example.com/test_model.gguf',
      fileName: 'test_model.gguf',
      licence: 'Apache 2.0',
      deviceNotice: 'Runs locally',
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  void installFakeModel() {
    final modelFile = File(
      '${tempDir.path}${Platform.pathSeparator}${testDescriptor.fileName}',
    );
    modelFile.writeAsBytesSync(fakeModelBytes, flush: true);
    final markerFile = File('${modelFile.path}.sha256');
    markerFile.writeAsStringSync(testDescriptor.sha256, flush: true);
  }

  group('P3-02b [FR-AI-02] OnDeviceSummaryModelAccess unit tests', () {
    test('P3-02b [FR-AI-02] unavailableReason returns download guidance when no model installed', () async {
      final access = OnDeviceSummaryModelAccess(
        getStore: () async => modelStore,
        getDescriptor: () async => testDescriptor,
        isIos: false,
      );

      final reason = await access.unavailableReason();
      expect(reason, 'Download the AI model in Settings > Optional AI');
    });

    test('P3-02b [FR-AI-02] unavailableReason returns unsupported message when on iOS', () async {
      installFakeModel();
      final access = OnDeviceSummaryModelAccess(
        getStore: () async => modelStore,
        getDescriptor: () async => testDescriptor,
        isIos: true,
      );

      final reason = await access.unavailableReason();
      expect(reason, 'On-device AI is not supported on iOS for now.');
    });

    test('P3-02b [FR-AI-02] unavailableReason returns null when model installed and verified', () async {
      installFakeModel();
      final access = OnDeviceSummaryModelAccess(
        getStore: () async => modelStore,
        getDescriptor: () async => testDescriptor,
        isIos: false,
      );

      final reason = await access.unavailableReason();
      expect(reason, isNull);
    });

    test('P3-02b [FR-AI-02] open verifies model on first load and returns LlamaTextGenerationEngine', () async {
      installFakeModel();
      final access = OnDeviceSummaryModelAccess(
        getStore: () async => modelStore,
        getDescriptor: () async => testDescriptor,
        isIos: false,
        inferenceRunner: (req, cb) async => 1,
        contextLengthResolver: (p) => 2048,
      );

      final engine = await access.open();
      expect(engine, isA<LlamaTextGenerationEngine>());
      expect(
        (engine as LlamaTextGenerationEngine).modelPath,
        contains('test_model.gguf'),
      );
      await engine.dispose();
    });

    test(
      'P3-02b [FR-AI-02] open treats full verification failure as no model',
      () async {
        // Write mismatched/corrupt file with marker
        final modelFile = File(
          '${tempDir.path}${Platform.pathSeparator}${testDescriptor.fileName}',
        );
        modelFile.writeAsBytesSync(
          utf8.encode('tampered bytes 1234'),
          flush: true,
        );
        final markerFile = File('${modelFile.path}.sha256');
        markerFile.writeAsStringSync(testDescriptor.sha256, flush: true);

        final access = OnDeviceSummaryModelAccess(
          getStore: () async => modelStore,
          getDescriptor: () async => testDescriptor,
          isIos: false,
          inferenceRunner: (req, cb) async => 1,
        );

        expect(
          access.open,
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'Download the AI model in Settings > Optional AI',
            ),
          ),
        );

        // Verification failure removed the file, so unavailableReason now guides to Settings
        final reason = await access.unavailableReason();
        expect(reason, 'Download the AI model in Settings > Optional AI');
      },
    );

    test('P3-02b [FR-AI-02] open throws UnsupportedError on iOS', () async {
      installFakeModel();
      final access = OnDeviceSummaryModelAccess(
        getStore: () async => modelStore,
        getDescriptor: () async => testDescriptor,
        isIos: true,
        inferenceRunner: (req, cb) async => 1,
      );

      expect(
        access.open,
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            'On-device AI is not supported on iOS for now.',
          ),
        ),
      );
    });
  });

  group('P3-02b [FR-AI-02] SummarySection widget tests', () {
    Future<void> pumpSection(
      WidgetTester tester, {
      required SummaryModelAccess modelAccess,
      bool recording = false,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            summaryTranscriptsProvider.overrideWithValue(
              (_) async => [_testTranscript()],
            ),
            summaryStoreProvider.overrideWithValue(() async => summaryStore),
            summaryModelAccessProvider.overrideWithValue(modelAccess),
            summaryBlockedByRecordingProvider.overrideWithValue(
              () => recording,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: SummarySection(
                  activityId: 'a1',
                  title: 'Samlytics Conference 2026 Session',
                  notesMd: null,
                  bookmarks: const [],
                  cuts: const [],
                  canPlay: true,
                  onPlayFrom: (_) {},
                  onOpenTranscription: () async {},
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);
    }

    testWidgets(
      'P3-02b [FR-AI-02] widget shows download guidance when no model installed',
      (tester) async {
        final access = OnDeviceSummaryModelAccess(
          getStore: () async => modelStore,
          getDescriptor: () async => testDescriptor,
          isIos: false,
        );

        await pumpSection(tester, modelAccess: access);

        expect(
          find.text('Download the AI model in Settings > Optional AI'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('summary-create')), findsNothing);
      },
    );

    testWidgets('P3-02b [FR-AI-02] widget shows unsupported message on iOS', (
      tester,
    ) async {
      installFakeModel();
      final access = OnDeviceSummaryModelAccess(
        getStore: () async => modelStore,
        getDescriptor: () async => testDescriptor,
        isIos: true,
      );

      await pumpSection(tester, modelAccess: access);

      expect(
        find.text('On-device AI is not supported on iOS for now.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('summary-create')), findsNothing);
    });

    testWidgets(
      'P3-02b [FR-AI-02] widget shows Create summary and generates with installed model',
      (tester) async {
        installFakeModel();
        final access = OnDeviceSummaryModelAccess(
          getStore: () async => modelStore,
          getDescriptor: () async => testDescriptor,
          isIos: false,
          inferenceRunner: (req, cb) async {
            scheduleMicrotask(() {
              cb(
                'SUMMARY: Grounded summary of Samlytics Conference 2026.\n'
                    'POINT [00:05]: Key note on local processing.\n'
                    'FOLLOWUP [00:25]: Explore offline models.\n'
                    'QUESTION: How are models deployed?',
                '',
                true,
                null,
              );
            });
            return 1;
          },
          contextLengthResolver: (p) => 2048,
        );

        await pumpSection(tester, modelAccess: access);

        final createButton = find.byKey(const Key('summary-create'));
        expect(createButton, findsOneWidget);

        await tester.tap(createButton);
        await settle(tester);

        expect(
          find.text('Grounded summary of Samlytics Conference 2026.'),
          findsOneWidget,
        );
        expect(find.text('Key note on local processing.'), findsOneWidget);
      },
    );

    testWidgets(
      'P3-02b [FR-AI-02] widget blocks start when recording is active',
      (tester) async {
        installFakeModel();
        final access = OnDeviceSummaryModelAccess(
          getStore: () async => modelStore,
          getDescriptor: () async => testDescriptor,
          isIos: false,
          inferenceRunner: (req, cb) async => 1,
          contextLengthResolver: (p) => 2048,
        );

        await pumpSection(tester, modelAccess: access, recording: true);

        final createButton = find.byKey(const Key('summary-create'));
        expect(createButton, findsOneWidget);

        await tester.tap(createButton);
        await tester.pump();

        expect(
          find.text(
            'A recording is running. Summaries wait until it stops, so the '
            'recording keeps the processor.',
          ),
          findsOneWidget,
        );
      },
    );
  });
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}
