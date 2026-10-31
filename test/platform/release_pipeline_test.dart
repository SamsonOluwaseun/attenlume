@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const workflowPath = '.github/workflows/release.yml';

  group('P1-28 GitHub Actions release pipeline', () {
    test(
      'P1-28 workflow exists and uses explicit manual workflow_dispatch only',
      () {
        final file = File(workflowPath);
        expect(file.existsSync(), isTrue, reason: '$workflowPath must exist');

        final content = file.readAsStringSync();

        // Explicit workflow_dispatch trigger
        expect(content, contains('workflow_dispatch:'));
        expect(content, contains('--draft'));
        expect(content, isNot(contains('inputs.draft')));
        expect(
          content,
          contains('--draft \\'),
          reason: 'draft releases must be default for safety',
        );

        // No automatic release triggers on push/schedule
        expect(
          RegExp(r'^\s*push:\s*$', multiLine: true).hasMatch(content),
          isFalse,
          reason: 'no automatic public release on ordinary push',
        );
        expect(
          RegExp(r'^\s*schedule:\s*$', multiLine: true).hasMatch(content),
          isFalse,
          reason: 'no periodic automated release schedule',
        );
      },
    );

    test('P1-28 shell bodies never interpolate Actions expressions', () {
      final content = File(workflowPath).readAsStringSync();
      var inRun = false;
      for (final line in content.split('\n')) {
        if (line.trimRight() == '        run: |') {
          inRun = true;
        } else if (line.trim().isNotEmpty && !line.startsWith('          ')) {
          inRun = false;
        }
        if (inRun) {
          expect(line, isNot(contains(r'${{')), reason: line);
        }
      }
      expect(content, contains(r'gh release create "$RELEASE_TAG"'));
      expect(content, contains(r'--title "$RELEASE_TITLE"'));
      expect(
        content,
        contains('Required Android signing configuration is missing'),
      );
      expect(content, isNot(contains('fallback release APK')));
    });

    test(
      'P1-28 preserves canonical download asset names matching README links',
      () {
        final file = File(workflowPath);
        final content = file.readAsStringSync();

        // Expected canonical asset names from Section 14 and README
        const expectedApk = 'attenlume-android.apk';
        const expectedExe = 'attenlume-windows-setup.exe';
        const expectedSums = 'SHA256SUMS.txt';

        expect(content, contains(expectedApk));
        expect(content, contains(expectedExe));
        expect(content, contains(expectedSums));

        // Verify README links align with canonical names
        final readme = File('README.md').readAsStringSync();
        expect(readme, contains('/releases/latest/download/$expectedApk'));
        expect(readme, contains('/releases/latest/download/$expectedExe'));
      },
    );

    test(
      'P1-28 references signing secret names without hardcoded credentials',
      () {
        final file = File(workflowPath);
        final content = file.readAsStringSync();

        // Repository secret placeholders
        expect(content, contains(r'${{ secrets.ANDROID_KEYSTORE_BASE64 }}'));
        expect(content, contains(r'${{ secrets.ANDROID_KEYSTORE_PASSWORD }}'));
        expect(content, contains(r'${{ secrets.ANDROID_KEY_ALIAS }}'));
        expect(content, contains(r'${{ secrets.ANDROID_KEY_PASSWORD }}'));

        // Ensure no raw private keys or embedded passwords exist
        expect(content, isNot(contains('-----BEGIN PRIVATE KEY-----')));
        expect(content, isNot(contains('-----BEGIN CERTIFICATE-----')));

        // Reuses build scripts
        expect(content, contains('flutter build apk --release'));
        expect(content, contains('tool/build_windows_installer.ps1'));
      },
    );
  });
}
