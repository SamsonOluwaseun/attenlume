import 'package:camera/camera.dart';

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
class PluginPhotoCamera implements ours.PhotoCamera {
  PluginPhotoCamera({this.resolution = ResolutionPreset.veryHigh});

  /// `veryHigh` is 1920 by 1080 on most devices, close to the 1600 to
  /// 2048 px long edge of FR-PHO-02. Compression is P1-14.
  final ResolutionPreset resolution;

  CameraController? _controller;
  List<CameraDescription>? _cameras;

  @override
  bool get isOpen => _controller?.value.isInitialized ?? false;

  Future<List<CameraDescription>> _descriptions() async =>
      _cameras ??= await availableCameras();

  @override
  Future<List<ours.CameraLens>> listCameras() async => [
    for (final c in await _descriptions()) _lens(c),
  ];

  @override
  Future<void> open({ours.CameraLens? lens}) async {
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
    } on Object {
      await controller.dispose();
      rethrow;
    }
    _controller = controller;
  }

  @override
  Future<ours.CapturedPhoto> takePhoto(String path) async {
    final controller = _controller;
    if (controller == null || !isOpen) {
      throw StateError('Camera is not open');
    }
    final shot = await controller.takePicture();
    final file = await ours.moveCapturedFile(shot.path, path);
    return ours.CapturedPhoto(path: file.path, bytes: await file.length());
  }

  @override
  Future<void> close() async {
    final controller = _controller;
    _controller = null;
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
