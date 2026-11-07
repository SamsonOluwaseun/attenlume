import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:attenlume/domain/transcription/transcription_engine.dart';
import 'package:audio_decoder/audio_decoder.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_whisper_ggml/flutter_whisper.dart';

import 'audio_to_wav_converter.dart';
import 'transcription_exceptions.dart';
import 'whisper_cpu.dart';

const Duration kMaxPilotTranscriptionDuration = Duration(minutes: 10);
const int kMaxPilotPcmBytes = 10 * 60 * 16000 * 2;
const int kMaxPilotWavBytes = kMaxPilotPcmBytes + 65536;

/// Silence skipping before Whisper [P2-11, FR-TRN-10]. Tuned to keep speech:
/// only pauses of a second or more are skipped, and each speech region keeps
/// padding either side. whisper.cpp maps timestamps back to the original audio.
WhisperVadConfig speechDetection(String modelPath) => WhisperVadConfig(
  modelPath: modelPath,
  minimumSilenceDuration: const Duration(seconds: 1),
  speechPadding: const Duration(milliseconds: 300),
);

/// whisper.cpp maps a segment that straddles a skipped pause onto both
/// sides of it, so a sentence after a long gap could start back in the
/// earlier speech. Such a segment is snapped to the speech region that holds
/// most of it, so tapping it plays its words, not the silence [P2-11].
/// [regions] are in original audio time; without them nothing changes.
@visibleForTesting
List<WhisperSegment> alignToSpeech(
  List<WhisperSegment> segments,
  List<WhisperVadSegment> regions,
) {
  if (regions.length < 2) return segments;
  // Continuous speech is split into back-to-back regions (at most 30 s each);
  // only a real skipped pause separates two regions here.
  final sorted = [...regions]..sort((a, b) => a.start.compareTo(b.start));
  final speech = <WhisperVadSegment>[sorted.first];
  for (final r in sorted.skip(1)) {
    final last = speech.last;
    if (r.start - last.end < const Duration(milliseconds: 500)) {
      speech.last = WhisperVadSegment(
        start: last.start,
        end: r.end > last.end ? r.end : last.end,
      );
    } else {
      speech.add(r);
    }
  }
  if (speech.length < 2) return segments;
  Duration overlap(WhisperSegment s, WhisperVadSegment r) {
    final start = s.start > r.start ? s.start : r.start;
    final end = s.end < r.end ? s.end : r.end;
    return end > start ? end - start : Duration.zero;
  }

  return [
    for (final segment in segments)
      () {
        final touched = [
          for (final r in speech)
            if (overlap(segment, r) > Duration.zero) r,
        ];
        if (touched.length < 2) return segment;
        // On a tie the later speech wins: text after a long pause is the
        // usual case.
        final best = touched.reduce(
          (a, b) => overlap(segment, b) >= overlap(segment, a) ? b : a,
        );
        return WhisperSegment(
          text: segment.text,
          start: segment.start > best.start ? segment.start : best.start,
          end: segment.end < best.end ? segment.end : best.end,
        );
      }(),
  ];
}

/// Explicit, offline after-recording inference with bounded PCM decoding.
/// Native conversion/model loading cannot be interrupted by their APIs: cancel
/// requests inference cancellation immediately, then drains them before cleanup.
class WhisperTranscriptionEngine implements TranscriptionEngine {
  WhisperTranscriptionEngine({
    AudioToWavConverter? audioConverter,
    Future<AudioInfo> Function(String path)? audioInfoProvider,
    Future<FlutterWhisper> Function(String modelPath)? whisperLoader,
    this.cpu = const PlatformWhisperCpu(),
    this.vadModelPath,
  }) : _audioConverter = audioConverter ?? const NativeAudioToWavConverter(),
       _audioInfoProvider = audioInfoProvider ?? AudioDecoder.getAudioInfo,
       _whisperLoader =
           whisperLoader ??
           ((path) => FlutterWhisper.load(
             modelPath: path,
             config: const WhisperModelConfig(useGpu: false),
           ));

  final AudioToWavConverter _audioConverter;
  final WhisperCpu cpu;

  /// The verified Silero model, or null to transcribe every sample as before.
  final Future<String?> Function()? vadModelPath;
  final Future<AudioInfo> Function(String path) _audioInfoProvider;
  final Future<FlutterWhisper> Function(String modelPath) _whisperLoader;
  bool _isTranscribing = false;
  bool _isCancelled = false;
  bool _disposed = false;
  FlutterWhisper? _currentWhisper;
  Future<void> _active = Future<void>.value();
  Future<void> _sessionDisposal = Future<void>.value();
  Future<void>? _disposing;

  @override
  Future<List<TranscriptSpan>> transcribe({
    required String audioPath,
    required String modelDirectory,
    required void Function(double) onProgress,
  }) {
    if (_disposed) {
      throw StateError('WhisperTranscriptionEngine has been disposed.');
    }
    if (_isTranscribing) {
      throw StateError(
        'A transcription job is already active on this engine instance.',
      );
    }
    // Reserve the job before the first metadata/path/loading await.
    _isTranscribing = true;
    _isCancelled = false;
    final result = _perform(audioPath, modelDirectory, onProgress);
    _active = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<List<TranscriptSpan>> _perform(
    String audioPath,
    String selectedModelFile,
    void Function(double) onProgress,
  ) async {
    Directory? temp;
    try {
      requireWhisperCpu(cpu);
      final source = File(audioPath);
      if (!source.existsSync()) {
        throw const AudioDecodingException('Source audio file not found.');
      }
      // Caller supplies the selected, store-verified model FILE, never a directory
      // to scan or a model name to download automatically.
      final model = File(selectedModelFile);
      if (FileSystemEntity.typeSync(model.path, followLinks: false) !=
              FileSystemEntityType.file ||
          model.lengthSync() == 0) {
        throw const WhisperModelNotFoundException(
          'A regular, installed model file is required.',
        );
      }
      AudioInfo info;
      try {
        info = await _audioInfoProvider(audioPath);
      } on Object catch (error) {
        throw AudioDecodingException(
          'Audio duration could not be verified; bounded decoding is required.',
          cause: error,
        );
      }
      _checkCancelled();
      if (info.duration <= Duration.zero ||
          info.duration > kMaxPilotTranscriptionDuration) {
        throw const AudioDecodingException(
          'Audio duration must be positive and no longer than 10 minutes for this pilot.',
        );
      }
      temp = Directory.systemTemp.createTempSync('attenlume_trn_');
      final wav = File(
        '${temp.path}${Platform.pathSeparator}input_16k_mono.wav',
      );
      onProgress(0);
      await _audioConverter.convertToWav(
        inputPath: audioPath,
        outputPath: wav.path,
        sampleRate: 16000,
        channels: 1,
        bitDepth: 16,
      );
      _checkCancelled();
      _validateWav(wav);
      final loaded = await _whisperLoader(model.path);
      // A late load must release its native session even after dispose was called.
      if (_disposed || _isCancelled) {
        await loaded.dispose();
        throw const TranscriptionCancelledException();
      }
      _currentWhisper = loaded;
      final vadPath = await vadModelPath?.call();
      _checkCancelled();
      final result = await loaded.transcribeFile(
        wav.path,
        config: WhisperTranscribeConfig(
          language: 'en',
          threads: 2,
          noContext: true,
          vad: vadPath == null ? null : speechDetection(vadPath),
        ),
        onProgress: (percent) {
          if (!_isCancelled && !_disposed) {
            onProgress((percent / 100).clamp(0, 1));
          }
        },
      );
      _checkCancelled();
      onProgress(1);
      return [
        for (final segment in alignToSpeech(
          result.segments,
          result.vadSegments,
        ))
          if (segment.text.trim().isNotEmpty)
            TranscriptSpan(
              start: segment.start.isNegative ? Duration.zero : segment.start,
              end:
                  segment.end <
                      (segment.start.isNegative ? Duration.zero : segment.start)
                  ? (segment.start.isNegative ? Duration.zero : segment.start)
                  : segment.end,
              text: segment.text.trim(),
            ),
      ];
    } on Object catch (error) {
      if (_isCancelled ||
          _disposed ||
          error is TranscriptionCancelledException) {
        throw const TranscriptionCancelledException();
      }
      if (error is AudioDecodingException ||
          error is UnsupportedWhisperCpuException ||
          error is WhisperModelNotFoundException) {
        rethrow;
      }
      if (error is WhisperException) {
        throw WhisperEngineException(
          error.message,
          code: error.code,
          cause: error,
        );
      }
      throw WhisperEngineException('Local transcription failed.', cause: error);
    } finally {
      try {
        await _releaseSession();
      } finally {
        if (temp != null && temp.existsSync()) temp.deleteSync(recursive: true);
        _isTranscribing = false;
      }
    }
  }

  void _checkCancelled() {
    if (_isCancelled || _disposed) {
      throw const TranscriptionCancelledException();
    }
  }

  @override
  Future<void> cancel() async {
    _isCancelled = true;
    _currentWhisper?.cancel();
    await _active;
    await _releaseSession();
  }

  Future<void> _releaseSession() async {
    final session = _currentWhisper;
    _currentWhisper = null;
    if (session != null) _sessionDisposal = session.dispose();
    await _sessionDisposal;
  }

  @override
  Future<void> dispose() {
    _disposed = true;
    return _disposing ??= cancel();
  }
}

/// Header parsing reads bounded small chunks before the package allocates PCM.
void _validateWav(File file) {
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      file.lengthSync() < 44 ||
      file.lengthSync() > kMaxPilotWavBytes) {
    throw const AudioDecodingException(
      'Decoded WAV exceeds the bounded pilot size or is invalid.',
    );
  }
  final handle = file.openSync();
  try {
    final header = handle.readSync(12);
    String tag(List<int> bytes, int start) =>
        String.fromCharCodes(bytes.skip(start).take(4));
    int number(List<int> bytes, int start, [int size = 4]) => size == 4
        ? ByteData.sublistView(Uint8List.fromList(bytes))
              .getUint32(start, Endian.little)
        : ByteData.sublistView(Uint8List.fromList(bytes))
              .getUint16(start, Endian.little);
    if (tag(header, 0) != 'RIFF' ||
        tag(header, 8) != 'WAVE' ||
        number(header, 4) + 8 != file.lengthSync()) {
      throw const AudioDecodingException(
        'Decoded audio is not a valid bounded WAV.',
      );
    }
    var format = false;
    var offset = 12;
    while (offset + 8 <= file.lengthSync() && offset <= 65536) {
      handle.setPositionSync(offset);
      final chunk = handle.readSync(8);
      final size = number(chunk, 4);
      final end = offset + 8 + size;
      if (end > file.lengthSync()) {
        throw const AudioDecodingException('Truncated decoded WAV.');
      }
      if (tag(chunk, 0) == 'fmt ') {
        if (size < 16 || size > 65536) {
          throw const AudioDecodingException('Invalid WAV format.');
        }
        final fmt = handle.readSync(16);
        format =
            number(fmt, 0, 2) == 1 &&
            number(fmt, 2, 2) == 1 &&
            number(fmt, 4) == 16000 &&
            number(fmt, 8) == 32000 &&
            number(fmt, 12, 2) == 2 &&
            number(fmt, 14, 2) == 16;
      } else if (tag(chunk, 0) == 'data') {
        if (!format || size == 0 || size.isOdd || size > kMaxPilotPcmBytes) {
          throw const AudioDecodingException(
            'Decoded WAV must be mono 16kHz PCM16 within 10 minutes.',
          );
        }
        return;
      }
      offset = end + (size.isOdd ? 1 : 0);
    }
    throw const AudioDecodingException('Decoded WAV has no bounded PCM data.');
  } finally {
    handle.closeSync();
  }
}
