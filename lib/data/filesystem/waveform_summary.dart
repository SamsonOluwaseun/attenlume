import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Decimated level summary of one segment (FR-REV-03, ADR-034) [P1-17].
///
/// File layout: an 8-byte header (`ALWF`, version 1, reserved byte, bucket
/// length in ms as little-endian uint16), then one byte per bucket: the
/// input level in that bucket, 0 for -60 dBFS or quieter, 255 for 0 dBFS.
/// About 18 KB per hour at the default 200 ms buckets. Readers fetch only
/// the byte range they draw, so a full session is never in memory.
abstract final class WaveformSummary {
  static const magic = [0x41, 0x4C, 0x57, 0x46]; // ALWF
  static const version = 1;
  static const headerBytes = 8;
  static const defaultBucketMs = 200;

  /// Levels at or below this map to 0.
  static const floorDbfs = -60.0;

  /// Maps a dBFS reading to a stored byte.
  static int levelByte(double dbfs) {
    if (dbfs.isNaN || dbfs <= floorDbfs) return 0;
    if (dbfs >= 0) return 255;
    return ((dbfs - floorDbfs) / -floorDbfs * 255).round();
  }

  static Uint8List header(int bucketMs) {
    final bytes = Uint8List(headerBytes);
    bytes.setAll(0, magic);
    bytes[4] = version;
    ByteData.sublistView(bytes).setUint16(6, bucketMs, Endian.little);
    return bytes;
  }
}

/// Appends levels to a summary file while a segment records. Holds at most
/// [flushEvery] bytes before writing them out.
class WaveformSummaryWriter {
  WaveformSummaryWriter(
    this.file, {
    this.bucketMs = WaveformSummary.defaultBucketMs,
    this.flushEvery = 25,
  });

  final File file;
  final int bucketMs;
  final int flushEvery;

  final _pending = BytesBuilder(copy: false);
  Future<void> _writes = Future.value();
  bool _opened = false;
  bool _closed = false;

  void add(double dbfs) {
    if (_closed) return;
    _pending.addByte(WaveformSummary.levelByte(dbfs));
    if (_pending.length >= flushEvery) _flush();
  }

  void _flush() {
    final chunk = _pending.takeBytes();
    final first = !_opened;
    _opened = true;
    _writes = _writes.then((_) async {
      if (first) {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(WaveformSummary.header(bucketMs), flush: true);
      }
      if (chunk.isNotEmpty) {
        await file.writeAsBytes(chunk, mode: FileMode.append, flush: true);
      }
    });
  }

  /// Writes what is left. Safe to call twice.
  Future<void> close() {
    if (!_closed) {
      _closed = true;
      if (_pending.length > 0 || !_opened) _flush();
    }
    return _writes;
  }
}

/// Levels for part of a segment, [startMs] from the segment start.
class WaveformSlice {
  const WaveformSlice({
    required this.startMs,
    required this.bucketMs,
    required this.levels,
  });

  final int startMs;
  final int bucketMs;

  /// One byte per bucket, 0 to 255.
  final Uint8List levels;

  int get endMs => startMs + levels.length * bucketMs;
}

/// Reads part of a summary file without loading the rest.
class WaveformSummaryReader {
  const WaveformSummaryReader();

  /// Levels between [fromMs] and [toMs] into the segment, or null when the
  /// file is missing or not a summary.
  Future<WaveformSlice?> read(File file, {int fromMs = 0, int? toMs}) async {
    final RandomAccessFile raf;
    try {
      raf = await file.open();
    } on FileSystemException {
      return null;
    }
    try {
      final length = await raf.length();
      if (length < WaveformSummary.headerBytes) return null;
      final header = await raf.read(WaveformSummary.headerBytes);
      for (var i = 0; i < 4; i++) {
        if (header[i] != WaveformSummary.magic[i]) return null;
      }
      if (header[4] != WaveformSummary.version) return null;
      final bucketMs = ByteData.sublistView(header).getUint16(6, Endian.little);
      if (bucketMs == 0) return null;

      final buckets = length - WaveformSummary.headerBytes;
      final first = math.max(0, fromMs ~/ bucketMs);
      final last = toMs == null
          ? buckets
          : math.min(buckets, (toMs + bucketMs - 1) ~/ bucketMs);
      if (first >= last) {
        return WaveformSlice(
          startMs: first * bucketMs,
          bucketMs: bucketMs,
          levels: Uint8List(0),
        );
      }
      await raf.setPosition(WaveformSummary.headerBytes + first);
      final levels = await raf.read(last - first);
      return WaveformSlice(
        startMs: first * bucketMs,
        bucketMs: bucketMs,
        levels: levels,
      );
    } finally {
      await raf.close();
    }
  }
}
