import 'dart:io';
import 'dart:math';

import 'package:attenlume/domain/ai/summary_prompt.dart';
import 'package:fllama_cpp/fllama_cpp.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Checks the cautious instruction count against the real tokenizer of a
/// downloaded model (P3-12). Windows only; set ATTENLUME_LLM_MODEL to a
/// GGUF file. Never estimate fewer tokens than the model uses.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final modelPath = Platform.environment['ATTENLUME_LLM_MODEL'];

  testWidgets('P3-12 the cautious estimate never undercounts', (tester) async {
    await tester.runAsync(() async {
      final random = Random(7);
      String pick(String chars, int n) =>
          List.generate(n, (_) => chars[random.nextInt(chars.length)]).join();
      const letters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
      const ascii =
          '$letters'
          '0123456789!"#\$%&\'()*+,-./:;<=>?@[\\]^_`{|}~';
      final fixtures = <String, String>{
        'default instructions': defaultSummaryInstructions,
        'compact instructions': compactSummaryInstructions,
        'random letters': pick(letters, 1400),
        'random ASCII': pick(ascii, 1400),
        'spaced digits': '7 ' * 700,
        'digits': pick('0123456789', 1400),
        'punctuation': pick('!"#\$%&\'()*+,-./:;<=>?@[]^_{|}~', 700),
        'Chinese': '数据质量和人工智能试点' * 40,
        'emoji': '📊🤖✅🚀' * 60,
        'accented names': 'François Zoë Ångström Łukasz Ñuñez ' * 20,
        'mixed': '${pick(ascii, 300)} 数据 📊 ${pick(letters, 300)} 123 456',
      };
      var worst = double.infinity;
      for (final entry in fixtures.entries) {
        final real = await fllamaTokenize(
          FllamaTokenizeRequest(input: entry.value, modelPath: modelPath!),
        );
        final estimate = instructionTokenEstimate(entry.value);
        final ratio = estimate / real;
        worst = min(worst, ratio);
        debugPrint(
          '${entry.key}: estimate $estimate, real $real '
          '(${ratio.toStringAsFixed(2)}x)',
        );
        expect(
          estimate,
          greaterThanOrEqualTo(real),
          reason: '${entry.key} is undercounted',
        );
      }
      debugPrint('Lowest estimate/real ratio: ${worst.toStringAsFixed(2)}');
    });
  }, skip: modelPath == null || !Platform.isWindows);
}
