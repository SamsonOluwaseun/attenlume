/// Text generation behind one interface (P3-01, ADR-076): a model on the
/// device by default, or a tested provider with the user's own key.
///
/// An engine is created for one model and lives until [dispose]. Inference
/// runs off the UI isolate. Inputs are read-only; callers own what they save.
abstract interface class TextGenerationEngine {
  /// Identifies the model in saved output, for example `gemma-4-e2b-q4`.
  String get modelId;

  /// Tokens the model accepts per request, prompt and answer together.
  /// Callers size transcript chunks from this.
  int get contextTokens;

  /// Generates an answer to [request]. [onProgress] gets finite values in
  /// [0, 1] when the engine can estimate them. Throws
  /// [TextGenerationCancelledException] after [cancel].
  Future<String> generate(
    TextGenerationRequest request, {
    void Function(double progress)? onProgress,
  });

  /// Idempotent. Stops the current request.
  Future<void> cancel();

  /// Idempotent. Cancels current work and releases the model.
  Future<void> dispose();
}

class TextGenerationRequest {
  const TextGenerationRequest({
    required this.system,
    required this.prompt,
    this.maxOutputTokens = 512,
    this.temperature = 0.2,
  });

  /// Instructions the model follows for the whole request.
  final String system;

  /// The user turn: the session material and the question.
  final String prompt;
  final int maxOutputTokens;
  final double temperature;
}

final class TextGenerationCancelledException implements Exception {
  const TextGenerationCancelledException();

  @override
  String toString() => 'Text generation was cancelled';
}
