import '../../data/repositories/activity_repository.dart';
import '../../data/repositories/media_asset_repository.dart';
import '../../platform/gallery/gallery_source.dart';
import '../models/enums.dart';
import '../models/media.dart';
import 'photo_capture_service.dart';

/// The span of time whose photos belong to an activity (FR-PHO-05).
class ImportWindow {
  const ImportWindow({
    required this.startUtc,
    required this.endUtc,
    required this.margin,
  });

  /// When the activity started and ended, before the margin.
  final DateTime startUtc;
  final DateTime endUtc;
  final Duration margin;

  DateTime get fromUtc => startUtc.subtract(margin);
  DateTime get toUtc => endUtc.add(margin);
}

/// One gallery photo offered for import, with its warnings.
class GalleryCandidate {
  const GalleryCandidate({
    required this.item,
    required this.duplicate,
    required this.large,
  });

  final GalleryItem item;

  /// An imported photo in this activity already has the same time.
  final bool duplicate;

  /// Bigger than [GalleryImportService.largeBytes] or
  /// [GalleryImportService.largePixels].
  final bool large;

  /// Selected for import by default unless it is a duplicate.
  bool get selectedByDefault => !duplicate;
}

/// What a scan found.
class GalleryScan {
  const GalleryScan({
    required this.access,
    this.window,
    this.candidates = const [],
  });

  final GalleryAccess access;

  /// Null when the activity has never started.
  final ImportWindow? window;
  final List<GalleryCandidate> candidates;
}

/// The result of an import.
class GalleryImportResult {
  const GalleryImportResult({required this.saved, required this.skipped});

  final List<Photo> saved;

  /// Photos that could not be read (for example a HEIC original on
  /// Android, or a photo still in iCloud).
  final int skipped;
}

/// "Import photos taken during this activity" (FR-PHO-05) [P1-15].
///
/// Lists gallery photos taken between the activity's start and end with a
/// margin (default 2 minutes), flags likely duplicates and large files,
/// and imports only what the user confirms. Each photo is copied, never
/// moved, and compressed like a camera shot through
/// [PhotoCaptureService.importFile]; its time is the gallery's capture
/// time, so it lines up with the recording.
class GalleryImportService {
  GalleryImportService({
    required this._gallery,
    required this._activities,
    required this._media,
    required this._photos,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final GallerySource _gallery;
  final ActivityRepository _activities;
  final MediaAssetRepository _media;
  final PhotoCaptureService _photos;
  final DateTime Function() _clock;

  static const defaultMargin = Duration(minutes: 2);

  /// Files above this are flagged as large (FR-PHO-05).
  static const largeBytes = 15 * 1024 * 1024;

  /// Photos above this pixel count are flagged when the size is unknown.
  static const largePixels = 24000000;

  /// Two photos this close in time are taken to be the same photo.
  static const duplicateTolerance = Duration(seconds: 1);

  GallerySource get gallery => _gallery;

  /// The activity's window: its recorded span if it has segments,
  /// otherwise its actual start and end. An activity still running ends
  /// now. Null when it has never started.
  Future<ImportWindow?> windowFor(
    String activityId, {
    Duration margin = defaultMargin,
  }) async {
    final activity = await _activities.get(activityId);
    if (activity == null) throw StateError('Activity $activityId not found');
    final segments = await _media.segmentsFor(activityId);
    DateTime? start = activity.actualStart;
    DateTime? end = activity.actualEnd;
    for (final s in segments) {
      if (start == null || s.startUtc.isBefore(start)) start = s.startUtc;
      final segEnd = s.endUtc;
      if (segEnd != null && (end == null || segEnd.isAfter(end))) end = segEnd;
    }
    if (start == null) return null;
    final now = _clock();
    if (end == null || end.isBefore(start)) {
      end = now.isAfter(start) ? now : start;
    }
    return ImportWindow(
      startUtc: start.toUtc(),
      endUtc: end.toUtc(),
      margin: margin,
    );
  }

  /// Asks for access (or a folder on Windows), then lists the window's
  /// photos. Call only when the user starts an import (FR-PRI-04).
  Future<GalleryScan> scan(
    String activityId, {
    Duration margin = defaultMargin,
    bool reopen = true,
  }) async {
    final window = await windowFor(activityId, margin: margin);
    if (window == null) return const GalleryScan(access: GalleryAccess.full);
    final access = reopen ? await _gallery.open() : GalleryAccess.full;
    if (access == GalleryAccess.denied || access == GalleryAccess.cancelled) {
      return GalleryScan(access: access, window: window);
    }
    final items = await _gallery.photosBetween(window.fromUtc, window.toUtc);
    final existing = [
      for (final photo in await _media.photosFor(activityId))
        if (photo.source != PhotoSource.inApp) photo.takenUtc,
    ];
    return GalleryScan(
      access: access,
      window: window,
      candidates: [
        for (final item in items)
          GalleryCandidate(
            item: item,
            duplicate: existing.any(
              (t) => t.difference(item.takenUtc).abs() <= duplicateTolerance,
            ),
            large: isLarge(item),
          ),
      ],
    );
  }

  static bool isLarge(GalleryItem item) {
    final bytes = item.bytes;
    if (bytes != null) return bytes > largeBytes;
    final w = item.width;
    final h = item.height;
    return w != null && h != null && w * h > largePixels;
  }

  /// Imports [items] into [activityId] with an optional [label].
  Future<GalleryImportResult> importItems(
    String activityId,
    List<GalleryItem> items, {
    String? label,
  }) async {
    final saved = <Photo>[];
    var skipped = 0;
    for (final item in items) {
      final file = await _gallery.fileFor(item);
      final photo = file == null
          ? null
          : await _photos.importFile(
              activityId,
              file.path,
              takenUtc: item.takenUtc,
              source: PhotoSource.galleryImport,
              label: label,
            );
      if (photo == null) {
        skipped++;
      } else {
        saved.add(photo);
      }
    }
    return GalleryImportResult(saved: saved, skipped: skipped);
  }
}
