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

/// Platform-neutral inspection of audio files to verify readability and duration.
abstract interface class AudioFileInspector {
  Future<InspectedAudioInfo> inspect(File file);
}

/// Default inspector implementation reusing M4aInspector and AudioDecoder.
class DefaultAudioFileInspector implements AudioFileInspector {
  const DefaultAudioFileInspector();

  @override
  Future<InspectedAudioInfo> inspect(File file) async {
    final ext = p.extension(file.path).toLowerCase();
    if (ext == '.m4a') {
      try {
        const m4aInspector = M4aInspector();
        final info = await m4aInspector.inspect(file);
        if (info.durationMs <= 0) {
          throw const AudioInspectionException(
            'Audio duration is zero or invalid',
          );
        }
        return InspectedAudioInfo(
          duration: Duration(milliseconds: info.durationMs),
          channelCount: info.channelCount,
          sampleRateHz: info.sampleRateHz,
          codec: info.codec,
          container: 'm4a',
          bitrateBps: info.observedBitrateBps > 0
              ? info.observedBitrateBps
              : null,
        );
      } catch (e) {
        // If M4aInspector fails, try AudioDecoder fallback below
      }
    }

    try {
      final info = await AudioDecoder.getAudioInfo(file.path);
      if (info.duration <= Duration.zero) {
        throw const AudioInspectionException(
          'Audio duration is zero or invalid',
        );
      }
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
