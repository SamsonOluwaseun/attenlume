import 'dart:io';

import 'package:attenlume/domain/ai/summary_quality.dart';
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
    if (!hasModel) {
      // ignore: avoid_print
      print(
        '=== [P3-02b SKIP] ATTENLUME_LLM_MODEL environment variable not set '
        'or model file not found. Skipping Windows real-model summary quality benchmark. ===',
      );
      return;
    }

    await tester.runAsync(() async {
      final modelPath = envModelPath.trim();
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

      final summariser = SessionSummariser(engine: engine);

      try {
        for (final testCase in summaryQualitySet) {
          debugPrint('--------------------------------------------------');
          debugPrint(
            'Running summary case: "${testCase.title}" (${testCase.id})',
          );
          final material = testCase.material();

          int tokenUpdates = 0;
          final stopwatchGen = Stopwatch()..start();
          final summary = await summariser.summarise(
            material,
            activityId: testCase.id,
            onProgress: (_) => tokenUpdates++,
          );
          stopwatchGen.stop();

          final genTimeMs = stopwatchGen.elapsedMilliseconds;
          final totalOutputChars = [
            summary.summary,
            for (final p in summary.points) p.text,
            for (final f in summary.followUps) f.text,
            ...summary.questions,
          ].join(' ').length;
          final approxOutputTokens = (totalOutputChars / 4.0).round();
          final tps = genTimeMs > 0
              ? (approxOutputTokens / (genTimeMs / 1000.0))
              : 0.0;

          final score = scoreSummary(summary, testCase);

          debugPrint('Case ID: ${testCase.id}');
          debugPrint('Title: ${testCase.title}');
          debugPrint('Load time: $loadTimeMs ms');
          debugPrint('Generation time: $genTimeMs ms');
          debugPrint('Token callback updates: $tokenUpdates');
          debugPrint(
            'Approx output tokens: $approxOutputTokens (~$totalOutputChars characters)',
          );
          debugPrint('Output speed: ${tps.toStringAsFixed(2)} tokens/sec');
          debugPrint('Score: $score (passes: ${score.passes})');
          debugPrint('Summary text: ${summary.summary}');
          debugPrint('Points count: ${summary.points.length}');
        }
      } finally {
        await engine.dispose();
        debugPrint('LLM engine disposed.');
      }
      debugPrint('=== [P3-02b BENCHMARK COMPLETE] ===');
    });
  });
}
