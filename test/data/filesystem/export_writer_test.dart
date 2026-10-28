import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:attenlume/data/filesystem/export_writer.dart';
import 'package:attenlume/data/filesystem/folder_export.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/cut_range_math.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../fixtures/mp4_fixture.dart';

void main() {
  late Directory root;
  late Directory dest;
  late File audio;
  late File photo;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('export_writer_test');
    dest = Directory(p.join(root.path, 'dest'));
    audio = File(p.join(root.path, 'src', 'a.m4a'));
    await audio.parent.create(recursive: true);
    await writeMp4Fixture(audio);
    photo = File(p.join(root.path, 'src', 'p.jpg'))
      ..writeAsBytesSync(List.generate(250000, (i) => i % 253));
  });

  tearDown(() => root.delete(recursive: true));

  ExportWritePlan plan(ExportFormat format, {List<ExportEntry>? entries}) =>
      ExportWritePlan(
        format: format,
        destinationParent: dest.path,
        rootName: 'export',
        tempDirectory: p.join(root.path, 'tmp', 'job'),
        entries:
            entries ??
            [
              ExportEntry(
                relativePath: 'conference.json',
                source: TextExportSource('{}\n'),
                estimatedBytes: 3,
              ),
              ExportEntry(
                relativePath: 'activities/001_talk/audio/segment-001.m4a',
                source: FileExportSource(audio.path),
                estimatedBytes: audio.lengthSync(),
              ),
              ExportEntry(
                relativePath:
                    'activities/001_talk/audio/segment-001-trimmed.m4a',
                source: TrimmedAudioExportSource(audio.path, const [
                  TimeRange(5000, 10000),
                ]),
                estimatedBytes: audio.lengthSync(),
              ),
              ExportEntry(
                relativePath: 'activities/001_talk/photos/p.jpg',
                source: FileExportSource(photo.path),
                estimatedBytes: photo.lengthSync(),
              ),
            ],
      );

  test('FR-EXP-02 FR-EXP-06 folder output with verified checksums', () async {
    final progress = <ExportWriteProgress>[];
    final result = await writeExport(
      plan(ExportFormat.folder),
      onProgress: progress.add,
    );
    expect(result.outputPath, p.join(dest.path, 'export'));
    expect(result.files, hasLength(4));
    expect(await verifyChecksums(Directory(result.outputPath)), isEmpty);
    expect(progress.last.filesDone, 4);
    expect(progress.last.fraction, closeTo(1, 0.5));
    expect(Directory(p.join(root.path, 'tmp', 'job')).existsSync(), isFalse);
  });

  test(
    'FR-EXP-02 FR-EXP-04 ZIP output stores members under the root',
    () async {
      final result = await writeExport(plan(ExportFormat.zip));
      expect(result.outputPath, p.join(dest.path, 'export.zip'));
      final input = InputFileStream(result.outputPath);
      final archive = ZipDecoder().decodeStream(input);
      expect(archive.files.map((f) => f.name), [
        'export/conference.json',
        'export/activities/001_talk/audio/segment-001.m4a',
        'export/activities/001_talk/audio/segment-001-trimmed.m4a',
        'export/activities/001_talk/photos/p.jpg',
        'export/checksums.sha256',
      ]);
      // Stored, not deflated: the ZIP is barely larger than its contents.
      final content = result.files.fold(0, (n, f) => n + f.bytes);
      expect(File(result.outputPath).lengthSync() - content, lessThan(4096));
      final photoMember = archive.findFile(
        'export/activities/001_talk/photos/p.jpg',
      )!;
      expect(
        sha256.convert(photoMember.content).toString(),
        result.files
            .singleWhere((f) => f.relativePath.endsWith('p.jpg'))
            .sha256,
      );
      await input.close();
      // Scratch trimmed copies are gone.
      expect(Directory(p.join(root.path, 'tmp', 'job')).existsSync(), isFalse);
    },
  );

  for (final format in ExportFormat.values) {
    test(
      'FR-EXP-05 ${format.key}: a failure leaves no partial and sources intact',
      () async {
        final before = sha256.convert(photo.readAsBytesSync()).toString();
        final broken = plan(
          format,
          entries: [
            ExportEntry(
              relativePath: 'photos/p.jpg',
              source: FileExportSource(photo.path),
              estimatedBytes: 1,
            ),
            ExportEntry(
              relativePath: 'audio/missing.m4a',
              source: FileExportSource(p.join(root.path, 'nope.m4a')),
              estimatedBytes: 1,
            ),
          ],
        );
        await expectLater(
          writeExport(broken),
          throwsA(isA<FileSystemException>()),
        );
        expect(
          dest.existsSync() ? dest.listSync() : const <FileSystemEntity>[],
          isEmpty,
        );
        expect(sha256.convert(photo.readAsBytesSync()).toString(), before);
      },
    );

    test('FR-EXP-05 ${format.key}: cancelling removes the partial', () async {
      var calls = 0;
      await expectLater(
        writeExport(plan(format), isCancelled: () => ++calls > 2),
        throwsA(isA<ExportCancelledException>()),
      );
      expect(dest.listSync(), isEmpty);
    });
  }

  test('FR-EXP-05 never overwrites an existing export', () async {
    await Directory(p.join(dest.path, 'export')).create(recursive: true);
    await expectLater(
      writeExport(plan(ExportFormat.folder)),
      throwsA(isA<FileSystemException>()),
    );
    expect(Directory(p.join(dest.path, 'export')).listSync(), isEmpty);
  });

  test('FR-EXP-04 background isolate writes the same export', () async {
    final progress = <ExportWriteProgress>[];
    final result = await writeExportInBackground(
      plan(ExportFormat.folder),
      onProgress: progress.add,
    );
    expect(await verifyChecksums(Directory(result.outputPath)), isEmpty);
    expect(progress, isNotEmpty);
  });

  test('FR-EXP-05 background isolate: errors and cancel come back', () async {
    await expectLater(
      writeExportInBackground(
        plan(
          ExportFormat.zip,
          entries: [
            ExportEntry(
              relativePath: 'x.m4a',
              source: FileExportSource(p.join(root.path, 'nope.m4a')),
              estimatedBytes: 1,
            ),
          ],
        ),
      ),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      writeExportInBackground(
        plan(ExportFormat.folder),
        cancel: Future<void>.value(),
      ),
      throwsA(isA<ExportCancelledException>()),
    );
    expect(dest.listSync(), isEmpty);
  });
}
