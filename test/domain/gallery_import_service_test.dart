import 'dart:io';

import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/gallery_import_service.dart';
import 'package:attenlume/domain/services/photo_capture_service.dart';
import 'package:attenlume/platform/gallery/gallery_source.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../fixtures/fake_gallery_source.dart';
import '../fixtures/fake_photo_camera.dart';
import '../fixtures/fixtures.dart';

void main() {
  late TestData t;
  late Directory root;
  late FakeGallerySource gallery;
  late GalleryImportService service;
  final start = DateTime.utc(2026, 11, 4, 9, 30);
  var now = DateTime.utc(2026, 11, 4, 12);

  setUp(() async {
    t = TestData();
    root = await Directory.systemTemp.createTemp('gallery_import_test_');
    gallery = FakeGallerySource();
    service = GalleryImportService(
      gallery: gallery,
      activities: t.activities,
      media: t.media,
      photos: PhotoCaptureService(
        camera: FakePhotoCamera(),
        activities: t.activities,
        media: t.media,
        mediaRoot: () async => root,
      ),
      clock: () => now,
    );
  });

  tearDown(() async {
    await t.close();
    await root.delete(recursive: true);
  });

  GalleryItem item(
    String id,
    DateTime taken, {
    int? bytes,
    int? width,
    int? height,
  }) => GalleryItem(
    id: id,
    takenUtc: taken,
    bytes: bytes,
    width: width,
    height: height,
  );

  Future<File> jpeg(String name) async {
    final file = File(p.join(root.path, 'roll', name));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(img.encodeJpg(img.Image(width: 640, height: 480)));
    return file;
  }

  test(
    'FR-PHO-05 window is the recorded span with a 2-minute margin',
    () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);
      await t.segment(
        act.id,
        start: start,
        length: const Duration(minutes: 20),
      );
      await t.segment(
        act.id,
        start: start.add(const Duration(minutes: 25)),
        length: const Duration(minutes: 30),
      );

      final window = (await service.windowFor(act.id))!;

      expect(window.startUtc, start);
      expect(window.endUtc, start.add(const Duration(minutes: 55)));
      expect(window.fromUtc, DateTime.utc(2026, 11, 4, 9, 28));
      expect(window.toUtc, DateTime.utc(2026, 11, 4, 10, 27));
    },
  );

  test('FR-PHO-05 margin is configurable', () async {
    final conf = await t.conference();
    final act = await t.activity(conf.id);
    await t.segment(act.id, start: start, length: const Duration(minutes: 10));

    final window = (await service.windowFor(
      act.id,
      margin: const Duration(minutes: 10),
    ))!;

    expect(window.fromUtc, DateTime.utc(2026, 11, 4, 9, 20));
    expect(window.toUtc, DateTime.utc(2026, 11, 4, 9, 50));
  });

  test('FR-PHO-05 an activity without audio uses its actual start and end; '
      'one still running ends now; one never started has no window', () async {
    final conf = await t.conference();
    final notRecorded = await t.activity(conf.id, typeKey: 'networking');
    await t.activities.update(
      notRecorded.id,
      ActivitiesCompanion(
        actualStart: Value(start),
        actualEnd: Value(start.add(const Duration(minutes: 15))),
      ),
    );
    final running = await t.activity(conf.id);
    await t.activities.update(
      running.id,
      ActivitiesCompanion(actualStart: Value(start)),
    );
    final never = await t.activity(conf.id);
    now = DateTime.utc(2026, 11, 4, 10);

    final a = (await service.windowFor(notRecorded.id))!;
    expect(a.endUtc, start.add(const Duration(minutes: 15)));
    final b = (await service.windowFor(running.id))!;
    expect(b.endUtc, now);
    expect(await service.windowFor(never.id), isNull);
    final scan = await service.scan(never.id);
    expect(scan.window, isNull);
    expect(gallery.opens, 0, reason: 'no permission asked for nothing');
  });

  test('FR-PHO-05 lists only photos in the window and flags duplicates and '
      'large files', () async {
    final conf = await t.conference();
    final act = await t.activity(conf.id);
    await t.segment(act.id, start: start, length: const Duration(minutes: 30));
    final already = start.add(const Duration(minutes: 5));
    await t.media.addPhoto(
      activityId: act.id,
      filePath: 'photos/x.jpg',
      takenUtc: already,
      source: PhotoSource.galleryImport,
    );
    gallery.items = [
      item('before', start.subtract(const Duration(minutes: 3))),
      item('margin', start.subtract(const Duration(minutes: 1))),
      item('dup', already),
      item('big', start.add(const Duration(minutes: 10)), bytes: 20 << 20),
      item(
        'huge',
        start.add(const Duration(minutes: 11)),
        width: 8000,
        height: 6000,
      ),
      item('after', start.add(const Duration(minutes: 33))),
    ];

    final scan = await service.scan(act.id);

    expect(gallery.opens, 1);
    expect(
      [for (final c in scan.candidates) c.item.id],
      ['margin', 'dup', 'big', 'huge'],
    );
    final byId = {for (final c in scan.candidates) c.item.id: c};
    expect(byId['dup']!.duplicate, isTrue);
    expect(byId['dup']!.selectedByDefault, isFalse);
    expect(byId['margin']!.duplicate, isFalse);
    expect(byId['margin']!.large, isFalse);
    expect(byId['big']!.large, isTrue);
    expect(byId['huge']!.large, isTrue);
  });

  test('FR-PHO-05 in-app photos are not taken as duplicates', () async {
    final conf = await t.conference();
    final act = await t.activity(conf.id);
    await t.segment(act.id, start: start, length: const Duration(minutes: 30));
    final at = start.add(const Duration(minutes: 5));
    await t.media.addPhoto(
      activityId: act.id,
      filePath: 'photos/x.jpg',
      takenUtc: at,
      source: PhotoSource.inApp,
    );
    gallery.items = [item('roll', at)];

    final scan = await service.scan(act.id);

    expect(scan.candidates.single.duplicate, isFalse);
  });

  test('FR-PHO-05 refused access lists nothing', () async {
    final conf = await t.conference();
    final act = await t.activity(conf.id);
    await t.segment(act.id, start: start, length: const Duration(minutes: 30));
    gallery
      ..access = GalleryAccess.denied
      ..items = [item('a', start)];

    final scan = await service.scan(act.id);

    expect(scan.access, GalleryAccess.denied);
    expect(scan.candidates, isEmpty);
    expect(gallery.queries, isEmpty);
  });

  test('FR-PHO-05 import copies the photo with its gallery time and offset, '
      'leaves the original unchanged and skips unreadable ones', () async {
    final conf = await t.conference();
    final act = await t.activity(conf.id);
    await t.segment(act.id, start: start, length: const Duration(minutes: 30));
    final taken = start.add(const Duration(minutes: 12));
    final original = await jpeg('IMG_0001.jpg');
    final before = await original.readAsBytes();
    final good = item('good', taken);
    gallery.files['good'] = original;

    final result = await service.importItems(act.id, [
      good,
      item('missing', taken),
    ], label: 'Slides');

    expect(result.skipped, 1);
    final photo = result.saved.single;
    expect(photo.source, PhotoSource.galleryImport);
    expect(photo.takenUtc, taken);
    expect(photo.offsetMs, const Duration(minutes: 12).inMilliseconds);
    expect(photo.label, 'Slides');
    expect(photo.thumbnailPath, isNotNull);
    expect(await original.readAsBytes(), before);
    expect(original.existsSync(), isTrue);

    final again = await service.scan(act.id);
    gallery.items = [good];
    final rescan = await service.scan(act.id);
    expect(again.candidates, isEmpty);
    expect(rescan.candidates.single.duplicate, isTrue);
  });
}
