import 'dart:core';

/// Exception thrown when native audio decoding or conversion to 16kHz mono WAV fails.
class AudioDecodingException implements Exception {
  const AudioDecodingException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'AudioDecodingException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Exception thrown when a preinstalled Whisper model is not found in the given location.
///
/// Attenlume never downloads or loads models automatically on transcribe.
class WhisperModelNotFoundException implements Exception {
  const WhisperModelNotFoundException(this.message);

  final String message;

  @override
  String toString() => 'WhisperModelNotFoundException: $message';
}

/// Exception thrown when model storage preflight, download or verification fails.
class WhisperStorageException implements Exception {
  const WhisperStorageException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'WhisperStorageException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Exception thrown when the native Whisper inference engine reports an error.
class WhisperEngineException implements Exception {
  const WhisperEngineException(this.message, {this.code, this.cause});

  final String message;
  final int? code;
  final Object? cause;

  @override
  String toString() =>
      'WhisperEngineException: $message${code != null ? ' (code $code)' : ''}${cause != null ? ' ($cause)' : ''}';
}
