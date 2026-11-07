import 'dart:io';

import 'package:audio_decoder/audio_decoder.dart';
import 'package:path/path.dart' as p;

import '../../data/filesystem/m4a_inspector.dart';

/// Metadata extracted from an audio file before importing (FR-TRN-03) [P2-13].
class InspectedAudioInfo {
  const InspectedAudioInfo({
    required this.duration,
    required this.channelCount,
    required this.sampleRateHz,
    required this.codec,
    required this.container,
    this.bitrateBps,
  });

  final Duration duration;
  final int channelCount;
  final int sampleRateHz;
  final String codec;
  final String container;
  final int? bitrateBps;
}

/// Thrown when an audio file cannot be decoded or inspected.
class AudioInspectionException implements Exception {
  const AudioInspectionException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'AudioInspectionException: $message';
}

/// Signature for fetching audio metadata via the platform decoder.
typedef AudioInfoProvider = Future<AudioInfo> Function(String path);

/// Signature for decoding a slice of an audio file to WAV to verify sample readability.
typedef AudioSampleDecoder = Future<String> Function(
  String inputPath,
  String outputPath,
  Duration start,
  Duration end,
);

/// Platform-neutral inspection of audio files to verify readability and duration.
abstract interface class AudioFileInspector {
  Future<InspectedAudioInfo> inspect(File file);
}

/// Default inspector implementation reusing M4aInspector and AudioDecoder.
class DefaultAudioFileInspector implements AudioFileInspector {
  const DefaultAudioFileInspector({
    this.audioInfoProvider = AudioDecoder.getAudioInfo,
    this.sampleDecoder = AudioDecoder.trimAudio,
    this.m4aInspector = const M4aInspector(),
  });

  final AudioInfoProvider audioInfoProvider;
  final AudioSampleDecoder sampleDecoder;
  final M4aInspector m4aInspector;

  Future<void> _verifySampleReadability(
    File file,
    Duration totalDuration,
  ) async {
    final sliceEnd = totalDuration < const Duration(seconds: 3)
        ? totalDuration
        : const Duration(seconds: 3);

    final tempDir = Directory.systemTemp;
    final tempWav = File(
      p.join(
        tempDir.path,
        'attenlume_verify_${DateTime.now().microsecondsSinceEpoch}.wav',
      ),
    );

    try {
      await sampleDecoder(file.path, tempWav.path, Duration.zero, sliceEnd);
      if (!tempWav.existsSync() || tempWav.lengthSync() <= 44) {
        throw const AudioInspectionException(
          'Audio file contains no readable audio samples',
        );
      }
    } on AudioInspectionException {
      rethrow;
    } catch (e) {
      throw AudioInspectionException(
        'Could not decode audio samples: $e',
        cause: e,
      );
    } finally {
      try {
        if (tempWav.existsSync()) {
          tempWav.deleteSync();
        }
      } catch (_) {}
    }
  }

  @override
  Future<InspectedAudioInfo> inspect(File file) async {
    final ext = p.extension(file.path).toLowerCase();
    if (ext == '.m4a') {
      final info = await m4aInspector.inspect(file);
      if (info.durationMs <= 0) {
        throw const AudioInspectionException(
          'Audio duration is zero or invalid',
        );
      }
      if (info.mediaDataBytes <= 0) {
        throw const AudioInspectionException(
          'Audio file contains no audio data (mdat box is missing or empty)',
        );
      }

      // Require the platform decoder to read the file with a positive duration (FR-TRN-03) [P2-13].
      final AudioInfo decoded;
      try {
        decoded = await audioInfoProvider(file.path);
      } catch (e) {
        throw AudioInspectionException(
          'Could not decode audio file: $e',
          cause: e,
        );
      }
      if (decoded.duration <= Duration.zero) {
        throw const AudioInspectionException(
          'Audio duration is zero or invalid',
        );
      }

      // Prove sample readability before accepting by decoding a short slice (FR-TRN-03) [P2-13].
      await _verifySampleReadability(file, decoded.duration);

      return InspectedAudioInfo(
        duration: Duration(milliseconds: info.durationMs),
        channelCount: decoded.channels > 0
            ? decoded.channels
            : info.channelCount,
        sampleRateHz: decoded.sampleRate > 0
            ? decoded.sampleRate
            : info.sampleRateHz,
        codec: info.codec,
        container: 'm4a',
        bitrateBps: info.observedBitrateBps > 0
            ? info.observedBitrateBps
            : (decoded.bitRate > 0 ? decoded.bitRate : null),
      );
    }

    try {
      final info = await audioInfoProvider(file.path);
      if (info.duration <= Duration.zero) {
        throw const AudioInspectionException(
          'Audio duration is zero or invalid',
        );
      }

      // Prove sample readability before accepting by decoding a short slice (FR-TRN-03) [P2-13].
      await _verifySampleReadability(file, info.duration);

      final container = ext.startsWith('.') ? ext.substring(1) : ext;
      return InspectedAudioInfo(
        duration: info.duration,
        channelCount: info.channels,
        sampleRateHz: info.sampleRate,
        codec: _normalizeCodec(info.format, container),
        container: container,
        bitrateBps: info.bitRate > 0 ? info.bitRate : null,
      );
    } catch (e) {
      if (e is AudioInspectionException) rethrow;
      throw AudioInspectionException(
        'Could not decode audio file: $e',
        cause: e,
      );
    }
  }

  static String _normalizeCodec(String format, String container) {
    final lower = format.toLowerCase();
    if (lower.contains('aac')) return 'aac_lc';
    if (lower.contains('mp3') || lower.contains('mpeg')) return 'mp3';
    if (lower.contains('pcm') || lower.contains('wav')) return 'pcm_s16le';
    return container;
  }
}
