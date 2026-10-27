import 'dart:io';

import '../../domain/services/cut_range_math.dart';

/// The result of an audio trim operation (FR-REV-06, FR-REV-07).
class TrimResult {
  const TrimResult({
    required this.targetFile,
    required this.durationMs,
    required this.bytes,
    required this.sha256,
  });

  final File targetFile;
  final int durationMs;
  final int bytes;
  final String sha256;

  Map<String, Object?> toJson() => {
    'target_file': targetFile.path,
    'duration_ms': durationMs,
    'bytes': bytes,
    'sha256': sha256,
  };
}

/// Thrown when an audio trimming operation fails.
class AudioTrimException implements Exception {
  const AudioTrimException(this.message);

  final String message;

  @override
  String toString() => 'AudioTrimException: $message';
}

/// Abstract interface for platform audio trimming engines (FR-REV-07, ADR-003)
/// [P0-14].
///
/// Implementations must perform passthrough trimming without re-encoding,
/// stage output in a `.partial` temporary file, and guarantee non-destructive
/// safety: original files are never altered or deleted automatically (NFR-07).
abstract interface class AudioTrimmer {
  /// Trims [sourceFile] to retain only the audio in [keepRanges], writing the
  /// output to [targetFile].
  ///
  /// Atomic contract:
  /// - Staged in `<targetFile.path>.partial` during processing.
  /// - Atomically renamed to [targetFile] on success.
  /// - On failure or cancellation, `<targetFile.path>.partial` is cleaned up
  ///   and [sourceFile] is left completely untouched (FR-REV-06, NFR-07).
  Future<TrimResult> trim({
    required File sourceFile,
    required File targetFile,
    required List<TimeRange> keepRanges,
  });
}
