import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/repositories/activity_repository.dart';
import '../../data/repositories/conference_repository.dart';
import '../../data/repositories/media_asset_repository.dart';
import '../../domain/models/enums.dart';
import '../../domain/services/recording_service.dart';
import '../../domain/services/recording_state.dart';
import '../../platform/shortcuts/shortcut_command.dart';
import '../capture/camera_screen.dart';
import '../capture/recording_screen.dart';
import '../conferences/conference_wizard_screen.dart';

/// Routes shortcut commands (launcher shortcuts, Quick Settings tile,
/// `attenlume://` deep links) to app screens and recording actions
/// [P0-13, P2-03, FR-HF-01, FR-HF-04, FR-HF-05, ADR-078].
///
/// Starting always goes through the normal recording screen, so the privacy
/// reminder, consent and one-active rules apply (no hidden recording).
class ShortcutCoordinator {
  ShortcutCoordinator({
    required this.navigatorKey,
    required this.conferenceRepository,
    required this.activityRepository,
    required this.mediaRepository,
    required this.recordingService,
    DateTime Function()? clock,
    this.onNavigate,
  }) : _clock = clock ?? DateTime.now;

  final GlobalKey<NavigatorState> navigatorKey;
  final ConferenceRepository conferenceRepository;
  final ActivityRepository activityRepository;
  final MediaAssetRepository mediaRepository;
  final RecordingService recordingService;
  final DateTime Function() _clock;

  /// Replaces navigation in tests.
  final void Function(Widget screen)? onNavigate;

  Route<dynamic>? _lastRoute;
  String? _lastKey;
  Object? _pendingStart;

  static String _keyOf(Widget screen) => screen is RecordingScreen
      ? 'recording:${screen.activityId}'
      : screen is CameraScreen
      ? 'camera:${screen.activityId}'
      : '${screen.runtimeType}';

  /// Pushes [screen]. If an earlier shortcut opened the same screen and it is
  /// still open, it is brought back to the top instead (it follows the
  /// recording status itself), so repeated taps do not stack copies behind
  /// Back. A prompt open over it, such as the privacy reminder, is left
  /// alone [P2-03].
  void _push(Widget screen, {VoidCallback? onClosed}) {
    if (onNavigate != null) {
      onNavigate!(screen);
      return;
    }
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      onClosed?.call();
      return;
    }
    final key = _keyOf(screen);
    final last = _lastRoute;
    if (last != null && last.isActive && _lastKey == key) {
      // No new screen will mount to report this attempt's outcome.
      onClosed?.call();
      Route<dynamic>? top;
      navigator.popUntil((r) {
        top ??= r;
        return true;
      });
      if (top is PopupRoute) return;
      navigator.popUntil((r) => r == last);
      return;
    }
    final route = MaterialPageRoute<dynamic>(builder: (_) => screen);
    _lastRoute = route;
    _lastKey = key;
    navigator.push(route).whenComplete(() => onClosed?.call());
  }

  /// The activity holding the recorder, or null when nothing is recording.
  String? get _heldActivityId {
    final status = recordingService.status;
    return status.state.holdsActivity ? status.activityId : null;
  }

  Future<void> handleCommand(ShortcutCommand command) async {
    switch (command.action) {
      case ShortcutAction.startRecording:
      case ShortcutAction.toggleRecording:
        await _startIn(command.activityId, typeKey: 'session');
      case ShortcutAction.newConversation:
        await _startIn(null, typeKey: 'business_conversation');
      case ShortcutAction.stopRecording:
        await _stop();
      case ShortcutAction.bookmark:
        await _bookmark();
      case ShortcutAction.takePhoto:
        final held = _heldActivityId;
        if (held != null) _push(CameraScreen(activityId: held));
    }
  }

  /// Opens the running recording if there is one; otherwise starts in
  /// [activityId], or a new activity in the most recent conference, or opens
  /// "New conference" when there is none [P2-03].
  Future<void> _startIn(String? activityId, {required String typeKey}) async {
    // Covers repository work, screen loading and privacy/consent prompts.
    if (_pendingStart != null) return;
    final held = _heldActivityId;
    if (held != null) {
      _push(RecordingScreen(activityId: held));
      return;
    }
    final pending = Object();
    _pendingStart = pending;
    void complete() {
      if (identical(_pendingStart, pending)) _pendingStart = null;
    }

    void openRecording(String id) => _push(
      RecordingScreen(
        activityId: id,
        autoStart: true,
        onAutoStartComplete: complete,
      ),
      onClosed: complete,
    );

    try {
      if (activityId != null && activityId.isNotEmpty) {
        openRecording(activityId);
        return;
      }
      final recent = await conferenceRepository.getRecent(limit: 1);
      if (recent.isEmpty) {
        _push(const ConferenceWizardScreen(), onClosed: complete);
        return;
      }
      final types = await activityRepository.types();
      final type = types.firstWhere(
        (t) => t.key == typeKey,
        orElse: () => types.first,
      );
      final activity = await activityRepository.create(
        conferenceId: recent.first.id,
        typeId: type.id,
      );
      openRecording(activity.id);
    } catch (_) {
      complete();
      rethrow;
    }
  }

  Future<void> _stop() async {
    final held = _heldActivityId;
    if (held == null) return;
    await recordingService.stop();
    _push(RecordingScreen(activityId: held));
  }

  /// Bookmarks need a running or paused recording (ADR-018).
  Future<void> _bookmark() async {
    final status = recordingService.status;
    final held = _heldActivityId;
    if (held == null ||
        (status.state != RecordingState.recording &&
            status.state != RecordingState.paused)) {
      return;
    }
    await mediaRepository.addBookmark(
      activityId: held,
      source: BookmarkSource.shortcut,
      atUtc: _clock().toUtc(),
    );
  }
}
