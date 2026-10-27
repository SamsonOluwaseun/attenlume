import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../data/filesystem/m4a_inspector.dart';
import '../../data/filesystem/mp4_sample_table.dart';
import '../../domain/services/cut_range_math.dart';
import 'audio_trimmer.dart';

/// Passthrough trimmer that rewrites the MP4 sample tables (FR-REV-06,
/// FR-REV-07, ADR-037) [P1-19].
///
/// Encoded AAC frames whose start time falls inside a keep range are copied
/// byte for byte into a new file; nothing is decoded or re-encoded, so the
/// kept audio is exactly the original. Cuts land on frame boundaries
/// (1024 samples, about 21 ms at 48 kHz). The new file is written
/// `ftyp`, `moov`, `mdat` (fast start) with only the audio track; edit
/// lists and metadata boxes are left out.
///
/// The same Dart code runs on Android, iOS and Windows because every
/// platform records AAC in MP4 (ADR-012). Memory is bounded: the sample
/// tables and one copy buffer at a time (NFR-10).
class Mp4SampleTrimmer implements AudioTrimmer {
  const Mp4SampleTrimmer({
    this.inspector = const M4aInspector(),
    this.samplesPerChunk = 32,
    this.copyBufferBytes = 1024 * 1024,
  });

  final M4aInspector inspector;
  final int samplesPerChunk;
  final int copyBufferBytes;

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
    if (targetFile.existsSync()) {
      // Never overwrite a file: it could be an original (NFR-07).
      throw AudioTrimException('Target already exists: ${targetFile.path}');
    }

    final Mp4SampleTable table;
    try {
      table = await Mp4SampleTable.read(sourceFile);
    } on MediaInspectionException catch (e) {
      throw AudioTrimException(e.message);
    }

    final selected = selectSamples(table, keepRanges);
    if (selected.isEmpty) {
      throw const AudioTrimException('Cannot trim: no audio is kept');
    }

    await targetFile.parent.create(recursive: true);
    final partialFile = File('${targetFile.path}.partial');
    if (partialFile.existsSync()) await partialFile.delete();

    try {
      var payloadBytes = 0;
      var mediaUnits = 0;
      for (final i in selected) {
        payloadBytes += table.sampleSizes[i];
        mediaUnits += table.sampleDurations[i];
      }
      final ftyp = table.ftyp;
      final largeMdat = payloadBytes + 8 > 0xFFFFFFFF;
      final mdatHeader = largeMdat ? 16 : 8;
      final use64 = ftyp.length + payloadBytes + 64 * 1024 > 0xFFFFFFFF;
      // The moov size does not depend on the offsets in it, so build it
      // once to measure and once with the real base offset.
      final probe = _buildMoov(table, selected, mediaUnits, 0, use64);
      final base = ftyp.length + probe.length + mdatHeader;
      final moov = _buildMoov(table, selected, mediaUnits, base, use64);

      final out = await partialFile.open(mode: FileMode.write);
      final source = await sourceFile.open();
      try {
        await out.writeFrom(ftyp);
        await out.writeFrom(moov);
        final header = Uint8List(mdatHeader);
        final view = ByteData.sublistView(header);
        if (largeMdat) {
          view.setUint32(0, 1);
          view.setUint64(8, payloadBytes + 16);
        } else {
          view.setUint32(0, payloadBytes + 8);
        }
        header.setAll(4, ascii.encode('mdat'));
        await out.writeFrom(header);
        await _copySamples(table, selected, source, out);
        await out.flush();
      } finally {
        await source.close();
        await out.close();
      }

      final AudioFileInfo info;
      try {
        info = await inspector.inspect(partialFile);
      } on MediaInspectionException catch (e) {
        throw AudioTrimException('Trimmed file did not verify: ${e.message}');
      }
      if (info.durationMs <= 0) {
        throw const AudioTrimException('Trimmed file has no duration');
      }
      final hash = await partialFile.openRead().transform(sha256).single;
      final finalised = await partialFile.rename(targetFile.path);
      return TrimResult(
        targetFile: finalised,
        durationMs: (mediaUnits * 1000 / table.mediaTimescale).round(),
        bytes: finalised.lengthSync(),
        sha256: hash.toString(),
      );
    } catch (e) {
      if (partialFile.existsSync()) {
        try {
          await partialFile.delete();
        } on FileSystemException {
          // Leave it; the next attempt deletes it first.
        }
      }
      if (e is AudioTrimException) rethrow;
      throw AudioTrimException('Trimming failed: $e');
    }
  }

  /// Indexes of the samples whose start time falls inside a keep range.
  static List<int> selectSamples(
    Mp4SampleTable table,
    List<TimeRange> keepRanges,
  ) {
    final ranges = [...keepRanges]
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    final selected = <int>[];
    var t = 0;
    var r = 0;
    for (var i = 0; i < table.sampleCount; i++) {
      final ms = t * 1000 / table.mediaTimescale;
      t += table.sampleDurations[i];
      while (r < ranges.length && ms >= ranges[r].endMs) {
        r++;
      }
      if (r == ranges.length) break;
      if (ms >= ranges[r].startMs) selected.add(i);
    }
    return selected;
  }

  Future<void> _copySamples(
    Mp4SampleTable table,
    List<int> selected,
    RandomAccessFile source,
    RandomAccessFile out,
  ) async {
    var runStart = -1;
    var runEnd = -1;
    Future<void> flushRun() async {
      var pos = runStart;
      while (pos < runEnd) {
        final n = math.min(copyBufferBytes, runEnd - pos);
        await source.setPosition(pos);
        final bytes = await source.read(n);
        if (bytes.length != n) {
          throw const AudioTrimException('Source file ended early');
        }
        await out.writeFrom(bytes);
        pos += n;
      }
    }

    for (final i in selected) {
      final start = table.sampleOffsets[i];
      final end = start + table.sampleSizes[i];
      if (start == runEnd && runEnd - runStart < copyBufferBytes) {
        runEnd = end;
        continue;
      }
      if (runStart >= 0) await flushRun();
      runStart = start;
      runEnd = end;
    }
    if (runStart >= 0) await flushRun();
  }

  Uint8List _buildMoov(
    Mp4SampleTable table,
    List<int> selected,
    int mediaUnits,
    int base,
    bool use64,
  ) {
    final moov = table.moov;
    final movieUnits =
        (mediaUnits * table.movieTimescale / table.mediaTimescale).round();
    Uint8List payload(Mp4Box b) => Uint8List.sublistView(moov, b.start, b.end);

    final mvhd = Uint8List.fromList(payload(table.mvhd));
    _patchDuration(mvhd, v0At: 16, v1At: 24, value: movieUnits);

    final trakParts = BytesBuilder(copy: false);
    for (final box in mp4Children(moov, table.trak.start, table.trak.end)) {
      switch (box.type) {
        case 'tkhd':
          final tkhd = Uint8List.fromList(payload(box));
          _patchDuration(tkhd, v0At: 20, v1At: 28, value: movieUnits);
          trakParts.add(_box('tkhd', tkhd));
        case 'mdia':
          trakParts.add(
            _box(
              'mdia',
              _buildMdia(table, box, selected, mediaUnits, base, use64),
            ),
          );
      }
    }
    return _box('moov', [
      ..._box('mvhd', mvhd),
      ..._box('trak', trakParts.takeBytes()),
    ]);
  }

  Uint8List _buildMdia(
    Mp4SampleTable table,
    Mp4Box mdia,
    List<int> selected,
    int mediaUnits,
    int base,
    bool use64,
  ) {
    final moov = table.moov;
    Uint8List payload(Mp4Box b) => Uint8List.sublistView(moov, b.start, b.end);
    final parts = BytesBuilder(copy: false);
    for (final box in mp4Children(moov, mdia.start, mdia.end)) {
      switch (box.type) {
        case 'mdhd':
          final mdhd = Uint8List.fromList(payload(box));
          _patchDuration(mdhd, v0At: 16, v1At: 24, value: mediaUnits);
          parts.add(_box('mdhd', mdhd));
        case 'hdlr':
          parts.add(_box('hdlr', payload(box)));
        case 'minf':
          final minf = BytesBuilder(copy: false);
          for (final child in mp4Children(moov, box.start, box.end)) {
            if (child.type == 'stbl') {
              final stsd = mp4Children(
                moov,
                child.start,
                child.end,
              ).firstWhere((b) => b.type == 'stsd');
              minf.add(
                _box(
                  'stbl',
                  _buildStbl(table, payload(stsd), selected, base, use64),
                ),
              );
            } else {
              minf.add(_box(child.type, payload(child)));
            }
          }
          parts.add(_box('minf', minf.takeBytes()));
      }
    }
    return parts.takeBytes();
  }

  Uint8List _buildStbl(
    Mp4SampleTable table,
    Uint8List stsd,
    List<int> selected,
    int base,
    bool use64,
  ) {
    final n = selected.length;

    // stts: run-length encoded durations.
    final runs = <(int, int)>[];
    for (final i in selected) {
      final d = table.sampleDurations[i];
      if (runs.isNotEmpty && runs.last.$2 == d) {
        runs[runs.length - 1] = (runs.last.$1 + 1, d);
      } else {
        runs.add((1, d));
      }
    }
    final stts = ByteData(8 + runs.length * 8)..setUint32(4, runs.length);
    for (var k = 0; k < runs.length; k++) {
      stts
        ..setUint32(8 + k * 8, runs[k].$1)
        ..setUint32(12 + k * 8, runs[k].$2);
    }

    // stsc: fixed-size chunks, the last one possibly shorter.
    final chunks = (n + samplesPerChunk - 1) ~/ samplesPerChunk;
    final remainder = n % samplesPerChunk;
    final stscRows = <(int, int)>[
      (1, remainder == 0 || chunks > 1 ? samplesPerChunk : remainder),
      if (remainder != 0 && chunks > 1) (chunks, remainder),
    ];
    final stsc = ByteData(8 + stscRows.length * 12)
      ..setUint32(4, stscRows.length);
    for (var k = 0; k < stscRows.length; k++) {
      stsc
        ..setUint32(8 + k * 12, stscRows[k].$1)
        ..setUint32(12 + k * 12, stscRows[k].$2)
        ..setUint32(16 + k * 12, 1);
    }

    // stsz and chunk offsets.
    final stsz = ByteData(12 + n * 4)..setUint32(8, n);
    final entry = use64 ? 8 : 4;
    final stco = ByteData(8 + chunks * entry)..setUint32(4, chunks);
    var pos = base;
    for (var k = 0; k < n; k++) {
      final size = table.sampleSizes[selected[k]];
      stsz.setUint32(12 + k * 4, size);
      if (k % samplesPerChunk == 0) {
        final c = k ~/ samplesPerChunk;
        if (use64) {
          stco.setUint64(8 + c * 8, pos);
        } else {
          stco.setUint32(8 + c * 4, pos);
        }
      }
      pos += size;
    }

    return Uint8List.fromList([
      ..._box('stsd', stsd),
      ..._box('stts', stts.buffer.asUint8List()),
      ..._box('stsc', stsc.buffer.asUint8List()),
      ..._box('stsz', stsz.buffer.asUint8List()),
      ..._box(use64 ? 'co64' : 'stco', stco.buffer.asUint8List()),
    ]);
  }

  /// Writes [value] into the duration field of a version 0 or 1 full box
  /// payload (`mvhd`, `tkhd`, `mdhd`).
  static void _patchDuration(
    Uint8List payload, {
    required int v0At,
    required int v1At,
    required int value,
  }) {
    final view = ByteData.sublistView(payload);
    if (payload[0] == 1) {
      view.setUint64(v1At, value);
    } else {
      view.setUint32(v0At, math.min(value, 0xFFFFFFFF));
    }
  }

  static Uint8List _box(String type, List<int> payload) {
    final out = Uint8List(payload.length + 8);
    ByteData.sublistView(out).setUint32(0, payload.length + 8);
    out.setAll(4, ascii.encode(type));
    out.setAll(8, payload);
    return out;
  }
}
