import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../domain/services/cut_range_math.dart';
import 'audio_trimmer.dart';

/// Configurable simulated audio trimmer for testing and benchmarks
/// (FR-REV-06, FR-REV-07) [P0-14].
///
/// Supports simulated delays, simulated memory allocations, and failure
/// injection while strictly respecting the atomic `.partial` transaction contract.
class SimulatedAudioTrimmer implements AudioTrimmer {
  SimulatedAudioTrimmer({
    this.delay = Duration.zero,
    this.shouldFail = false,
    this.failureMessage = 'Simulated trimming error',
  });

  final Duration delay;
  final bool shouldFail;
  final String failureMessage;

  @override
  Future<TrimResult> trim({
    required File sourceFile,
    required File targetFile,
    required List<TimeRange> keepRanges,
  }) async {
    if (!sourceFile.existsSync()) {
      throw AudioTrimException('Source file not found: ${sourceFile.path}');
    }

    if (keepRanges.isEmpty) {
      throw const AudioTrimException('Cannot trim: keepRanges is empty');
    }

    var totalDurationMs = 0;
    for (final r in keepRanges) {
      totalDurationMs += r.durationMs;
    }

    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }

    final parent = targetFile.parent;
    if (!parent.existsSync()) {
      await parent.create(recursive: true);
    }

    final partialFile = File('${targetFile.path}.partial');
    if (partialFile.existsSync()) {
      await partialFile.delete();
    }

    try {
      if (shouldFail) {
        // Write some partial data first, then fail
        await partialFile.writeAsString('partial data', flush: true);
        throw AudioTrimException(failureMessage);
      }

      // Stream copy simulated slice to partial file
      final sourceBytes = await sourceFile.length();
      final ratio = totalDurationMs > 0
          ? (totalDurationMs / 10000.0).clamp(0.1, 1.0)
          : 0.5;
      final targetBytes = (sourceBytes * ratio).round();

      final raf = await partialFile.open(mode: FileMode.write);
      await raf.truncate(targetBytes);
      await raf.close();

      final hash = await partialFile.openRead().transform(sha256).single;

      if (targetFile.existsSync()) {
        await targetFile.delete();
      }
      final finalised = await partialFile.rename(targetFile.path);

      return TrimResult(
        targetFile: finalised,
        durationMs: totalDurationMs,
        bytes: finalised.lengthSync(),
        sha256: hash.toString(),
      );
    } catch (e) {
      if (partialFile.existsSync()) {
        try {
          await partialFile.delete();
        } catch (_) {}
      }
      if (e is AudioTrimException) rethrow;
      throw AudioTrimException('Trimming failed: $e');
    }
  }
}
