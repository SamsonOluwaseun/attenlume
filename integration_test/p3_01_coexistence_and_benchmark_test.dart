import 'dart:io';

import 'package:attenlume/domain/ai/text_generation_engine.dart';
import 'package:attenlume/platform/ai/llama_text_generation_engine.dart';
import 'package:attenlume/platform/transcription/whisper_transcription_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P3-01 Coexistence and Performance Benchmark on Android', (
    tester,
  ) async {
    await tester.runAsync(() async {
      debugPrint('=== [P3-01 BENCHMARK START] ===');

      final baseDir = Directory(
        '/data/user/0/com.samlytics.attenlume/app_flutter',
      );
      final modelsDir = Directory('${baseDir.path}/models');
      final audioFile = File('${modelsDir.path}/sample_speech.wav').existsSync()
          ? File('${modelsDir.path}/sample_speech.wav')
          : File('/data/local/tmp/sample_speech.wav');
      final whisperModelFile =
          File('${modelsDir.path}/ggml-tiny.en-q5_1.bin').existsSync()
          ? File('${modelsDir.path}/ggml-tiny.en-q5_1.bin')
          : File('/data/local/tmp/ggml-tiny.en-q5_1.bin');
      final llmModelFile =
          File('${modelsDir.path}/gemma-3-1b-it-Q4_K_M.gguf').existsSync()
          ? File('${modelsDir.path}/gemma-3-1b-it-Q4_K_M.gguf')
          : File('/data/local/tmp/gemma-3-1b-it-Q4_K_M.gguf');

      expect(audioFile.existsSync(), isTrue, reason: 'Test audio must exist');
      expect(
        whisperModelFile.existsSync(),
        isTrue,
        reason: 'Whisper model must exist',
      );
      expect(llmModelFile.existsSync(), isTrue, reason: 'LLM model must exist');

      // -------------------------------------------------------------
      // 1. First Whisper Transcription Pass
      // -------------------------------------------------------------
      debugPrint('[P3-01 Step 1] Running Whisper transcription pass 1...');
      final whisper1 = WhisperTranscriptionEngine();
      final stopwatchWhisper1 = Stopwatch()..start();
      final spans1 = await whisper1.transcribe(
        audioPath: audioFile.path,
        modelDirectory: whisperModelFile.path,
        onProgress: (p) {},
      );
      stopwatchWhisper1.stop();
      await whisper1.dispose();

      debugPrint(
        '[P3-01 Step 1] Whisper pass 1 complete: ${spans1.length} spans in ${stopwatchWhisper1.elapsedMilliseconds} ms',
      );
      expect(spans1, isNotNull);

      // -------------------------------------------------------------
      // 2. LLM Text Generation Benchmark (~1,500 token prompt)
      // -------------------------------------------------------------
      debugPrint('[P3-01 Step 2] Initialising LlamaTextGenerationEngine...');
      final stopwatchLoad = Stopwatch()..start();
      final llmEngine = LlamaTextGenerationEngine(
        modelPath: llmModelFile.path,
        maxContextTokens: 2048,
      );
      stopwatchLoad.stop();
      debugPrint(
        '[P3-01 Step 2] LLM engine initialised in ${stopwatchLoad.elapsedMilliseconds} ms; contextTokens: ${llmEngine.contextTokens}',
      );

      final fakeTranscript = _generateSamlyticsTranscript();
      final promptText =
          'Transcript:\n$fakeTranscript\n\n'
          'Based solely on the transcript above from Samlytics Conference 2026, '
          'provide a concise five-bullet summary highlighting the core engineering decisions.';

      final promptChars = promptText.length;
      final estimatedPromptTokens = (promptChars / 4.0).round();
      debugPrint(
        '[P3-01 Step 2] Prompt size: $promptChars characters (~$estimatedPromptTokens tokens)',
      );

      final stopwatchGen = Stopwatch()..start();
      int tokenUpdates = 0;
      final responseText = await llmEngine.generate(
        TextGenerationRequest(
          system:
              'You are an expert conference assistant for Samlytics Data Services. '
              'Provide accurate summaries grounded solely in the provided session material.',
          prompt: promptText,
          maxOutputTokens: 128,
          temperature: 0.2,
        ),
        onProgress: (progress) {
          tokenUpdates++;
        },
      );
      stopwatchGen.stop();

      final genElapsedMs = stopwatchGen.elapsedMilliseconds;
      final approxOutputTokens = (responseText.length / 4.0).round();
      final tps = (approxOutputTokens / (genElapsedMs / 1000.0));

      debugPrint('[P3-01 Step 2] LLM generation complete!');
      debugPrint('[P3-01 Step 2] Generation time: $genElapsedMs ms');
      debugPrint('[P3-01 Step 2] Token callbacks: $tokenUpdates');
      debugPrint('[P3-01 Step 2] Approx output tokens: $approxOutputTokens');
      debugPrint(
        '[P3-01 Step 2] Generation speed: ${tps.toStringAsFixed(2)} tokens/sec',
      );
      debugPrint('[P3-01 Step 2] Response text:\n$responseText');

      await llmEngine.dispose();
      debugPrint('[P3-01 Step 2] LLM engine disposed.');

      // -------------------------------------------------------------
      // 3. Second Whisper Transcription Pass (Coexistence Verification)
      // -------------------------------------------------------------
      debugPrint('[P3-01 Step 3] Running Whisper transcription pass 2...');
      final whisper2 = WhisperTranscriptionEngine();
      final stopwatchWhisper2 = Stopwatch()..start();
      final spans2 = await whisper2.transcribe(
        audioPath: audioFile.path,
        modelDirectory: whisperModelFile.path,
        onProgress: (p) {},
      );
      stopwatchWhisper2.stop();
      await whisper2.dispose();

      debugPrint(
        '[P3-01 Step 3] Whisper pass 2 complete: ${spans2.length} spans in ${stopwatchWhisper2.elapsedMilliseconds} ms',
      );
      expect(spans2, isNotNull);
      expect(spans2.length, equals(spans1.length));

      debugPrint('=== [P3-01 BENCHMARK COMPLETE SUCCESS] ===');
    });
  });
}

/// Generates a realistic ~6,000 character (~1,500 token) transcript
/// strictly adhering to Samlytics Conference 2026 and Samlytics Data Services.
String _generateSamlyticsTranscript() {
  final buffer = StringBuffer();
  buffer.writeln(
    'Speaker 1: Welcome everyone to Samlytics Conference 2026. '
    'Today we are proud to present the latest edge computing architecture from Samlytics Data Services. '
    'Our core objective this year has been delivering a completely offline-first experience for conference participants, '
    'guaranteeing that delegates never need an active internet connection or cloud account to capture, organise, '
    'and extract insights from their sessions.',
  );
  buffer.writeln(
    'Speaker 2: Thank you. At Samlytics Data Services, reliability in convention centers where Wi-Fi degrades '
    'under heavy load is paramount. In this architecture, all recording segments are written incrementally using '
    'uncompressed or lightweight streaming containers. Audio is captured directly to local application storage, '
    'and metadata changes are committed to SQLite using transactional boundaries.',
  );
  buffer.writeln(
    'Speaker 1: Let us dive deeper into the on-device transcription pipeline introduced at Samlytics Conference 2026. '
    'Delegates requested fast turnaround without uploading private recordings to cloud servers. '
    'We integrated a local Whisper engine that performs acoustic inference entirely within the mobile process. '
    'By leveraging integer quantisation, specifically 5-bit quantised acoustic models, the transcription engine '
    'consumes minimal memory while maintaining high word accuracy for technical presentations.',
  );
  buffer.writeln(
    'Speaker 2: Moving beyond transcription, today we are demonstrating on-device generative reasoning. '
    'Samlytics Data Services designed a unified text generation contract capable of running compact language models '
    'directly on consumer smartphones. Rather than shipping heavyweight models inside the application package, '
    'the application dynamically pulls verified model weights matching the device memory budget. '
    'For instance, on handsets with four gigabytes of physical RAM, our engine constrains the context window '
    'to two thousand and forty-eight tokens. This deliberate ceiling prevents out-of-memory terminations by bounding '
    'the key-value attention cache to well under one hundred megabytes.',
  );
  buffer.writeln(
    'Speaker 1: A vital question raised during early technical reviews was library coexistence. '
    'Both the speech recognition pipeline and the language model runtime depend on tensor calculation backends. '
    'Historically, shipping multiple native shared libraries resulted in dynamic linker symbol collisions '
    'and packaging conflicts over shared object filenames. At Samlytics Data Services, our packaging strategy '
    'statically isolates tensor dependencies with hidden symbol visibility. The speech engine exposes only its own '
    'plugin entry point, while the language model runtime operates through isolated helper threads, eliminating '
    'linker collisions entirely.',
  );
  buffer.writeln(
    'Speaker 2: To validate this coexistence at Samlytics Conference 2026, our test harness executes a sequential '
    'workload. First, an audio segment is transcribed by the Whisper engine. Second, the generated transcript '
    'is passed to the on-device language model to synthesise a five-bullet takeaway summary. Third, the speech engine '
    'is reinvoked on a second recording segment to verify that native memory was properly reclaimed and that no '
    'global execution state was corrupted. In our automated test passes, memory reclamation has been verified '
    'with zero leaks across repeated cycles.',
  );
  buffer.writeln(
    'Speaker 1: Grounding is another fundamental tenet for Samlytics Data Services. On-device models must never '
    'hallucinate facts or cite external training data when summarising a talk. Every bullet point in the generated summary '
    'is required to reference a specific timestamp within fifteen seconds of actual spoken dialogue. If a proposed takeaway '
    'cannot be anchored to an authentic timestamp, our post-processing filter drops the item to maintain strict factual integrity. '
    'This guarantees that attendees reviewing their notes months later can click any bullet point to jump directly '
    'to the exact audio timestamp where the speaker made the claim.',
  );
  buffer.writeln(
    'Speaker 2: Furthermore, privacy remains central to Samlytics Data Services. Because all transcription and language '
    'modelling take place strictly on device, sensitive executive briefings and proprietary conference presentations '
    'never leave the physical hardware. When users export their conference archives, transcripts and summaries are bundled '
    'alongside checksums and cryptographic manifests, allowing offline verification on any standard workstation.',
  );
  buffer.writeln(
    'Speaker 1: To summarise our discussion today at Samlytics Conference 2026: '
    'first, full offline functionality without cloud dependencies; '
    'second, efficient local speech-to-text using quantised acoustic models; '
    'third, compact on-device language models with bounded attention context; '
    'fourth, robust coexistence without native symbol conflicts; '
    'and fifth, strictly grounded timestamp citations for all generated summaries. '
    'Thank you all for joining us, and we invite everyone to test the workflow on the showroom floor.',
  );

  return buffer.toString();
}
