/// Platform audio interruptions and route events (BUILD_GUIDE 10.5,
/// ARCHITECTURE 3) [P0-04, FR-REC-05].
///
/// The `InterruptionCoordinator` (P1-07) turns these into recording
/// commands. The P0-04 spike logs them. Kept behind an interface so the
/// platform code can change after device testing (AGENTS.md).
abstract interface class AudioInterruptionSource {
  /// Sets up the platform audio session for recording and asks for audio
  /// focus where the platform has it. Call while the app is visible.
  Future<void> activate();

  /// Gives audio focus back. Safe to call when not active.
  Future<void> deactivate();

  Stream<AudioInterruption> get events;
}

enum AudioInterruptionKind {
  /// Another app or the system (often a call) took the audio session.
  began,

  /// The interruption is over.
  ended,

  /// Headphones or a headset were unplugged.
  becomingNoisy,

  /// Audio devices were added or removed (for example Bluetooth).
  devicesChanged,
}

class AudioInterruption {
  const AudioInterruption(
    this.kind, {
    this.mayDuck = false,
    this.shouldResume = false,
    this.devicesAdded = const [],
    this.devicesRemoved = const [],
  });

  final AudioInterruptionKind kind;

  /// For [AudioInterruptionKind.began]: the system only asked to lower the
  /// volume. Recording can carry on.
  final bool mayDuck;

  /// For [AudioInterruptionKind.ended]: the system says the app may resume
  /// on its own. When false, the user has to resume (FR-REC-05).
  final bool shouldResume;

  final List<String> devicesAdded;
  final List<String> devicesRemoved;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    if (kind == AudioInterruptionKind.began) 'may_duck': mayDuck,
    if (kind == AudioInterruptionKind.ended) 'should_resume': shouldResume,
    if (devicesAdded.isNotEmpty) 'devices_added': devicesAdded,
    if (devicesRemoved.isNotEmpty) 'devices_removed': devicesRemoved,
  };
}

/// For platforms with no audio session events (Windows, ADR-013).
class NoAudioInterruptions implements AudioInterruptionSource {
  const NoAudioInterruptions();

  @override
  Future<void> activate() async {}

  @override
  Future<void> deactivate() async {}

  @override
  Stream<AudioInterruption> get events => const Stream.empty();
}
