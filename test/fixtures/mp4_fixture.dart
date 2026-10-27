import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Builds an AAC-in-MP4 file shaped like an Android or Windows recording:
/// `ftyp`, `mdat`, then `moov` at the end, chunks of [perChunk] samples
/// (so `stsc` has two rows), an edit list and a `udta` box [P1-19].
///
/// Sample `i` is [sampleBytes] bytes long: its index as a big-endian
/// uint32, then the byte `i % 251` repeated, so a test can tell exactly
/// which samples a trimmed file holds.
Future<File> writeMp4Fixture(
  File file, {
  int samples = 470, // about 10 s at 48 kHz
  int sampleRateHz = 48000,
  int sampleDelta = 1024,
  int perChunk = 10,
  int Function(int index)? sampleBytes,
  bool use64BitOffsets = false,
}) async {
  int sizeOf(int i) => sampleBytes?.call(i) ?? (180 + (i % 7) * 3);
  final payload = BytesBuilder(copy: false);
  for (var i = 0; i < samples; i++) {
    final s = Uint8List(sizeOf(i))..fillRange(0, sizeOf(i), i % 251);
    ByteData.sublistView(s).setUint32(0, i);
    payload.add(s);
  }
  final mdatPayload = payload.takeBytes();

  final ftyp = _box('ftyp', [
    ...ascii.encode('M4A '),
    ..._u32(0),
    ...ascii.encode('M4A mp42isom'),
  ]);
  final mdatStart = ftyp.length + 8;

  final chunks = (samples + perChunk - 1) ~/ perChunk;
  final rest = samples % perChunk;
  final chunkOffsets = <int>[];
  var pos = mdatStart;
  for (var i = 0; i < samples; i++) {
    if (i % perChunk == 0) chunkOffsets.add(pos);
    pos += sizeOf(i);
  }
  final units = samples * sampleDelta;
  final movieUnits = (units * 1000 / sampleRateHz).round();

  final asc = [0x11, 0x90]; // AAC LC, 48 kHz, mono
  List<int> descriptor(int tag, List<int> body) => [tag, body.length, ...body];
  final esds = _box('esds', [
    ..._u32(0),
    ...descriptor(0x03, [
      0,
      1,
      0,
      ...descriptor(0x04, [
        0x40,
        0x15,
        0,
        0,
        0,
        ..._u32(64000),
        ..._u32(64000),
        ...descriptor(0x05, asc),
      ]),
      ...descriptor(0x06, [2]),
    ]),
  ]);
  final mp4a = _box('mp4a', [
    ...List<int>.filled(6, 0),
    ..._u16(1),
    ...List<int>.filled(8, 0),
    ..._u16(1),
    ..._u16(16),
    ..._u16(0),
    ..._u16(0),
    ..._u32(sampleRateHz << 16),
    ...esds,
  ]);
  final stbl = _box('stbl', [
    ..._box('stsd', [..._u32(0), ..._u32(1), ...mp4a]),
    ..._box('stts', [
      ..._u32(0),
      ..._u32(1),
      ..._u32(samples),
      ..._u32(sampleDelta),
    ]),
    ..._box('stsc', [
      ..._u32(0),
      ..._u32(rest == 0 ? 1 : 2),
      ..._u32(1),
      ..._u32(perChunk),
      ..._u32(1),
      if (rest != 0) ...[..._u32(chunks), ..._u32(rest), ..._u32(1)],
    ]),
    ..._box('stsz', [
      ..._u32(0),
      ..._u32(0),
      ..._u32(samples),
      for (var i = 0; i < samples; i++) ..._u32(sizeOf(i)),
    ]),
    if (use64BitOffsets)
      ..._box('co64', [
        ..._u32(0),
        ..._u32(chunks),
        for (final o in chunkOffsets) ...[..._u32(0), ..._u32(o)],
      ])
    else
      ..._box('stco', [
        ..._u32(0),
        ..._u32(chunks),
        for (final o in chunkOffsets) ..._u32(o),
      ]),
  ]);
  final mdhd = _box('mdhd', [
    ..._u32(0),
    ..._u32(0),
    ..._u32(0),
    ..._u32(sampleRateHz),
    ..._u32(units),
    0x55,
    0xc4,
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
  final minf = _box('minf', [
    ..._box('smhd', List<int>.filled(8, 0)),
    ..._box(
      'dinf',
      _box('dref', [..._u32(0), ..._u32(1), ..._box('url ', _u32(1))]),
    ),
    ...stbl,
  ]);
  final tkhd = List<int>.filled(84, 0);
  tkhd.setAll(12, _u32(1)); // track ID
  tkhd.setAll(20, _u32(movieUnits));
  final trak = _box('trak', [
    ..._box('tkhd', tkhd),
    ..._box(
      'edts',
      _box('elst', [
        ..._u32(0),
        ..._u32(1),
        ..._u32(movieUnits),
        ..._u32(2048),
        ..._u32(0x10000),
      ]),
    ),
    ..._box('mdia', [...mdhd, ...hdlr, ...minf]),
  ]);
  final mvhd = List<int>.filled(100, 0);
  mvhd.setAll(12, _u32(1000));
  mvhd.setAll(16, _u32(movieUnits));
  final moov = _box('moov', [
    ..._box('mvhd', mvhd),
    ...trak,
    ..._box('udta', ascii.encode('meta-like')),
  ]);

  final out = file.openWrite();
  out
    ..add(ftyp)
    ..add(_u32(mdatPayload.length + 8))
    ..add(ascii.encode('mdat'))
    ..add(mdatPayload)
    ..add(moov);
  await out.close();
  return file;
}

/// Index of a fixture sample from its bytes.
int fixtureSampleIndex(Uint8List sample) =>
    ByteData.sublistView(sample).getUint32(0);

List<int> _box(String type, List<int> payload) => [
  ..._u32(payload.length + 8),
  ...ascii.encode(type),
  ...payload,
];

List<int> _u16(int v) => [(v >> 8) & 0xff, v & 0xff];

List<int> _u32(int v) => [
  (v >> 24) & 0xff,
  (v >> 16) & 0xff,
  (v >> 8) & 0xff,
  v & 0xff,
];
