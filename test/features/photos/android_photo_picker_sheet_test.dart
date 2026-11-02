import 'dart:io';

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/photo_capture_service.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/features/photos/activity_photos_section.dart';
import 'package:attenlume/features/photos/gallery_import_sheet.dart';
import 'package:attenlume/platform/gallery/gallery_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../fixtures/fake_gallery_source.dart';
import '../../fixtures/fake_photo_camera.dart';
import '../../fixtures/fixtures.dart';

class _FakeAndroidPickerSource extends FakeGallerySource {
  _FakeAndroidPickerSource();

  @override
  Future<List<GalleryItem>> photosBetween(
    DateTime fromUtc,
    DateTime toUtc,
  ) async {
    queries.add((fromUtc, toUtc));
    // As required by P1-58, Android picker returns ALL picked photos
    return List.from(items);
  }
}

void main() {
  late TestData t;
  late Directory root;
  late _FakeAndroidPickerSource gallery;
  final start = DateTime.utc(2026, 11, 4, 9, 30);

  setUp(() async {
    t = TestData();
    root = await Directory.systemTemp.createTemp('android_picker_sheet_test_');
    gallery = _FakeAndroidPickerSource();
  });

  tearDown(() async {
    await t.close();
    for (var i = 0; i < 20; i++) {
      try {
        if (root.existsSync()) await root.delete(recursive: true);
        break;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Widget subject(String activityId) => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(t.db),
      activityRepositoryProvider.overrideWithValue(t.activities),
      mediaAssetRepositoryProvider.overrideWithValue(t.media),
      mediaRootProvider.overrideWithValue(() async => root),
      capturePlatformProvider.overrideWithValue(CapturePlatform.android),
      gallerySourceProvider.overrideWithValue(gallery),
      photoCaptureServiceProvider.overrideWithValue(
        PhotoCaptureService(
          camera: FakePhotoCamera(),
          activities: t.activities,
          media: t.media,
          mediaRoot: () async => root,
        ),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ActivityPhotosSection(
            activityId: activityId,
            timezone: 'Europe/London',
          ),
        ),
      ),
    ),
  );

  Future<String> recordedActivity() async {
    final conf = await t.conference(name: 'Samlytics Conference 2026');
    final act = await t.activity(conf.id, title: 'Keynote');
    await t.segment(act.id, start: start, length: const Duration(minutes: 30));
    return act.id;
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const Key('activity-photos-import-taken-button')),
    );
    await settle(tester);
  }

  Future<File> writePhotoFile(String name) async {
    final file = File(p.join(root.path, 'roll', name));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(img.encodeJpg(img.Image(width: 64, height: 48)));
    return file;
  }

  testWidgets(
    'FR-PHO-05 Android picker shows limit note, outside session note and no capture time',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final actId = (await tester.runAsync(recordedActivity))!;
      late File insideFile;
      late File outsideFile;
      late File noExifFile;

      await tester.runAsync(() async {
        insideFile = await writePhotoFile('inside.jpg');
        outsideFile = await writePhotoFile('outside.jpg');
        noExifFile = await writePhotoFile('no_exif.jpg');
      });

      gallery
        ..items = [
          GalleryItem(
            id: 'inside',
            path: insideFile.path,
            takenUtc: start.add(const Duration(minutes: 10)),
            hasExifTime: true,
          ),
          GalleryItem(
            id: 'outside',
            path: outsideFile.path,
            takenUtc: start.subtract(const Duration(hours: 1)),
            hasExifTime: true,
          ),
          GalleryItem(
            id: 'no_exif',
            path: noExifFile.path,
            takenUtc: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            hasExifTime: false,
          ),
        ]
        ..files['inside'] = insideFile
        ..files['outside'] = outsideFile
        ..files['no_exif'] = noExifFile;

      await tester.pumpWidget(subject(actId));
      await settle(tester);
      await openSheet(tester);

      expect(find.byKey(const Key('gallery-import-sheet')), findsOneWidget);
      expect(
        find.text('Choose up to 50 photos from your gallery.'),
        findsOneWidget,
      );

      // Warning note for photo outside session
      expect(find.text('Taken outside this session'), findsOneWidget);

      // Label for photo without EXIF capture time
      expect(find.text('No capture time'), findsOneWidget);

      // Re-pick button is available on Android
      expect(
        find.byKey(const Key('gallery-import-repick-button')),
        findsOneWidget,
      );

      // Import photos
      await tester.ensureVisible(
        find.byKey(const Key('gallery-import-confirm-button')),
      );
      await tester.tap(find.byKey(const Key('gallery-import-confirm-button')));
      for (
        var i = 0;
        i < 200 && find.text('Photos (3)').evaluate().isEmpty;
        i++
      ) {
        await settle(tester);
      }

      expect(find.text('Photos (3)'), findsOneWidget);
      expect(find.text('3 photos imported.'), findsOneWidget);

      final photos = (await tester.runAsync(() => t.media.photosFor(actId)))!;
      expect(photos.length, 3);

      final importedNoExif = photos.firstWhere(
        (p) => p.filePath.contains('no_exif') || p.offsetMs == 0,
      );
      // Photo without EXIF was placed at the activity start (offset 0)
      expect(importedNoExif.takenUtc, start);
      expect(importedNoExif.offsetMs, 0);

      await tester.pumpWidget(const SizedBox());
      imageCache.clear();
      await settle(tester);
    },
  );
}
