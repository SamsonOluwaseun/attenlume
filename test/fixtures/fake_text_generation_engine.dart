import 'dart:async';

import 'package:attenlume/domain/ai/text_generation_engine.dart';

/// A [TextGenerationEngine] that answers from [respond] and records every
/// request, for summary tests (P3-02).
class FakeTextGenerationEngine implements TextGenerationEngine {
  FakeTextGenerationEngine({
    required this.respond,
    this.contextTokens = 4096,
    this.modelId = 'fake-model',
  });

  final FutureOr<String> Function(TextGenerationRequest request) respond;

  @override
  final int contextTokens;

  @override
  final String modelId;

  final requests = <TextGenerationRequest>[];
  bool cancelled = false;
  bool disposed = false;

  /// When set, [generate] waits for it before answering.
  Completer<void>? gate;

  @override
  Future<String> generate(
    TextGenerationRequest request, {
    void Function(double progress)? onProgress,
  }) async {
    requests.add(request);
    onProgress?.call(0.5);
    await gate?.future;
    if (cancelled) throw const TextGenerationCancelledException();
    return respond(request);
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
    if (gate case final g? when !g.isCompleted) g.complete();
  }

  @override
  Future<void> dispose() async {
    await cancel();
    disposed = true;
  }
}
