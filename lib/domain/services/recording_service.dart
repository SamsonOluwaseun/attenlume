import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;

import '../../data/filesystem/m4a_inspector.dart';
import '../../data/filesystem/media_paths.dart';
import '../../data/local_database/app_database.dart';
import '../../data/repositories/activity_repository.dart';
import '../../data/repositories/media_asset_repository.dart';
import '../../data/repositories/repository_support.dart';
import '../../platform/audio_capture/audio_capture_engine.dart';
import '../../shared/utilities/serial_lock.dart';
import '../models/enums.dart';
import 'capture_settings.dart';
import 'recording_state.dart';

/// Result of [RecordingService.start].
enum StartOutcome {
  /// A new segment is being written.
  started,

  /// This activity was already recording or paused. Nothing changed.
  alreadyRecording,

  /// Another activity holds the recorder (NFR-04). Nothing changed. The
  /// one-active prompt (FR-REC-04, P1-06) resolves this.
  conflict,

  activityNotFound,

  /// The activity is marked "not recording audio" (FR-ACT-07).
  recordingNotPermitted,

  /// The app may not use the microphone. Nothing was written.
  microphoneDenied,

  /// Capture could not start. The segment row is kept as damaged and the
  /// recorder is in [RecordingState.errorRecoverable].
  failed,
}

/// SHA-256 of a file, streamed off the UI isolate (BUILD_GUIDE 12.4).
Future<String> sha256OfFileInIsolate(File file) {
  final path = file.path;
  return Isolate.run(
    () async => (await sha256.bind(File(path).openRead()).first).toString(),
  );
}

/// Start, pause, resume and stop for one recording at a time
/// (BUILD_GUIDE 9.3, ARCHITECTURE 3) [P1-04, FR-REC-01, FR-REC-02,
/// FR-REC-09].
///
/// Every command runs under one [SerialLock] and is idempotent, so rapid
/// taps from any trigger never create a second recording. The segment row
/// is written before the encoder starts (FR-REC-01). Audio goes straight
/// from the encoder to a file: this class never holds audio bytes
/// (FR-REC-02). Files are never deleted or overwritten here (NFR-07).
class RecordingService {
  RecordingService({
    required this._engine,
    required this._activities,
    required this._media,
    required this._mediaRoot,
    required this._platform,
    this._inspector = const M4aInspector(),
    this._clock = systemUtcClock,
    this._hashFile = sha256OfFileInIsolate,
  });

  final AudioCaptureEngine _engine;
  final ActivityRepository _activities;
  final MediaAssetRepository _media;
  final Future<Directory> Function() _mediaRoot;
  final CapturePlatform _platform;
  final M4aInspector _inspector;
  final UtcClock _clock;
  final Future<String> Function(File) _hashFile;

  final _lock = SerialLock();
  final _statusController = StreamController<RecordingStatus>.broadcast();
  Directory? _resolvedRoot;
  RecordingStatus _status = RecordingStatus.idle;
  _OpenSegment? _open;
  bool _disposed = false;

  RecordingStatus get status => _status;

  /// Every status change, starting with the next one.
  Stream<RecordingStatus> get statusStream => _statusController.stream;

  /// Starts recording [activityId] in one call (FR-REC-01). After a failed
  /// start, calling it again for the same activity retries.
  Future<StartOutcome> start(String activityId) => _lock.run(() async {
    final retry =
        _status.state == RecordingState.errorRecoverable &&
        _status.activityId == activityId;
    if (_status.state.holdsActivity && !retry) {
      return _status.activityId == activityId
          ? StartOutcome.alreadyRecording
          : StartOutcome.conflict;
    }
    final activity = await _activities.get(activityId);
    if (activity == null) return StartOutcome.activityNotFound;
    if (activity.recordingPermissionStatus ==
        RecordingPermissionStatus.notPermitted) {
      return StartOutcome.recordingNotPermitted;
    }
    if (!await _engine.hasPermission()) return StartOutcome.microphoneDenied;

    final profile = await _activities.effectiveProfile(activityId);
    _moveTo(
      RecordingStatus(
        state: RecordingState.starting,
        activityId: activityId,
        profile: profile,
      ),
    );
    return _guard(() async {
      await _activities.update(
        activityId,
        const ActivitiesCompanion(status: Value(ActivityStatus.active)),
      );
      final began = await _beginSegment(
        activityId,
        activity.conferenceId,
        profile,
      );
      return began ? StartOutcome.started : StartOutcome.failed;
    });
  });

  /// Pauses the running recording. The open segment ends with reason
  /// `pause` (FR-REC-03). Returns false if nothing was recording.
  Future<bool> pause() => _lock.run(() async {
    if (_status.state != RecordingState.recording) return false;
    return _guard(() async {
      await _finishSegment(SegmentEndReason.pause);
      _moveTo(_copyStatus(RecordingState.paused));
      return true;
    });
  });

  /// Resumes a paused recording in a new segment. Returns false if there
  /// was nothing to resume, or capture failed (see [status]).
  Future<bool> resume() => _lock.run(() async {
    final state = _status.state;
    if (state != RecordingState.paused &&
        state != RecordingState.userResumeRequired) {
      return false;
    }
    final activityId = _status.activityId!;
    return _guard(() async {
      final activity = (await _activities.get(activityId))!;
      return _beginSegment(
        activityId,
        activity.conferenceId,
        await _activities.effectiveProfile(activityId),
      );
    });
  });

  /// Stops and saves the current recording. Returns the saved activity ID,
  /// or null if nothing was held (repeat stops are harmless).
  Future<String?> stop() => _lock.run(() async {
    if (!_status.state.holdsActivity) return null;
    final activityId = _status.activityId!;
    return _guard(() async {
      _moveTo(_copyStatus(RecordingState.stopping));
      if (_open != null) await _finishSegment(SegmentEndReason.userStop);
      final segments = await _media.segmentsFor(activityId);
      final lastEnd = segments.isEmpty ? null : segments.last.endUtc;
      await _activities.update(
        activityId,
        ActivitiesCompanion(
          status: const Value(ActivityStatus.completed),
          actualEnd: Value(lastEnd ?? _clock()),
        ),
      );
      _moveTo(
        RecordingStatus(state: RecordingState.saved, activityId: activityId),
      );
      return activityId;
    });
  });

  /// Saves any open recording, then releases the microphone.
  Future<void> dispose() async {
    if (_disposed) return;
    try {
      await stop();
    } on Object {
      // Partial files stay on disk for recovery (FR-REC-08).
    }
    _disposed = true;
    await _engine.dispose();
    await _statusController.close();
  }

  /// Creates the segment row, then starts the encoder on its file.
  Future<bool> _beginSegment(
    String activityId,
    String conferenceId,
    RecordingProfile profile,
  ) async {
    final root = await _root();
    final sequence = await _media.nextSegmentSequence(activityId);
    var attempt = 0;
    var relative = MediaPaths.segment(conferenceId, activityId, sequence);
    var file = MediaPaths.resolve(root, relative);
    while (file.existsSync()) {
      attempt++;
      relative = MediaPaths.segment(
        conferenceId,
        activityId,
        sequence,
        attempt: attempt,
      );
      file = MediaPaths.resolve(root, relative);
    }
    await file.parent.create(recursive: true);

    final settings = effectiveCaptureSettings(profile, _platform);
    final segment = await _media.startSegment(
      activityId: activityId,
      filePath: relative,
      requestedProfile: profile,
      codec: 'aac_lc',
      container: 'm4a',
      channelCount: settings.channelCount,
      sampleRateHz: settings.sampleRateHz,
      requestedBitrateBps: settings.bitrateBps,
    );
    try {
      await _engine.start(
        CaptureRequest(
          bitrateBps: settings.bitrateBps,
          sampleRateHz: settings.sampleRateHz,
          channelCount: settings.channelCount,
        ),
        file.path,
      );
    } on Object catch (error) {
      await _media.finaliseSegment(
        segment.id,
        endUtc: _clock(),
        endReason: SegmentEndReason.error,
        bytes: file.existsSync() ? file.lengthSync() : null,
        state: SegmentState.damaged,
      );
      _moveTo(
        RecordingStatus(
          state: RecordingState.errorRecoverable,
          activityId: activityId,
          profile: profile,
          errorMessage: 'Recording could not start: $error',
        ),
      );
      return false;
    }
    _open = _OpenSegment(segment.id, file);
    _moveTo(
      RecordingStatus(
        state: RecordingState.recording,
        activityId: activityId,
        profile: profile,
        segmentId: segment.id,
        segmentSequence: segment.sequence,
        segmentStartUtc: segment.startUtc,
      ),
    );
    return true;
  }

  /// Stops the encoder and records what the file really holds
  /// (FR-QUAL-06). A file that does not parse is marked damaged and kept.
  Future<void> _finishSegment(SegmentEndReason reason) async {
    final open = _open!;
    _open = null;
    try {
      await _engine.stop();
    } on Object {
      // The file is judged by inspection below, not by the plugin.
    }
    final end = _clock();
    final file = open.file;
    if (!file.existsSync()) {
      await _media.finaliseSegment(
        open.segmentId,
        endUtc: end,
        endReason: reason,
        state: SegmentState.damaged,
      );
      return;
    }
    final AudioFileInfo info;
    try {
      info = await _inspector.inspect(file);
    } on MediaInspectionException {
      await _media.finaliseSegment(
        open.segmentId,
        endUtc: end,
        endReason: reason,
        bytes: file.lengthSync(),
        state: SegmentState.damaged,
      );
      return;
    }
    String? digest;
    try {
      digest = await _hashFile(file);
    } on Object {
      // Left null: export re-hashes, and a missing hash is honest.
    }
    await _media.finaliseSegment(
      open.segmentId,
      endUtc: end,
      endReason: reason,
      durationMs: info.durationMs,
      bytes: info.bytes,
      sha256: digest,
      observedBitrateBps: info.observedBitrateBps,
      codec: info.codec,
      container: info.container,
      channelCount: info.channelCount,
      sampleRateHz: info.sampleRateHz,
    );
  }

  /// Runs [body]. On an unexpected error, moves to
  /// [RecordingState.errorRecoverable] (files are kept) and rethrows.
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on Object catch (error) {
      if (_open != null) {
        // Release the microphone. The row stays `writing` for crash
        // recovery to judge (FR-REC-08).
        _open = null;
        try {
          await _engine.stop();
        } on Object {
          // Nothing more to do here.
        }
      }
      _moveTo(
        _copyStatus(
          RecordingState.errorRecoverable,
          errorMessage: 'Recording error: $error',
        ),
      );
      rethrow;
    }
  }

  Future<Directory> _root() async => _resolvedRoot ??= await _mediaRoot();

  RecordingStatus _copyStatus(RecordingState state, {String? errorMessage}) =>
      RecordingStatus(
        state: state,
        activityId: _status.activityId,
        profile: _status.profile,
        errorMessage: errorMessage,
      );

  void _moveTo(RecordingStatus next) {
    if (!canTransition(_status.state, next.state)) {
      throw StateError(
        'Recording cannot go from ${_status.state.name} '
        'to ${next.state.name}',
      );
    }
    _status = next;
    if (!_statusController.isClosed) _statusController.add(next);
  }
}

class _OpenSegment {
  _OpenSegment(this.segmentId, this.file);

  final String segmentId;
  final File file;
}
