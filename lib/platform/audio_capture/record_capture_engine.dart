import 'package:record/record.dart';

import 'audio_capture_engine.dart';

/// [AudioCaptureEngine] backed by the `record` package (ADR-002) [P0-06].
///
/// On Windows `record` uses Media Foundation and picks the supported AAC
/// bitrate closest to the request, so the request is not a promise.
class RecordCaptureEngine implements AudioCaptureEngine {
  RecordCaptureEngine([AudioRecorder? recorder])
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  List<InputDevice> _devices = const [];

  @override
  Future<List<CaptureInput>> listInputs() async {
    _devices = await _recorder.listInputDevices();
    return [
      for (final device in _devices)
        CaptureInput(id: device.id, label: device.label),
    ];
  }

  @override
  Future<bool> supportsAacLc() =>
      _recorder.isEncoderSupported(AudioEncoder.aacLc);

  /// Asks the user when permission has not been decided yet. On Android
  /// and iOS that shows the system prompt; on Windows it only checks.
  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start(CaptureRequest request, String path) async {
    InputDevice? device;
    if (request.inputId != null) {
      if (_devices.isEmpty) await listInputs();
      device = _devices.where((d) => d.id == request.inputId).firstOrNull;
    }
    await _recorder.start(
      RecordConfig(
        bitRate: request.bitrateBps,
        sampleRate: request.sampleRateHz,
        numChannels: request.channelCount,
        device: device,
        // The app's audio session owns audio focus and interruptions
        // (ADR-021). Left on, `record` asks Android for focus itself, takes
        // it from that session, and every recording looks interrupted at
        // once (ADR-043).
        audioInterruption: AudioInterruptionMode.none,
      ),
      path: path,
    );
  }

  @override
  Future<double> levelDbfs() async => (await _recorder.getAmplitude()).current;

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> dispose() => _recorder.dispose();
}
