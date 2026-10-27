import 'dart:async';

import '../../data/repositories/repository_support.dart';
import '../../platform/interruptions/audio_interruption_source.dart';
import '../models/enums.dart';
import 'recording_service.dart';
import 'recording_state.dart';

/// What the person is told after an interruption (FR-REC-05).
enum InterruptionNoticeKind {
  /// Recording carried on by itself: "Recording resumed".
  resumed,

  /// Recording is waiting for a tap on Resume. The audio so far is saved.
  resumeRequired,
}

class InterruptionNotice {
  const InterruptionNotice(this.kind, this.message, {this.activityId});

  final InterruptionNoticeKind kind;
  final String message;
  final String? activityId;

  @override
  String toString() => 'InterruptionNotice(${kind.name}, $message)';
}

/// Shows [InterruptionNotice]s. The Android notification with a Resume
/// action (P1-11) will implement this; until then
/// [InAppInterruptionNotices] shows them as a banner on return to the app.
abstract interface class InterruptionNoticeSink {
  Future<void> show(InterruptionNotice notice);
}

/// Keeps notices in a stream for the app to show as a banner.
class InAppInterruptionNotices implements InterruptionNoticeSink {
  final _notices = StreamController<InterruptionNotice>.broadcast();

  Stream<InterruptionNotice> get notices => _notices.stream;

  @override
  Future<void> show(InterruptionNotice notice) async {
    if (!_notices.isClosed) _notices.add(notice);
  }

  Future<void> dispose() => _notices.close();
}

/// Turns platform audio events into recording commands (FR-REC-05,
/// FR-PHO-07, FR-REC-03, FR-REC-07) [P1-07].
///
/// - An interruption that is not a duck ends the segment through
///   [RecordingService.interrupt], so the call is never recorded. While
///   the app's camera is busy, or within [cameraWindow] of a shot, the
///   reason is `camera`; otherwise `system`, because the platform does not
///   say whether it was a call, an alarm or another app (ADR-021).
/// - When the interruption ends, recording resumes only if the system says
///   it may; a camera interruption resumes as soon as the shot is done.
///   Otherwise the recorder waits for the user and a notice says so.
/// - Device changes and unplugged headsets go to
///   [RecordingService.routeChanged]. With [forceRouteRoll] (platforms that
///   do not report the active input, ADR-016) every change cuts a segment.
///
/// Events are handled one at a time, in the order they arrive.
class InterruptionCoordinator {
  InterruptionCoordinator({
    required this._recorder,
    required this._source,
    required this._notices,
    this.forceRouteRoll = false,
    this.cameraWindow = const Duration(seconds: 2),
    this._clock = systemUtcClock,
  });

  final RecordingService _recorder;
  final AudioInterruptionSource _source;
  final InterruptionNoticeSink _notices;
  final UtcClock _clock;

  /// Cut a segment on every device change, for platforms that cannot say
  /// which input is in use (Android and Windows, ADR-016).
  final bool forceRouteRoll;

  /// How long after a shot an interruption is still put down to the
  /// camera (ADR-017; to tune from MT-21).
  final Duration cameraWindow;

  StreamSubscription<AudioInterruption>? _subscription;
  Future<void> _pending = Future<void>.value();
  int _cameraUses = 0;
  DateTime? _lastCameraUseEnd;

  /// Starts listening. Calling it again does nothing.
  void start() {
    _subscription ??= _source.events.listen((event) {
      // Judged on arrival, not when the queue reaches it.
      final nearCamera = _nearCamera;
      _then(() => _handle(event, nearCamera: nearCamera));
    });
  }

  /// Completes once every event received so far has been handled.
  Future<void> get settled => _pending;

  /// Runs [action] (opening the camera or taking a photo) and marks the
  /// camera busy meanwhile, so an interruption it causes is logged as
  /// `camera` and recording resumes straight after (FR-PHO-07, ADR-017).
  Future<T> duringCameraUse<T>(Future<T> Function() action) async {
    _cameraUses++;
    try {
      return await action();
    } finally {
      _cameraUses--;
      _lastCameraUseEnd = _clock();
      if (_cameraUses == 0) _then(_resumeAfterCamera);
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _pending;
  }

  bool get _nearCamera {
    final last = _lastCameraUseEnd;
    return _cameraUses > 0 ||
        (last != null && _clock().difference(last) <= cameraWindow);
  }

  void _then(Future<void> Function() action) {
    // A failed command is already shown in the recorder's status.
    _pending = _pending.then((_) => action()).catchError((Object _) {});
  }

  Future<void> _handle(
    AudioInterruption event, {
    required bool nearCamera,
  }) async {
    switch (event.kind) {
      case AudioInterruptionKind.began:
        if (event.mayDuck) return; // Only quieter playback; keep recording.
        await _recorder.interrupt(
          nearCamera ? InterruptionReason.camera : InterruptionReason.system,
        );
      case AudioInterruptionKind.ended:
        final status = _recorder.status;
        if (status.state != RecordingState.interrupted) return;
        // A camera interruption waits for the shot to finish, not for the
        // system (ADR-017).
        if (status.interruption == InterruptionReason.camera &&
            _cameraUses > 0) {
          return;
        }
        await _endInterruption(
          mayResume:
              event.shouldResume ||
              status.interruption == InterruptionReason.camera,
        );
      case AudioInterruptionKind.becomingNoisy ||
          AudioInterruptionKind.devicesChanged:
        final result = await _recorder.routeChanged(force: forceRouteRoll);
        if (result.outcome == RouteChangeOutcome.resumeRequired) {
          await _notices.show(
            InterruptionNotice(
              InterruptionNoticeKind.resumeRequired,
              result.reason!,
              activityId: _recorder.status.activityId,
            ),
          );
        }
    }
  }

  Future<void> _resumeAfterCamera() async {
    final status = _recorder.status;
    if (status.state != RecordingState.interrupted ||
        status.interruption != InterruptionReason.camera) {
      return;
    }
    await _endInterruption(mayResume: true);
  }

  Future<void> _endInterruption({required bool mayResume}) async {
    final result = await _recorder.interruptionEnded(mayResume: mayResume);
    switch (result.outcome) {
      case InterruptionEndOutcome.resumed:
        await _notices.show(
          InterruptionNotice(
            InterruptionNoticeKind.resumed,
            'Recording resumed',
            activityId: result.activityId,
          ),
        );
      case InterruptionEndOutcome.resumeRequired:
        await _notices.show(
          InterruptionNotice(
            InterruptionNoticeKind.resumeRequired,
            result.reason!,
            activityId: result.activityId,
          ),
        );
      case InterruptionEndOutcome.notInterrupted:
        break;
    }
  }
}
