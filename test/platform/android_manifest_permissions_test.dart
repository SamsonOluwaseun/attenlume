import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'FR-PRI-04 AndroidManifest.xml does not request photo media permissions',
    () {
      final manifestFile = File('android/app/src/main/AndroidManifest.xml');
      expect(manifestFile.existsSync(), isTrue, reason: 'Manifest file exists');

      final content = manifestFile.readAsStringSync();

      // Must not request READ_MEDIA_IMAGES or READ_MEDIA_VISUAL_USER_SELECTED
      // without tools:node="remove".
      final lines = content.split('\n');

      for (final rawLine in lines) {
        final line = rawLine.trim();
        if (!line.startsWith('<uses-permission')) continue;

        if (line.contains('android.permission.READ_MEDIA_IMAGES')) {
          expect(
            line,
            contains('tools:node="remove"'),
            reason: 'READ_MEDIA_IMAGES must have tools:node="remove"',
          );
        }
        if (line.contains(
          'android.permission.READ_MEDIA_VISUAL_USER_SELECTED',
        )) {
          expect(
            line,
            contains('tools:node="remove"'),
            reason:
                'READ_MEDIA_VISUAL_USER_SELECTED must have tools:node="remove"',
          );
        }
        if (line.contains('android.permission.READ_EXTERNAL_STORAGE')) {
          expect(
            line,
            contains('tools:node="remove"'),
            reason: 'READ_EXTERNAL_STORAGE must have tools:node="remove"',
          );
        }
      }

      // Verify tools:node="remove" is explicitly present for media permissions
      expect(
        content,
        contains(
          '<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" tools:node="remove" />',
        ),
      );
      expect(
        content,
        contains(
          '<uses-permission android:name="android.permission.READ_MEDIA_VISUAL_USER_SELECTED" tools:node="remove" />',
        ),
      );
      expect(
        content,
        contains(
          '<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" tools:node="remove" />',
        ),
      );
    },
  );
}
