import 'dart:async';

import '../../data/repositories/activity_repository.dart';
import '../../data/repositories/media_asset_repository.dart';
import '../../data/repositories/repository_support.dart';
import '../../shared/utilities/date_formatters.dart';
import 'recording_service.dart';
import 'recording_state.dart';

/// Where a request to start recording came from (FR-REC-04, section 6).
enum RecordingTrigger {
  /// A button in the app.
  ui,

  /// A notification action. Tapping it brings the app forward, so the
  /// prompt can be shown (ADR-020).
  notification,

  /// An OS shortcut: App Intent, Quick Settings tile, launcher shortcut,
  /// deep link or Windows hotkey.
  shortcut,

  /// A voice command (Siri, assistant routine, push-to-talk).
  voice;

  /// True when a person is looking at the app and can answer the prompt.
  /// Shortcuts and voice are non-visual: they stop the old recording,
  /// start the new one and confirm (FR-REC-04).
  bool get canPrompt => this == ui || this == notification;
}

/// The three answers to the one-active prompt (FR-REC-04).
enum OneActiveChoice {
  /// Stop and save the running recording, then start the new one.
  stopAndStartNew,

  /// Leave the running recording as it is. The new activity is not
  /// recorded, but the caller may still open it for notes and photos.
  keepRunning,

  /// Do nothing.
  cancel,
}

/// The recording that is in the way of a new one.
class OneActiveConflict {
  const OneActiveConflict({
    required this.activityId,
    required this.title,
    required this.state,
    required this.recorded,
  });

  final String activityId;
  final String title;
  final RecordingState state;

  /// Audio captured so far, across all its segments.
  final Duration recorded;

  bool get isPaused => state != RecordingState.recording;

  /// "'Data Mesh Keynote' is still recording (47 min)."
  String get message => isPaused
      ? "'$title' is paused (${formatDuration(recorded)} recorded)."
      : "'$title' is still recording (${formatDuration(recorded)}).";
}

/// Asks the person what to do. Null means the prompt was dismissed, which
/// counts as [OneActiveChoice.cancel].
typedef OneActivePrompt = Future<OneActiveChoice?> Function(
  OneActiveConflict conflict,
);

/// What a request ended in.
enum RecordRequestOutcome {
  /// Nothing else was held. The new activity is recording.
  started,

  /// The old recording was stopped and saved, and the new one started.
  switched,

  /// This activity was already recording or paused.
  alreadyRecording,

  /// The person kept the old recording running.
  keptRunning,

  /// The person cancelled. Nothing changed.
  cancelled,

  /// The new activity could not start. See
  /// [RecordRequestResult.startOutcome]. If an old recording was stopped
  /// first, [RecordRequestResult.stoppedActivityId] names it.
  refused,
}

/// What [OneActiveCoordinator.requestStart] did.
class RecordRequestResult {
  const RecordRequestResult(
    this.outcome, {
    this.startOutcome,
    this.stoppedActivityId,
    this.conflict,
    this.confirmation,
  });

  final RecordRequestOutcome outcome;

  /// The service's answer to the start, when a start was attempted.
  final StartOutcome? startOutcome;

  /// The recording that was stopped and saved to make way, if any.
  final String? stoppedActivityId;

  /// The recording that was in the way, if there was one.
  final OneActiveConflict? conflict;

  /// What was sent to the confirmation sink, for non-visual triggers.
  final String? confirmation;

  @override
  String toString() =>
      'RecordRequestResult(${outcome.name}, ${startOutcome?.name}, '
      'stopped: $stoppedActivityId)';
}

/// Tells the person what a non-visual trigger did (FR-REC-04, section 6).
/// The Android notification (P1-11) and haptics will implement this; until
/// then [InAppTriggerConfirmations] shows it on return to the app.
abstract interface class TriggerConfirmationSink {
  Future<void> confirm(RecordingTrigger trigger, String message);
}

/// Keeps confirmations in a stream for the app to show as a banner.
class InAppTriggerConfirmations implements TriggerConfirmationSink {
  final _messages = StreamController<String>.broadcast();

  Stream<String> get messages => _messages.stream;

  @override
  Future<void> confirm(RecordingTrigger trigger, String message) async {
    if (!_messages.isClosed) _messages.add(message);
  }

  Future<void> dispose() => _messages.close();
}

/// Applies the one-active rule to every start, whatever the trigger
/// (FR-REC-04, AT-REC-04) [P1-06].
///
/// A start that meets another activity is never refused silently: a
/// visual trigger asks the person, a non-visual one stops the old
/// recording, starts the new one and confirms. The old recording is only
/// stopped through [RecordingService.switchTo], which saves it before the
/// new one starts and refuses if a different activity took over while the
/// person was deciding.
class OneActiveCoordinator {
  OneActiveCoordinator({
    required this._recorder,
    required this._activities,
    required this._media,
    required this._confirmations,
    this._clock = systemUtcClock,
  });

  final RecordingService _recorder;
  final ActivityRepository _activities;
  final MediaAssetRepository _media;
  final TriggerConfirmationSink _confirmations;
  final UtcClock _clock;

  /// Starts recording [activityId] from [trigger].
  ///
  /// [prompt] is asked when [trigger] can prompt and another activity holds
  /// the recorder. A visual trigger with no [prompt] (for example a
  /// notification action handled while the app has no screen) follows the
  /// non-visual default and confirms.
  Future<RecordRequestResult> requestStart(
    String activityId, {
    required RecordingTrigger trigger,
    OneActivePrompt? prompt,
  }) => _request(activityId, trigger, prompt, retried: false);

  Future<RecordRequestResult> _request(
    String activityId,
    RecordingTrigger trigger,
    OneActivePrompt? prompt, {
    required bool retried,
  }) async {
    final outcome = await _recorder.start(activityId);
    if (outcome != StartOutcome.conflict) {
      return _finish(
        trigger,
        activityId,
        RecordRequestResult(switch (outcome) {
          StartOutcome.started => RecordRequestOutcome.started,
          StartOutcome.alreadyRecording =>
            RecordRequestOutcome.alreadyRecording,
          _ => RecordRequestOutcome.refused,
        }, startOutcome: outcome),
      );
    }

    final conflict = await _describeHeld();
    if (conflict == null && !retried) {
      // The other recording ended between the two calls. Try once more.
      return _request(activityId, trigger, prompt, retried: true);
    }
    if (conflict == null) {
      return _finish(
        trigger,
        activityId,
        const RecordRequestResult(
          RecordRequestOutcome.refused,
          startOutcome: StartOutcome.conflict,
        ),
      );
    }

    final asks = trigger.canPrompt && prompt != null;
    final choice = asks
        ? await prompt(conflict) ?? OneActiveChoice.cancel
        : OneActiveChoice.stopAndStartNew;
    switch (choice) {
      case OneActiveChoice.keepRunning:
        return RecordRequestResult(
          RecordRequestOutcome.keptRunning,
          conflict: conflict,
        );
      case OneActiveChoice.cancel:
        return RecordRequestResult(
          RecordRequestOutcome.cancelled,
          conflict: conflict,
        );
      case OneActiveChoice.stopAndStartNew:
        break;
    }

    final switched = await _recorder.switchTo(
      activityId,
      replacing: conflict.activityId,
    );
    final result = RecordRequestResult(
      switch (switched.outcome) {
        StartOutcome.started =>
          switched.stoppedActivityId == null
              ? RecordRequestOutcome.started
              : RecordRequestOutcome.switched,
        StartOutcome.alreadyRecording => RecordRequestOutcome.alreadyRecording,
        _ => RecordRequestOutcome.refused,
      },
      startOutcome: switched.outcome,
      stoppedActivityId: switched.stoppedActivityId,
      conflict: conflict,
    );
    return _finish(trigger, activityId, result, prompted: asks);
  }

  /// Sends a confirmation for non-visual triggers and for visual ones that
  /// had no prompt.
  Future<RecordRequestResult> _finish(
    RecordingTrigger trigger,
    String activityId,
    RecordRequestResult result, {
    bool prompted = false,
  }) async {
    if (trigger.canPrompt && (prompted || result.conflict == null)) {
      return result;
    }
    final message = await _confirmationFor(activityId, result);
    try {
      await _confirmations.confirm(trigger, message);
    } on Object {
      // A missed confirmation never undoes the recording.
    }
    return RecordRequestResult(
      result.outcome,
      startOutcome: result.startOutcome,
      stoppedActivityId: result.stoppedActivityId,
      conflict: result.conflict,
      confirmation: message,
    );
  }

  Future<String> _confirmationFor(
    String activityId,
    RecordRequestResult result,
  ) async {
    final title = await _titleOf(activityId);
    final stopped = result.conflict?.title;
    return switch (result.outcome) {
      RecordRequestOutcome.started => "Recording '$title'.",
      RecordRequestOutcome.switched =>
        "Stopped and saved '$stopped'. Now recording '$title'.",
      RecordRequestOutcome.alreadyRecording => "'$title' is already recording.",
      RecordRequestOutcome.refused =>
        (result.stoppedActivityId != null
                ? "Stopped and saved '$stopped'. "
                : '') +
            _refusalMessage(title, result.startOutcome),
      // Only reachable from a prompt, which never confirms.
      RecordRequestOutcome.keptRunning ||
      RecordRequestOutcome.cancelled => "'$stopped' is still recording.",
    };
  }

  String _refusalMessage(String title, StartOutcome? outcome) =>
      switch (outcome) {
        StartOutcome.recordingNotPermitted =>
          "'$title' is set to not record audio.",
        StartOutcome.microphoneDenied =>
          "Couldn't record '$title'. Allow microphone access in Settings.",
        StartOutcome.activityNotFound =>
          "Couldn't find that activity. Open the app to choose one.",
        StartOutcome.conflict =>
          'Another recording started first. Open the app to choose.',
        _ => "Couldn't start recording '$title'. Open the app to try again.",
      };

  Future<String> _titleOf(String activityId) async =>
      (await _activities.get(activityId))?.title ?? 'Activity';

  /// The activity holding the recorder now, or null if none is.
  Future<OneActiveConflict?> _describeHeld() async {
    final status = _recorder.status;
    final heldId = status.activityId;
    if (!status.state.holdsActivity || heldId == null) return null;
    return OneActiveConflict(
      activityId: heldId,
      title: await _titleOf(heldId),
      state: status.state,
      recorded: await _recordedSoFar(heldId),
    );
  }

  /// Sum of segment wall-clock spans, the open one up to now.
  Future<Duration> _recordedSoFar(String activityId) async {
    final now = _clock();
    var total = Duration.zero;
    for (final segment in await _media.segmentsFor(activityId)) {
      final end = segment.endUtc ?? now;
      if (end.isAfter(segment.startUtc)) {
        total += end.difference(segment.startUtc);
      }
    }
    return total;
  }
}
