import 'dart:io';
import 'dart:typed_data';

/// What a finished audio file actually contains (FR-QUAL-01, FR-QUAL-06)
/// [P0-06].
class AudioFileInfo {
  const AudioFileInfo({
    required this.bytes,
    required this.majorBrand,
    required this.codec,
    required this.container,
    required this.channelCount,
    required this.sampleRateHz,
    required this.durationMs,
    required this.declaredAvgBitrateBps,
    required this.declaredMaxBitrateBps,
    required this.mediaDataBytes,
  });

  /// Whole file size.
  final int bytes;
  final String majorBrand;

  /// Stored codec key, for example `aac_lc` (matches `recording_segments`).
  final String codec;
  final String container;
  final int channelCount;
  final int sampleRateHz;
  final int durationMs;

  /// Bitrates the encoder wrote into the `esds` descriptor. Zero if absent.
  final int declaredAvgBitrateBps;
  final int declaredMaxBitrateBps;

  /// Size of the `mdat` payload (encoded audio without container).
  final int mediaDataBytes;

  /// Whole-file bitrate, the figure stored as `observed_bitrate_bps`
  /// (ARCHITECTURE 3). Includes container overhead.
  int get observedBitrateBps =>
      durationMs <= 0 ? 0 : (bytes * 8 * 1000 / durationMs).round();

  /// Encoded audio bitrate without container overhead.
  int get payloadBitrateBps =>
      durationMs <= 0 ? 0 : (mediaDataBytes * 8 * 1000 / durationMs).round();

  Map<String, Object?> toJson() => {
    'bytes': bytes,
    'major_brand': majorBrand,
    'codec': codec,
    'container': container,
    'channel_count': channelCount,
    'sample_rate_hz': sampleRateHz,
    'duration_ms': durationMs,
    'declared_avg_bitrate_bps': declaredAvgBitrateBps,
    'declared_max_bitrate_bps': declaredMaxBitrateBps,
    'media_data_bytes': mediaDataBytes,
    'observed_bitrate_bps': observedBitrateBps,
    'payload_bitrate_bps': payloadBitrateBps,
  };
}

/// Thrown when a file is not a finalised MP4 audio file. A recording that
/// was cut off before its `moov` box was written lands here, so it is never
/// reported as good (FR-REC-08).
class MediaInspectionException implements Exception {
  const MediaInspectionException(this.message);

  final String message;

  @override
  String toString() => 'MediaInspectionException: $message';
}

/// Reads codec, format and duration from an MP4/M4A file [P0-06].
///
/// Only box headers and the `moov` box are read. Audio data is skipped, so
/// memory stays bounded however long the recording is (NFR-10).
class M4aInspector {
  const M4aInspector({this.maxMoovBytes = 16 * 1024 * 1024});

  /// Refuse `moov` boxes larger than this rather than load them.
  final int maxMoovBytes;

  Future<AudioFileInfo> inspect(File file) async {
    final raf = await file.open();
    try {
      final length = await raf.length();
      String? majorBrand;
      Uint8List? moov;
      var mediaDataBytes = 0;
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
            await raf.setPosition(offset + headerSize);
            majorBrand = String.fromCharCodes(await raf.read(4));
          case 'moov':
            if (size > maxMoovBytes) {
              throw MediaInspectionException('moov box is $size bytes');
            }
            await raf.setPosition(offset + headerSize);
            moov = await raf.read(size - headerSize);
          case 'mdat':
            mediaDataBytes += size - headerSize;
        }
        offset += size;
      }
      if (majorBrand == null) {
        throw const MediaInspectionException('No ftyp box: not an MP4 file');
      }
      if (moov == null) {
        throw const MediaInspectionException(
          'No moov box: the file was not finalised',
        );
      }
      final track = _findAudioTrack(moov);
      return AudioFileInfo(
        bytes: length,
        majorBrand: majorBrand,
        codec: track.codec,
        container: 'm4a',
        channelCount: track.channelCount,
        sampleRateHz: track.sampleRateHz,
        durationMs: track.timescale == 0
            ? 0
            : (track.duration * 1000 / track.timescale).round(),
        declaredAvgBitrateBps: track.avgBitrate,
        declaredMaxBitrateBps: track.maxBitrate,
        mediaDataBytes: mediaDataBytes,
      );
    } finally {
      await raf.close();
    }
  }
}

class _Track {
  int timescale = 0;
  int duration = 0;
  String? handler;
  String codec = 'unknown';
  int channelCount = 0;
  int sampleRateHz = 0;
  int avgBitrate = 0;
  int maxBitrate = 0;
}

typedef _Box = ({String type, int start, int end});

Iterable<_Box> _children(Uint8List data, int start, int end) sync* {
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

_Track _findAudioTrack(Uint8List moov) {
  for (final trak in _children(moov, 0, moov.length)) {
    if (trak.type != 'trak') continue;
    final track = _Track();
    for (final mdia in _children(moov, trak.start, trak.end)) {
      if (mdia.type == 'mdia') _readMdia(moov, mdia, track);
    }
    if (track.handler == 'soun') return track;
  }
  throw const MediaInspectionException('No audio track');
}

void _readMdia(Uint8List data, _Box mdia, _Track track) {
  final view = ByteData.sublistView(data);
  for (final box in _children(data, mdia.start, mdia.end)) {
    switch (box.type) {
      case 'mdhd':
        final version = data[box.start];
        if (version == 1) {
          track.timescale = view.getUint32(box.start + 20);
          track.duration = view.getUint64(box.start + 24);
        } else {
          track.timescale = view.getUint32(box.start + 12);
          track.duration = view.getUint32(box.start + 16);
        }
      case 'hdlr':
        track.handler = String.fromCharCodes(
          data,
          box.start + 8,
          box.start + 12,
        );
      case 'minf':
        for (final stbl in _children(data, box.start, box.end)) {
          if (stbl.type != 'stbl') continue;
          for (final stsd in _children(data, stbl.start, stbl.end)) {
            if (stsd.type == 'stsd') _readStsd(data, stsd, track);
          }
        }
    }
  }
}

void _readStsd(Uint8List data, _Box stsd, _Track track) {
  final view = ByteData.sublistView(data);
  // Full box header (4) and entry count (4), then sample entries.
  for (final entry in _children(data, stsd.start + 8, stsd.end)) {
    track.codec = entry.type;
    if (entry.type != 'mp4a') return;
    // SampleEntry (8) then AudioSampleEntry fields (20).
    track.channelCount = view.getUint16(entry.start + 16);
    track.sampleRateHz = view.getUint32(entry.start + 24) >> 16;
    for (final child in _children(data, entry.start + 28, entry.end)) {
      if (child.type == 'esds') _readEsds(data, child, track);
    }
    return;
  }
}

void _readEsds(Uint8List data, _Box esds, _Track track) {
  final view = ByteData.sublistView(data);
  var p = esds.start + 4;

  // Reads a descriptor tag and its variable-length size.
  (int tag, int bodyStart, int bodyEnd)? descriptor(int at, int end) {
    if (at >= end) return null;
    final tag = data[at];
    var length = 0;
    var i = at + 1;
    for (var n = 0; n < 4 && i < end; n++) {
      final b = data[i++];
      length = (length << 7) | (b & 0x7f);
      if (b & 0x80 == 0) break;
    }
    return (tag, i, i + length > end ? end : i + length);
  }

  final es = descriptor(p, esds.end);
  if (es == null || es.$1 != 0x03) return;
  p = es.$2 + 2; // ES_ID
  final flags = data[p++];
  if (flags & 0x80 != 0) p += 2;
  if (flags & 0x40 != 0) p += 1 + data[p];
  if (flags & 0x20 != 0) p += 2;

  final config = descriptor(p, es.$3);
  if (config == null || config.$1 != 0x04) return;
  final objectType = data[config.$2];
  track.maxBitrate = view.getUint32(config.$2 + 5);
  track.avgBitrate = view.getUint32(config.$2 + 9);
  if (objectType != 0x40 && objectType != 0x67) {
    track.codec = 'mp4a.${objectType.toRadixString(16)}';
    return;
  }

  final specific = descriptor(config.$2 + 13, config.$3);
  if (specific == null || specific.$1 != 0x05) {
    track.codec = 'aac';
    return;
  }
  var audioObjectType = data[specific.$2] >> 3;
  if (audioObjectType == 31 && specific.$2 + 1 < specific.$3) {
    audioObjectType =
        32 + (((data[specific.$2] & 0x07) << 3) | (data[specific.$2 + 1] >> 5));
  }
  track.codec = switch (audioObjectType) {
    2 => 'aac_lc',
    5 => 'aac_he',
    29 => 'aac_he_v2',
    _ => 'mp4a.40.$audioObjectType',
  };
}
