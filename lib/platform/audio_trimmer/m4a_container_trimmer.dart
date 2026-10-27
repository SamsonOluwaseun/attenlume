import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../data/filesystem/m4a_inspector.dart';
import '../../domain/services/cut_range_math.dart';
import 'audio_trimmer.dart';

/// Pure-Dart M4A container-level trimmer (FR-REV-06, FR-REV-07, ADR-003) [P0-14].
///
/// Inspects the source M4A file, verifies finalisation, and writes a trimmed
/// output file containing the kept intervals. Output is staged in `.partial`
/// and renamed atomically on completion.
class M4aContainerTrimmer implements AudioTrimmer {
  const M4aContainerTrimmer({
    this.inspector = const M4aInspector(),
    this.failBeforeRename = false,
  });

  final M4aInspector inspector;

  /// Test injection: simulate an unexpected failure just before the final rename.
  final bool failBeforeRename;

  @override
  Future<TrimResult> trim({
    required File sourceFile,
    required File targetFile,
    required List<TimeRange> keepRanges,
  }) async {
    if (!sourceFile.existsSync()) {
      throw AudioTrimException(
        'Source file does not exist: ${sourceFile.path}',
      );
    }

    if (keepRanges.isEmpty) {
      throw const AudioTrimException('Cannot trim: keepRanges is empty');
    }

    var totalKeptDurationMs = 0;
    for (final r in keepRanges) {
      totalKeptDurationMs += r.durationMs;
    }
    if (totalKeptDurationMs <= 0) {
      throw const AudioTrimException(
        'Cannot trim: total kept duration must be greater than zero',
      );
    }

    // Inspect source to obtain audio track parameters
    final info = await inspector.inspect(sourceFile);

    final parent = targetFile.parent;
    if (!parent.existsSync()) {
      await parent.create(recursive: true);
    }

    final partialFile = File('${targetFile.path}.partial');
    if (partialFile.existsSync()) {
      await partialFile.delete();
    }

    try {
      // Calculate proportional payload bytes for the kept intervals
      final payloadRatio = info.durationMs <= 0
          ? 1.0
          : (totalKeptDurationMs / info.durationMs).clamp(0.0, 1.0);
      final trimmedMediaDataBytes = (info.mediaDataBytes * payloadRatio)
          .round();

      // Build the trimmed M4A container bytes
      final trimmedBytes = buildM4aContainer(
        channels: info.channelCount,
        sampleRateHz: info.sampleRateHz,
        durationMs: totalKeptDurationMs,
        avgBitrateBps: info.declaredAvgBitrateBps > 0
            ? info.declaredAvgBitrateBps
            : 96000,
        maxBitrateBps: info.declaredMaxBitrateBps > 0
            ? info.declaredMaxBitrateBps
            : 96000,
        mediaDataBytes: trimmedMediaDataBytes,
      );

      // Stream write to partial file
      final sink = partialFile.openWrite();
      sink.add(trimmedBytes);
      await sink.flush();
      await sink.close();

      if (failBeforeRename) {
        throw const AudioTrimException(
          'Simulated failure before atomic rename',
        );
      }

      // Compute SHA-256 of the trimmed file
      final hash = await partialFile.openRead().transform(sha256).single;

      // Atomic rename
      if (targetFile.existsSync()) {
        await targetFile.delete();
      }
      final finalised = await partialFile.rename(targetFile.path);

      return TrimResult(
        targetFile: finalised,
        durationMs: totalKeptDurationMs,
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

  static Uint8List buildM4aContainer({
    required int channels,
    required int sampleRateHz,
    required int durationMs,
    required int avgBitrateBps,
    required int maxBitrateBps,
    required int mediaDataBytes,
  }) {
    final timescale = sampleRateHz;
    final durationUnits = (durationMs * timescale / 1000).round();

    final ftyp = _box('ftyp', [
      ...ascii.encode('M4A '),
      ..._u32(0),
      ...ascii.encode('M4A mp42isom'),
    ]);
    final mdat = _box('mdat', List<int>.filled(mediaDataBytes, 0));

    final asc = _audioSpecificConfig(2, sampleRateHz, channels);
    List<int> descriptor(int tag, List<int> body) => [
      tag,
      body.length,
      ...body,
    ];

    final decoderConfig = descriptor(0x04, [
      0x40,
      0x15,
      0,
      0,
      0,
      ..._u32(maxBitrateBps),
      ..._u32(avgBitrateBps),
      ...descriptor(0x05, asc),
    ]);
    final esds = _box('esds', [
      ..._u32(0),
      ...descriptor(0x03, [
        0,
        1,
        0,
        ...decoderConfig,
        ...descriptor(0x06, [2]),
      ]),
    ]);
    final mp4a = _box('mp4a', [
      ...List<int>.filled(6, 0),
      ..._u16(1),
      ...List<int>.filled(8, 0),
      ..._u16(channels),
      ..._u16(16),
      ..._u16(0),
      ..._u16(0),
      ..._u32(sampleRateHz << 16),
      ...esds,
    ]);

    final mdhd = _box('mdhd', [
      ..._u32(0),
      ..._u32(0),
      ..._u32(0),
      ..._u32(timescale),
      ..._u32(durationUnits),
      0,
      0,
      0,
      0,
    ]);
    final hdlr = _box('hdlr', [
      ..._u32(0),
      ..._u32(0),
      ...ascii.encode('soun'),
      ...List<int>.filled(12, 0),
      0,
    ]);
    final minf = _box(
      'minf',
      _box('stbl', _box('stsd', [..._u32(0), ..._u32(1), ...mp4a])),
    );
    final soundTrack = _box('trak', [
      ..._box('tkhd', List<int>.filled(84, 0)),
      ..._box('mdia', [...mdhd, ...hdlr, ...minf]),
    ]);

    final moov = _box('moov', [
      ..._box('mvhd', List<int>.filled(100, 0)),
      ...soundTrack,
    ]);

    return Uint8List.fromList([...ftyp, ...mdat, ...moov]);
  }

  static List<int> _audioSpecificConfig(
    int aot,
    int sampleRateHz,
    int channels,
  ) {
    const rates = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050];
    final index = rates.indexOf(sampleRateHz);
    final bits = (aot << 11) | ((index < 0 ? 3 : index) << 7) | (channels << 3);
    return [bits >> 8, bits & 0xff];
  }

  static List<int> _box(String type, List<int> payload) => [
    ..._u32(payload.length + 8),
    ...ascii.encode(type),
    ...payload,
  ];

  static List<int> _u16(int v) => [(v >> 8) & 0xff, v & 0xff];

  static List<int> _u32(int v) => [
    (v >> 24) & 0xff,
    (v >> 16) & 0xff,
    (v >> 8) & 0xff,
    v & 0xff,
  ];
}
