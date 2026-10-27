import 'dart:io';

import 'package:attenlume/platform/gallery/folder_gallery_source.dart';
import 'package:attenlume/platform/gallery/gallery_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  final from = DateTime.utc(2026, 11, 4, 9, 28);
  final to = DateTime.utc(2026, 11, 4, 10, 2);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('folder_gallery_test_');
  });

  tearDown(() => dir.delete(recursive: true));

  /// A JPEG with EXIF DateTimeOriginal [exifTime] and optional offset.
  Future<File> photo(
    String relative, {
    String? exifTime,
    String? offset,
    DateTime? modified,
  }) async {
    final image = img.Image(width: 64, height: 48);
    var bytes = img.encodeJpg(image);
    if (exifTime != null) {
      final exif = img.ExifData();
      exif.exifIfd['DateTimeOriginal'] = img.IfdValueAscii(exifTime);
      if (offset != null) {
        exif.exifIfd['OffsetTimeOriginal'] = img.IfdValueAscii(offset);
      }
      bytes = img.injectJpgExif(bytes, exif)!;
    }
    final file = File(p.join(dir.path, relative));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    if (modified != null) await file.setLastModified(modified);
    return file;
  }

  test('FR-PHO-05 EXIF time with an offset converts to UTC', () {
    expect(
      parseExifTime('2026:11:04 10:45:00', '+01:00'),
      DateTime.utc(2026, 11, 4, 9, 45),
    );
    expect(
      parseExifTime('2026:11:04 04:45:00', '-05:00'),
      DateTime.utc(2026, 11, 4, 9, 45),
    );
    expect(
      parseExifTime('2026:11:04 09:45:00'),
      DateTime(2026, 11, 4, 9, 45).toUtc(),
      reason: 'no offset: this device local time',
    );
    expect(parseExifTime('0000:00:00 00:00:00'), isNull);
    expect(parseExifTime('not a date'), isNull);
  });

  test('FR-PHO-05 reads DateTimeOriginal from a JPEG', () async {
    final file = await photo(
      'a.jpg',
      exifTime: '2026:11:04 09:40:00',
      offset: '+00:00',
    );
    expect(exifTakenUtc(file), DateTime.utc(2026, 11, 4, 9, 40));
    final plain = await photo('b.jpg');
    expect(exifTakenUtc(plain), isNull);
  });

  test('FR-PHO-05 folder scan uses EXIF time, falls back to modified time, '
      'looks in subfolders and ignores other files', () async {
    // EXIF says in the window although the file was copied later.
    await photo(
      '2026/11/slide.jpg',
      exifTime: '2026:11:04 09:40:00',
      offset: '+00:00',
      modified: DateTime.utc(2026, 11, 5, 8),
    );
    // EXIF outside the window although modified inside it.
    await photo(
      'lunch.jpg',
      exifTime: '2026:11:04 12:30:00',
      offset: '+00:00',
      modified: DateTime.utc(2026, 11, 4, 9, 50),
    );
    // PNG without EXIF: modified time.
    final png = File(p.join(dir.path, 'board.png'));
    await png.writeAsBytes(img.encodePng(img.Image(width: 8, height: 8)));
    await png.setLastModified(DateTime.utc(2026, 11, 4, 9, 55));
    // Modified long before the window: skipped unread.
    await photo('old.jpg', modified: DateTime.utc(2026, 10, 1));
    await File(p.join(dir.path, 'notes.txt')).writeAsString('x');

    final items = scanFolder(dir.path, from, to);

    expect([for (final i in items) i.name], ['slide.jpg', 'board.png']);
    expect(items.first.takenUtc, DateTime.utc(2026, 11, 4, 9, 40));
    expect(items.first.path, isNotNull);
    expect(items.first.bytes, greaterThan(0));
    expect(items.last.takenUtc, DateTime.utc(2026, 11, 4, 9, 55));
  });

  test('FR-PHO-05 cancelling the folder picker cancels the import', () async {
    final cancelled = FolderGallerySource(pickFolder: () async => null);
    expect(await cancelled.open(), GalleryAccess.cancelled);
    expect(await cancelled.photosBetween(from, to), isEmpty);

    await photo(
      'slide.jpg',
      exifTime: '2026:11:04 09:40:00',
      offset: '+00:00',
      modified: DateTime.utc(2026, 11, 4, 9, 41),
    );
    final chosen = FolderGallerySource(pickFolder: () async => dir.path);
    expect(await chosen.open(), GalleryAccess.full);
    expect(chosen.choosesFolder, isTrue);
    final items = await chosen.photosBetween(from, to);
    expect(items, hasLength(1));
    final file = await chosen.fileFor(items.single);
    expect(file!.path, items.single.path);
    expect(await chosen.thumbnail(items.single), isNull);
  });
}
