import 'dart:io';

import 'package:archive/archive.dart';
import 'package:attenlume/data/filesystem/export_space.dart';
import 'package:attenlume/data/filesystem/zip_export.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../fixtures/fake_free_space_probe.dart';

void main() {
  late Directory root;
  late Directory source;
  late Directory destination;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('zip_export_test');
    source = Directory(p.join(root.path, 'source'));
    destination = Directory(p.join(root.path, 'dest'));
    await destination.create(recursive: true);

    // audio/segment-001.m4a: 300 KB of pseudo-audio.
    await File(p.join(source.path, 'audio', 'segment-001.m4a'))
        .create(recursive: true)
        .then((f) => f.writeAsBytes(List.generate(300000, (i) => i % 251)));
    // audio/segment-002.m4a: 1 KB.
    await File(p.join(source.path, 'audio', 'segment-002.m4a'))
        .writeAsBytes(List.generate(1000, (i) => i % 7));
    // notes.md: a short text file.
    await File(p.join(source.path, 'notes.md')).writeAsString('# Notes\n');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  group('FR-EXP-02 streaming ZIP export with store compression [P0-11]', () {
    test('FR-EXP-02 produces a valid ZIP with all files', () async {
      final result = await exportZip(
        source: source,
        destinationParent: destination,
        zipName: 'conference-export',
      );
      expect(result.zipFile.existsSync(), isTrue);
      expect(result.files.map((f) => f.relativePath), [
        'audio/segment-001.m4a',
        'audio/segment-002.m4a',
        'notes.md',
      ]);
      expect(result.totalContentBytes, 300000 + 1000 + 8);

      // The ZIP should contain checksums.sha256 too.
      final checksumsFile = File(
        p.join(destination.path, 'conference-export.sha256'),
      );
      expect(checksumsFile.existsSync(), isTrue);
    });

    test('FR-EXP-04 ZIP uses store (no compression) for media', () async {
      final result = await exportZip(
        source: source,
        destinationParent: destination,
        zipName: 'export-store',
      );
      // The ZIP size should be close to the sum of the source files plus
      // ZIP overhead (local file headers, central directory). With store
      // (no compression), the overhead is small.
      final zipSize = result.zipFile.lengthSync();
      final dataSize = result.totalContentBytes;
      // Overhead per file: ~80 bytes local header + 80 bytes central entry.
      // Plus end of central directory. Total overhead under 2 KiB for 3 files.
      expect(zipSize, greaterThan(dataSize));
      expect(zipSize - dataSize, lessThan(4096));
    });

    test('FR-EXP-06 checksums.sha256 lists every file', () async {
      final result = await exportZip(
        source: source,
        destinationParent: destination,
        zipName: 'export-cs',
      );
      final checksumFile = File(p.join(destination.path, 'export-cs.sha256'));
      final lines = checksumFile.readAsLinesSync().where(
        (l) => l.trim().isNotEmpty,
      );
      expect(lines.length, result.files.length);
      for (final f in result.files) {
        expect(
          lines.any((l) => l.contains(f.sha256) && l.contains(f.relativePath)),
          isTrue,
          reason: '${f.relativePath} should be in checksums',
        );
      }
    });

    test('FR-EXP-05 refuses to overwrite an existing ZIP', () async {
      final existing = File(p.join(destination.path, 'export-dup.zip'));
      await existing.writeAsString('mine');
      await expectLater(
        exportZip(
          source: source,
          destinationParent: destination,
          zipName: 'export-dup',
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(existing.readAsStringSync(), 'mine');
    });

    test('FR-EXP-05 source files are unchanged after ZIP export', () async {
      String hashDir(Directory dir) {
        final sb = StringBuffer();
        final files = dir.listSync(recursive: true).whereType<File>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        for (final f in files) {
          sb.write(p.relative(f.path, from: dir.path));
          sb.write(':');
          sb.write(sha256.convert(f.readAsBytesSync()));
          sb.write('\n');
        }
        return sb.toString();
      }

      final before = hashDir(source);
      await exportZip(
        source: source,
        destinationParent: destination,
        zipName: 'export-safe',
      );
      expect(hashDir(source), before);
    });
  });

  group('AT-STO-03 preflight and disk-full for ZIP [P0-11]', () {
    test('AT-STO-03 preflight rejects when space is insufficient', () async {
      // Pretend only 1 KiB free.
      final probe = FakeFreeSpaceProbe(1024);
      await expectLater(
        exportZip(
          source: source,
          destinationParent: destination,
          zipName: 'export-full',
          freeSpace: probe,
        ),
        throwsA(isA<InsufficientSpaceException>()),
      );
      // No ZIP file should have been created.
      expect(
        destination.listSync().where(
          (e) =>
              e.path.endsWith('.zip') ||
              e.path.endsWith('.zip.partial') ||
              e.path.endsWith('.sha256'),
        ),
        isEmpty,
      );
    });

    test('AT-STO-03 preflight passes when space is plenty', () async {
      final probe = FakeFreeSpaceProbe(1 << 30);
      final result = await exportZip(
        source: source,
        destinationParent: destination,
        zipName: 'export-ok',
        freeSpace: probe,
      );
      expect(result.zipFile.existsSync(), isTrue);
    });

    test('FR-EXP-06 ZIP archive contains checksums.sha256 entry', () async {
      final result = await exportZip(
        source: source,
        destinationParent: destination,
        zipName: 'export-archive-cs',
      );
      final bytes = result.zipFile.readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      final checksumEntry = archive.findFile('checksums.sha256');
      expect(checksumEntry, isNotNull);
      final content = String.fromCharCodes(checksumEntry!.content as List<int>);
      for (final f in result.files) {
        expect(content, contains('${f.sha256}  ${f.relativePath}'));
      }
    });

    test(
      'FR-EXP-05 failure mid-archive removes partial files and leaves sources',
      () async {
        final before = File(p.join(source.path, 'notes.md')).readAsStringSync();
        var count = 0;
        await expectLater(
          exportZip(
            source: source,
            destinationParent: destination,
            zipName: 'export-abort',
            onFileDone: (_) {
              if (++count == 2) throw const FileSystemException('interrupted');
            },
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(count, 2);
        expect(
          destination.listSync().where(
            (e) => p.basename(e.path).startsWith('export-abort'),
          ),
          isEmpty,
        );
        expect(
          File(p.join(source.path, 'notes.md')).readAsStringSync(),
          before,
        );
      },
    );

    test(
      'FR-STO-04 disk-full error mid-archive throws ExportOutOfSpaceException',
      () async {
        var count = 0;
        await expectLater(
          exportZip(
            source: source,
            destinationParent: destination,
            zipName: 'export-disk-full',
            onFileDone: (_) {
              if (++count == 2) {
                throw FileSystemException(
                  'disk full',
                  '',
                  OSError('disk full', Platform.isWindows ? 112 : 28),
                );
              }
            },
          ),
          throwsA(isA<ExportOutOfSpaceException>()),
        );
        expect(
          destination.listSync().where(
            (e) => p.basename(e.path).startsWith('export-disk-full'),
          ),
          isEmpty,
        );
      },
    );
  });
}
