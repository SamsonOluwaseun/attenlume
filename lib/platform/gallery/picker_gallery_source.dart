import 'dart:io';

import 'package:flutter/services.dart';

import 'exif_reader.dart';
import 'gallery_source.dart';

/// The Android system photo picker (FR-PHO-05, ADR-074, P1-58).
///
/// Uses AndroidX Activity Result photo picker via method channel
/// `com.samlytics.attenlume/photo_picker`. Does not require or request
/// `READ_MEDIA_IMAGES` or any storage permissions.
/// Picked files are streamed byte-for-byte into the app cache; HEIC/HEIF
/// files are decoded and saved as high-quality JPEG on Android 9+ (API 28+)
/// with EXIF metadata preserved.
class PickerGallerySource implements GallerySource {
  PickerGallerySource({MethodChannel? channel, this.maxItems = 50})
    : _channel =
          channel ??
          const MethodChannel('com.samlytics.attenlume/photo_picker');

  final MethodChannel _channel;

  /// Maximum number of photos allowed in a single pick selection.
  final int maxItems;

  final List<GalleryItem> _items = [];

  List<GalleryItem> get items => List.unmodifiable(_items);

  @override
  bool get choosesFolder => false;

  @override
  Future<GalleryAccess> open() async {
    await cleanUp();
    final List<dynamic>? rawList;
    try {
      rawList = await _channel.invokeMethod<List<dynamic>>('pick', {
        'maxItems': maxItems,
      });
    } on PlatformException {
      return GalleryAccess.cancelled;
    }

    if (rawList == null || rawList.isEmpty) {
      return GalleryAccess.cancelled;
    }

    _items.clear();
    for (final raw in rawList) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final path = map['path'] as String?;
      if (path == null) continue;
      final file = File(path);

      // Prefer native EXIF timestamp from ExifInterface (supports HEIF/JPEG)
      // over Dart JPEG reader [P1-58 review item 1].
      final nativeIso = (map['takenIso'] as String?)?.trim();
      final nativeTaken = (nativeIso != null && nativeIso.isNotEmpty)
          ? DateTime.tryParse(nativeIso)?.toUtc()
          : null;
      final taken = nativeTaken ?? exifTakenUtc(file);

      final name = map['name'] as String? ?? file.uri.pathSegments.last;
      final bytes =
          (map['bytes'] as num?)?.toInt() ??
          (file.existsSync() ? file.lengthSync() : null);

      _items.add(
        GalleryItem(
          id: path,
          takenUtc:
              taken ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          hasExifTime: taken != null,
          name: name,
          bytes: bytes,
          path: path,
        ),
      );
    }

    if (_items.isEmpty) {
      return GalleryAccess.cancelled;
    }

    return GalleryAccess.full;
  }

  @override
  Future<List<GalleryItem>> photosBetween(
    DateTime fromUtc,
    DateTime toUtc,
  ) async {
    // Returns ALL picked photos, not only those inside the window,
    // so the sheet can show them and display any outside-session warnings
    // (FR-PHO-05, P1-58 requirement 2).
    final list = [
      for (final item in _items)
        if (!item.hasExifTime) item.copyWith(takenUtc: fromUtc) else item,
    ];
    list.sort((a, b) {
      if (a.hasExifTime && b.hasExifTime) {
        return a.takenUtc.compareTo(b.takenUtc);
      }
      if (a.hasExifTime) return -1;
      if (b.hasExifTime) return 1;
      return (a.name ?? '').compareTo(b.name ?? '');
    });
    return list;
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
  Future<void> cleanUp() async {
    for (final item in _items) {
      final path = item.path;
      if (path != null) {
        try {
          final file = File(path);
          if (file.existsSync()) {
            file.deleteSync();
          }
        } catch (_) {}
      }
    }
    _items.clear();
    try {
      await _channel.invokeMethod<void>('cleanUp');
    } catch (_) {}
  }
}
