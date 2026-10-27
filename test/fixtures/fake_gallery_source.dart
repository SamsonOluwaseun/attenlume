import 'dart:io';
import 'dart:typed_data';

import 'package:attenlume/platform/gallery/gallery_source.dart';

/// A [GallerySource] for tests [P1-15].
///
/// [photosBetween] filters [items] by time, as the platform query would.
/// [fileFor] returns [files] for an item's ID, or null when there is none.
class FakeGallerySource implements GallerySource {
  FakeGallerySource({this.items = const [], this.access = GalleryAccess.full});

  List<GalleryItem> items;
  GalleryAccess access;
  final Map<String, File> files = {};
  int opens = 0;
  int settingsOpened = 0;
  final List<(DateTime, DateTime)> queries = [];

  @override
  bool choosesFolder = false;

  @override
  Future<GalleryAccess> open() async {
    opens++;
    return access;
  }

  @override
  Future<List<GalleryItem>> photosBetween(
    DateTime fromUtc,
    DateTime toUtc,
  ) async {
    queries.add((fromUtc, toUtc));
    return [
      for (final i in items)
        if (!i.takenUtc.isBefore(fromUtc) && !i.takenUtc.isAfter(toUtc)) i,
    ]..sort((a, b) => a.takenUtc.compareTo(b.takenUtc));
  }

  @override
  Future<Uint8List?> thumbnail(GalleryItem item, {int size = 200}) async =>
      null;

  @override
  Future<File?> fileFor(GalleryItem item) async => files[item.id];

  @override
  Future<void> openSettings() async => settingsOpened++;
}
