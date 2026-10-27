import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

/// Photo size and quality defaults (FR-PHO-02, FR-PHO-03) [P1-14].
class PhotoQuality {
  const PhotoQuality({
    this.maxLongEdge = 2048,
    this.jpegQuality = 85,
    this.thumbLongEdge = 320,
    this.thumbQuality = 75,
    this.keepOriginal = false,
  });

  /// Photos with a longer edge are scaled down to it. 2048 px keeps slide
  /// text legible (FR-PHO-02: about 1600 to 2048 px).
  final int maxLongEdge;
  final int jpegQuality;
  final int thumbLongEdge;
  final int thumbQuality;

  /// "Keep highest quality": the camera's file is stored as taken.
  final bool keepOriginal;
}

/// What [processPhoto] produced.
class ProcessedPhoto {
  const ProcessedPhoto({
    required this.bytes,
    required this.sha256,
    this.width,
    this.height,
    this.thumbnailWritten = false,
  });

  final int bytes;
  final String sha256;

  /// Null when the file could not be decoded. It is then kept as taken.
  final int? width;
  final int? height;
  final bool thumbnailWritten;
}

/// Compresses [photo] in place, writes its thumbnail to [thumbnail] once
/// and hashes the stored file (FR-PHO-02, FR-PHO-03) [P1-14].
///
/// Runs on a background isolate so the shutter stays ready. Camera EXIF
/// orientation is applied to the pixels, because re-encoding drops EXIF.
/// The photo is only replaced through a temporary file and a rename, and a
/// photo that cannot be decoded is kept untouched: never lose the shot.
Future<ProcessedPhoto> processPhoto({
  required File photo,
  required File thumbnail,
  PhotoQuality quality = const PhotoQuality(),
}) => Isolate.run(() => _process(photo.path, thumbnail.path, quality));

Future<ProcessedPhoto> _process(
  String photoPath,
  String thumbPath,
  PhotoQuality quality,
) async {
  final photo = File(photoPath);
  final original = await photo.readAsBytes();
  img.Image? decoded;
  try {
    decoded = img.decodeImage(original);
  } on Object {
    decoded = null;
  }

  if (decoded == null) {
    return ProcessedPhoto(
      bytes: original.length,
      sha256: sha256.convert(original).toString(),
    );
  }

  final exif = decoded.exif.imageIfd;
  final rotated = exif.hasOrientation && exif.orientation != 1;
  final upright = rotated ? img.bakeOrientation(decoded) : decoded;
  var stored = original;
  var width = upright.width;
  var height = upright.height;
  if (!quality.keepOriginal) {
    final scaled = _fit(upright, quality.maxLongEdge);
    final encoded = img.encodeJpg(scaled, quality: quality.jpegQuality);
    // Only replace when it helps: a small, already compressed, upright
    // photo stays as taken.
    if (rotated ||
        !identical(scaled, upright) ||
        encoded.length < original.length) {
      final temp = File('$photoPath.tmp');
      await temp.writeAsBytes(encoded, flush: true);
      await temp.rename(photoPath);
      stored = encoded;
      width = scaled.width;
      height = scaled.height;
    }
  }

  final thumb = File(thumbPath);
  await thumb.parent.create(recursive: true);
  await thumb.writeAsBytes(
    img.encodeJpg(
      _fit(upright, quality.thumbLongEdge),
      quality: quality.thumbQuality,
    ),
    flush: true,
  );

  return ProcessedPhoto(
    bytes: stored.length,
    sha256: sha256.convert(stored).toString(),
    width: width,
    height: height,
    thumbnailWritten: true,
  );
}

img.Image _fit(img.Image image, int longEdge) {
  if (image.width <= longEdge && image.height <= longEdge) return image;
  return image.width >= image.height
      ? img.copyResize(
          image,
          width: longEdge,
          interpolation: img.Interpolation.average,
        )
      : img.copyResize(
          image,
          height: longEdge,
          interpolation: img.Interpolation.average,
        );
}
