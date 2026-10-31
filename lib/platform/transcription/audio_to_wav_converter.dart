import 'package:audio_decoder/audio_decoder.dart';

import 'transcription_exceptions.dart';

/// Abstraction for converting arbitrary input audio files (M4A, MP3, AAC, WAV)
/// into a standard mono 16kHz 16-bit PCM WAV file required by Whisper.
abstract interface class AudioToWavConverter {
  /// Converts [inputPath] to WAV at [outputPath].
  ///
  /// Returns the path to the output WAV file.
  /// Throws [AudioDecodingException] if conversion fails.
  Future<String> convertToWav({
    required String inputPath,
    required String outputPath,
    int sampleRate = 16000,
    int channels = 1,
    int bitDepth = 16,
  });
}

/// Native implementation of [AudioToWavConverter] using `audio_decoder` (OS native decoders).
class NativeAudioToWavConverter implements AudioToWavConverter {
  const NativeAudioToWavConverter();

  @override
  Future<String> convertToWav({
    required String inputPath,
    required String outputPath,
    int sampleRate = 16000,
    int channels = 1,
    int bitDepth = 16,
  }) async {
    try {
      return await AudioDecoder.convertToWav(
        inputPath,
        outputPath,
        sampleRate: sampleRate,
        channels: channels,
        bitDepth: bitDepth,
      );
    } on AudioConversionException catch (e) {
      throw AudioDecodingException(e.message, cause: e);
    } catch (e) {
      throw AudioDecodingException(
        'Failed to convert audio to 16kHz mono WAV: $e',
        cause: e,
      );
    }
  }
}
