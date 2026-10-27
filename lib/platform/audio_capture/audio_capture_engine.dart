/// Platform-neutral microphone capture (BUILD_GUIDE 9.3, ADR-002) [P0-06].
///
/// One engine records one file at a time. Rolling to a new segment is
/// stop then start with a new path, never a change to a running encoder
/// (FR-QUAL-04).
abstract interface class AudioCaptureEngine {
  /// Input devices the platform reports. May be empty when it reports none.
  Future<List<CaptureInput>> listInputs();

  /// Whether the platform has an AAC-LC encoder.
  Future<bool> supportsAacLc();

  /// Whether the app may use the microphone. Windows always answers true,
  /// because the plugin has no permission check there (ADR-002).
  Future<bool> hasPermission();

  /// Starts writing AAC-LC to [path]. Throws if capture cannot start.
  Future<void> start(CaptureRequest request, String path);

  /// Current input level in dBFS, for the level meter and silence checks.
  Future<double> levelDbfs();

  /// Stops and finalises the file. Returns its path, or null if nothing
  /// was written.
  Future<String?> stop();

  Future<void> dispose();
}

/// A microphone the platform reports.
class CaptureInput {
  const CaptureInput({required this.id, required this.label});

  final String id;
  final String label;

  Map<String, Object?> toJson() => {'id': id, 'label': label};
}

/// What the app asks the encoder for. The platform may deliver something
/// else, so the file is inspected after finalisation (FR-QUAL-01).
class CaptureRequest {
  const CaptureRequest({
    required this.bitrateBps,
    required this.sampleRateHz,
    this.channelCount = 1,
    this.inputId,
  });

  final int bitrateBps;
  final int sampleRateHz;
  final int channelCount;

  /// Null means the system default input.
  final String? inputId;

  Map<String, Object?> toJson() => {
    'bitrate_bps': bitrateBps,
    'sample_rate_hz': sampleRateHz,
    'channel_count': channelCount,
    'input_id': inputId,
  };
}
