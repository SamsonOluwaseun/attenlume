import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' show AppLifecycleState;

import '../data/repositories/media_asset_repository.dart';
import '../domain/models/enums.dart';
import '../domain/models/media.dart';
import '../domain/services/recording_service.dart';
import '../domain/services/recording_state.dart';
import '../platform/audio_capture/audio_capture_engine.dart';
import '../platform/shortcuts/shortcut_bridge.dart';
import '../platform/shortcuts/shortcut_command.dart';
import 'background_recording_spike.dart' show SpikeEvent;

/// What the spike did with one trigger.
enum TriggerOutcome {
  started,
  alreadyRecording,

  /// Another activity holds the recorder (one-active rule, FR-REC-04).
  conflict,
  stopped,
  nothingToStop,
  bookmarked,
  noRecordingToBookmark,

  /// Start was refused or failed. See [TriggerResult.detail].
  startFailed,

  /// Photo and new conversation only open the app until P1-14 and P2.
  openedAppOnly,
  error,
}

/// Spike P0-13: can an iOS App Intent or an Android Quick Settings tile
/// start a recording, and from which app states [P0-13, FR-HF-01,
/// FR-HF-04, FR-HF-05, AT-HF-01].
///
/// Listens on a [ShortcutBridge] for [run]'s `duration` while the tester
/// taps the tile, runs the intents and opens deep links with the app in
/// front, in the background, killed and with the phone locked (manual
/// steps in `TEST_PLAN.md` MT-22). Each command drives the real
/// [RecordingService] as the Phase 2 handler would: start, stop and
/// toggle respect the one-active rule (a start for another activity is
/// logged as a conflict, so the spike never stops a test recording; the
/// app's handler goes through `OneActiveCoordinator`, which switches and
/// confirms, ADR-020), bookmarks need a running recording.
///
/// For each trigger it logs where it came from, whether it launched the
/// app, whether an app screen was visible, the Flutter lifecycle state on
/// arrival, the time from tap to recording, and the input level for the
/// first [levelSamplesPerStart] samples after a start. A start that
/// succeeded while the app was not visible but whose level stays at or
/// below [flatSignalDbfs] is the OS silencing a
/// background microphone, which is exactly the question.
///
/// Observations only, no verdict. Spike code, not used by the app. The
/// real handler, confirmations and tile state are Phase 2 (P2-01, P2-03).
class ShortcutTriggerSpike {
  ShortcutTriggerSpike({
    required this.service,
    required this.engine,
    required this.media,
    required this.bridge,
    required this.lifecycle,
    this.initialLifecycle = AppLifecycleState.resumed,
    this.sampleInterval = const Duration(seconds: 1),
    this.levelSamplesPerStart = 5,
    Future<void> Function(Duration)? wait,
    DateTime Function()? clock,
  }) : _wait = wait ?? Future<void>.delayed,
       _clock = clock ?? DateTime.now;

  final RecordingService service;
  final AudioCaptureEngine engine;
  final MediaAssetRepository media;
  final ShortcutBridge bridge;
  final Stream<AppLifecycleState> lifecycle;
  final AppLifecycleState initialLifecycle;
  final Duration sampleInterval;
  final int levelSamplesPerStart;
  final Future<void> Function(Duration) _wait;
  final DateTime Function() _clock;

  static const flatSignalDbfs = -90.0;

  Future<void> _pending = Future<void>.value();

  /// Completes when every command queued so far has run. For tests.
  Future<void> settle() => _pending;

  /// Listens for [duration]. Commands that name no activity use
  /// [activityId]. With [tileDirect] the Android tile sends commands to
  /// the running app without opening it.
  Future<ShortcutTriggerReport> run({
    required String activityId,
    Duration duration = const Duration(minutes: 5),
    bool tileDirect = false,
  }) async {
    final startedAt = _clock().toUtc();
    final events = <SpikeEvent>[];
    final triggers = <TriggerResult>[];
    var appState = initialLifecycle;

    int offsetMs() => _clock().toUtc().difference(startedAt).inMilliseconds;
    void log(String kind, [Map<String, Object?> detail = const {}]) =>
        events.add(SpikeEvent(offsetMs(), kind, detail));

    Future<void> handle(ShortcutCommand command, {required bool initial}) =>
        _pending = _pending
            .then((_) async {
              final received = _clock().toUtc();
              log('command', {...command.toJson(), 'initial': initial});
              final target = command.activityId ?? activityId;
              final (outcome, detail) = await _dispatch(command, target);
              final done = _clock().toUtc();
              final result = TriggerResult(
                number: triggers.length + 1,
                offsetMs: received.difference(startedAt).inMilliseconds,
                command: command,
                initial: initial,
                lifecycleOnArrival: appState,
                outcome: outcome,
                detail: detail,
                stateAfter: service.status.state,
                deliveryMs: command.triggeredAt == null
                    ? null
                    : received.difference(command.triggeredAt!).inMilliseconds,
                triggerToDoneMs: command.triggeredAt == null
                    ? null
                    : done.difference(command.triggeredAt!).inMilliseconds,
              );
              triggers.add(result);
              log('outcome', {
                'number': result.number,
                'outcome': outcome.name,
                'detail': detail,
                'state': service.status.state.name,
              });
            })
            .catchError((Object e) {
              log('command_error', {'error': '$e'});
            });

    log('permission', {'microphone': await engine.hasPermission()});
    try {
      await bridge.setTileDirect(tileDirect);
      log('tile_mode', {'direct': tileDirect});
    } on Object catch (e) {
      log('tile_mode_error', {'error': '$e'});
    }

    final subscriptions = <StreamSubscription<Object?>>[
      lifecycle.listen((s) {
        appState = s;
        log('app_state', {'state': s.name});
      }),
      service.statusStream.listen(
        (s) => log('state', {
          'state': s.state.name,
          'segment': s.segmentSequence,
          if (s.errorMessage != null) 'error': s.errorMessage,
        }),
      ),
      bridge.commands.listen((c) => handle(c, initial: false)),
    ];

    try {
      final initial = await bridge.takeInitialCommand();
      if (initial != null) await handle(initial, initial: true);
    } on Object catch (e) {
      log('initial_command_error', {'error': '$e'});
    }

    final end = startedAt.add(duration);
    while (_clock().toUtc().isBefore(end)) {
      await _wait(sampleInterval);
      await _pending;
      if (service.status.state != RecordingState.recording) continue;
      final waiting = [
        for (final t in triggers)
          if (t.outcome == TriggerOutcome.started &&
              t.levelsAfterStart.length < levelSamplesPerStart)
            t,
      ];
      double? dbfs;
      try {
        dbfs = await engine.levelDbfs();
      } on Object {
        dbfs = null;
      }
      log('level', {'dbfs': dbfs, 'app_state': appState.name});
      for (final t in waiting) {
        t.levelsAfterStart.add(dbfs);
      }
    }

    for (final s in subscriptions) {
      await s.cancel();
    }
    await _pending;
    if (service.status.state.holdsActivity) {
      await service.stop();
      log('stopped_at_end');
    }
    try {
      await bridge.setTileDirect(false);
    } on Object {
      // Best effort: leave the tile opening the app.
    }

    return ShortcutTriggerReport(
      startedAtUtc: startedAt,
      os: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
      tileDirect: tileDirect,
      events: events,
      triggers: triggers,
      segments: await media.segmentsFor(activityId),
      bookmarks: await media.bookmarksFor(activityId),
    );
  }

  Future<(TriggerOutcome, String?)> _dispatch(
    ShortcutCommand command,
    String activityId,
  ) async {
    try {
      switch (command.action) {
        case ShortcutAction.startRecording:
          return await _start(activityId);
        case ShortcutAction.stopRecording:
          return await _stop();
        case ShortcutAction.toggleRecording:
          return service.status.state.holdsActivity
              ? await _stop()
              : await _start(activityId);
        case ShortcutAction.bookmark:
          final status = service.status;
          if (status.state != RecordingState.recording &&
              status.state != RecordingState.paused) {
            return (TriggerOutcome.noRecordingToBookmark, null);
          }
          final bookmark = await media.addBookmark(
            activityId: status.activityId!,
            source: BookmarkSource.shortcut,
            atUtc: _clock().toUtc(),
            label: 'Shortcut (${command.source.key})',
          );
          return (TriggerOutcome.bookmarked, 'offset ${bookmark.offsetMs} ms');
        case ShortcutAction.takePhoto:
        case ShortcutAction.newConversation:
          return (TriggerOutcome.openedAppOnly, null);
      }
    } on Object catch (e) {
      return (TriggerOutcome.error, '$e');
    }
  }

  Future<(TriggerOutcome, String?)> _start(String activityId) async {
    final outcome = await service.start(activityId);
    return switch (outcome) {
      StartOutcome.started => (TriggerOutcome.started, null),
      StartOutcome.alreadyRecording => (TriggerOutcome.alreadyRecording, null),
      StartOutcome.conflict => (
        TriggerOutcome.conflict,
        'held by ${service.status.activityId}',
      ),
      _ => (
        TriggerOutcome.startFailed,
        [outcome.name, ?service.status.errorMessage].join(': '),
      ),
    };
  }

  Future<(TriggerOutcome, String?)> _stop() async {
    if (!service.status.state.holdsActivity) {
      return (TriggerOutcome.nothingToStop, null);
    }
    final saved = await service.stop();
    return (TriggerOutcome.stopped, saved == null ? null : 'saved $saved');
  }
}

class TriggerResult {
  TriggerResult({
    required this.number,
    required this.offsetMs,
    required this.command,
    required this.initial,
    required this.lifecycleOnArrival,
    required this.outcome,
    required this.detail,
    required this.stateAfter,
    required this.deliveryMs,
    required this.triggerToDoneMs,
  });

  final int number;
  final int offsetMs;
  final ShortcutCommand command;

  /// The command that launched or reopened the app.
  final bool initial;
  final AppLifecycleState lifecycleOnArrival;
  final TriggerOutcome outcome;
  final String? detail;
  final RecordingState stateAfter;

  /// Tap to Dart receiving the command, when the native side timed it.
  final int? deliveryMs;

  /// Tap to the command's work being done (for a start: recording).
  final int? triggerToDoneMs;

  /// Input levels sampled after a successful start. Null entries could not
  /// be read.
  final List<double?> levelsAfterStart = [];

  /// The app was not on screen when the trigger fired or arrived.
  bool get inBackground =>
      command.appVisibleAtTrigger == false ||
      command.deliveredDirect ||
      lifecycleOnArrival != AppLifecycleState.resumed;

  /// Started, but every level read shows silence: the OS probably
  /// silenced the microphone. Null until a level was read.
  bool? get silentAfterStart {
    final read = levelsAfterStart.whereType<double>().toList();
    if (read.isEmpty) return null;
    return read.every((d) => d <= ShortcutTriggerSpike.flatSignalDbfs);
  }

  Map<String, Object?> toJson() => {
    'number': number,
    'offset_ms': offsetMs,
    ...command.toJson(),
    'initial': initial,
    'lifecycle_on_arrival': lifecycleOnArrival.name,
    'in_background': inBackground,
    'outcome': outcome.name,
    'detail': detail,
    'state_after': stateAfter.name,
    'delivery_ms': deliveryMs,
    'trigger_to_done_ms': triggerToDoneMs,
    'levels_after_start': levelsAfterStart,
    'silent_after_start': silentAfterStart,
  };
}

class ShortcutTriggerReport {
  ShortcutTriggerReport({
    required this.startedAtUtc,
    required this.os,
    required this.osVersion,
    required this.tileDirect,
    required this.events,
    required this.triggers,
    required this.segments,
    required this.bookmarks,
  });

  final DateTime startedAtUtc;
  final String os;
  final String osVersion;
  final bool tileDirect;
  final List<SpikeEvent> events;
  final List<TriggerResult> triggers;
  final List<RecordingSegment> segments;
  final List<Bookmark> bookmarks;

  List<TriggerResult> get startsWithSound => [
    for (final t in triggers)
      if (t.outcome == TriggerOutcome.started && t.silentAfterStart == false) t,
  ];

  /// The feasibility answer: starts that fired with no app screen showing.
  List<TriggerResult> get backgroundStarts => [
    for (final t in triggers)
      if (t.outcome == TriggerOutcome.started && t.inBackground) t,
  ];

  List<TriggerResult> get silentStarts => [
    for (final t in triggers)
      if (t.outcome == TriggerOutcome.started && t.silentAfterStart == true) t,
  ];

  /// Starts that came while another activity held the recorder. Each must
  /// be a conflict, never a switch (FR-REC-04).
  List<TriggerResult> get conflicts => [
    for (final t in triggers)
      if (t.outcome == TriggerOutcome.conflict) t,
  ];

  /// Plain observations for `PLATFORM_FEASIBILITY.md` 2.13. Not a verdict.
  List<String> get observations {
    String sources() {
      final keys = {for (final t in triggers) t.command.source.key}.toList()
        ..sort();
      return keys.isEmpty ? 'none' : keys.join(', ');
    }

    final timed = [
      for (final t in triggers)
        if (t.outcome == TriggerOutcome.started && t.triggerToDoneMs != null)
          t.triggerToDoneMs!,
    ]..sort();
    return [
      '${triggers.length} trigger(s) received, from: ${sources()}.',
      'Tile mode: ${tileDirect ? 'direct (no app opened when running)' : 'opens the app'}.',
      if (triggers.any((t) => t.initial))
        'The app was launched or reopened by a trigger '
            '(${triggers.where((t) => t.initial && t.command.coldStart).length} '
            'cold start(s)).',
      '${triggers.where((t) => t.outcome == TriggerOutcome.started).length} '
          'start(s), ${startsWithSound.length} with sound, '
          '${silentStarts.length} silent.',
      '${backgroundStarts.length} start(s) with no app screen showing'
          '${backgroundStarts.isEmpty ? '' : ': ${backgroundStarts.map((t) => '#${t.number} ${t.silentAfterStart == true
                    ? 'silent'
                    : t.silentAfterStart == false
                    ? 'with sound'
                    : 'level unread'}').join(', ')}'}.',
      if (timed.isNotEmpty)
        'Tap to recording: min ${timed.first} ms, '
            'median ${timed[timed.length ~/ 2]} ms, max ${timed.last} ms.',
      if (conflicts.isNotEmpty)
        '${conflicts.length} start(s) refused because another activity was '
            'recording (one-active rule).',
      if (triggers.any((t) => t.outcome == TriggerOutcome.startFailed))
        'Start failed: '
            '${triggers.where((t) => t.outcome == TriggerOutcome.startFailed).map((t) => '#${t.number} ${t.detail}').join('; ')}.',
      '${bookmarks.length} bookmark(s) written, '
          '${triggers.where((t) => t.outcome == TriggerOutcome.noRecordingToBookmark).length} '
          'refused with nothing recording.',
      '${segments.length} segment(s) written.',
    ];
  }

  Map<String, Object?> toJson() => {
    'spike': 'P0-13',
    'started_at_utc': startedAtUtc.toIso8601String(),
    'os': os,
    'os_version': osVersion,
    'tile_direct': tileDirect,
    'background_starts': backgroundStarts.length,
    'silent_starts': silentStarts.length,
    'observations': observations,
    'triggers': [for (final t in triggers) t.toJson()],
    'segments': [
      for (final s in segments)
        {
          'sequence': s.sequence,
          'path': s.filePath,
          'state': s.state.key,
          'end_reason': s.endReason?.key,
          'duration_ms': s.durationMs,
          'bytes': s.bytes,
        },
    ],
    'bookmarks': [
      for (final b in bookmarks)
        {'offset_ms': b.offsetMs, 'source': b.source.key, 'label': b.label},
    ],
    'events': [for (final e in events) e.toJson()],
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Rows for the P0-13 table in `docs/PLATFORM_FEASIBILITY.md` 2.13.
  String toMarkdown() {
    final out = StringBuffer()
      ..writeln('P0-13 run, $os $osVersion, ${startedAtUtc.toIso8601String()}')
      ..writeln();
    for (final o in observations) {
      out.writeln('- $o');
    }
    out
      ..writeln()
      ..writeln(
        '| # | Source | Action | Cold | Visible | Direct | App state '
        '| Outcome | Tap to done ms | Sound |',
      )
      ..writeln('|---:|---|---|---|---|---|---|---|---:|---|');
    String yn(bool? v) => v == null ? '-' : (v ? 'yes' : 'no');
    for (final t in triggers) {
      final c = t.command;
      out.writeln(
        '| ${t.number} | ${c.source.key} | ${c.action.key} '
        '| ${yn(c.coldStart)} | ${yn(c.appVisibleAtTrigger)} '
        '| ${yn(c.deliveredDirect)} | ${t.lifecycleOnArrival.name} '
        '| ${t.outcome.name} | ${t.triggerToDoneMs ?? '-'} '
        '| ${t.silentAfterStart == null ? '-' : (t.silentAfterStart! ? '**silent**' : 'yes')} |',
      );
    }
    return out.toString();
  }
}
