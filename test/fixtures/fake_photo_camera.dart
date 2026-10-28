import 'dart:io';

import 'package:attenlume/platform/camera/photo_camera.dart';
import 'package:flutter/widgets.dart';

/// A [PhotoCamera] for tests [P0-05].
///
/// [takePhoto] writes [photoBytes] bytes to the path, as the plugin would
/// after moving its temporary file.
class FakePhotoCamera implements PhotoCamera {
  List<CameraLens> lenses = const [
    CameraLens(id: 'back-0', facing: CameraFacing.back),
  ];
  Object? openError;

  /// When it returns an error for a shot number (1-based), that shot
  /// throws it.
  Object? Function(int shot) shotError = (_) => null;

  /// Called inside [takePhoto], before the file exists, with the shot
  /// number. Lets a test make the camera disturb the audio session.
  Future<void> Function(int shot)? onShot;
  int photoBytes = 1024;

  /// When set, each shot writes these bytes (for example a real JPEG)
  /// instead of [photoBytes] filler bytes.
  List<int>? photoData;

  /// When it returns an error for a lens, opening that lens throws it.
  Object? Function(CameraLens lens) lensError = (_) => null;

  /// When set, [open] waits for it before the camera is open.
  Future<void>? openGate;

  final List<String> paths = [];

  /// Every lens opened, in order.
  final List<CameraLens> opened = [];
  int shots = 0;
  bool closed = false;
  bool _open = false;
  CameraLens? _lens;

  @override
  bool get isOpen => _open;

  @override
  CameraLens? get lens => _open ? _lens : null;

  @override
  Future<List<CameraLens>> listCameras() async => lenses;

  /// Chooses like the plugin: the asked-for lens, else the first back
  /// camera, else the first camera.
  @override
  Future<void> open({CameraLens? lens}) async {
    if (openError != null) throw openError!;
    if (lenses.isEmpty) {
      throw const CameraUnavailableException('No camera found.');
    }
    final chosen =
        lenses.where((l) => l.id == lens?.id).firstOrNull ??
        lenses.where((l) => l.facing == CameraFacing.back).firstOrNull ??
        lenses.first;
    final error = lensError(chosen);
    if (error != null) throw error;
    await openGate;
    opened.add(chosen);
    _lens = chosen;
    _open = true;
  }

  @override
  Future<CapturedPhoto> takePhoto(String path) async {
    if (!_open) throw StateError('Camera is not open');
    final n = ++shots;
    await onShot?.call(n);
    final error = shotError(n);
    if (error != null) throw error;
    final file = File(path);
    await file.parent.create(recursive: true);
    final data = photoData ?? List<int>.filled(photoBytes, 0xff);
    await file.writeAsBytes(data);
    paths.add(path);
    return CapturedPhoto(path: path, bytes: data.length);
  }

  @override
  Widget buildPreview() => _open
      ? const SizedBox.expand(key: Key('fake-camera-preview'))
      : const SizedBox.shrink();

  @override
  Future<void> close() async {
    _open = false;
    _lens = null;
    closed = true;
  }
}
