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

Future<int> _runNativeChat(
  OpenAiRequest request,
  FllamaInferenceCallback callback,
) async {
  if (Platform.isWindows) {
    // fllama 0.1.0 reads ggml_time_ms before its first backend initialisation.
    // On Windows the timer frequency is zero until llama_backend_init runs.
    // This public API performs the package's idempotent backend initialisation.
    await fllamaLoadedBackendFiles();
  }
  return fllamaChat(request, callback);
}

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
    this.tokenCounter,
  }) : _inferenceRunner = inferenceRunner ?? _runNativeChat,
       _cancelRunner = cancelRunner ?? fllamaCancelInference,
       _contextLengthResolver =
           contextLengthResolver ?? fllamaTrainedContextLength {
    if (!(Platform.isAndroid || Platform.isWindows) &&
        inferenceRunner == null) {
      throw UnsupportedError(
        'LlamaTextGenerationEngine on-device native inference is currently '
        'enabled for Android and Windows. iOS requires native runtime packaging.',
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

  /// Replaces the model's tokenizer in tests.
  final Future<int> Function(String text)? tokenCounter;

  late final String _modelId;
  late final int _contextTokens;

  bool _isDisposed = false;
  _ActiveGeneration? _activeGeneration;

  @override
  String get modelId => _modelId;

  @override
  int get contextTokens => _contextTokens;

  @override
  Future<int> countTokens(String text) =>
      tokenCounter?.call(text) ??
      fllamaTokenize(FllamaTokenizeRequest(input: text, modelPath: modelPath));

  bool get isDisposed => _isDisposed;
  bool get isGenerating => _activeGeneration != null;

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
    if (_activeGeneration != null) {
      throw StateError(
        'A generation request is already active on this engine instance.',
      );
    }

    final generation = _ActiveGeneration();
    _activeGeneration = generation;

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
      // Gemma 4 uses this template flag to omit the <|think|> switch.
      enableThinking: false,
      messages: messages,
    );

    try {
      final reqId = await _inferenceRunner(openAiRequest, (
        String response,
        String openaiResponseJsonString,
        bool done,
        FllamaError? error,
      ) {
        if (generation.terminalCompleter.isCompleted) {
          return;
        }

        final isTerminal = done || error != null;

        if (generation.isCancelled) {
          if (!generation.completer.isCompleted) {
            generation.completer.completeError(
              const TextGenerationCancelledException(),
            );
          }
          if (isTerminal && !generation.terminalCompleter.isCompleted) {
            generation.terminalCompleter.complete();
          }
          return;
        }

        if (error != null) {
          if (!generation.completer.isCompleted) {
            generation.completer.completeError(_mapFllamaError(error));
          }
          if (!generation.terminalCompleter.isCompleted) {
            generation.terminalCompleter.complete();
          }
          return;
        }

        tokenCount++;
        if (onProgress != null && maxTokens > 0) {
          final progress = (tokenCount / maxTokens).clamp(0.0, 1.0);
          onProgress(progress);
        }

        if (done) {
          if (!generation.completer.isCompleted) {
            generation.completer.complete(response.trim());
          }
          if (!generation.terminalCompleter.isCompleted) {
            generation.terminalCompleter.complete();
          }
        }
      });

      generation.nativeRequestId = reqId;

      if (generation.isCancelled) {
        try {
          _cancelRunner(reqId);
        } catch (_) {}
        if (!generation.completer.isCompleted) {
          generation.completer.completeError(
            const TextGenerationCancelledException(),
          );
        }
      }

      return await generation.completer.future;
    } on TextGenerationCancelledException {
      rethrow;
    } catch (e, st) {
      if (!generation.terminalCompleter.isCompleted) {
        generation.terminalCompleter.complete();
      }
      if (generation.isCancelled) {
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
      if (!generation.terminalCompleter.isCompleted) {
        try {
          await generation.terminalCompleter.future;
        } catch (_) {}
      }
      if (identical(_activeGeneration, generation)) {
        _activeGeneration = null;
      }
    }
  }

  @override
  Future<void> cancel() async {
    final active = _activeGeneration;
    if (active != null) {
      active.isCancelled = true;
      final activeId = active.nativeRequestId;
      if (activeId != null) {
        try {
          _cancelRunner(activeId);
        } catch (_) {
          // Suppress cancel runner dispatch errors on teardown
        }
      }
    }
  }

  /// Disposes the engine instance, cancelling any active generation request
  /// and dropping internal references.
  ///
  /// Resident memory limit note:
  /// fllama_cpp 0.1.0 does not expose an explicit native model unload or server
  /// shutdown API. Native server contexts and cached model weights (e.g. in
  /// `ServerManager`) remain resident in memory after [dispose] returns until
  /// process termination or eviction by subsequent operations. Therefore,
  /// disposal stops active inference and frees Dart-side references, but does
  /// not claim to immediately free native resident model memory.
  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await cancel();
    final active = _activeGeneration;
    if (active != null && !active.terminalCompleter.isCompleted) {
      try {
        await active.terminalCompleter.future;
      } catch (_) {}
    }
    _activeGeneration = null;
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

class _ActiveGeneration {
  final Completer<String> completer = Completer<String>();
  final Completer<void> terminalCompleter = Completer<void>();
  bool isCancelled = false;
  int? nativeRequestId;
}
