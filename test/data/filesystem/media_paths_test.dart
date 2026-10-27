import 'dart:io';

import 'package:attenlume/data/filesystem/media_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('FR-REC-02 media paths (BUILD_GUIDE 9.5)', () {
    test('FR-REC-02 segment paths are relative and use forward slashes', () {
      expect(
        MediaPaths.segment('c1', 'a1', 3),
        'conferences/c1/activities/a1/audio/segment-003.m4a',
      );
      expect(MediaPaths.segmentFileName(12, attempt: 1), 'segment-012-2.m4a');
    });

    test('FR-REC-02 resolve joins with the platform separator', () {
      final root = Directory(p.join('base', 'media'));
      final file = MediaPaths.resolve(root, 'conferences/c1/audio/x.m4a');
      expect(
        file.path,
        p.join('base', 'media', 'conferences', 'c1', 'audio', 'x.m4a'),
      );
    });
  });
}
