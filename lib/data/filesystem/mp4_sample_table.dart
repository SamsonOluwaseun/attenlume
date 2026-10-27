import 'dart:io';
import 'dart:typed_data';

import 'm4a_inspector.dart';

/// Box of an MP4 file: its type, where its payload starts and where it ends.
typedef Mp4Box = ({String type, int start, int end});

/// Children of the box payload between [start] and [end] in [data].
Iterable<Mp4Box> mp4Children(Uint8List data, int start, int end) sync* {
  final view = ByteData.sublistView(data);
  var offset = start;
  while (offset + 8 <= end) {
    var size = view.getUint32(offset);
    var headerSize = 8;
    if (size == 1) {
      if (offset + 16 > end) return;
      size = view.getUint64(offset + 8);
      headerSize = 16;
    } else if (size == 0) {
      size = end - offset;
    }
    if (size < headerSize || offset + size > end) {
      throw const MediaInspectionException('Malformed box inside moov');
    }
    yield (
      type: String.fromCharCodes(data, offset + 4, offset + 8),
      start: offset + headerSize,
      end: offset + size,
    );
    offset += size;
  }
}

Mp4Box? _child(Uint8List data, Mp4Box parent, String type) {
  for (final box in mp4Children(data, parent.start, parent.end)) {
    if (box.type == type) return box;
  }
  return null;
}

/// The audio track of a finalised MP4/M4A file and where every encoded
/// sample sits in it (FR-REV-07, ADR-037) [P1-19].
///
/// Only the `ftyp` and `moov` boxes are read into memory. A 10-minute
/// AAC segment has about 28,000 samples, so the tables stay small.
class Mp4SampleTable {
  Mp4SampleTable._({
    required this.ftyp,
    required this.moov,
    required this.mvhd,
    required this.trak,
    required this.movieTimescale,
    required this.mediaTimescale,
    required this.sampleOffsets,
    required this.sampleSizes,
    required this.sampleDurations,
  });

  /// Whole `ftyp` box, header included, copied as is into a trimmed file.
  final Uint8List ftyp;

  /// `moov` payload (without its header). The box positions below index it.
  final Uint8List moov;
  final Mp4Box mvhd;

  /// The audio (`soun`) track.
  final Mp4Box trak;
  final int movieTimescale;
  final int mediaTimescale;

  /// File offset, size and duration (in [mediaTimescale] units) per sample.
  final Int64List sampleOffsets;
  final Int32List sampleSizes;
  final Int32List sampleDurations;

  int get sampleCount => sampleSizes.length;

  /// Reads the tables of [file]. Throws [MediaInspectionException] for a file
  /// that is not finalised, is fragmented, or has no audio track.
  static Future<Mp4SampleTable> read(
    File file, {
    int maxMoovBytes = 16 * 1024 * 1024,
  }) async {
    final raf = await file.open();
    try {
      final length = await raf.length();
      Uint8List? ftyp;
      Uint8List? moov;
      var offset = 0;
      while (offset + 8 <= length) {
        await raf.setPosition(offset);
        final header = await raf.read(16);
        if (header.length < 8) break;
        final view = ByteData.sublistView(header);
        var size = view.getUint32(0);
        final type = String.fromCharCodes(header, 4, 8);
        var headerSize = 8;
        if (size == 1) {
          if (header.length < 16) break;
          size = view.getUint64(8);
          headerSize = 16;
        } else if (size == 0) {
          size = length - offset;
        }
        if (size < headerSize || offset + size > length) {
          throw MediaInspectionException(
            'Box "$type" at $offset runs past the end of the file',
          );
        }
        switch (type) {
          case 'ftyp':
            if (size > 4096) {
              throw const MediaInspectionException('ftyp box is too large');
            }
            await raf.setPosition(offset);
            ftyp = await raf.read(size);
          case 'moov':
            if (size > maxMoovBytes) {
              throw MediaInspectionException('moov box is $size bytes');
            }
            await raf.setPosition(offset + headerSize);
            moov = await raf.read(size - headerSize);
          case 'moof':
            throw const MediaInspectionException(
              'Fragmented MP4 files cannot be trimmed',
            );
        }
        offset += size;
      }
      if (ftyp == null) {
        throw const MediaInspectionException('No ftyp box: not an MP4 file');
      }
      if (moov == null) {
        throw const MediaInspectionException(
          'No moov box: the file was not finalised',
        );
      }
      return _parse(ftyp, moov, length);
    } finally {
      await raf.close();
    }
  }

  static Mp4SampleTable _parse(Uint8List ftyp, Uint8List moov, int fileLength) {
    final view = ByteData.sublistView(moov);
    final root = (type: 'moov', start: 0, end: moov.length);
    final mvhd = _child(moov, root, 'mvhd');
    if (mvhd == null) throw const MediaInspectionException('No mvhd box');
    if (_child(moov, root, 'mvex') != null) {
      throw const MediaInspectionException(
        'Fragmented MP4 files cannot be trimmed',
      );
    }
    final movieTimescale = moov[mvhd.start] == 1
        ? view.getUint32(mvhd.start + 20)
        : view.getUint32(mvhd.start + 12);

    for (final trak in mp4Children(moov, 0, moov.length)) {
      if (trak.type != 'trak') continue;
      final mdia = _child(moov, trak, 'mdia');
      if (mdia == null) continue;
      final hdlr = _child(moov, mdia, 'hdlr');
      if (hdlr == null ||
          String.fromCharCodes(moov, hdlr.start + 8, hdlr.start + 12) !=
              'soun') {
        continue;
      }
      final mdhd = _child(moov, mdia, 'mdhd');
      final minf = _child(moov, mdia, 'minf');
      final stbl = minf == null ? null : _child(moov, minf, 'stbl');
      if (mdhd == null || stbl == null) {
        throw const MediaInspectionException('Audio track has no sample table');
      }
      final mediaTimescale = moov[mdhd.start] == 1
          ? view.getUint32(mdhd.start + 20)
          : view.getUint32(mdhd.start + 12);
      if (mediaTimescale == 0 || movieTimescale == 0) {
        throw const MediaInspectionException('Zero timescale');
      }
      final tables = _readSampleTables(moov, stbl, fileLength);
      return Mp4SampleTable._(
        ftyp: ftyp,
        moov: moov,
        mvhd: mvhd,
        trak: trak,
        movieTimescale: movieTimescale,
        mediaTimescale: mediaTimescale,
        sampleOffsets: tables.offsets,
        sampleSizes: tables.sizes,
        sampleDurations: tables.durations,
      );
    }
    throw const MediaInspectionException('No audio track');
  }

  static ({Int64List offsets, Int32List sizes, Int32List durations})
  _readSampleTables(Uint8List moov, Mp4Box stbl, int fileLength) {
    final view = ByteData.sublistView(moov);
    Mp4Box need(String type) =>
        _child(moov, stbl, type) ??
        (throw MediaInspectionException('No $type box'));

    // Sample sizes.
    final stsz = need('stsz');
    final fixedSize = view.getUint32(stsz.start + 4);
    final count = view.getUint32(stsz.start + 8);
    if (fixedSize == 0 && stsz.start + 12 + count * 4 > stsz.end) {
      throw const MediaInspectionException('stsz table is truncated');
    }
    final sizes = Int32List(count);
    for (var i = 0; i < count; i++) {
      sizes[i] = fixedSize != 0
          ? fixedSize
          : view.getUint32(stsz.start + 12 + i * 4);
    }

    // Sample durations.
    final stts = need('stts');
    final durations = Int32List(count);
    final sttsEntries = view.getUint32(stts.start + 4);
    var s = 0;
    for (var e = 0; e < sttsEntries && s < count; e++) {
      final at = stts.start + 8 + e * 8;
      if (at + 8 > stts.end) {
        throw const MediaInspectionException('stts table is truncated');
      }
      final n = view.getUint32(at);
      final delta = view.getUint32(at + 4);
      for (var k = 0; k < n && s < count; k++) {
        durations[s++] = delta;
      }
    }
    if (s != count) {
      throw const MediaInspectionException('stts and stsz disagree');
    }

    // Chunk offsets.
    final stco = _child(moov, stbl, 'stco');
    final co64 = stco == null ? _child(moov, stbl, 'co64') : null;
    if (stco == null && co64 == null) {
      throw const MediaInspectionException('No chunk offset box');
    }
    final chunkBox = stco ?? co64!;
    final chunkCount = view.getUint32(chunkBox.start + 4);
    final entryBytes = stco != null ? 4 : 8;
    if (chunkBox.start + 8 + chunkCount * entryBytes > chunkBox.end) {
      throw const MediaInspectionException('Chunk offset table is truncated');
    }
    int chunkOffset(int c) {
      final at = chunkBox.start + 8 + c * entryBytes;
      return stco != null ? view.getUint32(at) : view.getUint64(at);
    }

    // Samples per chunk, then each sample's file offset.
    final stsc = need('stsc');
    final stscEntries = view.getUint32(stsc.start + 4);
    if (stsc.start + 8 + stscEntries * 12 > stsc.end) {
      throw const MediaInspectionException('stsc table is truncated');
    }
    final offsets = Int64List(count);
    var sample = 0;
    for (var e = 0; e < stscEntries; e++) {
      final at = stsc.start + 8 + e * 12;
      final firstChunk = view.getUint32(at) - 1;
      final perChunk = view.getUint32(at + 4);
      final lastChunk = e + 1 < stscEntries
          ? view.getUint32(at + 12) - 1
          : chunkCount;
      for (var c = firstChunk; c < lastChunk && c < chunkCount; c++) {
        var pos = chunkOffset(c);
        for (var k = 0; k < perChunk && sample < count; k++) {
          offsets[sample] = pos;
          pos += sizes[sample];
          sample++;
        }
      }
    }
    if (sample != count) {
      throw const MediaInspectionException('stsc and stsz disagree');
    }
    for (var i = 0; i < count; i++) {
      if (offsets[i] + sizes[i] > fileLength) {
        throw const MediaInspectionException(
          'A sample runs past the end of the file',
        );
      }
    }
    return (offsets: offsets, sizes: sizes, durations: durations);
  }
}
