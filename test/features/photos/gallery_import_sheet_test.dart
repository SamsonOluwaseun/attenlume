import 'dart:io';

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/models/enums.dart';
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

void main() {
  late TestData t;
  late Directory root;
  late FakeGallerySource gallery;
  final start = DateTime.utc(2026, 11, 4, 9, 30);

  setUp(() async {
    t = TestData();
    root = await Directory.systemTemp.createTemp('gallery_sheet_test_');
    gallery = FakeGallerySource();
  });

  tearDown(() async {
    await t.close();
    // Windows can hold an image file open briefly after a decode.
    for (var i = 0; ; i++) {
      try {
        await root.delete(recursive: true);
        break;
      } on FileSystemException {
        if (i == 20) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
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
    final conf = await t.conference();
    final act = await t.activity(conf.id);
    await t.segment(act.id, start: start, length: const Duration(minutes: 30));
    return act.id;
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const Key('activity-photos-import-taken-button')),
    );
    await settle(tester);
  }

  testWidgets(
    'FR-PHO-05 lists photos from the window, warns on large files and '
    'imports after confirmation',
    (tester) async {
      final actId = (await tester.runAsync(recordedActivity))!;
      final slide = File(p.join(root.path, 'roll', 'IMG_1.jpg'));
      await tester.runAsync(() async {
        await slide.parent.create(recursive: true);
        await slide.writeAsBytes(
          img.encodeJpg(img.Image(width: 640, height: 480)),
        );
      });
      gallery
        ..items = [
          GalleryItem(
            id: 'slide',
            takenUtc: start.add(const Duration(minutes: 4)),
            bytes: 20 << 20,
          ),
          GalleryItem(
            id: 'lunch',
            takenUtc: start.add(const Duration(hours: 3)),
          ),
        ]
        ..files['slide'] = slide;

      await tester.pumpWidget(subject(actId));
      await settle(tester);
      await openSheet(tester);

      expect(find.byKey(const Key('gallery-import-sheet')), findsOneWidget);
      // 09:30 UTC is 09:30 in London in November.
      expect(
        find.text('09:30 to 10:00, with 2 min either side'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('gallery-candidate-slide')), findsOneWidget);
      expect(find.byKey(const Key('gallery-candidate-lunch')), findsNothing);
      expect(find.text('Large file'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('gallery-import-label-input')),
        'Slides',
      );
      await tester.tap(find.byKey(const Key('gallery-import-confirm-button')));
      await settle(tester);
      expect(find.text('Import anyway?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('gallery-import-anyway-button')));
      for (
        var i = 0;
        i < 200 && find.text('Photos (1)').evaluate().isEmpty;
        i++
      ) {
        await settle(tester);
      }

      expect(find.text('Photos (1)'), findsOneWidget);
      expect(find.text('1 photo imported.'), findsOneWidget);
      final photo = (await tester.runAsync(() => t.media.photosFor(actId)))!
          .single;
      expect(photo.source, PhotoSource.galleryImport);
      expect(photo.label, 'Slides');
      expect(photo.offsetMs, const Duration(minutes: 4).inMilliseconds);

      // Let image reads started by the thumbnails finish so the temp
      // folder can be deleted on Windows.
      await tester.pumpWidget(const SizedBox());
      imageCache.clear();
      await settle(tester);
    },
  );

  testWidgets(
    'FR-PHO-05 duplicates start unselected and changing the margin looks '
    'again without asking for access again',
    (tester) async {
      final actId = (await tester.runAsync(recordedActivity))!;
      final at = start.add(const Duration(minutes: 5));
      await tester.runAsync(
        () => t.media.addPhoto(
          activityId: actId,
          filePath: 'photos/x.jpg',
          takenUtc: at,
          source: PhotoSource.galleryImport,
        ),
      );
      gallery.items = [
        GalleryItem(id: 'dup', takenUtc: at),
        GalleryItem(
          id: 'early',
          takenUtc: start.subtract(const Duration(minutes: 4)),
        ),
      ];

      await tester.pumpWidget(subject(actId));
      await settle(tester);
      await openSheet(tester);

      expect(find.text('Already imported'), findsOneWidget);
      expect(find.byKey(const Key('gallery-candidate-early')), findsNothing);
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('gallery-import-confirm-button')),
      );
      expect(button.onPressed, isNull, reason: 'nothing selected');

      await tester.tap(find.byKey(const Key('gallery-import-margin-5')));
      await settle(tester);

      expect(find.byKey(const Key('gallery-candidate-early')), findsOneWidget);
      expect(find.text('Import 1 photo'), findsOneWidget);
      expect(gallery.opens, 1);
    },
  );

  testWidgets('FR-PHO-05 limited access says only some photos are listed', (
    tester,
  ) async {
    final actId = (await tester.runAsync(recordedActivity))!;
    gallery.access = GalleryAccess.limited;

    await tester.pumpWidget(subject(actId));
    await settle(tester);
    await openSheet(tester);

    expect(find.byKey(const Key('gallery-import-limited')), findsOneWidget);
    expect(find.byKey(const Key('gallery-import-empty')), findsOneWidget);
  });

  testWidgets('FR-PRI-04 refused access explains and offers settings', (
    tester,
  ) async {
    final actId = (await tester.runAsync(recordedActivity))!;
    gallery.access = GalleryAccess.denied;

    await tester.pumpWidget(subject(actId));
    await settle(tester);
    await openSheet(tester);

    expect(find.byKey(const Key('gallery-import-denied')), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    await settle(tester);
    expect(gallery.settingsOpened, 1);
  });

  testWidgets('FR-PHO-05 cancelling the folder picker closes the sheet', (
    tester,
  ) async {
    final actId = (await tester.runAsync(recordedActivity))!;
    gallery.access = GalleryAccess.cancelled;

    await tester.pumpWidget(subject(actId));
    await settle(tester);
    await openSheet(tester);

    expect(find.byKey(const Key('gallery-import-sheet')), findsNothing);
    expect(find.text('No photos yet.'), findsOneWidget);
  });

  testWidgets('FR-PHO-05 an activity not started yet has no window', (
    tester,
  ) async {
    final conf = (await tester.runAsync(t.conference))!;
    final act = (await tester.runAsync(() => t.activity(conf.id)))!;

    await tester.pumpWidget(subject(act.id));
    await settle(tester);
    await openSheet(tester);

    expect(find.byKey(const Key('gallery-import-not-started')), findsOneWidget);
    expect(gallery.opens, 0);
  });
}
