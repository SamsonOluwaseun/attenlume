import 'dart:io';

import '../../data/filesystem/media_paths.dart';
import '../../data/filesystem/photo_processor.dart';
import '../../data/repositories/activity_repository.dart';
import '../../data/repositories/media_asset_repository.dart';
import '../../data/repositories/repository_support.dart' show uuidV4;
import '../../platform/camera/photo_camera.dart';
import '../models/enums.dart';
import '../models/media.dart';
import 'interruption_coordinator.dart';

typedef PhotoProcess = Future<ProcessedPhoto> Function({
  required File photo,
  required File thumbnail,
  PhotoQuality quality,
});

/// In-app photos for an activity (FR-PHO-01 to 04, FR-UI-03) [P1-14].
///
/// Opening the camera and each shot run inside
/// [InterruptionCoordinator.duringCameraUse], so an audio interruption the
/// camera causes is logged as `camera` and recording resumes (FR-PHO-07).
/// Photos go only to the app library, never the camera roll (FR-PHO-04).
class PhotoCaptureService {
  PhotoCaptureService({
    required this._camera,
    required this._activities,
    required this._media,
    required this._mediaRoot,
    this._interruptions,
    DateTime Function()? clock,
    this.quality = const PhotoQuality(),
    this._qualitySource,
    this._process = processPhoto,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final PhotoCamera _camera;
  final ActivityRepository _activities;
  final MediaAssetRepository _media;
  final Future<Directory> Function() _mediaRoot;
  final InterruptionCoordinator? _interruptions;
  final DateTime Function() _clock;
  final PhotoProcess _process;

  /// Used when no quality source is given.
  final PhotoQuality quality;

  /// Reads the quality chosen in Settings before each photo, so a change
  /// applies to the next shot or import (FR-PHO-02, 5.11, ADR-048).
  final Future<PhotoQuality> Function()? _qualitySource;

  Future<PhotoQuality> _currentQuality() async {
    final source = _qualitySource;
    if (source == null) return quality;
    try {
      return await source();
    } on Object {
      // A settings read that fails must not lose the shot.
      return quality;
    }
  }

  PhotoCamera get camera => _camera;

  /// The camera chosen with [switchCamera], reopened by [open] for the
  /// rest of the app run. Null means the platform default (back camera).
  CameraLens? _preferred;

  /// Cameras the device reports, for showing a switch button.
  Future<List<CameraLens>> cameras() => _camera.listCameras();

  Future<T> _cameraUse<T>(Future<T> Function() action) {
    final interruptions = _interruptions;
    return interruptions == null
        ? action()
        : interruptions.duringCameraUse(action);
  }

  /// Opens the camera if it is not open yet.
  Future<void> open() async {
    if (_camera.isOpen) return;
    await _cameraUse(() => _camera.open(lens: _preferred));
  }

  /// Opens the next camera: back to front and on through any external
  /// cameras, then round again. Returns the camera now open.
  ///
  /// Call only when no shot is in progress. If the next camera will not
  /// open, the previous one is reopened and the error is rethrown.
  Future<CameraLens?> switchCamera() async {
    final lenses = await _camera.listCameras();
    final current = _camera.lens;
    if (lenses.length < 2) return current;
    final at = lenses.indexWhere((l) => l.id == current?.id);
    final next = lenses[(at + 1) % lenses.length];
    await _camera.close();
    try {
      await _cameraUse(() => _camera.open(lens: next));
    } on Object {
      await _cameraUse(() => _camera.open(lens: current));
      rethrow;
    }
    _preferred = _camera.lens;
    return _preferred;
  }

  /// Takes one photo for [activityId], compresses it, writes its thumbnail
  /// and stores the row with its recording offset.
  ///
  /// [onShutterReady] runs as soon as the camera has the shot, before
  /// compression, so the next photo can be taken straight away (FR-UI-03).
  Future<Photo> capture(
    String activityId, {
    void Function()? onShutterReady,
  }) async {
    final activity = await _activities.get(activityId);
    if (activity == null) throw StateError('Activity $activityId not found');
    await open();

    final photoId = uuidV4();
    final root = await _mediaRoot();
    final photoPath = MediaPaths.photo(
      activity.conferenceId,
      activityId,
      photoId,
    );
    final thumbPath = MediaPaths.thumbnail(
      activity.conferenceId,
      activityId,
      photoId,
    );
    final file = MediaPaths.resolve(root, photoPath);
    await file.parent.create(recursive: true);

    final takenUtc = _clock();
    try {
      await _cameraUse(() => _camera.takePhoto(file.path));
    } finally {
      onShutterReady?.call();
    }

    final chosen = await _currentQuality();
    final processed = await _process(
      photo: file,
      thumbnail: MediaPaths.resolve(root, thumbPath),
      quality: chosen,
    );
    return _media.addPhoto(
      id: photoId,
      activityId: activityId,
      filePath: photoPath,
      thumbnailPath: processed.thumbnailWritten ? thumbPath : null,
      takenUtc: takenUtc,
      source: PhotoSource.inApp,
      width: processed.width,
      height: processed.height,
      bytes: processed.bytes,
      sha256: processed.sha256,
      originalKept: chosen.keepOriginal,
    );
  }

  /// Imports image files the user picked into [activityId], with an
  /// optional [label] for all of them (FR-PHO-06) [P1-14].
  ///
  /// Each file is copied, never moved, then compressed and thumbnailed
  /// like a camera shot. Its time is the file's last-modified time, so
  /// the offset lines up when the photo was taken during the recording.
  /// Returns the saved photos; a file that cannot be read is skipped.
  Future<List<Photo>> importFiles(
    String activityId,
    List<String> paths, {
    String? label,
  }) async {
    final saved = <Photo>[];
    for (final source in paths) {
      final photo = await importFile(activityId, source, label: label);
      if (photo != null) saved.add(photo);
    }
    return saved;
  }

  /// Imports one image file into [activityId] (FR-PHO-05, FR-PHO-06).
  ///
  /// The file at [sourcePath] is copied, never moved or changed, then
  /// compressed and thumbnailed like a camera shot. [takenUtc] defaults to
  /// the file's last-modified time. Returns null when the file cannot be
  /// read; nothing is left behind in the library.
  Future<Photo?> importFile(
    String activityId,
    String sourcePath, {
    DateTime? takenUtc,
    PhotoSource source = PhotoSource.manualImport,
    String? label,
  }) async {
    final activity = await _activities.get(activityId);
    if (activity == null) throw StateError('Activity $activityId not found');
    final root = await _mediaRoot();
    final photoId = uuidV4();
    final photoPath = MediaPaths.photo(
      activity.conferenceId,
      activityId,
      photoId,
    );
    final thumbPath = MediaPaths.thumbnail(
      activity.conferenceId,
      activityId,
      photoId,
    );
    final file = MediaPaths.resolve(root, photoPath);
    try {
      await file.parent.create(recursive: true);
      final original = File(sourcePath);
      final taken = (takenUtc ?? original.lastModifiedSync()).toUtc();
      await original.copy(file.path);
      final chosen = await _currentQuality();
      final processed = await _process(
        photo: file,
        thumbnail: MediaPaths.resolve(root, thumbPath),
        quality: chosen,
      );
      return await _media.addPhoto(
        id: photoId,
        activityId: activityId,
        filePath: photoPath,
        thumbnailPath: processed.thumbnailWritten ? thumbPath : null,
        takenUtc: taken,
        source: source,
        label: label,
        width: processed.width,
        height: processed.height,
        bytes: processed.bytes,
        sha256: processed.sha256,
        originalKept: chosen.keepOriginal,
      );
    } on FileSystemException {
      if (file.existsSync()) await file.delete();
      return null;
    }
  }

  /// Releases the camera.
  Future<void> close() => _camera.close();
}
