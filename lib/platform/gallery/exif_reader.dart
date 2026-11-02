import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// EXIF sits in the first segments of a JPEG, well inside this.
const _exifHeadBytes = 128 * 1024;

/// The EXIF capture time of a JPEG [file] in UTC, or null when it has none.
DateTime? exifTakenUtc(File file) {
  final ext = p.extension(file.path).toLowerCase();
  if (ext != '.jpg' && ext != '.jpeg') return null;
  Uint8List head;
  try {
    final raf = file.openSync();
    try {
      head = raf.readSync(_exifHeadBytes);
    } finally {
      raf.closeSync();
    }
  } on FileSystemException {
    return null;
  }
  final exif = img.decodeJpgExif(head);
  if (exif == null) return null;
  final original = exif.exifIfd['DateTimeOriginal']?.toString();
  if (original == null) return null;
  return parseExifTime(
    original,
    exif.exifIfd['OffsetTimeOriginal']?.toString(),
  );
}

/// Parses EXIF `YYYY:MM:DD HH:MM:SS` with an optional `+HH:MM` offset.
/// Without an offset the time is taken as this device's local time.
DateTime? parseExifTime(String value, [String? offset]) {
  final m = RegExp(r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})')
      .firstMatch(value.trim());
  if (m == null) return null;
  final parts = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
  if (parts[0] == 0) return null;
  final o = offset == null
      ? null
      : RegExp(r'^([+-])(\d{2}):(\d{2})$').firstMatch(offset.trim());
  if (o == null) {
    return DateTime(
      parts[0],
      parts[1],
      parts[2],
      parts[3],
      parts[4],
      parts[5],
    ).toUtc();
  }
  final sign = o.group(1) == '-' ? -1 : 1;
  final shift = Duration(
    hours: int.parse(o.group(2)!),
    minutes: int.parse(o.group(3)!),
  );
  final wall = DateTime.utc(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
  );
  return sign > 0 ? wall.subtract(shift) : wall.add(shift);
}
