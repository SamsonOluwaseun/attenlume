import 'package:attenlume/data/filesystem/safe_export_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FR-EXP-07 slugs', () {
    test('FR-EXP-07 ASCII slug with accents transliterated', () {
      expect(exportSlug('Data Mesh in Practice'), 'data-mesh-in-practice');
      expect(
        exportSlug('Café Zürich: Ærø & Łódź'),
        'cafe-zurich-aero-and-lodz',
      );
      expect(exportSlug('日本語'), 'x');
      expect(exportSlug('  ', fallback: 'untitled'), 'untitled');
      expect(exportSlug(null, fallback: 'photo'), 'photo');
    });

    test('FR-EXP-07 reserved characters are replaced', () {
      final slug = exportSlug(r'a<b>c:d"e/f\g|h?i*j');
      expect(slug, 'a-b-c-d-e-f-g-h-i-j');
      expect(safeExportComponent(r'a<b>:"/\|?*.txt', maxLength: 60), 'a-b.txt');
    });

    test('FR-EXP-07 reserved Windows names are changed', () {
      for (final name in ['CON', 'con', 'NUL', 'Aux', 'PRN', 'COM1', 'lpt9']) {
        final safe = safeExportComponent(name, maxLength: 60);
        expect(safe.toLowerCase(), isNot(name.toLowerCase()));
        expect(
          isSafeExportComponent(safe, maxLength: 60),
          isTrue,
          reason: safe,
        );
      }
      expect(safeExportComponent('nul.txt', maxLength: 60), 'nul_.txt');
      expect(exportSlug('con'), 'con_');
      expect(isSafeExportComponent('CON.txt', maxLength: 60), isFalse);
      expect(isSafeExportComponent('console.txt', maxLength: 60), isTrue);
    });

    test('FR-EXP-07 no leading or trailing dots or spaces', () {
      expect(safeExportComponent('notes. . ', maxLength: 60), 'notes');
      // A dot-only stem never leads: '...hidden' is all extension.
      expect(safeExportComponent('...hidden', maxLength: 60), 'x.hidden');
      expect(
        safeExportComponent('...my notes.md', maxLength: 60),
        'my-notes.md',
      );
      expect(safeExportComponent('report .md', maxLength: 60), 'report.md');
      expect(exportSlug('-- trailing --.'), 'trailing');
      expect(isSafeExportComponent('name.', maxLength: 60), isFalse);
      expect(isSafeExportComponent('name ', maxLength: 60), isFalse);
      expect(isSafeExportComponent('.name', maxLength: 60), isFalse);
    });

    test('FR-EXP-07 folder names capped at 60 characters', () {
      final paths = ExportPathAllocator('r' * 100);
      expect(paths.root.length, maxExportFolderNameLength);
      final folder = paths.folder('activities', '001_${'long-title-' * 20}');
      expect(folder.split('/').last.length, lessThanOrEqualTo(60));
      expect(folder.split('/').last, isNot(endsWith('-')));
    });
  });

  group('FR-EXP-07 path allocation', () {
    test('FR-EXP-07 total relative path stays under 180 characters', () {
      final paths = ExportPathAllocator('a' * 60);
      final folder = paths.folder('activities', 'b' * 60);
      final file = paths.file('$folder/photos', '${'c' * 300}.jpg');
      final full = '${paths.root}/$file';
      expect(full.length, lessThan(exportPathLengthLimit));
      expect(file, endsWith('.jpg'));
      expect(isSafeExportPath(full), isTrue);
    });

    test('FR-EXP-07 clashes get a suffix, compared case-insensitively', () {
      final paths = ExportPathAllocator('root');
      expect(paths.file('audio', 'Segment-001.m4a'), 'audio/Segment-001.m4a');
      expect(paths.file('audio', 'segment-001.m4a'), 'audio/segment-001-2.m4a');
      expect(paths.file('audio', 'segment-001.m4a'), 'audio/segment-001-3.m4a');
      expect(paths.folder('activities', 'talk'), 'activities/talk');
      expect(paths.folder('activities', 'TALK'), 'activities/TALK-2');
    });

    test('FR-EXP-07 a long clashing name keeps its suffix and extension', () {
      final paths = ExportPathAllocator('a' * 60);
      final folder = paths.folder('activities', 'b' * 60);
      final first = paths.file(folder, '${'c' * 200}.json');
      final second = paths.file(folder, '${'c' * 200}.json');
      expect(second, endsWith('-2.json'));
      expect(second, isNot(first));
      expect('${paths.root}/$second'.length, lessThan(exportPathLengthLimit));
    });

    test('FR-EXP-07 isSafeExportPath rejects long and unsafe paths', () {
      expect(
        isSafeExportPath('root/activities/x/audio/segment-001.m4a'),
        isTrue,
      );
      expect(isSafeExportPath('root/${'a' * 61}/file.txt'), isFalse);
      expect(isSafeExportPath('root/a b/file.txt'), isFalse);
      expect(isSafeExportPath('root/${'a/' * 90}f'), isFalse);
    });
  });
}
