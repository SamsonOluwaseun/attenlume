import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'audio_playback_engine.dart';

/// [AudioPlaybackEngine] backed by `audioplayers` (ADR-034) [P1-17].
///
/// Android uses MediaPlayer, iOS AVPlayer and Windows Media Foundation,
/// which all play the app's AAC-LC M4A segments. The plugin streams from
/// the file; it does not load the whole file into memory.
class AudioplayersPlaybackEngine implements AudioPlaybackEngine {
  AudioplayersPlaybackEngine([AudioPlayer? player])
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;
  double _speed = 1.0;

  @override
  Future<void> open(String path) async {
    await _player.setReleaseMode(ReleaseMode.stop);
    await _player.setSourceDeviceFile(path);
    if (_speed != 1.0) await _player.setPlaybackRate(_speed);
  }

  @override
  Future<void> play() async {
    await _player.resume();
    // Some platforms reset the rate when playback starts.
    if (_speed != 1.0) await _player.setPlaybackRate(_speed);
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    await _player.setPlaybackRate(speed);
  }

  @override
  Stream<Duration> get positions => _player.onPositionChanged;

  @override
  Stream<void> get completed => _player.onPlayerComplete;

  @override
  Future<void> dispose() => _player.dispose();
}
