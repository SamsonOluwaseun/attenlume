import 'dart:io';

import 'package:attenlume/data/filesystem/media_paths.dart';
import 'package:attenlume/data/filesystem/photo_processor.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/photo_capture_service.dart';
import 'package:attenlume/platform/camera/photo_camera.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../fixtures/fake_photo_camera.dart';
import '../fixtures/fixtures.dart';

void main() {
  late TestData t;
  late Directory root;
  late FakePhotoCamera camera;
  late PhotoCaptureService service;
  var now = DateTime.utc(2026, 11, 4, 9, 40);

  setUp(() async {
    t = TestData();
    root = await Directory.systemTemp.createTemp('photo_capture_test_');
    camera = FakePhotoCamera()
      ..photoData = img.encodeJpg(img.Image(width: 3000, height: 2000));
    service = PhotoCaptureService(
      camera: camera,
      activities: t.activities,
      media: t.media,
      mediaRoot: () async => root,
      clock: () => now,
    );
  });

  tearDown(() async {
    await t.close();
    await root.delete(recursive: true);
  });

  test(
    'FR-PHO-01 saves the photo to the activity with time and offset',
    () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);
      await t.segment(
        act.id,
        start: DateTime.utc(2026, 11, 4, 9, 30),
        length: const Duration(minutes: 20),
      );

      final photo = await service.capture(act.id);

      expect(photo.activityId, act.id);
      expect(photo.source, PhotoSource.inApp);
      expect(photo.takenUtc, now);
      expect(photo.offsetMs, const Duration(minutes: 10).inMilliseconds);
      expect(photo.filePath, MediaPaths.photo(conf.id, act.id, photo.id));
    },
  );

  test(
    'FR-PHO-02 and FR-PHO-03 the stored photo is compressed with a thumbnail',
    () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);

      final photo = await service.capture(act.id);

      final file = MediaPaths.resolve(root, photo.filePath);
      expect(photo.width, 2048);
      expect(photo.height, 1365);
      expect(photo.bytes, await file.length());
      expect(photo.sha256, sha256.convert(await file.readAsBytes()).toString());
      expect(
        photo.thumbnailPath,
        MediaPaths.thumbnail(conf.id, act.id, photo.id),
      );
      expect(
        MediaPaths.resolve(root, photo.thumbnailPath!).existsSync(),
        isTrue,
      );
      expect(photo.originalKept, isFalse);
    },
  );

  test('FR-PHO-04 photos are stored only in the app library', () async {
    final conf = await t.conference();
    final act = await t.activity(conf.id);

    await service.capture(act.id);

    expect(camera.paths, hasLength(1));
    expect(p.isWithin(root.path, camera.paths.single), isTrue);
  });

  test('FR-UI-03 the shutter is ready before compression starts', () async {
    final conf = await t.conference();
    final act = await t.activity(conf.id);
    final order = <String>[];
    final ordered = PhotoCaptureService(
      camera: camera,
      activities: t.activities,
      media: t.media,
      mediaRoot: () async => root,
      process:
          ({
            required File photo,
            required File thumbnail,
            PhotoQuality quality = const PhotoQuality(),
          }) {
            order.add('process');
            return processPhoto(
              photo: photo,
              thumbnail: thumbnail,
              quality: quality,
            );
          },
    );

    await ordered.capture(act.id, onShutterReady: () => order.add('ready'));

    expect(order, ['ready', 'process']);
    expect(camera.shots, 1);
  });

  test('FR-UI-03 several shots in a row each get a photo', () async {
    final conf = await t.conference();
    final act = await t.activity(conf.id);

    for (var i = 0; i < 3; i++) {
      now = now.add(const Duration(seconds: 5));
      await service.capture(act.id);
    }

    expect(await t.media.photosFor(act.id), hasLength(3));
  });

  test('a failed shot saves nothing and frees the shutter', () async {
    final conf = await t.conference();
    final act = await t.activity(conf.id);
    camera.shotError = (_) => StateError('camera busy');
    var ready = false;

    await expectLater(
      service.capture(act.id, onShutterReady: () => ready = true),
      throwsStateError,
    );

    expect(ready, isTrue);
    expect(await t.media.photosFor(act.id), isEmpty);
  });

  test('FR-PRI-04 a refused camera is reported as access denied', () async {
    camera.openError = const CameraAccessDeniedException();

    await expectLater(
      service.open(),
      throwsA(isA<CameraAccessDeniedException>()),
    );
  });

  test('FR-PHO-06 imports copies of picked files with a label, originals untouched', () async {
    final conf = await t.conference();
    final act = await t.activity(conf.id);
    final picked = File(p.join(root.path, 'picked', 'slide.png'));
    await picked.parent.create(recursive: true);
    final bytes = img.encodePng(img.Image(width: 2400, height: 1800));
    await picked.writeAsBytes(bytes);
    final modified = DateTime.utc(2026, 11, 4, 9, 45);
    picked.setLastModifiedSync(modified);

    final saved = await service.importFiles(act.id, [
      picked.path,
      p.join(root.path, 'missing.jpg'),
    ], label: 'Slides');

    expect(saved, hasLength(1), reason: 'the missing file is skipped');
    final photo = saved.single;
    expect(photo.source, PhotoSource.manualImport);
    expect(photo.label, 'Slides');
    expect(photo.takenUtc, modified);
    expect(photo.width, 2048);
    expect(photo.thumbnailPath, isNotNull);
    expect(await picked.readAsBytes(), bytes);
    expect(camera.shots, 0);
  });

  test('FR-PHO-06 caption and label can be set and cleared', () async {
    final conf = await t.conference();
    final act = await t.activity(conf.id);
    final photo = await service.capture(act.id);

    final captioned = await t.media.updatePhotoText(
      photo.id,
      caption: ' Roadmap slide ',
      label: 'Slides',
    );
    expect(captioned.caption, 'Roadmap slide');
    expect(captioned.label, 'Slides');

    final cleared = await t.media.updatePhotoText(
      photo.id,
      caption: '',
      label: '  ',
    );
    expect(cleared.caption, isNull);
    expect(cleared.label, isNull);
  });
}
