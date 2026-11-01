import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import '../../shared/utilities/serial_lock.dart';
import 'photo_camera.dart' as ours;

/// [ours.PhotoCamera] on the `camera` plugin: CameraX on Android,
/// AVFoundation on iOS, `camera_windows` (Media Foundation) on Windows
/// [P0-05, FR-PHO-01, FR-PHO-07].
///
/// Opened with `enableAudio: false`. In `camera_avfoundation` 0.10.3+1
/// that skips the only code that changes the shared `AVAudioSession`
/// category, and the capture sessions are created with
/// `automaticallyConfiguresApplicationAudioSession = false`. Whether the
/// recording really carries on is what P0-05 measures on devices.
class PluginPhotoCamera implements ours.PhotoCamera, ours.PhotoCameraZoom {
  PluginPhotoCamera({this.resolution = ResolutionPreset.veryHigh});

  /// `veryHigh` is 1920 by 1080 on most devices, close to the 1600 to
  /// 2048 px long edge of FR-PHO-02. Compression is P1-14.
  final ResolutionPreset resolution;

  final _lock = SerialLock();
  CameraController? _controller;
  ours.CameraZoomRange? _zoomRange;
  double _zoomLevel = 1;
  double? _pendingZoom;
  Future<void>? _zoomJob;

  @override
  ours.CameraZoomRange? get zoomRange => _zoomRange;
  @override
  double get zoomLevel => _zoomLevel;

  @override
  Future<void> setZoomLevel(double level) {
    final range = _zoomRange;
    if (range == null || !isOpen || !level.isFinite) return Future.value();
    _pendingZoom = range.clamp(level);
    return _zoomJob ??= _drainZoom().whenComplete(() async {
      _zoomJob = null;
      // A request may arrive after the drain loop finishes but before this
      // completion callback. Do not strand it behind a completed job.
      final pending = _pendingZoom;
      if (pending != null) await setZoomLevel(pending);
    });
  }

  Future<void> _drainZoom() => _lock.run(() async {
    while (_pendingZoom != null) {
      await _applyPendingZoomLocked();
    }
  });

  Future<void> _applyPendingZoomLocked() async {
    final requested = _pendingZoom;
    _pendingZoom = null;
    final controller = _controller;
    final range = _zoomRange;
    if (requested == null || controller == null || range == null) return;
    try {
      final level = range.clamp(requested);
      await controller.setZoomLevel(level);
      _zoomLevel = level;
    } on Object {
      // Some Windows cameras report limits but reject setting zoom.
      // Zoom failure must not disable the viewfinder or photo capture.
      _zoomRange = null;
      _pendingZoom = null;
    }
  }

  List<CameraDescription>? _cameras;
  ours.CameraLens? _openLens;

  @override
  bool get isOpen => _controller?.value.isInitialized ?? false;

  @override
  ours.CameraLens? get lens => isOpen ? _openLens : null;

  Future<List<CameraDescription>> _descriptions() async =>
      _cameras ??= await availableCameras();

  @override
  Future<List<ours.CameraLens>> listCameras() async => [
    for (final c in await _descriptions()) _lens(c),
  ];

  @override
  Future<void> open({ours.CameraLens? lens}) =>
      _lock.run(() => _openLocked(lens: lens));

  Future<void> _openLocked({ours.CameraLens? lens}) async {
    if (isOpen) return;
    final cameras = await _descriptions();
    if (cameras.isEmpty) {
      throw const ours.CameraUnavailableException('No camera found.');
    }
    final chosen =
        _find(cameras, (c) => lens != null && c.name == lens.id) ??
        _find(cameras, (c) => c.lensDirection == CameraLensDirection.back) ??
        cameras.first;
    final controller = CameraController(
      chosen,
      resolution,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await controller.initialize();
    } on CameraException catch (e) {
      await controller.dispose();
      // CameraAccessDenied, CameraAccessDeniedWithoutPrompt and
      // CameraAccessRestricted on Android, iOS and Windows.
      if (e.code.startsWith('CameraAccess')) {
        throw const ours.CameraAccessDeniedException();
      }
      rethrow;
    } on Object {
      await controller.dispose();
      rethrow;
    }
    _controller = controller;
    _openLens = _lens(chosen);
    _zoomRange = null;
    _zoomLevel = 1;
    try {
      final min = await controller.getMinZoomLevel();
      final max = await controller.getMaxZoomLevel();
      final range = ours.CameraZoomRange(min, max);
      if (range.isUsable) {
        final initial = range.clamp(1);
        await controller.setZoomLevel(initial);
        _zoomLevel = initial;
        _zoomRange = range;
      }
    } on Object {
      // Optional capability: unsupported/invalid queries keep capture available.
    }
  }

  @override
  Widget buildPreview() {
    final controller = _controller;
    if (controller == null || !isOpen) return const SizedBox.shrink();
    return CameraPreview(controller);
  }

  @override
  Future<ours.CapturedPhoto> takePhoto(String path) =>
      _lock.run(() => _takePhotoLocked(path));

  Future<ours.CapturedPhoto> _takePhotoLocked(String path) async {
    // The shutter must use the latest requested zoom, including a request
    // arriving in the zoom drain's completion microtask gap.
    await _applyPendingZoomLocked();
    final controller = _controller;
    if (controller == null || !isOpen) {
      throw StateError('Camera is not open');
    }
    final shot = await controller.takePicture();
    final file = await ours.moveCapturedFile(shot.path, path);
    return ours.CapturedPhoto(path: file.path, bytes: await file.length());
  }

  @override
  Future<void> close() => _lock.run(_closeLocked);

  Future<void> _closeLocked() async {
    _pendingZoom = null;
    _zoomRange = null;
    _zoomLevel = 1;
    final controller = _controller;
    _controller = null;
    _openLens = null;
    await controller?.dispose();
  }

  static CameraDescription? _find(
    List<CameraDescription> cameras,
    bool Function(CameraDescription) test,
  ) {
    for (final c in cameras) {
      if (test(c)) return c;
    }
    return null;
  }

  static ours.CameraLens _lens(CameraDescription c) => ours.CameraLens(
    id: c.name,
    facing: switch (c.lensDirection) {
      CameraLensDirection.back => ours.CameraFacing.back,
      CameraLensDirection.front => ours.CameraFacing.front,
      CameraLensDirection.external => ours.CameraFacing.external,
    },
  );
}
