import 'dart:io';

import 'package:attenlume/platform/gallery/gallery_source.dart';
import 'package:attenlume/platform/gallery/picker_gallery_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.samlytics.attenlume/photo_picker');

  late Directory tempDir;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('picker_test_');
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<File> createTestPhoto(
    String filename, {
    String? exifTime,
    String? offset,
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
    final file = File(p.join(tempDir.path, filename));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return file;
  }

  test('FR-PHO-05 picker returns cancelled when user cancels picker', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pick') return <Map<String, dynamic>>[];
      if (call.method == 'cleanUp') return true;
      return null;
    });

    final source = PickerGallerySource();
    expect(source.choosesFolder, isFalse);

    final result = await source.open();
    expect(result, GalleryAccess.cancelled);
    expect(source.items, isEmpty);
  });

  test(
    'FR-PHO-05 picker processes picked file with EXIF capture time',
    () async {
      final photo = await createTestPhoto(
        'photo1.jpg',
        exifTime: '2026:11:04 10:15:00',
        offset: '+00:00',
      );

      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'pick') {
          return [
            {
              'path': photo.path,
              'name': 'Samlytics_Presentation_1.jpg',
              'bytes': photo.lengthSync(),
            },
          ];
        }
        if (call.method == 'cleanUp') return true;
        return null;
      });

      final source = PickerGallerySource();
      final result = await source.open();
      expect(result, GalleryAccess.full);
      expect(source.items.length, 1);

      final item = source.items.first;
      expect(item.path, photo.path);
      expect(item.name, 'Samlytics_Presentation_1.jpg');
      expect(item.hasExifTime, isTrue);
      expect(item.takenUtc, DateTime.utc(2026, 11, 4, 10, 15));

      final file = await source.fileFor(item);
      expect(file, isNotNull);
      expect(file!.existsSync(), isTrue);
    },
  );

  test(
    'FR-PHO-05 picker marks file without EXIF time with hasExifTime false',
    () async {
      final plain = await createTestPhoto('plain.jpg');

      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'pick') {
          return [
            {
              'path': plain.path,
              'name': 'plain.jpg',
              'bytes': plain.lengthSync(),
            },
          ];
        }
        if (call.method == 'cleanUp') return true;
        return null;
      });

      final source = PickerGallerySource();
      final access = await source.open();
      expect(access, GalleryAccess.full);

      final items = await source.photosBetween(
        DateTime.utc(2026, 11, 4, 9, 30),
        DateTime.utc(2026, 11, 4, 10, 30),
      );
      expect(items.length, 1);
      expect(items.first.hasExifTime, isFalse);
      expect(items.first.takenUtc, DateTime.utc(2026, 11, 4, 9, 30));
    },
  );

  test('FR-PHO-05 photosBetween returns all picked photos including outside window', () async {
    final inside = await createTestPhoto(
      'inside.jpg',
      exifTime: '2026:11:04 09:45:00',
      offset: '+00:00',
    );
    final outside = await createTestPhoto(
      'outside.jpg',
      exifTime: '2026:11:04 14:00:00',
      offset: '+00:00',
    );

    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pick') {
        return [
          {'path': inside.path, 'name': 'inside.jpg'},
          {'path': outside.path, 'name': 'outside.jpg'},
        ];
      }
      if (call.method == 'cleanUp') return true;
      return null;
    });

    final source = PickerGallerySource();
    await source.open();

    final windowStart = DateTime.utc(2026, 11, 4, 9, 30);
    final windowEnd = DateTime.utc(2026, 11, 4, 10, 0);

    final all = await source.photosBetween(windowStart, windowEnd);
    expect(all.length, 2);
    expect(all.map((i) => i.name), containsAll(['inside.jpg', 'outside.jpg']));
  });

  test('FR-PHO-05 cleanUp deletes cached files and notifies channel', () async {
    final photo = await createTestPhoto('cached.jpg');
    expect(photo.existsSync(), isTrue);

    var channelCleaned = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pick') {
        return [
          {'path': photo.path, 'name': 'cached.jpg'},
        ];
      }
      if (call.method == 'cleanUp') {
        channelCleaned = true;
        return true;
      }
      return null;
    });

    final source = PickerGallerySource();
    await source.open();
    expect(source.items.length, 1);

    await source.cleanUp();
    expect(source.items, isEmpty);
    expect(photo.existsSync(), isFalse);
    expect(channelCleaned, isTrue);
  });

  test('FR-PHO-05 native-provided takenIso takes priority over missing JPEG EXIF time', () async {
    // Photo has no JPEG EXIF header (e.g. from transcoded HEIC file)
    final plain = await createTestPhoto('transcoded_heic.jpg');

    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pick') {
        return [
          {
            'path': plain.path,
            'name': 'Samlytics_Slide_HEIC.jpg',
            'bytes': plain.lengthSync(),
            'takenIso': '2026-11-04T09:42:15.000Z',
          },
        ];
      }
      if (call.method == 'cleanUp') return true;
      return null;
    });

    final source = PickerGallerySource();
    final result = await source.open();
    expect(result, GalleryAccess.full);

    final item = source.items.single;
    expect(item.name, 'Samlytics_Slide_HEIC.jpg');
    expect(item.hasExifTime, isTrue);
    expect(item.takenUtc, DateTime.utc(2026, 11, 4, 9, 42, 15));
  });
}
