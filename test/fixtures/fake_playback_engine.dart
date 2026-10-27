import 'dart:async';

import 'package:attenlume/platform/audio_playback/audio_playback_engine.dart';

/// Records what the review player asks for, and lets a test play out
/// positions and file ends by hand [P1-17].
class FakePlaybackEngine implements AudioPlaybackEngine {
  final List<String> calls = [];
  final _positions = StreamController<Duration>.broadcast();
  final _completed = StreamController<void>.broadcast();

  String? openPath;
  Duration seekedTo = Duration.zero;
  bool playing = false;
  double speed = 1.0;
  bool disposed = false;

  /// Paths that fail to open, as a missing file would.
  final Set<String> broken = {};

  @override
  Future<void> open(String path) async {
    calls.add('open $path');
    if (broken.contains(path)) throw StateError('cannot open $path');
    openPath = path;
    seekedTo = Duration.zero;
  }

  @override
  Future<void> play() async {
    calls.add('play');
    playing = true;
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    playing = false;
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek ${position.inMilliseconds}');
    seekedTo = position;
  }

  @override
  Future<void> setSpeed(double speed) async {
    calls.add('speed $speed');
    this.speed = speed;
  }

  @override
  Stream<Duration> get positions => _positions.stream;

  @override
  Stream<void> get completed => _completed.stream;

  /// The open file reports it has reached [position].
  void emitPosition(Duration position) => _positions.add(position);

  /// The open file played to its end.
  void complete() => _completed.add(null);

  @override
  Future<void> dispose() async {
    disposed = true;
    await _positions.close();
    await _completed.close();
  }
}
