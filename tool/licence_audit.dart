// Generates THIRD_PARTY_NOTICES.md from pubspec.lock and the licence files
// of the resolved packages (P0-08).
//
// Run from the repo root after `flutter pub get`, whenever pubspec.lock
// changes:
//   dart run tool/licence_audit.dart          (writes the file)
//   dart run tool/licence_audit.dart --check  (exit 1 if stale or flagged)
//
// test/docs/third_party_notices_test.dart fails if the file is stale or a
// package in pubspec.lock is missing from it.

import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

const lockPath = 'pubspec.lock';
const pubspecPath = 'pubspec.yaml';
const packageConfigPath = '.dart_tool/package_config.json';
const noticesPath = 'THIRD_PARTY_NOTICES.md';
const fontLicencePath = 'assets/fonts/OFL.txt';

void main(List<String> args) {
  final audit = LicenceAudit.fromDisk();
  final notices = audit.renderNotices(File(fontLicencePath).readAsStringSync());
  for (final p in audit.flagged) {
    stderr.writeln('Flagged: ${p.name} ${p.version} (${p.licence.id})');
  }
  if (args.contains('--check')) {
    final current = File(noticesPath).existsSync()
        ? _lf(File(noticesPath).readAsStringSync())
        : '';
    if (current != notices) {
      stderr.writeln(
        '$noticesPath is stale. Run dart run tool/licence_audit.dart',
      );
      exit(1);
    }
    if (audit.flagged.isNotEmpty) exit(1);
    stdout.writeln('$noticesPath is up to date. Nothing flagged.');
    return;
  }
  File(noticesPath).writeAsStringSync(notices);
  stdout.writeln(
    'Wrote $noticesPath: ${audit.packages.length} packages, '
    '${audit.flagged.length} flagged.',
  );
}

/// A licence family recognised from a licence file's text.
enum Licence {
  apache2('Apache-2.0', permissive: true),
  mit('MIT', permissive: true),
  bsd3('BSD-3-Clause', permissive: true),
  bsd2('BSD-2-Clause', permissive: true),
  isc('ISC', permissive: true),
  flutterEngine(
    'Flutter engine bundle (permissive, see note)',
    permissive: true,
  ),
  mpl('MPL-2.0', permissive: false),
  lgpl('LGPL', permissive: false),
  gpl('GPL or AGPL', permissive: false),
  unknown('Unknown', permissive: false);

  const Licence(this.id, {required this.permissive});

  final String id;

  /// True for licences that allow MIT or Apache 2.0 distribution of the app
  /// with attribution only.
  final bool permissive;
}

/// Recognises a licence from its text. Copyleft markers are checked first so
/// a mixed file is never reported as permissive.
Licence classifyLicence(String text) {
  final t = text.toUpperCase();
  if (t.contains('GNU AFFERO') ||
      (t.contains('GNU GENERAL PUBLIC') && !t.contains('LESSER'))) {
    return Licence.gpl;
  }
  if (t.contains('GNU LESSER') || t.contains('GNU LIBRARY GENERAL')) {
    return Licence.lgpl;
  }
  if (t.contains('MOZILLA PUBLIC LICENSE')) return Licence.mpl;
  if (t.contains('APACHE LICENSE') && t.contains('VERSION 2.0')) {
    return Licence.apache2;
  }
  if (t.contains('PERMISSION IS HEREBY GRANTED, FREE OF CHARGE')) {
    return Licence.mit;
  }
  if (t.contains('PERMISSION TO USE, COPY, MODIFY, AND/OR DISTRIBUTE')) {
    return Licence.isc;
  }
  if (t.contains('REDISTRIBUTION AND USE IN SOURCE AND BINARY FORMS')) {
    return t.contains('NEITHER THE NAME') ||
            t.contains('NAMES OF ITS CONTRIBUTORS') ||
            t.contains('NAME OF THE COPYRIGHT HOLDER')
        ? Licence.bsd3
        : Licence.bsd2;
  }
  return Licence.unknown;
}

/// One package from pubspec.lock with its licence.
class AuditedPackage {
  AuditedPackage({
    required this.name,
    required this.version,
    required this.source,
    required this.dependency,
    required this.inApp,
    required this.licence,
    required this.licenceText,
    required this.copyright,
  });

  final String name;
  final String version;

  /// `hosted` (pub.dev) or `sdk` (Flutter SDK).
  final String source;

  /// `direct main`, `direct dev` or `transitive`, as in pubspec.lock.
  final String dependency;

  /// Reachable from the app's `dependencies` (not only dev dependencies),
  /// so its code can end up in a release build.
  final bool inApp;
  final Licence licence;

  /// Licence text with LF line endings, or null when not reproduced here.
  final String? licenceText;
  final List<String> copyright;
}

class LicenceAudit {
  LicenceAudit(this.packages);

  /// Reads pubspec.lock, pubspec.yaml and each package's LICENSE file
  /// through `.dart_tool/package_config.json`.
  factory LicenceAudit.fromDisk() {
    final lock = loadYaml(File(lockPath).readAsStringSync()) as YamlMap;
    final pubspec = loadYaml(File(pubspecPath).readAsStringSync()) as YamlMap;
    final roots = _packageRoots();
    final locked = (lock['packages'] as YamlMap).cast<String, YamlMap>();

    // Packages reachable from the app's main dependencies.
    final inApp = <String>{};
    final queue = [...(pubspec['dependencies'] as YamlMap).keys.cast<String>()];
    while (queue.isNotEmpty) {
      final name = queue.removeLast();
      if (!inApp.add(name)) continue;
      final root = roots[name];
      if (root == null) continue;
      final deps = (loadYaml(
        File('${root.path}/pubspec.yaml').readAsStringSync(),
      ) as YamlMap)['dependencies'];
      if (deps is YamlMap) {
        queue.addAll(deps.keys.cast<String>().where(locked.containsKey));
      }
    }

    final packages = <AuditedPackage>[];
    for (final name in locked.keys.toList()..sort()) {
      final entry = locked[name]!;
      final root = roots[name];
      if (root == null) {
        throw StateError('$name is not in $packageConfigPath. Run pub get.');
      }
      final source = entry['source'] as String;
      final file = _findLicenceFile(root, searchParents: source == 'sdk');
      final raw = file == null ? '' : _lf(file.readAsStringSync());
      final isEngine = name == 'sky_engine';
      packages.add(
        AuditedPackage(
          name: name,
          version: entry['version'] as String,
          source: source,
          dependency: entry['dependency'] as String,
          inApp: inApp.contains(name),
          licence: isEngine ? Licence.flutterEngine : classifyLicence(raw),
          licenceText: isEngine || raw.isEmpty ? null : _cleanText(raw),
          copyright: isEngine ? const [] : _copyrightLines(raw),
        ),
      );
    }
    return LicenceAudit(packages);
  }

  final List<AuditedPackage> packages;

  /// Packages in the app whose licence is not permissive or not recognised.
  /// Build and test tools are not distributed, so they are only listed.
  List<AuditedPackage> get flagged =>
      packages.where((p) => p.inApp && !p.licence.permissive).toList();

  /// The full THIRD_PARTY_NOTICES.md, deterministic for a given lock file.
  String renderNotices(String fontLicence) {
    final app = packages.where((p) => p.inApp).toList();
    final tools = packages.where((p) => !p.inApp).toList();
    final counts = <String, int>{};
    for (final p in app) {
      counts[p.licence.id] = (counts[p.licence.id] ?? 0) + 1;
    }
    final out = StringBuffer()
      ..writeln('# Third-party notices')
      ..writeln()
      ..writeln(
        '<!-- GENERATED by tool/licence_audit.dart from pubspec.lock and the '
        'packages\' licence files. Do not edit by hand. Run '
        '`dart run tool/licence_audit.dart` after `flutter pub get`. -->',
      )
      ..writeln()
      ..writeln(
        'Attenlume is built with the open-source software listed below. '
        'Each component stays under its own licence. Attenlume\'s own code '
        'is under the MIT licence in `LICENSE` (ADR-007 in '
        '`docs/DECISIONS.md`).',
      )
      ..writeln()
      ..writeln('## Summary')
      ..writeln()
      ..writeln(
        '- ${packages.length} Dart and Flutter packages in `pubspec.lock`: '
        '${app.length} can be part of the app, ${tools.length} are build '
        'and test tools only.',
      )
      ..writeln(
        '- Licences of packages in the app: '
        '${(counts.keys.toList()..sort()).map((k) => '$k (${counts[k]})').join(', ')}.',
      )
      ..writeln(
        '- Packages in the app with a copyleft or unrecognised licence: '
        '${flagged.isEmpty ? 'none' : flagged.map((p) => '`${p.name}`').join(', ')}.',
      )
      ..writeln()
      ..writeln('## Packages in the app')
      ..writeln()
      ..writeln(
        'Reachable from the app\'s `dependencies`. Platform packages for '
        'targets Attenlume does not ship (Linux, macOS, web) are listed '
        'because they are in the dependency graph.',
      )
      ..writeln();
    _table(out, app);
    out
      ..writeln()
      ..writeln('## Build and test tools (not distributed)')
      ..writeln()
      ..writeln(
        'Reachable only from `dev_dependencies`. Used to generate code, '
        'lint and test. None of their code is in a release build.',
      )
      ..writeln();
    _table(out, tools);
    out
      ..writeln()
      ..write(_staticSections)
      ..writeln()
      ..writeln('### Montserrat licence text')
      ..writeln()
      ..writeln('```text')
      ..writeln(_cleanText(_lf(fontLicence)))
      ..writeln('```')
      ..writeln()
      ..writeln('## Licence texts of packages in the app')
      ..writeln()
      ..writeln(
        'Identical texts are printed once. The Flutter engine bundle '
        '(`sky_engine`) is over 1 MB and is not repeated here: the app shows '
        'it on its licences screen, and it ships with the Flutter SDK.',
      );

    // Group identical texts, ordered by first package name.
    final groups = <String, List<AuditedPackage>>{};
    for (final p in app.where((p) => p.licenceText != null)) {
      groups.putIfAbsent(p.licenceText!, () => []).add(p);
    }
    for (final entry in groups.entries) {
      final names = entry.value.map((p) => '`${p.name}`').join(', ');
      out
        ..writeln()
        ..writeln('### ${entry.value.first.licence.id}: $names')
        ..writeln()
        ..writeln('```text')
        ..writeln(entry.key)
        ..writeln('```');
    }
    return out.toString();
  }

  static void _table(StringBuffer out, List<AuditedPackage> list) {
    out
      ..writeln(
        '| Package | Version | Source | Dependency | Licence | Copyright |',
      )
      ..writeln('|---|---|---|---|---|---|');
    for (final p in list) {
      final copyright = p.copyright.isEmpty
          ? (p.licence == Licence.flutterEngine
                ? 'The Flutter Authors and many others'
                : 'Not stated in the licence file')
          : p.copyright.join('<br>');
      out.writeln(
        '| `${p.name}` | ${p.version} | ${p.source == 'sdk' ? 'Flutter SDK' : 'pub.dev'} '
        '| ${p.dependency} | ${p.licence.id} | ${_cell(copyright)} |',
      );
    }
  }
}

/// Components that are not Dart packages, written by hand. Keep in step with
/// docs/ARCHITECTURE.md and ADR-007.
const _staticSections = '''
## Native code and other components

| Component | Comes from | Licence | In the app |
|---|---|---|---|
| SQLite | `sqlite3` build hook: a prebuilt library from the `simolus3/sqlite3.dart` GitHub release, checked against hashes in the package (built from sqlite.org sources) | Public domain | Yes: `sqlite3.dll` on Windows, `libsqlite3.so` on Android, framework on iOS |
| Flutter engine, Dart runtime, Skia and Impeller | Flutter SDK (`sky_engine` and the embedders) | BSD-3-Clause plus the permissive licences in the engine bundle | Yes |
| Kotlin standard library, kotlinx.coroutines | Gradle, through `jni` (used by `path_provider_android`) | Apache-2.0 | Android only |
| AndroidX libraries | Gradle, through the Flutter Android embedding and plugins | Apache-2.0 | Android only |
| Microsoft Media Foundation, Windows SDK | Part of Windows, linked by `record_windows` | Operating system component, not redistributed | Windows (system) |
| AVFoundation and other Apple frameworks | Part of iOS | Operating system component, not redistributed | iOS (system) |
| GoogleTest 1.15.2 | `record_windows` CMake, fetched only when its own tests are built | BSD-3-Clause | No |

`sqlite3_flutter_libs` and `sqlcipher_flutter_libs` are end-of-life stubs with no native code. They are in the lock file only because `drift_flutter` still depends on them. SQLite comes from the `sqlite3` package's build hook.

The Flutter tool collects every package's `LICENSE` file into the app's `NOTICES` asset, which the app's licences screen (`showLicensePage`) shows. That screen is the in-app notice. This file is the repository notice.

## Fonts

| Font | Files | Licence |
|---|---|---|
| Montserrat (The Montserrat Project Authors, https://github.com/JulietaUla/Montserrat) | `assets/fonts/Montserrat-*.ttf` (400, 500, 600, 700) and `montserrat-latin-*.woff` | SIL Open Font License 1.1 (OFL-1.1) |

OFL-1.1 lets the fonts be bundled and redistributed with software under any licence. The font files may not be sold on their own, and a modified font may not use the reserved name "Montserrat". Attenlume bundles them unmodified.

## Brand assets (not open source)

The Attenlume name, logos and app icon in `assets/brand/` and `design/` belong to Samlytics Data Services. They are **not** covered by the project's open-source licence. Forks must remove or replace them. See ADR-007.

## Planned, not yet in the app

| Component | Licence | Note |
|---|---|---|
| Lucide icons (design guide) | ISC | Not added yet. Flutter wrappers `lucide_icons_flutter` and `flutter_lucide` are MIT and maintained; `lucide_icons` is stale (Dart 2). Choose in the first UI task and re-run this audit. |
''';

Map<String, Directory> _packageRoots() {
  final configFile = File(packageConfigPath);
  final json =
      jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
  final base = configFile.absolute.uri;
  return {
    for (final p in (json['packages'] as List).cast<Map<String, dynamic>>())
      p['name'] as String: Directory.fromUri(
        base.resolve(p['rootUri'] as String),
      ),
  };
}

final _licenceName = RegExp(
  r'^(licen[cs]e|copying)(\.(md|txt))?$',
  caseSensitive: false,
);

File? _findLicenceFile(Directory root, {required bool searchParents}) {
  var dir = root.absolute;
  // SDK packages such as flutter_test have no file of their own and fall
  // under the Flutter repository's LICENSE two levels up.
  for (var level = 0; level <= (searchParents ? 2 : 0); level++) {
    if (dir.existsSync()) {
      final files =
          dir
              .listSync()
              .whereType<File>()
              .where((f) => _licenceName.hasMatch(f.uri.pathSegments.last))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      if (files.isNotEmpty) return files.first;
    }
    dir = dir.parent;
  }
  return null;
}

String _lf(String s) => s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

/// Trims each line's trailing space and the text's outer blank lines, and
/// stops a stray fence from ending the code block early.
String _cleanText(String s) => s
    .split('\n')
    .map((l) => l.trimRight().replaceAll('```', "'''"))
    .join('\n')
    .trim();

/// A real notice such as "Copyright 2014, ..." or "Copyright (c) 2020 ...",
/// not licence prose ("copyright notice") or the Apache template line.
final _copyrightLine = RegExp(
  r'^copyright\s*(\(c\)|©)?\s*\d{4}',
  caseSensitive: false,
);

List<String> _copyrightLines(String text) {
  final lines = <String>[];
  for (final raw in text.split('\n')) {
    final line = raw.replaceFirst(RegExp(r'^\s*(//|#)\s?'), '').trim();
    if (_copyrightLine.hasMatch(line) && !lines.contains(line)) {
      lines.add(line);
      if (lines.length == 3) break;
    }
  }
  return lines;
}

String _cell(String s) => s.replaceAll('|', r'\|');
