/// Plays one audio file at a time for the review screen (FR-REV-01,
/// ADR-034) [P1-17].
///
/// The review player joins an activity's segments itself, so an engine
/// only ever needs to open, play and seek within a single file.
abstract interface class AudioPlaybackEngine {
  /// Loads [path], paused at the start. Throws if it cannot be opened.
  Future<void> open(String path);

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  /// 1.0 is normal speed.
  Future<void> setSpeed(double speed);

  /// Position in the open file while it plays.
  Stream<Duration> get positions;

  /// Fires when the open file plays to its end.
  Stream<void> get completed;

  Future<void> dispose();
}
