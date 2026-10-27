@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Documents required by docs/BUILD_GUIDE.md section 1.6.
const _requiredDocs = [
  'AGENTS.md',
  'docs/BUILD_GUIDE.md',
  'docs/PRODUCT_SPEC.md',
  'docs/ARCHITECTURE.md',
  'docs/PLATFORM_FEASIBILITY.md',
  'docs/PRIVACY_AND_SAFETY.md',
  'docs/TEST_PLAN.md',
  'docs/RELEASE_PLAN.md',
  'docs/DECISIONS.md',
  'docs/PROGRESS.md',
  'docs/HANDOVER.md',
];

void main() {
  test('P0-03 every document in build guide 1.6 exists and is not empty', () {
    for (final path in ['README.md', ..._requiredDocs]) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path is missing');
      expect(file.readAsStringSync().trim(), isNotEmpty, reason: path);
    }
  });

  test('P0-03 README links every document in build guide 1.6', () {
    final readme = File('README.md').readAsStringSync();
    for (final path in _requiredDocs) {
      expect(readme, contains('($path)'), reason: 'README does not link $path');
    }
  });
}
