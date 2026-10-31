import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:attenlume/domain/transcription/transcription_engine.dart';
import 'package:attenlume/platform/transcription/audio_to_wav_converter.dart';
import 'package:attenlume/platform/transcription/transcription_exceptions.dart';
import 'package:attenlume/platform/transcription/whisper_transcription_engine.dart';
import 'package:audio_decoder/audio_decoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_whisper_ggml/flutter_whisper.dart';

class _FakeAudioConverter implements AudioToWavConverter {
  bool wasCalled = false;
  String? lastInputPath;
  String? lastOutputPath;

  @override
  Future<String> convertToWav({
    required String inputPath,
    required String outputPath,
    int sampleRate = 16000,
    int channels = 1,
    int bitDepth = 16,
  }) async {
    wasCalled = true;
    lastInputPath = inputPath;
    lastOutputPath = outputPath;
    final file = File(outputPath);
    final bytes = Uint8List(44 + 32000);
    final view = ByteData.sublistView(bytes);
    bytes.setRange(0, 4, 'RIFF'.codeUnits);
    view.setUint32(4, bytes.length - 8, Endian.little);
    bytes.setRange(8, 12, 'WAVE'.codeUnits);
    bytes.setRange(12, 16, 'fmt '.codeUnits);
    view.setUint32(16, 16, Endian.little);
    view.setUint16(20, 1, Endian.little);
    view.setUint16(22, 1, Endian.little);
    view.setUint32(24, 16000, Endian.little);
    view.setUint32(28, 32000, Endian.little);
    view.setUint16(32, 2, Endian.little);
    view.setUint16(34, 16, Endian.little);
    bytes.setRange(36, 40, 'data'.codeUnits);
    view.setUint32(40, 32000, Endian.little);
    file.writeAsBytesSync(
      bytes,
    ); // One second of generated silence, no voice sample.
    return outputPath;
  }
}

class _FakeWhisperBackend implements WhisperBackend {
  bool wasTranscribeCalled = false;
  WhisperTranscribeConfig? lastConfig;
  bool wasCancelCalled = false;
  bool wasDisposeCalled = false;
  Completer<WhisperResult>? pendingTranscribe;

  @override
  Future<WhisperResult> transcribe(
    Float32List samples,
    WhisperTranscribeConfig config, {
    void Function(int progress)? onProgress,
    void Function(WhisperSegment segment)? onSegment,
  }) async {
    wasTranscribeCalled = true;
    lastConfig = config;
    onProgress?.call(25);
    onProgress?.call(75);

    if (pendingTranscribe != null) {
      return pendingTranscribe!.future;
    }

    const segments = [
      WhisperSegment(
        text: 'Hello world',
        start: Duration(seconds: 0),
        end: Duration(seconds: 2),
      ),
      WhisperSegment(
        text: 'Testing transcription',
        start: Duration(seconds: 2),
        end: Duration(seconds: 5),
      ),
    ];
    for (final s in segments) {
      onSegment?.call(s);
    }
    return const WhisperResult(
      language: 'en',
      segments: segments,
      vadSegments: [],
      timings: WhisperTimings(
        sample: Duration.zero,
        encode: Duration.zero,
        decode: Duration.zero,
        batchDecode: Duration.zero,
        prompt: Duration.zero,
      ),
    );
  }

  @override
  void cancel() {
    wasCancelCalled = true;
    if (pendingTranscribe != null && !pendingTranscribe!.isCompleted) {
      pendingTranscribe!.completeError(const TranscriptionCancelledException());
    }
  }

  @override
  void dispose() {
    wasDisposeCalled = true;
  }
}

void main() {
  late Directory tempDir;
  late File sourceAudioFile;
  late File modelFile;
  late _FakeAudioConverter audioConverter;
  late _FakeWhisperBackend whisperBackend;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('engine_test_');
    sourceAudioFile = File(
      '${tempDir.path}${Platform.pathSeparator}recording.m4a',
    );
    sourceAudioFile.writeAsStringSync('dummy-audio-content');

    modelFile = File('${tempDir.path}${Platform.pathSeparator}ggml-test.bin');
    modelFile.writeAsStringSync('dummy-model-weights');

    audioConverter = _FakeAudioConverter();
    whisperBackend = _FakeWhisperBackend();
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  WhisperTranscriptionEngine createEngine({
    Duration audioDuration = const Duration(seconds: 30),
  }) {
    return WhisperTranscriptionEngine(
      audioConverter: audioConverter,
      audioInfoProvider: (path) async => AudioInfo(
        duration: audioDuration,
        sampleRate: 44100,
        channels: 1,
        bitRate: 64000,
        format: 'm4a',
      ),
      whisperLoader: (path) async => FlutterWhisper.withBackend(whisperBackend),
    );
  }

  group('WhisperTranscriptionEngine', () {
    test(
      'transcribe successfully produces segment-relative TranscriptSpans',
      () async {
        final engine = createEngine();
        final progressList = <double>[];

        final spans = await engine.transcribe(
          audioPath: sourceAudioFile.path,
          modelDirectory: modelFile.path,
          onProgress: progressList.add,
        );

        expect(audioConverter.wasCalled, isTrue);
        expect(whisperBackend.wasTranscribeCalled, isTrue);
        // Upstream auto mode currently requests language detection only.
        expect(whisperBackend.lastConfig?.language, 'en');
        expect(whisperBackend.lastConfig?.threads, 2);
        expect(spans.length, 2);
        expect(spans[0].text, 'Hello world');
        expect(spans[0].start, const Duration(seconds: 0));
        expect(spans[0].end, const Duration(seconds: 2));

        expect(spans[1].text, 'Testing transcription');
        expect(spans[1].start, const Duration(seconds: 2));
        expect(spans[1].end, const Duration(seconds: 5));

        // Progress verified clamped in [0.0, 1.0]
        expect(progressList, isNotEmpty);
        expect(progressList.first, equals(0.0));
        expect(progressList.last, equals(1.0));
        for (final p in progressList) {
          expect(p >= 0.0 && p <= 1.0, isTrue);
        }

        // Source audio file was preserved
        expect(sourceAudioFile.existsSync(), isTrue);
      },
    );

    test(
      'throws AudioDecodingException when source audio does not exist',
      () async {
        final engine = createEngine();
        expect(
          () => engine.transcribe(
            audioPath: '${tempDir.path}/nonexistent.m4a',
            modelDirectory: modelFile.path,
            onProgress: (_) {},
          ),
          throwsA(isA<AudioDecodingException>()),
        );
      },
    );

    test(
      'throws WhisperModelNotFoundException when no model file is in directory',
      () async {
        final engine = createEngine();
        final emptyModelDir = Directory('${tempDir.path}/empty_models')
          ..createSync();

        expect(
          () => engine.transcribe(
            audioPath: sourceAudioFile.path,
            modelDirectory: emptyModelDir.path,
            onProgress: (_) {},
          ),
          throwsA(isA<WhisperModelNotFoundException>()),
        );
      },
    );

    test(
      'caps pilot duration and throws AudioDecodingException when audio > 10m',
      () async {
        final engine = createEngine(audioDuration: const Duration(minutes: 11));

        expect(
          () => engine.transcribe(
            audioPath: sourceAudioFile.path,
            modelDirectory: modelFile.path,
            onProgress: (_) {},
          ),
          throwsA(
            isA<AudioDecodingException>().having(
              (e) => e.message,
              'message',
              contains('10 minutes'),
            ),
          ),
        );
        // Ensure conversion was never even started
        expect(audioConverter.wasCalled, isFalse);
      },
    );

    test('disallows concurrent transcription jobs', () async {
      final engine = createEngine();
      whisperBackend.pendingTranscribe = Completer<WhisperResult>();

      final firstJob = engine.transcribe(
        audioPath: sourceAudioFile.path,
        modelDirectory: modelFile.path,
        onProgress: (_) {},
      );

      // Second transcribe while first is in flight
      expect(
        () => engine.transcribe(
          audioPath: sourceAudioFile.path,
          modelDirectory: modelFile.path,
          onProgress: (_) {},
        ),
        throwsA(isA<StateError>()),
      );

      // Clean up first job
      whisperBackend.pendingTranscribe!.complete(
        const WhisperResult(
          language: 'en',
          segments: [],
          vadSegments: [],
          timings: WhisperTimings(
            sample: Duration.zero,
            encode: Duration.zero,
            decode: Duration.zero,
            batchDecode: Duration.zero,
            prompt: Duration.zero,
          ),
        ),
      );
      await firstJob;
    });

    test(
      'cancellation throws TranscriptionCancelledException and stops backend',
      () async {
        final engine = createEngine();
        whisperBackend.pendingTranscribe = Completer<WhisperResult>();

        final job = engine.transcribe(
          audioPath: sourceAudioFile.path,
          modelDirectory: modelFile.path,
          onProgress: (_) {},
        );

        while (!whisperBackend.wasTranscribeCalled) {
          await Future<void>.delayed(Duration.zero);
        }
        final expected = expectLater(
          job,
          throwsA(isA<TranscriptionCancelledException>()),
        );
        await engine.cancel();
        await expected;
        expect(whisperBackend.wasCancelCalled, isTrue);
        expect(whisperBackend.wasDisposeCalled, isTrue);

        // Multiple cancels are idempotent
        await engine.cancel();
      },
    );

    test(
      'dispose cancels active work, cleans up resources and is idempotent',
      () async {
        final engine = createEngine();
        await engine.dispose();
        // Multiple disposes are idempotent
        await engine.dispose();

        expect(
          () => engine.transcribe(
            audioPath: sourceAudioFile.path,
            modelDirectory: modelFile.path,
            onProgress: (_) {},
          ),
          throwsA(isA<StateError>()),
        );
      },
    );
  });
  test('FR-TRN-04 metadata failure and nonpositive duration fail closed before conversion', () async {
    for (final duration in [Duration.zero, const Duration(seconds: -1)]) {
      final engine = createEngine(audioDuration: duration);
      await expectLater(
        engine.transcribe(
          audioPath: sourceAudioFile.path,
          modelDirectory: modelFile.path,
          onProgress: (_) {},
        ),
        throwsA(isA<AudioDecodingException>()),
      );
      expect(audioConverter.wasCalled, isFalse);
      await engine.dispose();
    }
    final engine = WhisperTranscriptionEngine(
      audioConverter: audioConverter,
      audioInfoProvider: (_) async => throw StateError('metadata unavailable'),
    );
    await expectLater(
      engine.transcribe(
        audioPath: sourceAudioFile.path,
        modelDirectory: modelFile.path,
        onProgress: (_) {},
      ),
      throwsA(isA<AudioDecodingException>()),
    );
    expect(audioConverter.wasCalled, isFalse);
    await engine.dispose();
  });

  test(
    'FR-TRN-06 metadata wait is reserved and cancellation cannot be reset',
    () async {
      final info = Completer<AudioInfo>();
      final engine = WhisperTranscriptionEngine(
        audioConverter: audioConverter,
        audioInfoProvider: (_) => info.future,
      );
      final job = engine.transcribe(
        audioPath: sourceAudioFile.path,
        modelDirectory: modelFile.path,
        onProgress: (_) {},
      );
      expect(
        () => engine.transcribe(
          audioPath: sourceAudioFile.path,
          modelDirectory: modelFile.path,
          onProgress: (_) {},
        ),
        throwsStateError,
      );
      final expected = expectLater(
        job,
        throwsA(isA<TranscriptionCancelledException>()),
      );
      final cancelled = engine.cancel();
      info.complete(
        const AudioInfo(
          duration: Duration(seconds: 1),
          sampleRate: 16000,
          channels: 1,
          bitRate: 256000,
          format: 'wav',
        ),
      );
      await cancelled;
      await expected;
      expect(audioConverter.wasCalled, isFalse);
      await engine.dispose();
    },
  );

  test(
    'FR-TRN-06 dispose drains a late native load and releases its session',
    () async {
      final loaded = Completer<FlutterWhisper>();
      final entered = Completer<void>();
      final engine = WhisperTranscriptionEngine(
        audioConverter: audioConverter,
        audioInfoProvider: (_) async => const AudioInfo(
          duration: Duration(seconds: 1),
          sampleRate: 16000,
          channels: 1,
          bitRate: 256000,
          format: 'wav',
        ),
        whisperLoader: (_) {
          entered.complete();
          return loaded.future;
        },
      );
      final job = engine.transcribe(
        audioPath: sourceAudioFile.path,
        modelDirectory: modelFile.path,
        onProgress: (_) {},
      );
      final expected = expectLater(
        job,
        throwsA(isA<TranscriptionCancelledException>()),
      );
      await entered.future;
      var completed = false;
      final disposed = engine.dispose().then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      loaded.complete(FlutterWhisper.withBackend(whisperBackend));
      await disposed;
      await expected;
      expect(whisperBackend.wasDisposeCalled, isTrue);
      expect(whisperBackend.wasTranscribeCalled, isFalse);
      await engine.dispose();
    },
  );

  test(
    'FR-TRN-04 oversized converted WAV is refused before backend allocation',
    () async {
      final engine = WhisperTranscriptionEngine(
        audioConverter: _OversizedConverter(),
        audioInfoProvider: (_) async => const AudioInfo(
          duration: Duration(seconds: 1),
          sampleRate: 16000,
          channels: 1,
          bitRate: 256000,
          format: 'wav',
        ),
        whisperLoader: (_) async {
          fail('No native model allocation for oversized output');
        },
      );
      await expectLater(
        engine.transcribe(
          audioPath: sourceAudioFile.path,
          modelDirectory: modelFile.path,
          onProgress: (_) {},
        ),
        throwsA(isA<AudioDecodingException>()),
      );
      expect(sourceAudioFile.readAsStringSync(), 'dummy-audio-content');
      await engine.dispose();
    },
  );
}

class _OversizedConverter implements AudioToWavConverter {
  @override
  Future<String> convertToWav({
    required String inputPath,
    required String outputPath,
    int sampleRate = 16000,
    int channels = 1,
    int bitDepth = 16,
  }) async {
    final handle = File(outputPath).openSync(mode: FileMode.write);
    handle.truncateSync(kMaxPilotWavBytes + 1);
    handle.closeSync();
    return outputPath;
  }
}
