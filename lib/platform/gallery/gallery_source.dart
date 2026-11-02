import 'dart:io';
import 'dart:typed_data';

/// What the user let Attenlume see of their photos (FR-PHO-05, FR-PRI-04).
enum GalleryAccess {
  /// Every photo.
  full,

  /// Only the photos the user selected (iOS limited library, Android 14+
  /// partial media access). The list shows only those.
  limited,

  /// Access refused or restricted.
  denied,

  /// The user closed the folder picker (Windows) or photo picker without choosing.
  cancelled,
}

/// One photo the gallery offers for import [P1-15, P1-58].
class GalleryItem {
  const GalleryItem({
    required this.id,
    required this.takenUtc,
    this.name,
    this.bytes,
    this.width,
    this.height,
    this.path,
    this.hasExifTime = true,
  });

  /// Stable within one listing: the asset ID on phones, the file path on
  /// Windows, or the cached copy path for the Android photo picker.
  final String id;
  final DateTime takenUtc;
  final String? name;

  /// File size when the platform can tell without reading the file.
  final int? bytes;
  final int? width;
  final int? height;

  /// Local file path when the photo is a plain file (Windows folders, Android
  /// photo picker cached copy).
  /// iOS leaves it null and gives a [GallerySource.thumbnail] instead.
  final String? path;

  /// False when the photo has no EXIF DateTimeOriginal (FR-PHO-05, P1-58).
  final bool hasExifTime;

  GalleryItem copyWith({
    String? id,
    DateTime? takenUtc,
    String? name,
    int? bytes,
    int? width,
    int? height,
    String? path,
    bool? hasExifTime,
  }) => GalleryItem(
    id: id ?? this.id,
    takenUtc: takenUtc ?? this.takenUtc,
    name: name ?? this.name,
    bytes: bytes ?? this.bytes,
    width: width ?? this.width,
    height: height ?? this.height,
    path: path ?? this.path,
    hasExifTime: hasExifTime ?? this.hasExifTime,
  );
}

/// The camera roll, photo picker or photo folder, behind an interface so
/// platform code can change after device testing (AGENTS.md) [P1-15, P1-58, FR-PHO-05].
abstract interface class GallerySource {
  /// True when the user has to choose a folder first (Windows has no
  /// photo library API, PLATFORM_FEASIBILITY 2.8).
  bool get choosesFolder;

  /// Asks for photo access on phones, opens the picker on Android, or asks
  /// for a folder on Windows. Only called when the user starts an import (FR-PRI-04).
  Future<GalleryAccess> open();

  /// Photos taken between [fromUtc] and [toUtc], inclusive, oldest first.
  /// On Android, returns all picked photos so the user can review them (P1-58).
  Future<List<GalleryItem>> photosBetween(DateTime fromUtc, DateTime toUtc);

  /// A small JPEG or PNG preview, or null when [GalleryItem.path] should
  /// be shown instead.
  Future<Uint8List?> thumbnail(GalleryItem item, {int size = 200});

  /// A JPEG or PNG file of [item] to copy into the library, or null when it
  /// cannot be read. The returned file is never moved or changed.
  Future<File?> fileFor(GalleryItem item);

  /// Opens the system settings so the user can change photo access.
  Future<void> openSettings();

  /// Cleans up any cached temporary files from import or cancel (P1-58).
  Future<void> cleanUp();
}
