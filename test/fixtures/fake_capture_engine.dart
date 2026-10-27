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

  /// What [levelDbfs] reports. Set very low to act as a muted mic.
  double level = -30;

  /// Audio bitrate the finished file holds for a request. The default
  /// ignores the request, as a fixed-rate encoder would.
  int Function(CaptureRequest request) deliveredBitrateBps = (_) => 48000;

  /// When it returns an error for a request, [start] throws it, as an
  /// encoder refusing that setting would.
  Object? Function(CaptureRequest request) refuse = (_) => null;

  /// When set, [start] waits for it, so tests can overlap commands.
  Completer<void>? startGate;

  /// Called at the top of [start], before any file exists.
  Future<void> Function(String path)? onStart;

  final List<String> startedPaths = [];
  final List<CaptureRequest> requests = [];
  int stopCalls = 0;
  bool disposed = false;
  String? _path;
  CaptureRequest? _request;

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
    final refusal = refuse(request);
    if (refusal != null) throw refusal;
    if (_path != null) throw StateError('Fake engine already capturing');
    startedPaths.add(path);
    requests.add(request);
    await File(path).writeAsBytes(const []);
    _path = path;
    _request = request;
  }

  @override
  Future<double> levelDbfs() async => level;

  @override
  Future<String?> stop() async {
    stopCalls++;
    final path = _path;
    _path = null;
    if (path == null) return null;
    final delivered = deliveredBitrateBps(_request!);
    await File(path).writeAsBytes(
      buildM4a(
        includeMoov: finaliseValidFile,
        durationUnits: 48000 * durationSeconds,
        avgBitrateBps: delivered,
        maxBitrateBps: delivered,
        mediaDataBytes: delivered ~/ 8 * durationSeconds,
      ),
    );
    return path;
  }

  @override
  Future<void> dispose() async => disposed = true;
}
