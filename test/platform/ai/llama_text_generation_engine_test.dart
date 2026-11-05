import 'dart:async';

import 'package:attenlume/domain/ai/text_generation_engine.dart';
import 'package:attenlume/platform/ai/llama_text_generation_engine.dart';
import 'package:fllama_cpp/fllama_cpp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P3-01 Gemma chat template formatting', () {
    test('P3-01 formats turn with both system and prompt', () {
      final formatted = LlamaTextGenerationEngine.formatGemmaChat(
        system: 'You are an assistant.',
        prompt: 'Summarise the Samlytics Conference 2026 session.',
      );
      expect(
        formatted,
        '<start_of_turn>user\n'
        'You are an assistant.\n\n'
        'Summarise the Samlytics Conference 2026 session.<end_of_turn>\n'
        '<start_of_turn>model\n',
      );
    });

    test('P3-01 formats turn with prompt only when system is empty', () {
      final formatted = LlamaTextGenerationEngine.formatGemmaChat(
        system: '   ',
        prompt: 'Provide three key takeaways.',
      );
      expect(
        formatted,
        '<start_of_turn>user\n'
        'Provide three key takeaways.<end_of_turn>\n'
        '<start_of_turn>model\n',
      );
    });
  });

  group('P3-01 Model ID and context length resolution', () {
    test('P3-01 derives modelId from gemma 3 filename', () {
      final engine = LlamaTextGenerationEngine(
        modelPath: 'path/to/gemma-3-1b-it-Q4_K_M.gguf',
        inferenceRunner: (req, cb) async => 1,
        contextLengthResolver: (p) => 8192,
      );
      expect(engine.modelId, 'gemma-3-1b-it-q4');
    });

    test('P3-01 derives modelId from gemma 4 filename', () {
      final engine = LlamaTextGenerationEngine(
        modelPath: 'models/gemma-4-E2B-it-Q4_0.gguf',
        inferenceRunner: (req, cb) async => 1,
        contextLengthResolver: (p) => 8192,
      );
      expect(engine.modelId, 'gemma-4-e2b-q4');
    });

    test('P3-01 honors explicitly provided modelId', () {
      final engine = LlamaTextGenerationEngine(
        modelPath: 'custom/model.gguf',
        modelId: 'custom-model-id',
        inferenceRunner: (req, cb) async => 1,
        contextLengthResolver: (p) => 4096,
      );
      expect(engine.modelId, 'custom-model-id');
    });

    test('P3-01 caps contextTokens at device budget', () {
      final engine = LlamaTextGenerationEngine(
        modelPath: 'test.gguf',
        maxContextTokens: 2048,
        inferenceRunner: (req, cb) async => 1,
        contextLengthResolver: (p) => 131072, // trained length 128k
      );
      expect(engine.contextTokens, 2048);
    });

    test('P3-01 keeps trained context length when lower than max cap', () {
      final engine = LlamaTextGenerationEngine(
        modelPath: 'test.gguf',
        maxContextTokens: 4096,
        inferenceRunner: (req, cb) async => 1,
        contextLengthResolver: (p) => 1024,
      );
      expect(engine.contextTokens, 1024);
    });

    test('P3-01 defaults contextTokens when resolver returns null', () {
      final engine = LlamaTextGenerationEngine(
        modelPath: 'test.gguf',
        maxContextTokens: 2048,
        inferenceRunner: (req, cb) async => 1,
        contextLengthResolver: (p) => null,
      );
      expect(engine.contextTokens, 2048);
    });
  });

  group('P3-01 Request execution, progress and error mapping', () {
    test('P3-01 builds request with system, prompt and parameters', () async {
      OpenAiRequest? capturedRequest;

      final engine = LlamaTextGenerationEngine(
        modelPath: 'test_model.gguf',
        maxContextTokens: 2048,
        inferenceRunner: (req, cb) async {
          capturedRequest = req;
          cb('Sample summary', '', true, null);
          return 42;
        },
        contextLengthResolver: (p) => 2048,
      );

      final result = await engine.generate(
        const TextGenerationRequest(
          system: 'You are an summariser for Samlytics Data Services.',
          prompt: 'Summarise the keynote.',
          maxOutputTokens: 256,
          temperature: 0.15,
        ),
      );

      expect(result, 'Sample summary');
      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.messages.length, 2);
      expect(capturedRequest!.messages[0].role, Role.system);
      expect(
        capturedRequest!.messages[0].text,
        'You are an summariser for Samlytics Data Services.',
      );
      expect(capturedRequest!.messages[1].role, Role.user);
      expect(capturedRequest!.messages[1].text, 'Summarise the keynote.');
      expect(capturedRequest!.maxTokens, 256);
      expect(capturedRequest!.temperature, 0.15);
      expect(capturedRequest!.contextSize, 2048);
    });

    test('P3-01 reports progress on token callback', () async {
      final progressValues = <double>[];

      final engine = LlamaTextGenerationEngine(
        modelPath: 'test_model.gguf',
        inferenceRunner: (req, cb) async {
          cb('Word1', '', false, null);
          cb('Word1 Word2', '', false, null);
          cb('Word1 Word2 Word3', '', true, null);
          return 1;
        },
        contextLengthResolver: (p) => 2048,
      );

      await engine.generate(
        const TextGenerationRequest(
          system: '',
          prompt: 'Generate',
          maxOutputTokens: 10,
        ),
        onProgress: progressValues.add,
      );

      expect(progressValues, isNotEmpty);
      expect(progressValues.every((p) => p >= 0.0 && p <= 1.0), isTrue);
    });

    test(
      'P3-01 maps fllama model load error to LlamaTextGenerationException',
      () async {
        final engine = LlamaTextGenerationEngine(
          modelPath: 'test_model.gguf',
          inferenceRunner: (req, cb) async {
            scheduleMicrotask(() {
              cb(
                '',
                '',
                true,
                const FllamaError(FllamaErrorType.modelLoad, 'Out of memory'),
              );
            });
            return 1;
          },
          contextLengthResolver: (p) => 2048,
        );

        await expectLater(
          engine.generate(
            const TextGenerationRequest(system: '', prompt: 'Hi'),
          ),
          throwsA(
            isA<LlamaTextGenerationException>().having(
              (e) => e.type,
              'type',
              LlamaTextGenerationErrorType.modelLoad,
            ),
          ),
        );
      },
    );

    test('P3-01 maps context exceeded error correctly', () async {
      final engine = LlamaTextGenerationEngine(
        modelPath: 'test_model.gguf',
        inferenceRunner: (req, cb) async {
          scheduleMicrotask(() {
            cb(
              '',
              '',
              true,
              const FllamaError(
                FllamaErrorType.contextSizeExceeded,
                'Prompt too long',
              ),
            );
          });
          return 1;
        },
        contextLengthResolver: (p) => 2048,
      );

      await expectLater(
        engine.generate(const TextGenerationRequest(system: '', prompt: 'Hi')),
        throwsA(
          isA<LlamaTextGenerationException>().having(
            (e) => e.type,
            'type',
            LlamaTextGenerationErrorType.contextExceeded,
          ),
        ),
      );
    });
  });

  group('P3-01 Cancel and dispose behavior', () {
    test('P3-01 cancel stops running request and throws TextGenerationCancelledException', () async {
      int? cancelledId;
      final completer = Completer<void>();

      final engine = LlamaTextGenerationEngine(
        modelPath: 'test_model.gguf',
        inferenceRunner: (req, cb) async {
          // Never sends done, waits for cancellation
          unawaited(
            completer.future.then((_) {
              cb('', '', true, null);
            }),
          );
          return 999;
        },
        cancelRunner: (id) {
          cancelledId = id;
          completer.complete();
        },
        contextLengthResolver: (p) => 2048,
      );

      final genFuture = engine.generate(
        const TextGenerationRequest(system: '', prompt: 'Prompt'),
      );

      // Cancel before completion
      await engine.cancel();

      expect(cancelledId, 999);
      await expectLater(
        genFuture,
        throwsA(isA<TextGenerationCancelledException>()),
      );
    });

    test('P3-01 prevents concurrent generation requests', () async {
      final completer = Completer<void>();
      final engine = LlamaTextGenerationEngine(
        modelPath: 'test_model.gguf',
        inferenceRunner: (req, cb) async {
          unawaited(completer.future.then((_) => cb('Done', '', true, null)));
          return 1;
        },
        contextLengthResolver: (p) => 2048,
      );

      unawaited(
        engine.generate(
          const TextGenerationRequest(system: '', prompt: 'Prompt 1'),
        ),
      );

      expect(
        () => engine.generate(
          const TextGenerationRequest(system: '', prompt: 'Prompt 2'),
        ),
        throwsA(isA<StateError>()),
      );

      completer.complete();
    });

    test('P3-01 dispose is idempotent and cancels active jobs', () async {
      int? cancelledId;
      final engine = LlamaTextGenerationEngine(
        modelPath: 'test_model.gguf',
        inferenceRunner: (req, cb) async => 123,
        cancelRunner: (id) => cancelledId = id,
        contextLengthResolver: (p) => 2048,
      );

      await engine.dispose();
      await engine.dispose(); // idempotent
      expect(engine.isDisposed, isTrue);
      expect(cancelledId, isNull);

      expect(
        () => engine.generate(
          const TextGenerationRequest(system: '', prompt: 'Prompt'),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('P3-02b ignores stale callbacks after cancel and drains terminal callback before next generation', () async {
      late FllamaInferenceCallback savedCallback;
      final progressValues = <double>[];

      final engine = LlamaTextGenerationEngine(
        modelPath: 'test_model.gguf',
        inferenceRunner: (req, cb) async {
          savedCallback = cb;
          return 777;
        },
        cancelRunner: (id) {
          // Native cancel received, but callbacks still pending
        },
        contextLengthResolver: (p) => 2048,
      );

      final genFuture1 = engine.generate(
        const TextGenerationRequest(
          system: '',
          prompt: 'Prompt 1',
          maxOutputTokens: 10,
        ),
        onProgress: progressValues.add,
      );

      // Give event loop time to set up
      await Future<void>.delayed(Duration.zero);

      // Emit first valid token
      savedCallback('Tok1', '', false, null);
      expect(progressValues, [0.1]);

      // Now cancel
      await engine.cancel();

      // Emit a stale streaming token callback while cancelled but before terminal callback
      savedCallback('Tok1 Tok2', '', false, null);
      // Stale callback must NOT trigger onProgress!
      expect(progressValues.length, 1);

      // Attempting a second generation while terminal callback is still pending must throw StateError
      expect(
        () => engine.generate(
          const TextGenerationRequest(system: '', prompt: 'Prompt 2'),
        ),
        throwsA(isA<StateError>()),
      );

      // Now emit terminal callback
      savedCallback('', '', true, null);

      // genFuture1 must complete with TextGenerationCancelledException
      await expectLater(
        genFuture1,
        throwsA(isA<TextGenerationCancelledException>()),
      );

      // Now that the old request has reached terminal completion, a new generation can start and succeed
      final genFuture2 = engine.generate(
        const TextGenerationRequest(system: '', prompt: 'Prompt 2'),
      );
      savedCallback('Success 2', '', true, null);
      final result2 = await genFuture2;
      expect(result2, 'Success 2');
    });
  });
}
