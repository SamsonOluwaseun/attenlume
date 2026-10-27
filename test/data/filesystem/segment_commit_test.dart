import 'dart:io';

import 'package:attenlume/data/filesystem/media_paths.dart';
import 'package:attenlume/data/filesystem/segment_commit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('attenlume_commit_');
  });

  tearDown(() => dir.delete(recursive: true));

  group('FR-REC-03 partial segment names', () {
    test('FR-REC-03 the partial name keeps the extension last', () {
      expect(
        MediaPaths.partial(
          'conferences/c1/activities/a1/audio/segment-001.m4a',
        ),
        'conferences/c1/activities/a1/audio/segment-001.partial.m4a',
      );
      expect(
        MediaPaths.partial('audio/segment-002-2.m4a'),
        'audio/segment-002-2.partial.m4a',
      );
    });

    test('FR-REC-03 partial names are recognised', () {
      expect(MediaPaths.isPartial('audio/segment-001.partial.m4a'), isTrue);
      expect(MediaPaths.isPartial('audio/segment-001.m4a'), isFalse);
    });

    test('FR-REC-08 finalName undoes partial and leaves other paths alone', () {
      const path = 'conferences/c/activities/a/audio/segment-001-2.m4a';
      expect(MediaPaths.finalName(MediaPaths.partial(path)), path);
      expect(MediaPaths.finalName(path), path);
    });
  });

  group('FR-REC-03 commitSegmentFile', () {
    test('FR-REC-03 renames the flushed file and keeps its bytes', () async {
      final partial = File(p.join(dir.path, 'segment-001.partial.m4a'));
      await partial.writeAsBytes([1, 2, 3, 4]);
      final target = File(p.join(dir.path, 'segment-001.m4a'));

      final done = await commitSegmentFile(partial, target);

      expect(done.path, target.path);
      expect(target.readAsBytesSync(), [1, 2, 3, 4]);
      expect(partial.existsSync(), isFalse);
    });

    test('FR-REC-03 never overwrites an existing segment (NFR-07)', () async {
      final partial = File(p.join(dir.path, 'segment-001.partial.m4a'));
      await partial.writeAsBytes([9]);
      final target = File(p.join(dir.path, 'segment-001.m4a'));
      await target.writeAsBytes([1]);

      await expectLater(
        commitSegmentFile(partial, target),
        throwsA(isA<FileSystemException>()),
      );
      expect(target.readAsBytesSync(), [1]);
      expect(partial.readAsBytesSync(), [9]);
    });

    test('FR-REC-03 a missing file fails without creating one', () async {
      final partial = File(p.join(dir.path, 'gone.partial.m4a'));
      final target = File(p.join(dir.path, 'gone.m4a'));

      await expectLater(
        commitSegmentFile(partial, target),
        throwsA(isA<FileSystemException>()),
      );
      expect(target.existsSync(), isFalse);
    });
  });
}
