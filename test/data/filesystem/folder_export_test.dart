import 'dart:io';

import 'package:attenlume/data/filesystem/folder_export.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory source;
  late Directory destination;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('folder_export_test');
    source = Directory(p.join(root.path, 'source'));
    destination = Directory(p.join(root.path, 'dest'));
    await File(p.join(source.path, 'audio', 'segment-001.m4a'))
        .create(recursive: true)
        .then((f) => f.writeAsBytes(List.generate(300000, (i) => i % 251)));
    await File(p.join(source.path, 'audio', 'segment-002.m4a'))
        .writeAsBytes(List.generate(1000, (i) => i % 7));
    await File(p.join(source.path, 'notes.md')).writeAsString('# Notes\n');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  Map<String, String> snapshot(Directory dir) => {
    for (final f in dir.listSync(recursive: true).whereType<File>())
      p.relative(f.path, from: dir.path): sha256
          .convert(f.readAsBytesSync())
          .toString(),
  };

  group('FR-EXP-06 folder export with checksums [P0-06]', () {
    test('FR-EXP-06 copies every file and writes checksums.sha256', () async {
      final result = await exportFolder(
        source: source,
        destinationParent: destination,
        folderName: 'export-1',
      );
      expect(result.folder.path, p.join(destination.path, 'export-1'));
      expect(result.files.map((f) => f.relativePath), [
        'audio/segment-001.m4a',
        'audio/segment-002.m4a',
        'notes.md',
      ]);
      expect(result.totalBytes, 300000 + 1000 + 8);

      final checksums = File(p.join(result.folder.path, checksumFileName))
          .readAsLinesSync();
      expect(checksums, hasLength(3));
      expect(
        checksums.first,
        '${sha256.convert(List.generate(300000, (i) => i % 251))}'
        '  audio/segment-001.m4a',
      );
      expect(await verifyChecksums(result.folder), isEmpty);
    });

    test('FR-EXP-06 verifyChecksums reports a changed file', () async {
      final result = await exportFolder(
        source: source,
        destinationParent: destination,
        folderName: 'export-1',
      );
      await File(p.join(result.folder.path, 'notes.md'))
          .writeAsString('changed');
      expect(await verifyChecksums(result.folder), ['notes.md']);
    });

    test('FR-EXP-04 leaves no temp or partial files behind', () async {
      await exportFolder(
        source: source,
        destinationParent: destination,
        folderName: 'export-1',
      );
      final names = destination
          .listSync(recursive: true)
          .map((e) => p.basename(e.path));
      expect(names.where((n) => n.endsWith('.tmp')), isEmpty);
      expect(names.where((n) => n.endsWith('.partial')), isEmpty);
    });
  });

  group('FR-EXP-05 export never harms sources or existing files [P0-06]', () {
    test('FR-EXP-05 source files are unchanged', () async {
      final before = snapshot(source);
      await exportFolder(
        source: source,
        destinationParent: destination,
        folderName: 'export-1',
      );
      expect(snapshot(source), before);
    });

    test('FR-EXP-05 refuses to overwrite an existing export folder', () async {
      final existing = File(p.join(destination.path, 'export-1', 'keep.txt'));
      await existing.create(recursive: true);
      await existing.writeAsString('mine');
      await expectLater(
        exportFolder(
          source: source,
          destinationParent: destination,
          folderName: 'export-1',
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(existing.readAsStringSync(), 'mine');
    });

    test('FR-EXP-05 failure mid-copy removes only the partial copy', () async {
      final before = snapshot(source);
      var copied = 0;
      await expectLater(
        exportFolder(
          source: source,
          destinationParent: destination,
          folderName: 'export-1',
          onFileDone: (_) {
            if (++copied == 2) throw const FileSystemException('disk full');
          },
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(copied, 2);
      expect(destination.listSync(), isEmpty);
      expect(snapshot(source), before);
    });
  });
}
