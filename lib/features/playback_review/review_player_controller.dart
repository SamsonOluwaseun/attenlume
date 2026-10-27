import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/models/media.dart';
import '../../domain/services/cut_range_math.dart';
import '../../domain/services/review_timeline.dart';
import '../../platform/audio_playback/audio_playback_engine.dart';
import '../../shared/utilities/serial_lock.dart';

/// Plays an activity's segments as one recording (FR-REV-01) [P1-17].
///
/// Positions are timeline offsets (BUILD_GUIDE 9.4). Gaps hold no audio:
/// playback runs from one segment straight into the next, scrubbing into
/// a gap lands on the next segment, and skipping counts audio time only,
/// so "back 15 s" always replays the last 15 seconds heard. Cut ranges
/// are skipped while playing (FR-REV-04, ADR-003) [P1-18], but the
/// playhead can still be put inside one to check or change it.
class ReviewPlayerController extends ChangeNotifier {
  ReviewPlayerController({
    required this.timeline,
    required this.engine,
    required this.resolvePath,
  }) : _position = timeline.locate(timeline.startMs) {
    _subs = [
      engine.positions.listen(_onPosition),
      engine.completed.listen((_) => unawaited(_lock.run(_advance))),
    ];
  }

  static const skipStep = Duration(seconds: 15);
  static const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

  final ReviewTimeline timeline;
  final AudioPlaybackEngine engine;

  /// The absolute file path of a segment.
  final Future<String> Function(RecordingSegment segment) resolvePath;

  final _lock = SerialLock();
  late final List<StreamSubscription<Object?>> _subs;
  TimelinePosition? _position;
  int? _openIndex;
  bool _playing = false;
  bool _disposed = false;
  double _speed = 1.0;
  String? _error;
  List<TimeRange> _cuts = const [];
  bool _skipping = false;

  bool get canPlay => timeline.hasAudio;
  bool get isPlaying => _playing;
  double get speed => _speed;

  /// Plain message when a segment could not be opened.
  String? get error => _error;

  /// Merged cut ranges in timeline offsets.
  List<TimeRange> get cuts => _cuts;

  /// Playable audio once cuts are skipped.
  int get keptAudioMs => timeline.keptAudioMs(_cuts);

  /// Replaces the cut ranges playback skips.
  set cutRanges(Iterable<CutRange> ranges) {
    _cuts = CutRangeMath.mergeOverlappingCutRanges(ranges);
    _notify();
  }

  TimeRange? _cutAt(int offsetMs) {
    for (final c in _cuts) {
      if (c.contains(offsetMs)) return c;
    }
    return null;
  }

  /// Moves past the cut under the playhead. Returns false when the cut
  /// runs to the end, leaving the playhead there and playback stopped.
  Future<bool> _leaveCut() async {
    var cut = _cutAt(positionMs);
    while (cut != null) {
      final target = timeline.locate(cut.endMs);
      if (target == null ||
          timeline.offsetOf(target) <= positionMs ||
          timeline.audioOf(target) >= timeline.audioDurationMs) {
        if (_playing) await engine.pause();
        _playing = false;
        final last = _lastPosition;
        if (last != null) await _goTo(last);
        _notify();
        return false;
      }
      await _goTo(target);
      cut = _cutAt(positionMs);
    }
    return true;
  }

  TimelinePosition? get _lastPosition =>
      timeline.locateAudio(timeline.audioDurationMs);

  /// The playhead as a timeline offset.
  int get positionMs {
    final p = _position;
    return p == null ? timeline.startMs : timeline.offsetOf(p);
  }

  /// The playhead in joined audio, gaps left out.
  int get audioPositionMs {
    final p = _position;
    return p == null ? 0 : timeline.audioOf(p);
  }

  void _onPosition(Duration position) {
    final index = _openIndex;
    if (index == null || _disposed) return;
    final duration = timeline.segments[index].durationMs;
    final ms = position.inMilliseconds.clamp(0, duration);
    _position = TimelinePosition(segmentIndex: index, inSegmentMs: ms);
    notifyListeners();
    if (_playing && !_skipping && _cutAt(positionMs) != null) {
      _skipping = true;
      unawaited(
        _lock.run(() async {
          try {
            if (_playing) await _leaveCut();
          } finally {
            _skipping = false;
          }
        }),
      );
    }
  }

  Future<void> _advance() async {
    final index = _openIndex;
    if (index == null) return;
    final next = timeline.nextPlayable(index);
    if (next == null) {
      _playing = false;
      _position = TimelinePosition(
        segmentIndex: index,
        inSegmentMs: timeline.segments[index].durationMs,
      );
      _notify();
      return;
    }
    if (!await _open(next)) return;
    _position = TimelinePosition(segmentIndex: next, inSegmentMs: 0);
    if (_cutAt(positionMs) != null && !await _leaveCut()) return;
    if (_playing) await engine.play();
    _notify();
  }

  Future<bool> _open(int index) async {
    if (_openIndex == index) return true;
    try {
      await engine.open(await resolvePath(timeline.segments[index].segment));
      _openIndex = index;
      _error = null;
      return true;
    } catch (_) {
      _openIndex = null;
      _playing = false;
      _error =
          'Part ${timeline.segments[index].segment.sequence} of this '
          'recording could not be opened.';
      _notify();
      return false;
    }
  }

  Future<void> _goTo(TimelinePosition? target) async {
    if (target == null) return;
    if (!await _open(target.segmentIndex)) return;
    await engine.seek(Duration(milliseconds: target.inSegmentMs));
    _position = target;
    _notify();
  }

  bool get _atEnd {
    final p = _position;
    return p == null ||
        (timeline.nextPlayable(p.segmentIndex) == null &&
            p.inSegmentMs >= timeline.segments[p.segmentIndex].durationMs);
  }

  /// The playhead sits in a cut that reaches the end of the audio.
  bool get _cutRunsToEnd {
    final cut = _cutAt(positionMs);
    return cut != null && cut.endMs >= timeline.audioEndMs;
  }

  Future<void> play() => _lock.run(() async {
    if (!canPlay || _playing) return;
    if (_atEnd || _cutRunsToEnd) {
      await _goTo(timeline.locateAudio(0));
    } else if (_openIndex != _position!.segmentIndex) {
      await _goTo(_position);
    }
    if (_openIndex == null) return;
    if (!await _leaveCut()) return;
    await engine.play();
    _playing = true;
    _notify();
  });

  Future<void> pause() => _lock.run(() async {
    if (!_playing) return;
    await engine.pause();
    _playing = false;
    _notify();
  });

  Future<void> togglePlay() => _playing ? pause() : play();

  /// Scrubs to a timeline offset (FR-REV-01).
  Future<void> seekTo(int offsetMs) =>
      _lock.run(() => _goTo(timeline.locate(offsetMs)));

  /// Skips by [delta] of audio, clamped to the start and end.
  Future<void> skipBy(Duration delta) => _lock.run(() async {
    if (!canPlay) return;
    final target = audioPositionMs + delta.inMilliseconds;
    await _goTo(
      timeline.locateAudio(target.clamp(0, timeline.audioDurationMs)),
    );
  });

  Future<void> skipBack() => skipBy(-skipStep);

  Future<void> skipForward() => skipBy(skipStep);

  Future<void> setSpeed(double speed) => _lock.run(() async {
    await engine.setSpeed(speed);
    _speed = speed;
    _notify();
  });

  /// Moves to the next speed in [speeds], wrapping round.
  Future<void> cycleSpeed() {
    final i = speeds.indexOf(_speed);
    return setSpeed(speeds[(i + 1) % speeds.length]);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    // Releases the decoder and the file (BUILD_GUIDE 12.3).
    unawaited(engine.dispose());
    super.dispose();
  }
}
