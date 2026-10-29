/// Reading an Attenlume export back in: a folder or a ZIP, listed, copied
/// into a staging folder and checked against `checksums.sha256`
/// (FR-EXP-11, ADR-049) [P1-23].
///
/// Nothing here loads a whole recording into memory: folder files are
/// streamed with [copyFileHashing], ZIP members are streamed by the
/// `archive` package into files on a background isolate, then hashed in
/// chunks.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'folder_export.dart';

/// Why an export cannot be read or imported. [message] is for the user.
class ExportImportException implements Exception {
  const ExportImportException(this.message);

  final String message;

  @override
  String toString() => 'ExportImportException: $message';
}

/// One file in the export, by its path from the export's root folder.
class ExportMember {
  const ExportMember(this.relativePath, this.bytes);

  /// Always with `/`, never starting with `/` and never holding `..`.
  final String relativePath;
  final int bytes;
}

/// The outcome of comparing the staged copies with `checksums.sha256`.
class ChecksumCheck {
  const ChecksumCheck({
    required this.checked,
    this.mismatched = const [],
    this.missing = const [],
    this.unlisted = const [],
  });

  /// Files listed and matching.
  final int checked;

  /// Listed, present, but a different SHA-256.
  final List<String> mismatched;

  /// Listed but not in the export.
  final List<String> missing;

  /// In the export but not listed: not checked, so never imported.
  final List<String> unlisted;

  bool get ok => mismatched.isEmpty && missing.isEmpty;
}

/// A staged, checked copy of an export.
class StagedExport {
  const StagedExport({
    required this.folder,
    required this.hashes,
    required this.sizes,
    required this.check,
  });

  /// The staging folder; it mirrors the export's root folder.
  final Directory folder;

  /// SHA-256 of every staged file, by relative path.
  final Map<String, String> hashes;

  /// Size of every staged file, by relative path.
  final Map<String, int> sizes;

  final ChecksumCheck check;

  File file(String relativePath) =>
      File(p.joinAll([folder.path, ...p.posix.split(relativePath)]));
}

/// Progress while staging and checking, in bytes.
typedef ImportByteProgress = void Function(int done, int total);

/// An export picked by the user, before anything is copied.
class ExportImportSource {
  ExportImportSource._({
    required this.path,
    required this.isZip,
    required this.rootName,
    required this.members,
    required this._zipPrefix,
    required this._folderRoot,
  });

  /// What the user picked: a folder or a `.zip` file.
  final String path;
  final bool isZip;

  /// Name of the export's root folder (`2026-11-04_samlytics-...`).
  final String rootName;

  /// Every file in the export, `checksums.sha256` included.
  final List<ExportMember> members;

  final String? _zipPrefix;
  final String? _folderRoot;

  int get totalBytes => members.fold(0, (n, m) => n + m.bytes);

  bool get hasChecksums =>
      members.any((m) => m.relativePath == checksumFileName);

  /// Opens [path]: a `.zip` file, an export folder, or a folder holding
  /// exactly one export folder. Refuses a half-written export (`.partial`)
  /// and anything without `checksums.sha256`.
  static Future<ExportImportSource> open(String path) async {
    if (_isPartial(path)) {
      throw const ExportImportException(
        'This export was not finished (its name ends in ".partial"), so it '
        'cannot be imported.',
      );
    }
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.file) {
      if (p.extension(path).toLowerCase() != '.zip') {
        throw const ExportImportException(
          'Choose an Attenlume export folder or its ZIP file.',
        );
      }
      return _openZip(path);
    }
    if (type == FileSystemEntityType.directory) return _openFolder(path);
    throw const ExportImportException('The chosen export could not be found.');
  }

  static bool _isPartial(String path) {
    final name = p.basename(
      path.endsWith(p.separator) ? p.dirname(path) : path,
    );
    return name.toLowerCase().endsWith('.partial') ||
        name.toLowerCase().endsWith('.partial.zip');
  }

  static bool _looksLikeRoot(Directory dir) =>
      File(p.join(dir.path, 'conference.json')).existsSync() ||
      File(p.join(dir.path, checksumFileName)).existsSync();

  static Future<ExportImportSource> _openFolder(String path) async {
    var root = Directory(path);
    if (!_looksLikeRoot(root)) {
      final inner = root
          .listSync()
          .whereType<Directory>()
          .where(_looksLikeRoot)
          .toList();
      if (inner.length != 1) {
        throw const ExportImportException(
          'This folder is not an Attenlume export: there is no '
          'conference.json in it.',
        );
      }
      root = inner.single;
    }
    if (_isPartial(root.path)) {
      throw const ExportImportException(
        'This export was not finished (its name ends in ".partial"), so it '
        'cannot be imported.',
      );
    }
    final members = <ExportMember>[];
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = p.posix.joinAll(p.split(p.relative(e.path, from: root.path)));
      members.add(ExportMember(rel, e.lengthSync()));
    }
    members.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return _checked(
      ExportImportSource._(
        path: path,
        isZip: false,
        rootName: p.basename(root.path),
        members: members,
        zipPrefix: null,
        folderRoot: root.path,
      ),
    );
  }

  static Future<ExportImportSource> _openZip(String path) async {
    final entries = await Isolate.run(() => _listZip(path));
    // Exports put everything under one `<root>/` folder; accept a ZIP
    // without it too.
    final firsts = {
      for (final (name, _) in entries)
        if (name.contains('/')) name.substring(0, name.indexOf('/')),
    };
    final topLevelFiles = entries.any((e) => !e.$1.contains('/'));
    final prefix = (firsts.length == 1 && !topLevelFiles)
        ? '${firsts.single}/'
        : '';
    final members = [
      for (final (name, size) in entries)
        ExportMember(name.substring(prefix.length), size),
    ]..sort((a, b) => a.relativePath.compareTo(b.relativePath));
    final rootName = prefix.isEmpty
        ? p.basenameWithoutExtension(path)
        : prefix.substring(0, prefix.length - 1);
    if (_isPartial(rootName)) {
      throw const ExportImportException(
        'This export was not finished (its name ends in ".partial"), so it '
        'cannot be imported.',
      );
    }
    return _checked(
      ExportImportSource._(
        path: path,
        isZip: true,
        rootName: rootName,
        members: members,
        zipPrefix: prefix,
        folderRoot: null,
      ),
    );
  }

  static ExportImportSource _checked(ExportImportSource source) {
    for (final m in source.members) {
      if (!isSafeRelativePath(m.relativePath)) {
        throw const ExportImportException(
          'This export holds a file with an unsafe name, so it cannot be '
          'imported.',
        );
      }
    }
    if (!source.members.any((m) => m.relativePath == 'conference.json')) {
      throw const ExportImportException(
        'This is not an Attenlume export: conference.json is missing.',
      );
    }
    if (!source.hasChecksums) {
      throw const ExportImportException(
        'checksums.sha256 is missing, so the export may be incomplete. It '
        'cannot be imported.',
      );
    }
    return source;
  }

  /// Copies every file into [staging] (which must not exist yet) and
  /// compares each copy with `checksums.sha256`. Files the checksum list
  /// does not name are not copied. The original export is only read.
  Future<StagedExport> stage(
    Directory staging, {
    ImportByteProgress? onProgress,
    bool Function()? isCancelled,
  }) async {
    await staging.create(recursive: true);
    File target(String rel) =>
        File(p.joinAll([staging.path, ...p.posix.split(rel)]));

    // The checksum list first, so only listed files are copied.
    await _copyMember(checksumFileName, target(checksumFileName));
    final expected = parseChecksums(
      await target(checksumFileName).readAsString(),
    );
    final present = {for (final m in members) m.relativePath: m};
    final listed = [
      for (final rel in expected.keys)
        if (present.containsKey(rel)) present[rel]!,
    ];
    final missing = [
      for (final rel in expected.keys)
        if (!present.containsKey(rel)) rel,
    ];
    final unlisted = [
      for (final m in members)
        if (m.relativePath != checksumFileName &&
            !expected.containsKey(m.relativePath))
          m.relativePath,
    ];

    final total = listed.fold<int>(0, (n, m) => n + m.bytes);
    var done = 0;
    onProgress?.call(0, total);
    final hashes = <String, String>{};
    final sizes = <String, int>{};
    for (final m in listed) {
      if (isCancelled?.call() ?? false) {
        throw const ExportImportException('Import cancelled.');
      }
      final out = target(m.relativePath);
      await out.parent.create(recursive: true);
      final (bytes, hash) = await _copyMember(m.relativePath, out);
      hashes[m.relativePath] = hash;
      sizes[m.relativePath] = bytes;
      done += m.bytes;
      onProgress?.call(done, total);
    }
    final mismatched = [
      for (final m in listed)
        if (hashes[m.relativePath] != expected[m.relativePath]) m.relativePath,
    ];
    return StagedExport(
      folder: staging,
      hashes: hashes,
      sizes: sizes,
      check: ChecksumCheck(
        checked: listed.length - mismatched.length,
        mismatched: mismatched,
        missing: missing,
        unlisted: unlisted,
      ),
    );
  }

  Future<(int, String)> _copyMember(String rel, File to) async {
    if (!isZip) {
      final from = File(p.joinAll([_folderRoot!, ...p.posix.split(rel)]));
      return copyFileHashing(from, to);
    }
    final zip = path;
    final name = '$_zipPrefix$rel';
    final temp = '${to.path}.tmp';
    await Isolate.run(() => _extractZipMember(zip, name, temp));
    final hash = await hashFileSha256(File(temp));
    final file = await File(temp).rename(to.path);
    return (file.lengthSync(), hash);
  }
}

/// True for a relative path made only of ordinary names: no drive, no
/// leading `/`, no `..`, no backslash (so a ZIP cannot write outside the
/// staging folder).
bool isSafeRelativePath(String rel) {
  if (rel.isEmpty || rel.startsWith('/') || rel.contains('\\')) return false;
  if (rel.contains(':')) return false;
  for (final part in rel.split('/')) {
    if (part.isEmpty || part == '.' || part == '..') return false;
  }
  return true;
}

/// `checksums.sha256` lines (`<sha256>  <relative path>`) as a map.
Map<String, String> parseChecksums(String text) {
  final out = <String, String>{};
  for (final line in text.split(RegExp(r'\r?\n'))) {
    if (line.trim().isEmpty) continue;
    final split = line.indexOf('  ');
    if (split <= 0) continue;
    final rel = line.substring(split + 2).trim();
    if (!isSafeRelativePath(rel)) continue;
    out[rel] = line.substring(0, split).trim().toLowerCase();
  }
  return out;
}

/// ZIP file names and sizes, read from the central directory only.
List<(String, int)> _listZip(String path) {
  final input = InputFileStream(path);
  try {
    final archive = ZipDecoder().decodeStream(input);
    return [
      for (final f in archive.files)
        if (f.isFile) (f.name, f.size),
    ];
  } on Object {
    throw const ExportImportException(
      'This ZIP file could not be read. It may be damaged or incomplete.',
    );
  } finally {
    input.closeSync();
  }
}

/// Streams one member of [zip] into [target] (runs on a background
/// isolate; the archive package decodes synchronously).
void _extractZipMember(String zip, String name, String target) {
  final input = InputFileStream(zip);
  try {
    final archive = ZipDecoder().decodeStream(input);
    final entry = archive.findFile(name);
    if (entry == null || !entry.isFile) {
      throw const ExportImportException('A file is missing from the ZIP.');
    }
    final output = OutputFileStream(target);
    try {
      entry.writeContent(output);
    } finally {
      output.closeSync();
    }
  } finally {
    input.closeSync();
  }
}
