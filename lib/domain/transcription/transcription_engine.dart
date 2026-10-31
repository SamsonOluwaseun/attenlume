import 'transcript.dart';

export 'transcript.dart' show TranscriptSpan;

/// On-device, after-recording inference. The caller explicitly requests each job.
///
/// Inputs are read-only. Implementations keep inference off the UI isolate,
/// report finite progress in [0, 1], and release resources on cancellation.
/// Returned spans use offsets relative to the supplied audio segment.
abstract interface class TranscriptionEngine {
  Future<List<TranscriptSpan>> transcribe({
    required String audioPath,
    required String modelDirectory,
    required void Function(double) onProgress,
  });

  /// Idempotent. Stops the current job; its future throws cancellation below.
  /// Already saved text and original media are owned by the caller, never deleted.
  Future<void> cancel();

  /// Idempotent. Cancels current work and releases worker/model resources.
  Future<void> dispose();
}

final class TranscriptionCancelledException implements Exception {
  const TranscriptionCancelledException();

  @override
  String toString() => 'Transcription was cancelled';
}
