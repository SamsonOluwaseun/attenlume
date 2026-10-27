import 'dart:io';

import 'package:attenlume/data/filesystem/app_data_directory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'ADR-028 on Windows, data lives in local app data, not Documents',
    () async {
      final dir = await appDataDirectory();
      expect(
        p.equals(
          dir.path,
          p.join(
            Platform.environment['LOCALAPPDATA']!,
            'Samlytics',
            'Attenlume',
          ),
        ),
        isTrue,
      );
      expect(dir.path.toLowerCase(), isNot(contains('onedrive')));
      expect(dir.existsSync(), isTrue);
    },
    skip: !Platform.isWindows,
  );
}
