@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/gen_tokens.dart';

void main() {
  test(
    'P0-02 lib/app/theme/tokens.dart is up to date with design/tokens.json',
    () {
      final tmp = Directory.systemTemp.createTempSync('attenlume_tokens');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final generated = File('${tmp.path}/tokens.dart')
        ..writeAsStringSync(
          generateTokensDart(File(tokensJsonPath).readAsStringSync()),
        );
      final format = Process.runSync('dart', [
        'format',
        generated.path,
      ], runInShell: true);
      expect(format.exitCode, 0, reason: '${format.stderr}');

      expect(
        File(tokensDartPath).readAsStringSync().replaceAll('\r\n', '\n'),
        generated.readAsStringSync().replaceAll('\r\n', '\n'),
        reason:
            'Run `dart run tool/gen_tokens.dart` after editing tokens.json.',
      );
    },
  );
}
