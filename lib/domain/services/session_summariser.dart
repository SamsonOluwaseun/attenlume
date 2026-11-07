import '../ai/session_material.dart';
import '../ai/session_summary.dart';
import '../ai/summary_prompt.dart';
import '../ai/text_generation_engine.dart';

final class NoSpeechToSummariseException implements Exception {
  const NoSpeechToSummariseException();

  @override
  String toString() => 'This session has no saved transcript to summarise';
}

/// Builds a grounded summary of one session with a [TextGenerationEngine]
/// (P3-02, ADR-076 item 5). A session that fits in the model's context is
/// summarised in one request; a longer one part by part, and the parts are
/// then combined (in rounds when there are many).
class SessionSummariser {
  SessionSummariser({
    required this.engine,
    this.instructions,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final TextGenerationEngine engine;

  /// The user's summary instructions (P3-12); null uses the default.
  final String? instructions;
  final DateTime Function() _clock;

  /// Tokens kept for the answer of the final request and of each part.
  static const answerTokens = 600;
  static const partAnswerTokens = 400;

  /// Room for the title, labels and the model's chat template.
  static const _overheadTokens = 64;

  /// Combining stops after this many rounds; what is left is shortened.
  static const _maxCombineRounds = 3;

  bool _cancelled = false;

  /// Tokens the user's own instructions take beyond the plain estimate.
  int _ownExtraTokens = 0;
  bool _prepared = false;

  /// Counts the instructions' tokens before [summarise], so a caller can
  /// check anything that may have changed during the wait (for example a
  /// recording starting) right before inference. Optional: [summarise]
  /// prepares itself when this was not called.
  Future<void> prepare() async {
    await _countOwnInstructions();
    _prepared = true;
  }

  /// Counts the user's own instructions with the model's tokenizer (P3-12),
  /// so token-dense text (codes, other scripts, emoji) never crowds the
  /// transcript out of the context. Falls back to the cautious estimate.
  Future<void> _countOwnInstructions() async {
    _ownExtraTokens = 0;
    final own = instructions?.trim() ?? '';
    if (own.isEmpty || isBuiltInSummaryInstructions(own)) return;
    int real;
    try {
      real = await engine.countTokens(own);
    } on Object {
      real = instructionTokenEstimate(own);
    }
    final extra = real - estimateTokens(own);
    _ownExtraTokens = extra > 0 ? extra : 0;
  }

  /// Throws [NoSpeechToSummariseException] without a transcript,
  /// [SummaryFormatException] when the final answer is unreadable, and
  /// [TextGenerationCancelledException] after [cancel].
  Future<SessionSummary> summarise(
    SessionMaterial material, {
    required String activityId,
    void Function(double progress)? onProgress,
  }) async {
    if (!material.hasSpeech) throw const NoSpeechToSummariseException();
    _cancelled = false;
    if (!_prepared) await prepare();
    final timestamps = material.timestamps;
    final chunks = material.chunks(
      _budget(partSystemPromptFor(99, 99, instructions), partAnswerTokens),
    );
    final fitsOnce =
        chunks.length == 1 &&
        chunks.single.fold<int>(0, (n, l) => n + l.estimatedTokens) <=
            _budget(summarySystemPromptFor(instructions), answerTokens);

    var calls = 0;
    final expected = fitsOnce ? 1 : chunks.length + 1;
    Future<String> ask(String system, String prompt, int answer) async {
      _checkCancelled();
      final done = calls;
      final text = await engine.generate(
        TextGenerationRequest(
          system: system,
          prompt: prompt,
          maxOutputTokens: answer,
        ),
        onProgress: onProgress == null
            ? null
            : (p) => onProgress(
                ((done + p.clamp(0, 1)) / expected).clamp(0.0, 0.99),
              ),
      );
      calls++;
      onProgress?.call((calls / expected).clamp(0.0, 0.99));
      _checkCancelled();
      return text;
    }

    ParsedSummary result;
    var leftOut = 0;
    if (fitsOnce) {
      result = parseSummaryAnswer(
        await ask(
          summarySystemPromptFor(instructions),
          materialPrompt(material.title, material.lines),
          answerTokens,
        ),
        timestamps,
      );
    } else {
      var notes = <String>[];
      for (var i = 0; i < chunks.length; i++) {
        final part = parseSummaryAnswer(
          await ask(
            partSystemPromptFor(i + 1, chunks.length, instructions),
            materialPrompt(material.title, chunks[i]),
            partAnswerTokens,
          ),
          timestamps,
          strict: false,
        );
        leftOut += part.leftOut;
        notes.addAll(part.asNotes());
      }
      final budget = _budget(
        combineSystemPromptFor(instructions),
        answerTokens,
      );
      for (var round = 0; _tokens(notes) > budget; round++) {
        if (round == _maxCombineRounds) {
          notes = _fit(notes, budget);
          break;
        }
        final next = <String>[];
        for (final group in _groups(notes, budget)) {
          final combined = parseSummaryAnswer(
            await ask(
              combineSystemPromptFor(instructions),
              combinePrompt(material.title, group),
              partAnswerTokens,
            ),
            timestamps,
            strict: false,
          );
          leftOut += combined.leftOut;
          next.addAll(combined.asNotes());
        }
        notes = next;
      }
      result = parseSummaryAnswer(
        await ask(
          combineSystemPromptFor(instructions),
          combinePrompt(material.title, notes),
          answerTokens,
        ),
        timestamps,
      );
    }
    onProgress?.call(1);
    return SessionSummary(
      activityId: activityId,
      modelId: engine.modelId,
      createdAt: _clock(),
      materialFingerprint: material.fingerprint,
      summary: result.summary,
      points: result.points,
      followUps: result.followUps,
      questions: result.questions,
      chunkCount: chunks.length,
      leftOut: leftOut + result.leftOut,
    );
  }

  /// Stops the current summary; [summarise] then throws
  /// [TextGenerationCancelledException].
  Future<void> cancel() async {
    _cancelled = true;
    await engine.cancel();
  }

  void _checkCancelled() {
    if (_cancelled) throw const TextGenerationCancelledException();
  }

  int _budget(String system, int answer) {
    // The user's own instructions are counted exactly (see below); the fixed
    // prompt and the built-in defaults are known English text.
    final systemTokens = estimateTokens(system) + _ownExtraTokens;
    final budget =
        engine.contextTokens - systemTokens - answer - _overheadTokens;
    if (budget < 128) {
      throw instructions == null
          ? StateError('The model context is too small for a summary')
          : const SummaryInstructionsTooLongException();
    }
    return budget;
  }

  static int _tokens(List<String> lines) =>
      lines.fold(0, (n, l) => n + estimateTokens(l) + 1);

  static List<List<String>> _groups(List<String> lines, int budget) {
    final groups = <List<String>>[];
    var current = <String>[];
    for (final line in _fit(lines, budget)) {
      if (_tokens([...current, line]) > budget && current.isNotEmpty) {
        groups.add(current);
        current = [];
      }
      current.add(line);
    }
    if (current.isNotEmpty) groups.add(current);
    return groups;
  }

  /// Shortens over-long lines, then drops lines from the end to fit.
  static List<String> _fit(List<String> lines, int budget) {
    final maxChars = budget * 2;
    final fitted = [
      for (final l in lines) l.length > maxChars ? l.substring(0, maxChars) : l,
    ];
    while (fitted.length > 1 && _tokens(fitted) > budget) {
      fitted.removeLast();
    }
    return fitted;
  }
}
