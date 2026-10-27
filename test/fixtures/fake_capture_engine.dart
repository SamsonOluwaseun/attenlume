import 'dart:async';
import 'dart:io';

import 'package:attenlume/platform/audio_capture/audio_capture_engine.dart';

import 'm4a_builder.dart';

/// An [AudioCaptureEngine] for tests [P1-04].
///
/// [start] creates an empty file, as an encoder would. [stop] writes a
/// small valid M4A of [durationSeconds], or leaves the file without a
/// `moov` box when [finaliseValidFile] is false (a cut-off recording).
class FakeCaptureEngine implements AudioCaptureEngine {
  bool permission = true;
  Object? startError;
  bool finaliseValidFile = true;
  int durationSeconds = 3;

  /// When set, [start] waits for it, so tests can overlap commands.
  Completer<void>? startGate;

  /// Called at the top of [start], before any file exists.
  Future<void> Function(String path)? onStart;

  final List<String> startedPaths = [];
  final List<CaptureRequest> requests = [];
  int stopCalls = 0;
  bool disposed = false;
  String? _path;

  bool get isCapturing => _path != null;

  @override
  Future<List<CaptureInput>> listInputs() async => const [];

  @override
  Future<bool> supportsAacLc() async => true;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<void> start(CaptureRequest request, String path) async {
    await onStart?.call(path);
    if (startGate != null) await startGate!.future;
    if (startError != null) throw startError!;
    if (_path != null) throw StateError('Fake engine already capturing');
    startedPaths.add(path);
    requests.add(request);
    await File(path).writeAsBytes(const []);
    _path = path;
  }

  @override
  Future<double> levelDbfs() async => -30;

  @override
  Future<String?> stop() async {
    stopCalls++;
    final path = _path;
    _path = null;
    if (path == null) return null;
    await File(path).writeAsBytes(
      buildM4a(
        includeMoov: finaliseValidFile,
        durationUnits: 48000 * durationSeconds,
        mediaDataBytes: durationSeconds * 6000,
      ),
    );
    return path;
  }

  @override
  Future<void> dispose() async => disposed = true;
}
