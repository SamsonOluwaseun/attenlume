import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import 'exif_reader.dart';
import 'gallery_source.dart';

export 'exif_reader.dart';

/// Photos in a folder the user chooses, for Windows, which has no photo
/// library API for `photo_manager` (ADR-035, PLATFORM_FEASIBILITY 2.8)
/// [P1-15, FR-PHO-05].
///
/// A photo's time is its EXIF `DateTimeOriginal` (with
/// `OffsetTimeOriginal` when the camera wrote one, otherwise this PC's
/// timezone), falling back to the file's last-modified time.
class FolderGallerySource implements GallerySource {
  FolderGallerySource({Future<String?> Function()? pickFolder})
    : _pickFolder = pickFolder ?? getDirectoryPath;

  final Future<String?> Function() _pickFolder;
  String? _folder;

  /// The folder chosen in [open].
  String? get folder => _folder;

  @override
  bool get choosesFolder => true;

  @override
  Future<GalleryAccess> open() async {
    final folder = await _pickFolder();
    if (folder == null) return GalleryAccess.cancelled;
    _folder = folder;
    return GalleryAccess.full;
  }

  @override
  Future<List<GalleryItem>> photosBetween(DateTime fromUtc, DateTime toUtc) {
    final folder = _folder;
    if (folder == null) return Future.value(const []);
    return Isolate.run(() => scanFolder(folder, fromUtc, toUtc));
  }

  @override
  Future<Uint8List?> thumbnail(GalleryItem item, {int size = 200}) async =>
      null;

  @override
  Future<File?> fileFor(GalleryItem item) async {
    final path = item.path;
    if (path == null) return null;
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  @override
  Future<void> openSettings() async {}

  @override
  Future<void> cleanUp() async {}
}

const _extensions = {'.jpg', '.jpeg', '.png'};

/// How deep below the chosen folder to look (Camera Roll\2026\11 is two).
const _maxDepth = 3;

/// Files read for EXIF in one scan, so a huge folder stays quick.
const _maxReads = 2000;

/// Lists JPEG and PNG files under [folder] taken between [fromUtc] and
/// [toUtc], oldest first. Files last modified more than a day before the
/// window are skipped unread: a photo cannot be saved before it was taken.
List<GalleryItem> scanFolder(String folder, DateTime fromUtc, DateTime toUtc) {
  final earliestModified = fromUtc.subtract(const Duration(days: 1));
  final items = <GalleryItem>[];
  var reads = 0;
  final pending = <(Directory, int)>[(Directory(folder), 0)];
  while (pending.isNotEmpty && reads < _maxReads) {
    final (dir, depth) = pending.removeLast();
    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } on FileSystemException {
      continue;
    }
    for (final entry in entries) {
      if (entry is Directory) {
        if (depth < _maxDepth) pending.add((entry, depth + 1));
        continue;
      }
      if (entry is! File) continue;
      if (!_extensions.contains(p.extension(entry.path).toLowerCase())) {
        continue;
      }
      final FileStat stat;
      try {
        stat = entry.statSync();
      } on FileSystemException {
        continue;
      }
      final modifiedUtc = stat.modified.toUtc();
      if (modifiedUtc.isBefore(earliestModified)) continue;
      if (reads >= _maxReads) break;
      reads++;
      final taken = exifTakenUtc(entry) ?? modifiedUtc;
      if (taken.isBefore(fromUtc) || taken.isAfter(toUtc)) continue;
      items.add(
        GalleryItem(
          id: entry.path,
          takenUtc: taken,
          name: p.basename(entry.path),
          bytes: stat.size,
          path: entry.path,
        ),
      );
    }
  }
  items.sort((a, b) => a.takenUtc.compareTo(b.takenUtc));
  return items;
}
