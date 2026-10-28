/// Safe export file and folder names (FR-EXP-07, ADR-040) [P1-21].
///
/// Every name an export writes is an ASCII slug that Windows, macOS and
/// Linux all accept: ASCII letters, digits, `-`, `_` and one `.` before
/// an extension. Slugs made from user text are lower case; fixed names such
/// as `README_START_HERE.md` keep their capitals, and names are compared
/// case-insensitively because Windows and macOS do. No reserved characters, no reserved Windows device
/// names (`CON`, `NUL`, `COM1` ...), no leading or trailing dots or spaces.
/// Folder names are capped at [maxExportFolderNameLength] characters and
/// every relative path, root folder included, stays under
/// [exportPathLengthLimit] characters so it unzips well within Windows'
/// 260-character limit.
library;

import 'package:path/path.dart' as p;

/// Longest folder name an export writes (FR-EXP-07).
const maxExportFolderNameLength = 60;

/// Longest file name an export writes. FR-EXP-07 caps folders only; files
/// get a cap too so one long caption cannot use the whole path budget.
const maxExportFileNameLength = 80;

/// Every relative path is strictly shorter than this (FR-EXP-07).
const exportPathLengthLimit = 180;

/// Windows device names, reserved with or without an extension.
const _reservedNames = {
  'con',
  'prn',
  'aux',
  'nul',
  'com0',
  'com1',
  'com2',
  'com3',
  'com4',
  'com5',
  'com6',
  'com7',
  'com8',
  'com9',
  'lpt0',
  'lpt1',
  'lpt2',
  'lpt3',
  'lpt4',
  'lpt5',
  'lpt6',
  'lpt7',
  'lpt8',
  'lpt9',
  'conin\$',
  'conout\$',
};

/// Common Latin letters with accents, ligatures and a few symbols, mapped
/// to ASCII so "Café Zürich" reads as "cafe-zurich", not "caf-z-rich".
const _transliteration = <String, String>{
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', //
  'ă': 'a', 'ą': 'a', 'æ': 'ae', 'ç': 'c', 'ć': 'c', 'č': 'c', 'ď': 'd',
  'đ': 'd', 'ð': 'd', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e',
  'ė': 'e', 'ę': 'e', 'ě': 'e', 'ğ': 'g', 'ì': 'i', 'í': 'i', 'î': 'i',
  'ï': 'i', 'ī': 'i', 'į': 'i', 'ı': 'i', 'ł': 'l', 'ľ': 'l', 'ñ': 'n',
  'ń': 'n', 'ň': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ø': 'o', 'ō': 'o', 'ő': 'o', 'œ': 'oe', 'ř': 'r', 'ś': 's', 'š': 's',
  'ş': 's', 'ș': 's', 'ß': 'ss', 'ť': 't', 'ţ': 't', 'ț': 't', 'þ': 'th',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ů': 'u', 'ű': 'u',
  'ų': 'u', 'ý': 'y', 'ÿ': 'y', 'ź': 'z', 'ż': 'z', 'ž': 'z', '&': 'and',
  '@': 'at', '+': 'plus',
};

final _notSlug = RegExp(r'[^a-z0-9]+');
final _edgeJunk = RegExp(r'^[-_. ]+|[-_. ]+$');

/// Lower-case ASCII slug of [text]: letters and digits joined by `-`, at
/// most [maxLength] characters, never starting or ending with `-`, `_`,
/// `.` or a space. Returns [fallback] when nothing usable is left.
String exportSlug(String? text, {int maxLength = 40, String fallback = 'x'}) {
  final lower = (text ?? '').toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_transliteration[char] ?? char);
  }
  var slug = buffer.toString().replaceAll(_notSlug, '-');
  slug = _trimEdges(slug);
  if (slug.length > maxLength) slug = _trimEdges(slug.substring(0, maxLength));
  if (slug.isEmpty) return fallback;
  return _avoidReserved(slug);
}

/// Makes one path component safe (FR-EXP-07): only `A-Z a-z 0-9 - _ .`, no
/// leading or trailing dots, dashes or spaces, not a reserved device name,
/// at most [maxLength] characters. The extension, if any, is kept.
String safeExportComponent(String name, {required int maxLength}) {
  final rawExt = p.posix.extension(name);
  final ext = _safeExtension(rawExt.toLowerCase());
  var stem = name.substring(0, name.length - rawExt.length);
  stem = stem
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
      .replaceAll(RegExp('-{2,}'), '-');
  stem = _trimEdges(stem);
  if (stem.isEmpty) stem = 'x';
  final room = maxLength - ext.length;
  if (stem.length > room) stem = _trimEdges(stem.substring(0, room));
  if (stem.isEmpty) stem = 'x';
  return '${_avoidReserved(stem)}$ext';
}

/// True when [component] alone meets FR-EXP-07.
bool isSafeExportComponent(String component, {required int maxLength}) {
  if (component.isEmpty || component.length > maxLength) return false;
  if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(component)) return false;
  if (component.startsWith('.') || component.startsWith('-')) return false;
  if (component.endsWith('.') || component.endsWith(' ')) return false;
  final stem = component.split('.').first.toLowerCase();
  return !_reservedNames.contains(stem);
}

/// True when every component of the `/`-separated [relativePath] is safe
/// and the whole path is under [exportPathLengthLimit] (FR-EXP-07).
bool isSafeExportPath(String relativePath) {
  if (relativePath.length >= exportPathLengthLimit) return false;
  final parts = relativePath.split('/');
  for (var i = 0; i < parts.length; i++) {
    final isFile = i == parts.length - 1;
    if (!isSafeExportComponent(
      parts[i],
      maxLength: isFile ? maxExportFileNameLength : maxExportFolderNameLength,
    )) {
      return false;
    }
  }
  return true;
}

/// Hands out unique, safe paths inside one export (FR-EXP-07).
///
/// Paths compare case-insensitively (Windows and macOS do). A clash gets
/// `-2`, `-3` ... before the extension. A path that would reach
/// [exportPathLengthLimit] has its file name shortened, keeping the
/// extension and any clash suffix.
class ExportPathAllocator {
  ExportPathAllocator(String rootFolder)
    : root = safeExportComponent(
        rootFolder,
        maxLength: maxExportFolderNameLength,
      );

  /// The export's top folder name.
  final String root;
  final _taken = <String>{};

  /// A unique folder [name] inside [parent] (a path relative to [root],
  /// empty for the root itself). Returns the folder path relative to
  /// [root].
  String folder(String parent, String name) {
    final safe = safeExportComponent(
      name,
      maxLength: maxExportFolderNameLength,
    );
    for (var n = 1; ; n++) {
      final candidate = n == 1 ? safe : _withSuffix(safe, n, isFolder: true);
      final relative = parent.isEmpty ? candidate : '$parent/$candidate';
      if (_taken.add('${relative.toLowerCase()}/')) return relative;
    }
  }

  /// A unique file [name] inside [parent] (relative to [root]). Returns
  /// the path relative to [root]; `'$root/$result'` is under the limit for
  /// any root of up to [maxExportFolderNameLength] characters.
  String file(String parent, String name) {
    // The root may get a `-2` suffix later if the destination already
    // holds an export of the same name, so count it at its full cap.
    final prefixLength =
        maxExportFolderNameLength +
        1 +
        (parent.isEmpty ? 0 : parent.length + 1);
    // Room left for the file name so the full path stays under the limit.
    final room = exportPathLengthLimit - 1 - prefixLength;
    if (room < 8) {
      throw StateError('Export folder path is too long for a file name');
    }
    final maxLength = room < maxExportFileNameLength
        ? room
        : maxExportFileNameLength;
    final safe = safeExportComponent(name, maxLength: maxLength);
    for (var n = 1; ; n++) {
      final candidate = n == 1
          ? safe
          : _fit(_withSuffix(safe, n, isFolder: false), maxLength);
      final relative = parent.isEmpty ? candidate : '$parent/$candidate';
      if (_taken.add(relative.toLowerCase())) return relative;
    }
  }

  static String _withSuffix(String name, int n, {required bool isFolder}) {
    final ext = isFolder ? '' : p.posix.extension(name);
    final stem = name.substring(0, name.length - ext.length);
    final suffix = '-$n';
    final cap =
        (isFolder ? maxExportFolderNameLength : maxExportFileNameLength) -
        ext.length -
        suffix.length;
    final cut = stem.length > cap ? _trimEdges(stem.substring(0, cap)) : stem;
    return '$cut$suffix$ext';
  }

  /// Shortens [name]'s stem, keeping a trailing `-n` suffix and extension.
  static String _fit(String name, int maxLength) {
    if (name.length <= maxLength) return name;
    final ext = p.posix.extension(name);
    final stem = name.substring(0, name.length - ext.length);
    final match = RegExp(r'-\d+$').firstMatch(stem);
    final suffix = match?.group(0) ?? '';
    final base = stem.substring(0, stem.length - suffix.length);
    final room = maxLength - ext.length - suffix.length;
    final cut = base.isEmpty
        ? 'x'
        : _trimEdges(base.substring(0, room.clamp(1, base.length)));
    return '${cut.isEmpty ? 'x' : cut}$suffix$ext';
  }
}

String _trimEdges(String s) => s.replaceAll(_edgeJunk, '');

String _safeExtension(String ext) {
  final cleaned = ext.replaceAll(RegExp(r'[^a-z0-9.]'), '');
  if (cleaned.length <= 1 || cleaned.length > 8) return '';
  return '.${cleaned.substring(1).replaceAll('.', '')}';
}

String _avoidReserved(String stem) {
  final head = stem.split('.').first.toLowerCase();
  return _reservedNames.contains(head) ? '${stem}_' : stem;
}
