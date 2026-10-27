import 'dart:convert';
import 'dart:typed_data';

/// Builds small synthetic MP4/M4A files for inspector tests [P0-06].
/// Only the boxes the inspector reads are filled in. The `mdat` payload is
/// zeros, so these files do not play.
Uint8List buildM4a({
  int channels = 1,
  int sampleRateHz = 48000,
  int timescale = 48000,
  int durationUnits = 48000 * 3,
  int avgBitrateBps = 96000,
  int maxBitrateBps = 96000,
  int audioObjectType = 2,
  int mediaDataBytes = 36000,
  bool moovFirst = false,
  bool includeMoov = true,
  bool mdhdVersion1 = false,
  bool longDescriptorLengths = false,
  bool videoTrackFirst = false,
}) {
  final ftyp = _box('ftyp', [
    ...ascii.encode('M4A '),
    ..._u32(0),
    ...ascii.encode('M4A mp42isom'),
  ]);
  final mdat = _box('mdat', List<int>.filled(mediaDataBytes, 0));

  final asc = _audioSpecificConfig(audioObjectType, sampleRateHz, channels);
  List<int> descriptor(int tag, List<int> body) => [
    tag,
    if (longDescriptorLengths) ...[0x80, 0x80, 0x80],
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
  final soundTrack = _track(
    'soun',
    [..._u32(0), ..._u32(1), ...mp4a],
    timescale,
    durationUnits,
    mdhdVersion1,
  );
  final videoTrack = _track(
    'vide',
    [..._u32(0), ..._u32(0)],
    90000,
    270000,
    false,
  );
  final moov = _box('moov', [
    ..._box('mvhd', List<int>.filled(100, 0)),
    if (videoTrackFirst) ...videoTrack,
    ...soundTrack,
  ]);

  return Uint8List.fromList([
    ...ftyp,
    if (includeMoov && moovFirst) ...moov,
    ...mdat,
    if (includeMoov && !moovFirst) ...moov,
  ]);
}

List<int> _track(
  String handler,
  List<int> stsdBody,
  int timescale,
  int duration,
  bool mdhdVersion1,
) {
  final mdhd = mdhdVersion1
      ? _box('mdhd', [
          1,
          0,
          0,
          0,
          ..._u64(0),
          ..._u64(0),
          ..._u32(timescale),
          ..._u64(duration),
          0,
          0,
          0,
          0,
        ])
      : _box('mdhd', [
          ..._u32(0),
          ..._u32(0),
          ..._u32(0),
          ..._u32(timescale),
          ..._u32(duration),
          0,
          0,
          0,
          0,
        ]);
  final hdlr = _box('hdlr', [
    ..._u32(0),
    ..._u32(0),
    ...ascii.encode(handler),
    ...List<int>.filled(12, 0),
    0,
  ]);
  final minf = _box('minf', _box('stbl', _box('stsd', stsdBody)));
  return _box('trak', [
    ..._box('tkhd', List<int>.filled(84, 0)),
    ..._box('mdia', [...mdhd, ...hdlr, ...minf]),
  ]);
}

List<int> _audioSpecificConfig(int aot, int sampleRateHz, int channels) {
  const rates = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050];
  final index = rates.indexOf(sampleRateHz);
  final bits = (aot << 11) | ((index < 0 ? 3 : index) << 7) | (channels << 3);
  return [bits >> 8, bits & 0xff];
}

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

List<int> _u64(int v) => [..._u32(v >> 32), ..._u32(v & 0xffffffff)];
