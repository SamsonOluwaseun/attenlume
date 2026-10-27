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
import '../../platform/audio_route/audio_route_probe.dart';
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

/// Result of [RecordingService.changeProfile].
enum ProfileChangeOutcome {
  /// The open segment ended with reason `quality_change` and a new one is
  /// recording with the new profile. When paused, the next segment will
  /// use it.
  changed,

  /// The recording already uses this profile. Nothing changed.
  alreadyInUse,

  /// Nothing is recording or paused. Nothing changed.
  notRecording,

  /// The encoder refused the new profile, so recording carried on in a new
  /// segment with the previous one (FR-QUAL-04). See
  /// [ProfileChangeResult.reason].
  declined,

  /// Neither profile could start. Earlier segments are kept and the
  /// recorder is in [RecordingState.errorRecoverable].
  failed,
}

/// What [RecordingService.changeProfile] did, with a plain reason when it
/// declined or failed.
class ProfileChangeResult {
  const ProfileChangeResult(this.outcome, {this.reason});

  final ProfileChangeOutcome outcome;
  final String? reason;

  @override
  String toString() => 'ProfileChangeResult(${outcome.name}, $reason)';
}

/// Result of [RecordingService.routeChanged].
enum RouteChangeOutcome {
  /// The open segment ended with reason `route_change` and a new one is
  /// recording from the input now in use (FR-REC-03, FR-REC-07).
  switched,

  /// The input in use is the one the open segment started with.
  unchanged,

  /// Nothing is recording. The next segment reads the route when it
  /// starts.
  notRecording,

  /// No input could take over. The segment was saved and the recorder is
  /// in [RecordingState.userResumeRequired] (FR-REC-07: pause with a
  /// prompt). See [RouteChangeResult.reason].
  resumeRequired,
}

/// What [RecordingService.routeChanged] did, with the routes either side.
class RouteChangeResult {
  const RouteChangeResult(this.outcome, {this.from, this.to, this.reason});

  final RouteChangeOutcome outcome;

  /// The input the open segment was recorded from. Null when unknown.
  final InputRoute? from;

  /// The input the new segment records from. Null when unknown.
  final InputRoute? to;
  final String? reason;

  @override
  String toString() => 'RouteChangeResult(${outcome.name}, $from -> $to)';
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
    this._routes = const NoAudioRouteProbe(),
    this._inspector = const M4aInspector(),
    this._clock = systemUtcClock,
    this._hashFile = sha256OfFileInIsolate,
  });

  final AudioCaptureEngine _engine;
  final ActivityRepository _activities;
  final MediaAssetRepository _media;
  final Future<Directory> Function() _mediaRoot;
  final CapturePlatform _platform;
  final AudioRouteProbe _routes;
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

  /// Changes the recording profile mid-recording (FR-QUAL-04) [P0-12].
  ///
  /// Finalises the open segment with reason `quality_change`, then starts
  /// a new segment with [profile]. The running encoder is never changed
  /// and no file is transcoded. If the encoder refuses [profile], the new
  /// segment starts with the previous profile instead and the change is
  /// declined with a reason. On success the profile is stored as the
  /// activity override, so a later resume keeps it. While paused, only the
  /// override changes.
  Future<ProfileChangeResult> changeProfile(
    RecordingProfile profile,
  ) => _lock.run(() async {
    final state = _status.state;
    final activityId = _status.activityId;
    if (activityId == null ||
        (state != RecordingState.recording && state != RecordingState.paused)) {
      return const ProfileChangeResult(ProfileChangeOutcome.notRecording);
    }
    final previous = _status.profile!;
    if (profile == previous) {
      return const ProfileChangeResult(ProfileChangeOutcome.alreadyInUse);
    }
    return _guard(() async {
      if (state == RecordingState.paused) {
        await _storeOverride(activityId, profile);
        _publish(
          RecordingStatus(
            state: RecordingState.paused,
            activityId: activityId,
            profile: profile,
          ),
        );
        return const ProfileChangeResult(ProfileChangeOutcome.changed);
      }
      _moveTo(_copyStatus(RecordingState.switchingSegment));
      await _finishSegment(SegmentEndReason.qualityChange);
      final conferenceId = (await _activities.get(activityId))!.conferenceId;
      final refused = await _tryBeginSegment(activityId, conferenceId, profile);
      if (refused == null) {
        await _storeOverride(activityId, profile);
        return const ProfileChangeResult(ProfileChangeOutcome.changed);
      }
      final reason = 'The ${profile.label} profile could not start ($refused).';
      if (await _beginSegment(activityId, conferenceId, previous)) {
        return ProfileChangeResult(
          ProfileChangeOutcome.declined,
          reason: '$reason Still recording with ${previous.label}.',
        );
      }
      return ProfileChangeResult(
        ProfileChangeOutcome.failed,
        reason: '$reason ${_status.errorMessage}',
      );
    });
  });

  /// Rolls to a new segment when the input in use has changed (FR-REC-03,
  /// FR-REC-07) [P0-07].
  ///
  /// Call on any audio device event. Reads the active input; if it differs
  /// from the one the open segment started with, or [force] is true (for
  /// platforms that do not report the active input), the open segment ends
  /// with reason `route_change` and a new one starts on whatever input the
  /// system now gives. The running encoder is never redirected. If no
  /// input can start, the segment is saved and the recorder waits in
  /// [RecordingState.userResumeRequired] for the user.
  Future<RouteChangeResult> routeChanged({bool force = false}) => _lock.run(
    () async {
      if (_status.state != RecordingState.recording) {
        return const RouteChangeResult(RouteChangeOutcome.notRecording);
      }
      final from = _open!.route;
      final now = await _readRoute();
      if (!force && now == from) {
        return RouteChangeResult(
          RouteChangeOutcome.unchanged,
          from: from,
          to: now,
        );
      }
      final activityId = _status.activityId!;
      final profile = _status.profile!;
      return _guard(() async {
        _moveTo(_copyStatus(RecordingState.switchingSegment));
        await _finishSegment(SegmentEndReason.routeChange);
        final conferenceId = (await _activities.get(activityId))!.conferenceId;
        final error = await _tryBeginSegment(activityId, conferenceId, profile);
        if (error == null) {
          return RouteChangeResult(
            RouteChangeOutcome.switched,
            from: from,
            to: _open!.route,
          );
        }
        final reason =
            'No microphone could take over ($error). Connect one and '
            'tap resume.';
        _moveTo(
          RecordingStatus(
            state: RecordingState.userResumeRequired,
            activityId: activityId,
            profile: profile,
            errorMessage: reason,
          ),
        );
        return RouteChangeResult(
          RouteChangeOutcome.resumeRequired,
          from: from,
          reason: reason,
        );
      });
    },
  );

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

  Future<void> _storeOverride(String activityId, RecordingProfile profile) =>
      _activities.update(
        activityId,
        ActivitiesCompanion(recordingProfileOverride: Value(profile)),
      );

  /// Starts a segment, or moves to [RecordingState.errorRecoverable] if
  /// the encoder refuses.
  Future<bool> _beginSegment(
    String activityId,
    String conferenceId,
    RecordingProfile profile,
  ) async {
    final error = await _tryBeginSegment(activityId, conferenceId, profile);
    if (error == null) return true;
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

  /// Creates the segment row, then starts the encoder on its file. Returns
  /// null once recording, or the encoder's error. A refused start leaves
  /// its row marked damaged and the state unchanged.
  Future<Object?> _tryBeginSegment(
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
    final route = await _readRoute();
    final segment = await _media.startSegment(
      activityId: activityId,
      filePath: relative,
      requestedProfile: profile,
      codec: 'aac_lc',
      container: 'm4a',
      channelCount: settings.channelCount,
      sampleRateHz: settings.sampleRateHz,
      requestedBitrateBps: settings.bitrateBps,
      inputRoute: route?.key,
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
      return error;
    }
    _open = _OpenSegment(segment.id, file, route);
    _moveTo(
      RecordingStatus(
        state: RecordingState.recording,
        activityId: activityId,
        profile: profile,
        segmentId: segment.id,
        segmentSequence: segment.sequence,
        segmentStartUtc: segment.startUtc,
        inputRoute: route?.key,
      ),
    );
    return null;
  }

  /// The input in use, or null when the platform does not say or the
  /// probe fails. Never guessed (ADR-016).
  Future<InputRoute?> _readRoute() async {
    try {
      return await _routes.activeInput();
    } on Object {
      return null;
    }
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
    _publish(next);
  }

  void _publish(RecordingStatus next) {
    _status = next;
    if (!_statusController.isClosed) _statusController.add(next);
  }
}

class _OpenSegment {
  _OpenSegment(this.segmentId, this.file, this.route);

  final String segmentId;
  final File file;
  final InputRoute? route;
}
