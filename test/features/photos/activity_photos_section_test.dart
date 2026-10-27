import 'dart:io';

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/services/photo_capture_service.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/features/photos/activity_photos_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../fixtures/fake_photo_camera.dart';
import '../../fixtures/fixtures.dart';

void main() {
  late TestData t;
  late Directory root;
  late List<String> picked;

  setUp(() async {
    t = TestData();
    root = await Directory.systemTemp.createTemp('photos_section_test_');
    picked = [];
  });

  tearDown(() async {
    await t.close();
    await root.delete(recursive: true);
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
      photoFilePickerProvider.overrideWithValue(() async => picked),
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
          child: ActivityPhotosSection(activityId: activityId),
        ),
      ),
    ),
  );

  testWidgets(
    'FR-PHO-06 imports photos with a label, then a caption is added',
    (tester) async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);
      final file = File(p.join(root.path, 'picked', 'whiteboard.jpg'));
      await tester.runAsync(() async {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(
          img.encodeJpg(img.Image(width: 800, height: 600)),
        );
      });
      picked = [file.path];

      await tester.pumpWidget(subject(act.id));
      await settle(tester);
      expect(find.text('No photos yet.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('activity-photos-import-button')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('photo-import-label-input')),
        'Whiteboard',
      );
      await tester.tap(find.byKey(const Key('photo-import-confirm-button')));
      // Compression runs on a background isolate: wait for it, up to 10 s.
      for (
        var i = 0;
        i < 200 && find.text('Photos (1)').evaluate().isEmpty;
        i++
      ) {
        await settle(tester);
      }

      expect(find.text('Photos (1)'), findsOneWidget);
      expect(find.text('1 photo imported.'), findsOneWidget);
      final photo = (await tester.runAsync(() => t.media.photosFor(act.id)))!
          .single;
      expect(photo.label, 'Whiteboard');

      await tester.tap(find.byKey(Key('activity-photo-${photo.id}')));
      await settle(tester);
      expect(find.byKey(const Key('photo-detail-sheet')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('photo-caption-input')),
        'Team map',
      );
      await tester.ensureVisible(find.byKey(const Key('photo-save-button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('photo-save-button')));
      await settle(tester);

      final saved = (await tester.runAsync(() => t.media.photosFor(act.id)))!
          .single;
      expect(saved.caption, 'Team map');
      expect(saved.label, 'Whiteboard');
    },
  );

  testWidgets('FR-PHO-06 cancelling the picker imports nothing', (
    tester,
  ) async {
    final conf = await t.conference();
    final act = await t.activity(conf.id);

    await tester.pumpWidget(subject(act.id));
    await settle(tester);
    await tester.tap(find.byKey(const Key('activity-photos-import-button')));
    await settle(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('No photos yet.'), findsOneWidget);
  });
}
