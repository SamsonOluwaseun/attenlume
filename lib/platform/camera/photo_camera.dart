import 'dart:io';

import 'package:flutter/widgets.dart';

/// Still photo capture for the recording screen (BUILD_GUIDE 5.6)
/// [P0-05, FR-PHO-01, FR-PHO-07].
///
/// Photos only: implementations never open a microphone, so the camera
/// does not compete with the recorder for audio. Kept behind an interface
/// so the platform code can change after device testing (AGENTS.md).
abstract interface class PhotoCamera {
  /// Cameras the platform reports. Empty when there are none.
  Future<List<CameraLens>> listCameras();

  /// Opens [lens], or the first back camera, or the first camera. Throws
  /// [CameraUnavailableException] when there is no camera to open, and
  /// [CameraAccessDeniedException] when the user or the OS blocks it.
  Future<void> open({CameraLens? lens});

  bool get isOpen;

  /// The live viewfinder for the open camera [P1-14]. An empty box when
  /// the camera is not open.
  Widget buildPreview();

  /// Takes one photo and stores it at [path]. The camera stays open for
  /// the next shot (FR-UI-03).
  Future<CapturedPhoto> takePhoto(String path);

  /// Releases the camera. Safe to call when not open.
  Future<void> close();
}

enum CameraFacing { back, front, external }

class CameraLens {
  const CameraLens({required this.id, required this.facing});

  final String id;
  final CameraFacing facing;

  Map<String, Object?> toJson() => {'id': id, 'facing': facing.name};

  @override
  bool operator ==(Object other) =>
      other is CameraLens && other.id == id && other.facing == facing;

  @override
  int get hashCode => Object.hash(id, facing);
}

class CapturedPhoto {
  const CapturedPhoto({required this.path, required this.bytes});

  final String path;
  final int bytes;
}

class CameraUnavailableException implements Exception {
  const CameraUnavailableException(this.message);

  final String message;

  @override
  String toString() => 'CameraUnavailableException: $message';
}

/// Camera access was refused by the user or blocked by the OS
/// (FR-PRI-04) [P1-14].
class CameraAccessDeniedException implements Exception {
  const CameraAccessDeniedException();

  @override
  String toString() => 'CameraAccessDeniedException';
}

/// Moves a photo the platform wrote to [from] into [to].
///
/// Renames when it can. Across volumes it copies, checks the size, and
/// only then removes the plugin's temporary file, so a failed copy never
/// loses the photo. Refuses to overwrite an existing file.
Future<File> moveCapturedFile(String from, String to) async {
  final source = File(from);
  final target = File(to);
  if (target.existsSync()) {
    throw FileSystemException('Photo already exists', to);
  }
  await target.parent.create(recursive: true);
  try {
    return await source.rename(to);
  } on FileSystemException {
    final copy = await source.copy(to);
    if (await copy.length() != await source.length()) {
      throw FileSystemException('Photo copy is incomplete', to);
    }
    await source.delete();
    return copy;
  }
}
