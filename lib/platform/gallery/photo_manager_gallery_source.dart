import 'dart:io';
import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

import 'gallery_source.dart';

/// The Android and iOS photo library through `photo_manager` (ADR-035)
/// [P1-15, FR-PHO-05].
///
/// Unverified on devices (MT-24). Only images are listed. On iOS the file
/// is the system's JPEG rendition, so HEIC photos can be imported; on
/// Android a HEIC original is skipped because `processPhoto` cannot decode
/// it.
class PhotoManagerGallerySource implements GallerySource {
  PhotoManagerGallerySource({this.maxItems = 500});

  /// Caps one listing so a long window never loads a whole camera roll.
  final int maxItems;

  static const _pageSize = 100;
  static const _readable = {'.jpg', '.jpeg', '.png'};

  final _assets = <String, AssetEntity>{};

  @override
  bool get choosesFolder => false;

  @override
  Future<GalleryAccess> open() async {
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.image,
          mediaLocation: false,
        ),
      ),
    );
    return switch (state) {
      PermissionState.authorized => GalleryAccess.full,
      PermissionState.limited => GalleryAccess.limited,
      _ => GalleryAccess.denied,
    };
  }

  @override
  Future<List<GalleryItem>> photosBetween(
    DateTime fromUtc,
    DateTime toUtc,
  ) async {
    final filter = FilterOptionGroup(
      createTimeCond: DateTimeCond(min: fromUtc, max: toUtc),
      orders: const [OrderOption(type: OrderOptionType.createDate, asc: true)],
    );
    final count = await PhotoManager.getAssetCount(
      filterOption: filter,
      type: RequestType.image,
    );
    final total = count < maxItems ? count : maxItems;
    _assets.clear();
    final items = <GalleryItem>[];
    for (var start = 0; start < total; start += _pageSize) {
      final end = start + _pageSize < total ? start + _pageSize : total;
      final page = await PhotoManager.getAssetListRange(
        start: start,
        end: end,
        filterOption: filter,
        type: RequestType.image,
      );
      for (final asset in page) {
        _assets[asset.id] = asset;
        items.add(
          GalleryItem(
            id: asset.id,
            takenUtc: asset.createDateTime.toUtc(),
            name: asset.title,
            width: asset.orientatedWidth,
            height: asset.orientatedHeight,
          ),
        );
      }
    }
    return items;
  }

  @override
  Future<Uint8List?> thumbnail(GalleryItem item, {int size = 200}) async =>
      _assets[item.id]?.thumbnailDataWithSize(ThumbnailSize.square(size));

  @override
  Future<File?> fileFor(GalleryItem item) async {
    final asset = _assets[item.id];
    if (asset == null) return null;
    final file = await asset.file;
    if (file == null) return null;
    final dot = file.path.lastIndexOf('.');
    final ext = dot < 0 ? '' : file.path.substring(dot).toLowerCase();
    return _readable.contains(ext) ? file : null;
  }

  @override
  Future<void> openSettings() => PhotoManager.openSetting();
}
