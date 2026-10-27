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
    this._process = processPhoto,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final PhotoCamera _camera;
  final ActivityRepository _activities;
  final MediaAssetRepository _media;
  final Future<Directory> Function() _mediaRoot;
  final InterruptionCoordinator? _interruptions;
  final DateTime Function() _clock;
  final PhotoProcess _process;
  final PhotoQuality quality;

  PhotoCamera get camera => _camera;

  Future<T> _cameraUse<T>(Future<T> Function() action) {
    final interruptions = _interruptions;
    return interruptions == null
        ? action()
        : interruptions.duringCameraUse(action);
  }

  /// Opens the camera if it is not open yet.
  Future<void> open() async {
    if (_camera.isOpen) return;
    await _cameraUse(_camera.open);
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

    final processed = await _process(
      photo: file,
      thumbnail: MediaPaths.resolve(root, thumbPath),
      quality: quality,
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
      originalKept: quality.keepOriginal,
    );
  }

  /// Releases the camera.
  Future<void> close() => _camera.close();
}
