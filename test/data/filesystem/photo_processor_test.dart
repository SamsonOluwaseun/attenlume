import 'dart:io';

import 'package:attenlume/data/filesystem/photo_processor.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late File photo;
  late File thumb;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('photo_processor_test_');
    photo = File(p.join(dir.path, 'photos', 'a.jpg'));
    thumb = File(p.join(dir.path, 'thumbs', 'a.jpg'));
    await photo.parent.create(recursive: true);
  });

  tearDown(() => dir.delete(recursive: true));

  Future<void> writeJpeg(int w, int h, {int? orientation}) async {
    final image = img.Image(width: w, height: h);
    img.fill(image, color: img.ColorRgb8(240, 240, 230));
    img.fillRect(
      image,
      x1: 0,
      y1: 0,
      x2: w ~/ 4,
      y2: h ~/ 4,
      color: img.ColorRgb8(0, 33, 43),
    );
    if (orientation != null) image.exif.imageIfd.orientation = orientation;
    await photo.writeAsBytes(img.encodeJpg(image, quality: 98));
  }

  test('FR-PHO-02 a large photo is scaled to a 2048 px long edge', () async {
    await writeJpeg(4000, 3000);
    final before = await photo.length();

    final result = await processPhoto(photo: photo, thumbnail: thumb);

    final stored = img.decodeJpg(await photo.readAsBytes())!;
    expect(stored.width, 2048);
    expect(stored.height, 1536);
    expect(result.width, 2048);
    expect(result.height, 1536);
    expect(result.bytes, await photo.length());
    expect(result.bytes, lessThan(before));
    expect(File('${photo.path}.tmp').existsSync(), isFalse);
  });

  test('FR-PHO-03 writes a small thumbnail once', () async {
    await writeJpeg(1920, 1080);

    final result = await processPhoto(photo: photo, thumbnail: thumb);

    expect(result.thumbnailWritten, isTrue);
    final t = img.decodeJpg(await thumb.readAsBytes())!;
    expect(t.width, 320);
    expect(t.height, 180);
  });

  test('FR-PHO-02 camera EXIF rotation is applied to the pixels', () async {
    await writeJpeg(1920, 1080, orientation: 6);

    final result = await processPhoto(photo: photo, thumbnail: thumb);

    expect(result.width, 1080);
    expect(result.height, 1920);
    final t = img.decodeJpg(await thumb.readAsBytes())!;
    expect(t.height, greaterThan(t.width));
  });

  test('FR-PHO-02 keep highest quality stores the photo as taken', () async {
    await writeJpeg(4000, 3000);
    final original = await photo.readAsBytes();

    final result = await processPhoto(
      photo: photo,
      thumbnail: thumb,
      quality: const PhotoQuality(keepOriginal: true),
    );

    expect(await photo.readAsBytes(), original);
    expect(result.width, 4000);
    expect(result.thumbnailWritten, isTrue);
  });

  test('a file that cannot be decoded is kept untouched and hashed', () async {
    final junk = List<int>.filled(1024, 0xff);
    await photo.writeAsBytes(junk);

    final result = await processPhoto(photo: photo, thumbnail: thumb);

    expect(await photo.readAsBytes(), junk);
    expect(result.width, isNull);
    expect(result.thumbnailWritten, isFalse);
    expect(thumb.existsSync(), isFalse);
    expect(result.sha256, sha256.convert(junk).toString());
  });

  test('the hash matches the stored file', () async {
    await writeJpeg(3000, 2000);

    final result = await processPhoto(photo: photo, thumbnail: thumb);

    expect(result.sha256, sha256.convert(await photo.readAsBytes()).toString());
  });
}
