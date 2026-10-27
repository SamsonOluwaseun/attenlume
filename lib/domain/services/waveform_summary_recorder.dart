import 'dart:async';
import 'dart:io';

import '../../data/filesystem/media_paths.dart';
import '../../data/filesystem/waveform_summary.dart';
import '../../data/repositories/activity_repository.dart';
import 'recording_service.dart';
import 'recording_state.dart';

/// Writes a level summary for every segment while it records, for the
/// review waveform (FR-REV-03, ADR-034) [P1-17].
///
/// No AAC decoder is needed: the summary is the input level the recorder
/// already reports, sampled every [bucket]. A segment recorded without it
/// (for example before this existed) simply has no waveform.
class WaveformSummaryRecorder {
  WaveformSummaryRecorder({
    required this.recorder,
    required this.activities,
    required this._mediaRoot,
    required this._level,
    this.bucket = const Duration(milliseconds: WaveformSummary.defaultBucketMs),
    Timer Function(Duration, void Function(Timer))? createTimer,
  }) : _createTimer = createTimer ?? Timer.periodic;

  final RecordingService recorder;
  final ActivityRepository activities;
  final Duration bucket;
  final Future<Directory> Function() _mediaRoot;
  final Future<double> Function() _level;
  final Timer Function(Duration, void Function(Timer)) _createTimer;

  StreamSubscription<RecordingStatus>? _statusSub;
  Timer? _timer;
  String? _segmentId;
  WaveformSummaryWriter? _writer;
  bool _sampling = false;
  Future<void> _closing = Future.value();

  void start() {
    _statusSub ??= recorder.statusStream.listen(_onStatus);
    _onStatus(recorder.status);
  }

  void _onStatus(RecordingStatus status) {
    final segmentId = status.state == RecordingState.recording
        ? status.segmentId
        : null;
    if (segmentId == _segmentId) return;
    _closeCurrent();
    final activityId = status.activityId;
    if (segmentId == null || activityId == null) return;
    _segmentId = segmentId;
    unawaited(_open(activityId, segmentId));
  }

  Future<void> _open(String activityId, String segmentId) async {
    final activity = await activities.get(activityId);
    final root = await _mediaRoot();
    if (activity == null || _segmentId != segmentId) return;
    _writer = WaveformSummaryWriter(
      MediaPaths.resolve(
        root,
        MediaPaths.waveform(activity.conferenceId, activityId, segmentId),
      ),
      bucketMs: bucket.inMilliseconds,
    );
    _timer = _createTimer(bucket, (_) => unawaited(sample()));
  }

  /// Reads the level once and appends it. Public for tests.
  Future<void> sample() async {
    final writer = _writer;
    if (writer == null || _sampling) return;
    _sampling = true;
    try {
      final level = await _level();
      if (identical(writer, _writer)) writer.add(level);
    } catch (_) {
      // A missed reading leaves a short flat spot, nothing worse.
    } finally {
      _sampling = false;
    }
  }

  void _closeCurrent() {
    _timer?.cancel();
    _timer = null;
    _segmentId = null;
    final writer = _writer;
    _writer = null;
    if (writer != null) {
      _closing = _closing.then((_) => writer.close()).catchError((_) {});
    }
  }

  /// Completes when every finished segment's summary is on disk.
  Future<void> flushed() => _closing;

  Future<void> dispose() async {
    await _statusSub?.cancel();
    _statusSub = null;
    _closeCurrent();
    await _closing;
  }
}
