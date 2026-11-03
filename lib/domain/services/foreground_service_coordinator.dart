import 'dart:async';

import '../../data/repositories/activity_repository.dart';
import '../../data/repositories/media_asset_repository.dart';
import '../../data/repositories/repository_support.dart';
import '../../platform/foreground_service/foreground_service_bridge.dart';
import '../../shared/utilities/date_formatters.dart';
import '../models/enums.dart';
import 'interruption_coordinator.dart';
import 'one_active_coordinator.dart';
import 'recording_service.dart';
import 'recording_state.dart';

/// Coordinates the Android foreground service and ongoing notification
/// with the recording lifecycle and notification actions (FR-REC-10) [P1-11].
///
/// - Starts the foreground service on recording start with activity title,
///   status, and elapsed timer chronometer.
/// - Updates the persistent notification on transitions (pause, resume,
///   interruption, route change, segment switch).
/// - Listens for notification action button taps:
///   - Pause: pauses the active recording.
///   - Resume: resumes recording from paused or userResumeRequired state.
///   - Stop: stops and saves the recording.
///   - Bookmark: inserts a bookmark with source `BookmarkSource.notification`.
/// - Stops the foreground service when recording transitions to `saved`, `idle`,
///   `stopping`, or `errorRecoverable`.
/// - Implements [InterruptionNoticeSink] to keep notification status aligned
///   with interruption notices while forwarding to in-app banners.
class ForegroundServiceCoordinator implements InterruptionNoticeSink {
  ForegroundServiceCoordinator({
    required this.recorder,
    required this.activities,
    required this.media,
    required this.bridge,
    required this.inAppNotices,
    this.clock = systemUtcClock,
    this.headsetBookmarksEnabled,
    this.confirmations,
  });

  final RecordingService recorder;
  final ActivityRepository activities;
  final MediaAssetRepository media;
  final ForegroundServiceBridge bridge;
  final InterruptionNoticeSink inAppNotices;
  final UtcClock clock;

  /// Reads "Headset button adds a bookmark" when a recording starts (P2-06).
  final Future<bool> Function()? headsetBookmarksEnabled;

  /// Shows the headset bookmark confirmation in the app (P2-06).
  final TriggerConfirmationSink? confirmations;

  bool _headsetBookmarks = false;

  StreamSubscription<RecordingStatus>? _statusSubscription;
  StreamSubscription<ForegroundServiceAction>? _actionSubscription;

  /// Starts listening to recording state changes and notification actions.
  void start() {
    _statusSubscription ??= recorder.statusStream.listen(_handleStatusChange);
    _actionSubscription ??= bridge.actions.listen(_handleAction);
  }

  /// Handles incoming recording state transitions.
  Future<void> _handleStatusChange(RecordingStatus status) async {
    final state = status.state;
    if (state == RecordingState.idle ||
        state == RecordingState.saved ||
        state == RecordingState.stopping ||
        state == RecordingState.errorRecoverable) {
      if (bridge.isRunning) {
        await bridge.stopService();
      }
      return;
    }

    if (state == RecordingState.starting) {
      return;
    }

    final activityId = status.activityId;
    if (!state.holdsActivity || activityId == null) {
      return;
    }

    final activity = await activities.get(activityId);
    final title = activity?.title ?? 'Recording';
    final elapsed = await calculateElapsed(activityId, status);

    final DateTime? baseTimeUtc = state == RecordingState.recording
        ? clock().subtract(elapsed)
        : null;

    final message = _buildMessage(status, elapsed);

    if (!bridge.isRunning) {
      _headsetBookmarks = await headsetBookmarksEnabled?.call() ?? false;
    }

    final details = NotificationDetails(
      activityId: activityId,
      title: title,
      state: state,
      elapsed: elapsed,
      baseTimeUtc: baseTimeUtc,
      message: message,
      headsetBookmarks: _headsetBookmarks,
    );

    if (!bridge.isRunning) {
      await bridge.startService(details);
    } else {
      await bridge.updateNotification(details);
    }
  }

  /// Calculates total audio duration recorded for [activityId] across
  /// all finalized/recovered segments plus the active open segment.
  Future<Duration> calculateElapsed(
    String activityId,
    RecordingStatus status,
  ) async {
    final segments = await media.segmentsFor(activityId);
    var finishedDuration = Duration.zero;

    for (final seg in segments) {
      if (seg.state == SegmentState.finalised ||
          seg.state == SegmentState.recovered) {
        if (seg.durationMs != null) {
          finishedDuration += Duration(milliseconds: seg.durationMs!);
        } else if (seg.endUtc != null) {
          finishedDuration += seg.endUtc!.difference(seg.startUtc);
        }
      }
    }

    if (status.state == RecordingState.recording &&
        status.segmentStartUtc != null) {
      final currentSpan = clock().difference(status.segmentStartUtc!);
      if (!currentSpan.isNegative) {
        finishedDuration += currentSpan;
      }
    }

    return finishedDuration;
  }

  String? _buildMessage(RecordingStatus status, Duration elapsed) {
    if (status.errorMessage != null && status.errorMessage!.isNotEmpty) {
      return status.errorMessage;
    }
    return switch (status.state) {
      RecordingState.paused =>
        'Recording paused (${formatDuration(elapsed)} recorded)',
      RecordingState.interrupted =>
        'Recording interrupted: ${status.interruption?.key ?? 'system'}',
      RecordingState.userResumeRequired =>
        'Recording interrupted. Tap Resume to continue.',
      RecordingState.recording => 'Recording',
      _ => null,
    };
  }

  /// Handles action buttons tapped in the notification.
  Future<void> _handleAction(ForegroundServiceAction action) async {
    switch (action) {
      case ForegroundServiceAction.pause:
        await recorder.pause();
      case ForegroundServiceAction.resume:
        await recorder.resume();
      case ForegroundServiceAction.stop:
        await recorder.stop();
      case ForegroundServiceAction.bookmark:
        await _bookmark(BookmarkSource.notification, 'Bookmark added');
      case ForegroundServiceAction.headsetBookmark:
        // Ignored if the setting was turned off after the recording started.
        if (!_headsetBookmarks) return;
        final added = await _bookmark(
          BookmarkSource.headset,
          'Bookmark added from headset',
        );
        if (added) {
          await confirmations?.confirm(
            RecordingTrigger.shortcut,
            'Bookmark added from headset',
          );
        }
      case ForegroundServiceAction.photo:
        // Photo action launches app camera via intent
        break;
    }
  }

  /// Adds a bookmark to the recording holding the recorder and says so in
  /// the notification. False when nothing is recording.
  Future<bool> _bookmark(BookmarkSource source, String message) async {
    final status = recorder.status;
    final activityId = status.activityId;
    if (!status.state.holdsActivity || activityId == null) return false;
    await media.addBookmark(
      activityId: activityId,
      source: source,
      atUtc: clock(),
    );
    if (bridge.isRunning) {
      final activity = await activities.get(activityId);
      final elapsed = await calculateElapsed(activityId, status);
      await bridge.updateNotification(
        NotificationDetails(
          activityId: activityId,
          title: activity?.title ?? 'Recording',
          state: status.state,
          elapsed: elapsed,
          baseTimeUtc: status.state == RecordingState.recording
              ? clock().subtract(elapsed)
              : null,
          message: message,
          headsetBookmarks: _headsetBookmarks,
        ),
      );
    }
    return true;
  }

  @override
  Future<void> show(InterruptionNotice notice) async {
    await inAppNotices.show(notice);
    if (bridge.isRunning) {
      final activityId = notice.activityId ?? recorder.status.activityId;
      if (activityId != null) {
        final activity = await activities.get(activityId);
        final status = recorder.status;
        final elapsed = await calculateElapsed(activityId, status);
        await bridge.updateNotification(
          NotificationDetails(
            activityId: activityId,
            title: activity?.title ?? 'Recording',
            state: status.state,
            elapsed: elapsed,
            baseTimeUtc: status.state == RecordingState.recording
                ? clock().subtract(elapsed)
                : null,
            message: notice.message,
            headsetBookmarks: _headsetBookmarks,
          ),
        );
      }
    }
  }

  Future<void> dispose() async {
    await _statusSubscription?.cancel();
    _statusSubscription = null;
    await _actionSubscription?.cancel();
    _actionSubscription = null;
    if (bridge.isRunning) {
      await bridge.stopService();
    }
  }
}
