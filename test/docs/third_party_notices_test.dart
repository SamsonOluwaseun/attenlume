@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/licence_audit.dart';

void main() {
  final notices = File(noticesPath).readAsStringSync().replaceAll('\r\n', '\n');

  test(
    'P0-08 every package in pubspec.lock appears in THIRD_PARTY_NOTICES.md',
    () {
      // Parsed independently of the generator: a two-space indented key under
      // `packages:` is a package name.
      final lock = File(lockPath).readAsLinesSync();
      final names = [
        for (final line in lock)
          if (RegExp(r'^  ([a-z0-9_]+):$').firstMatch(line) case final m?)
            m.group(1)!,
      ];
      expect(names.length, greaterThan(50));
      for (final name in names) {
        expect(
          notices,
          contains('| `$name` |'),
          reason: '$name is in pubspec.lock but not in $noticesPath',
        );
      }
    },
  );

  test('P0-08 THIRD_PARTY_NOTICES.md is up to date with pubspec.lock', () {
    final audit = LicenceAudit.fromDisk();
    expect(
      notices,
      audit.renderNotices(File(fontLicencePath).readAsStringSync()),
      reason: 'Run dart run tool/licence_audit.dart',
    );
  });

  test('P0-08 no package in the app has a copyleft or unknown licence', () {
    final audit = LicenceAudit.fromDisk();
    expect(audit.flagged.map((p) => '${p.name} ${p.licence.id}'), isEmpty);
    expect(audit.packages.where((p) => p.inApp), isNotEmpty);
  });

  test('P0-08 fonts and brand assets are covered', () {
    expect(notices, contains('SIL Open Font License'));
    expect(notices, contains('Montserrat'));
    expect(notices, contains('## Brand assets (not open source)'));
    expect(notices, contains('SQLite'));
  });

  group('P0-08 classifyLicence', () {
    const bsd =
        'Redistribution and use in source and binary forms, with or without '
        'modification, are permitted provided that ...';
    final cases = {
      'Permission is hereby granted, free of charge, to any person':
          Licence.mit,
      '$bsd Neither the name of Google Inc. nor the names': Licence.bsd3,
      bsd: Licence.bsd2,
      'Apache License\nVersion 2.0, January 2004': Licence.apache2,
      'Permission to use, copy, modify, and/or distribute this software':
          Licence.isc,
      'Mozilla Public License Version 2.0': Licence.mpl,
      'GNU LESSER GENERAL PUBLIC LICENSE Version 3': Licence.lgpl,
      'GNU GENERAL PUBLIC LICENSE Version 3': Licence.gpl,
      'GNU AFFERO GENERAL PUBLIC LICENSE': Licence.gpl,
      'All rights reserved.': Licence.unknown,
      '': Licence.unknown,
      // A copyleft licence in a mixed file must win over a permissive one.
      'Permission is hereby granted, free of charge.\n'
              'Parts: GNU GENERAL PUBLIC LICENSE':
          Licence.gpl,
    };
    cases.forEach((text, expected) {
      test('${expected.id}: "${text.split('\n').first}"', () {
        expect(classifyLicence(text), expected);
      });
    });

    test('only permissive families pass', () {
      expect(
        Licence.values.where((l) => l.permissive),
        unorderedEquals([
          Licence.apache2,
          Licence.mit,
          Licence.bsd3,
          Licence.bsd2,
          Licence.isc,
          Licence.flutterEngine,
        ]),
      );
    });
  });
}
