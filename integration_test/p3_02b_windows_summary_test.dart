import 'dart:io';

import 'package:attenlume/domain/ai/session_summary.dart';
import 'package:attenlume/domain/ai/summary_prompt.dart';
import 'package:attenlume/domain/ai/summary_quality.dart';
import 'package:attenlume/domain/ai/text_generation_engine.dart';
import 'package:attenlume/domain/services/session_summariser.dart';
import 'package:attenlume/platform/ai/llama_text_generation_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/fixtures/summary_quality_set.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final envModelPath = Platform.environment['ATTENLUME_LLM_MODEL'];
  final hasModel =
      envModelPath != null &&
      envModelPath.trim().isNotEmpty &&
      File(envModelPath.trim()).existsSync();

  testWidgets('P3-02b [FR-AI-02] Windows real-model summary quality benchmark', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final modelPath = envModelPath!.trim();
      debugPrint('=== [P3-02b BENCHMARK START] ===');
      debugPrint('Model path: $modelPath');

      // 1. Load model and measure load time
      final stopwatchLoad = Stopwatch()..start();
      final engine = LlamaTextGenerationEngine(
        modelPath: modelPath,
        maxContextTokens: 2048,
      );
      stopwatchLoad.stop();
      final loadTimeMs = stopwatchLoad.elapsedMilliseconds;
      debugPrint(
        'Model initialised in $loadTimeMs ms (context: ${engine.contextTokens} tokens)',
      );

      final measured = _MeasuredEngine(engine);
      // As the app does: the user's own instructions, else the compact
      // default for the small model, else the full default [P3-12].
      final custom = Platform.environment['ATTENLUME_SUMMARY_INSTRUCTIONS'];
      final instructions = custom != null && custom.trim().isNotEmpty
          ? custom
          : modelPath.contains('gemma-3-1b')
          ? compactSummaryInstructions
          : null;
      debugPrint('Instructions: ${instructions ?? 'full default'}');
      final summariser = SessionSummariser(
        engine: measured,
        instructions: instructions,
      );
      final qualityFailures = <String>[];

      try {
        for (final testCase in summaryQualitySet) {
          debugPrint('--------------------------------------------------');
          debugPrint(
            'Running summary case: "${testCase.title}" (${testCase.id})',
          );
          final material = testCase.material();

          int tokenUpdates = 0;
          measured.answers.clear();
          final stopwatchGen = Stopwatch()..start();
          SessionSummary? summary;
          try {
            summary = await summariser.summarise(
              material,
              activityId: testCase.id,
              onProgress: (_) => tokenUpdates++,
            );
          } on SummaryFormatException {
            qualityFailures.add('${testCase.id}: unparseable model answer');
          }
          stopwatchGen.stop();

          final genTimeMs = stopwatchGen.elapsedMilliseconds;
          final totalOutputChars = measured.answers.join(' ').length;
          final approxOutputTokens = (totalOutputChars / 4.0).round();
          final tps = genTimeMs > 0
              ? (approxOutputTokens / (genTimeMs / 1000.0))
              : 0.0;

          debugPrint('Case ID: ${testCase.id}');
          debugPrint('Title: ${testCase.title}');
          debugPrint('Load time: $loadTimeMs ms');
          debugPrint('Generation time: $genTimeMs ms');
          debugPrint('Token callback updates: $tokenUpdates');
          debugPrint(
            'Approx output tokens: $approxOutputTokens (~$totalOutputChars characters)',
          );
          debugPrint('Output speed: ${tps.toStringAsFixed(2)} tokens/sec');
          if (summary == null) {
            debugPrint(
              'Score: unavailable (unparseable answer; passes: false)',
            );
            for (final answer in measured.answers) {
              debugPrint('Raw model answer: $answer');
            }
            continue;
          }
          final score = scoreSummary(summary, testCase);
          debugPrint('Score: $score (passes: ${score.passes})');
          debugPrint('Summary text: ${summary.summary}');
          debugPrint('Points count: ${summary.points.length}');
          if (!score.passes) {
            qualityFailures.add('${testCase.id}: $score');
          }
          // The raw answer shows writing quality and why points were dropped.
          for (final answer in measured.answers) {
            debugPrint('Raw model answer: $answer');
          }
        }
      } finally {
        await engine.dispose();
        debugPrint('LLM engine disposed.');
      }
      debugPrint('=== [P3-02b BENCHMARK COMPLETE] ===');
      expect(qualityFailures, isEmpty, reason: qualityFailures.join('\n'));
    });
  }, skip: !hasModel);
}

// Capture actual generated text even when summary parsing rejects it. The
// native engine and its Windows initialisation remain on the production path.
class _MeasuredEngine implements TextGenerationEngine {
  _MeasuredEngine(this.delegate);

  final TextGenerationEngine delegate;
  final answers = <String>[];

  @override
  String get modelId => delegate.modelId;
  @override
  int get contextTokens => delegate.contextTokens;
  @override
  Future<String> generate(
    TextGenerationRequest request, {
    void Function(double progress)? onProgress,
  }) async {
    final answer = await delegate.generate(request, onProgress: onProgress);
    answers.add(answer);
    return answer;
  }

  @override
  Future<void> cancel() => delegate.cancel();
  @override
  Future<void> dispose() => delegate.dispose();
}
