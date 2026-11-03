import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/repositories/activity_repository.dart';
import '../../data/repositories/conference_repository.dart';
import '../../data/repositories/media_asset_repository.dart';
import '../../domain/models/enums.dart';
import '../../domain/services/recording_service.dart';
import '../../domain/services/recording_state.dart';
import '../../platform/shortcuts/shortcut_command.dart';
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

  void _push(Widget screen) {
    if (onNavigate != null) {
      onNavigate!(screen);
      return;
    }
    navigatorKey.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
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
        if (held != null) _push(RecordingScreen(activityId: held));
    }
  }

  /// Opens the running recording if there is one; otherwise starts in
  /// [activityId], or a new activity in the most recent conference, or opens
  /// "New conference" when there is none [P2-03].
  Future<void> _startIn(String? activityId, {required String typeKey}) async {
    final held = _heldActivityId;
    if (held != null) {
      _push(RecordingScreen(activityId: held));
      return;
    }
    if (activityId != null && activityId.isNotEmpty) {
      _push(RecordingScreen(activityId: activityId, autoStart: true));
      return;
    }
    final recent = await conferenceRepository.getRecent(limit: 1);
    if (recent.isEmpty) {
      _push(const ConferenceWizardScreen());
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
    _push(RecordingScreen(activityId: activity.id, autoStart: true));
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
