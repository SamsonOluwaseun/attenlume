import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:fllama_cpp/fllama_cpp.dart';

import '../../domain/ai/text_generation_engine.dart';

typedef LlamaInferenceRunner = Future<int> Function(
  OpenAiRequest request,
  FllamaInferenceCallback callback,
);

typedef LlamaCancelRunner = void Function(int requestId);

typedef LlamaContextLengthResolver = int? Function(String modelPath);

enum LlamaTextGenerationErrorType {
  modelNotFound,
  modelLoad,
  contextExceeded,
  invalidRequest,
  backend,
  other,
}

class LlamaTextGenerationException implements Exception {
  const LlamaTextGenerationException(
    this.message, {
    this.type = LlamaTextGenerationErrorType.other,
    this.cause,
  });

  final String message;
  final LlamaTextGenerationErrorType type;
  final Object? cause;

  @override
  String toString() => 'LlamaTextGenerationException($type): $message';
}

/// On-device language model runtime using llama.cpp / fllama (P3-01, ADR-076).
///
/// Inference executes off the UI isolate via helper isolates.
/// Memory is bounded by capping the active context window to a safe budget
/// suitable for 4 GB RAM Android devices (e.g. 2,048 tokens).
class LlamaTextGenerationEngine implements TextGenerationEngine {
  /// Maximum context tokens permitted on 4 GB RAM mobile devices.
  ///
  /// A cap of 2,048 tokens restricts peak KV-cache memory to < 128 MB,
  /// preventing OOM errors on devices with ~2.3 GB available RAM while
  /// providing enough space for ~1,500 token input transcripts + 512 token
  /// summaries.
  static const int kDefaultMaxDeviceContextTokens = 2048;

  LlamaTextGenerationEngine({
    required this.modelPath,
    String? modelId,
    this.maxContextTokens = kDefaultMaxDeviceContextTokens,
    this.numThreads = -1,
    LlamaInferenceRunner? inferenceRunner,
    LlamaCancelRunner? cancelRunner,
    LlamaContextLengthResolver? contextLengthResolver,
  }) : _inferenceRunner = inferenceRunner ?? fllamaChat,
       _cancelRunner = cancelRunner ?? fllamaCancelInference,
       _contextLengthResolver =
           contextLengthResolver ?? fllamaTrainedContextLength {
    if (!Platform.isAndroid && inferenceRunner == null) {
      throw UnsupportedError(
        'LlamaTextGenerationEngine on-device native inference is currently '
        'enabled for Android. iOS and Windows require native runtime packaging.',
      );
    }

    final file = File(modelPath);
    if (!file.existsSync() && inferenceRunner == null) {
      throw LlamaTextGenerationException(
        'Model file not found at $modelPath',
        type: LlamaTextGenerationErrorType.modelNotFound,
      );
    }

    _modelId = modelId ?? _deriveModelId(modelPath);

    final trainedLength = _contextLengthResolver(modelPath);
    if (trainedLength != null && trainedLength > 0) {
      _contextTokens = math.min(trainedLength, maxContextTokens);
    } else {
      _contextTokens = maxContextTokens;
    }
  }

  final String modelPath;
  final int maxContextTokens;
  final int numThreads;
  final LlamaInferenceRunner _inferenceRunner;
  final LlamaCancelRunner _cancelRunner;
  final LlamaContextLengthResolver _contextLengthResolver;

  late final String _modelId;
  late final int _contextTokens;

  bool _isDisposed = false;
  bool _isGenerating = false;
  bool _isCancelled = false;
  int? _activeRequestId;

  @override
  String get modelId => _modelId;

  @override
  int get contextTokens => _contextTokens;

  bool get isDisposed => _isDisposed;
  bool get isGenerating => _isGenerating;

  /// Formats prompt turns according to Gemma's chat template.
  static String formatGemmaChat({
    required String system,
    required String prompt,
  }) {
    final buffer = StringBuffer();
    final trimmedSystem = system.trim();
    final trimmedPrompt = prompt.trim();
    if (trimmedSystem.isNotEmpty) {
      buffer.write(
        '<start_of_turn>user\n$trimmedSystem\n\n$trimmedPrompt<end_of_turn>\n<start_of_turn>model\n',
      );
    } else {
      buffer.write(
        '<start_of_turn>user\n$trimmedPrompt<end_of_turn>\n<start_of_turn>model\n',
      );
    }
    return buffer.toString();
  }

  @override
  Future<String> generate(
    TextGenerationRequest request, {
    void Function(double progress)? onProgress,
  }) async {
    if (_isDisposed) {
      throw StateError('LlamaTextGenerationEngine has been disposed.');
    }
    if (_isGenerating) {
      throw StateError(
        'A generation request is already active on this engine instance.',
      );
    }

    _isGenerating = true;
    _isCancelled = false;

    final completer = Completer<String>();
    final maxTokens = request.maxOutputTokens;
    int tokenCount = 0;

    final messages = <Message>[
      if (request.system.trim().isNotEmpty)
        Message(Role.system, request.system.trim()),
      Message(Role.user, request.prompt.trim()),
    ];

    final openAiRequest = OpenAiRequest(
      modelPath: modelPath,
      contextSize: _contextTokens,
      maxTokens: maxTokens,
      temperature: request.temperature,
      messages: messages,
    );

    try {
      final reqId = await _inferenceRunner(openAiRequest, (
        String response,
        String openaiResponseJsonString,
        bool done,
        FllamaError? error,
      ) {
        if (_isCancelled) {
          if (!completer.isCompleted) {
            completer.completeError(const TextGenerationCancelledException());
          }
          return;
        }

        if (error != null) {
          if (!completer.isCompleted) {
            completer.completeError(_mapFllamaError(error));
          }
          return;
        }

        tokenCount++;
        if (onProgress != null && maxTokens > 0) {
          final progress = (tokenCount / maxTokens).clamp(0.0, 1.0);
          onProgress(progress);
        }

        if (done && !completer.isCompleted) {
          completer.complete(response.trim());
        }
      });

      _activeRequestId = reqId;

      if (_isCancelled) {
        _cancelRunner(reqId);
        if (!completer.isCompleted) {
          completer.completeError(const TextGenerationCancelledException());
        }
      }

      return await completer.future;
    } on TextGenerationCancelledException {
      rethrow;
    } catch (e, st) {
      if (_isCancelled) {
        throw const TextGenerationCancelledException();
      }
      if (e is LlamaTextGenerationException) {
        rethrow;
      }
      Error.throwWithStackTrace(
        LlamaTextGenerationException(
          'Inference failed: $e',
          type: LlamaTextGenerationErrorType.other,
          cause: e,
        ),
        st,
      );
    } finally {
      _isGenerating = false;
      _activeRequestId = null;
    }
  }

  @override
  Future<void> cancel() async {
    _isCancelled = true;
    final activeId = _activeRequestId;
    if (activeId != null) {
      try {
        _cancelRunner(activeId);
      } catch (_) {
        // Suppress cancel runner dispatch errors on teardown
      }
      _activeRequestId = null;
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await cancel();
  }

  static String _deriveModelId(String path) {
    final lower = path.toLowerCase();
    if (lower.contains('gemma-4-e2b')) return 'gemma-4-e2b-q4';
    if (lower.contains('gemma-3-1b')) return 'gemma-3-1b-it-q4';
    if (lower.contains('gemma-2-2b')) return 'gemma-2-2b-it-q4';
    final name = path.split(RegExp(r'[/\\]')).last;
    return name.replaceAll(RegExp(r'\.gguf$', caseSensitive: false), '');
  }

  LlamaTextGenerationException _mapFllamaError(FllamaError error) {
    switch (error.type) {
      case FllamaErrorType.modelLoad:
        return LlamaTextGenerationException(
          error.message,
          type: LlamaTextGenerationErrorType.modelLoad,
        );
      case FllamaErrorType.contextSizeExceeded:
        return LlamaTextGenerationException(
          error.message,
          type: LlamaTextGenerationErrorType.contextExceeded,
        );
      case FllamaErrorType.invalidRequest:
        return LlamaTextGenerationException(
          error.message,
          type: LlamaTextGenerationErrorType.invalidRequest,
        );
      case FllamaErrorType.backend:
        return LlamaTextGenerationException(
          error.message,
          type: LlamaTextGenerationErrorType.backend,
        );
      case FllamaErrorType.other:
        return LlamaTextGenerationException(
          error.message,
          type: LlamaTextGenerationErrorType.other,
        );
    }
  }
}
