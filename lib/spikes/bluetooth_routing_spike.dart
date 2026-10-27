import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/filesystem/m4a_inspector.dart';
import '../data/filesystem/media_paths.dart';
import '../data/repositories/media_asset_repository.dart';
import '../domain/models/enums.dart';
import '../domain/models/media.dart';
import '../domain/services/capture_settings.dart';
import '../domain/services/recording_service.dart';
import '../domain/services/recording_state.dart';
import '../platform/audio_capture/audio_capture_engine.dart';
import '../platform/audio_route/audio_route_probe.dart';
import '../platform/interruptions/audio_interruption_source.dart';
import 'background_recording_spike.dart' show SpikeEvent;

/// Spike P0-07: Bluetooth microphone routing and fallback on Android, iOS
/// and Windows [P0-07, FR-REC-07, FR-REC-03, FR-QUAL-06, AT-QUAL-03].
///
/// Drives the real [RecordingService] for a fixed time while the tester
/// connects and disconnects a headset (manual steps in `TEST_PLAN.md`
/// MT-20). Logs the available and active inputs at the start, on every
/// audio device event and once per [sampleInterval], so the report shows
/// whether the platform's events are enough or only polling sees a
/// change. Each change goes through [RecordingService.routeChanged], which
/// ends the segment with `route_change` and starts the next on whatever
/// input the system gives. A lost input is logged as a `route_lost`
/// interruption row, the timeline marker of FR-REC-07.
///
/// After the run every finished file is inspected again and compared with
/// what its row says (AT-QUAL-03: never mislabel codec or channels).
/// Observations only, no verdict: the tester listens to each segment.
/// Spike code, not used by the app. The real coordinator is P1-07.
class BluetoothRoutingSpike {
  BluetoothRoutingSpike({
    required this.service,
    required this.engine,
    required this.media,
    required this.routes,
    required this.interruptions,
    required this.mediaRoot,
    required this.platform,
    this.sampleInterval = const Duration(seconds: 1),
    this.inspector = const M4aInspector(),
    Future<void> Function(Duration)? wait,
    DateTime Function()? clock,
  }) : _wait = wait ?? Future<void>.delayed,
       _clock = clock ?? DateTime.now;

  final RecordingService service;
  final AudioCaptureEngine engine;
  final MediaAssetRepository media;
  final AudioRouteProbe routes;
  final AudioInterruptionSource interruptions;
  final Directory mediaRoot;
  final CapturePlatform platform;
  final Duration sampleInterval;
  final M4aInspector inspector;
  final Future<void> Function(Duration) _wait;
  final DateTime Function() _clock;

  Future<void> _pending = Future<void>.value();

  /// Completes when every command queued so far has run. For tests.
  Future<void> settle() => _pending;

  Future<BluetoothRoutingReport> run({
    required String activityId,
    required Duration length,
  }) async {
    final startedAt = _clock().toUtc();
    final events = <SpikeEvent>[];
    final samples = <RouteLevelSample>[];
    final changes = <RouteChangeSeen>[];
    var activeReported = false;
    var eventsWithoutChange = 0;

    int offsetMs() => _clock().toUtc().difference(startedAt).inMilliseconds;
    void log(String kind, [Map<String, Object?> detail = const {}]) =>
        events.add(SpikeEvent(offsetMs(), kind, detail));

    void then(Future<void> Function() action) =>
        _pending = _pending.then((_) => action()).catchError((Object e) {
          log('command_error', {'error': '$e'});
        });

    // Null when the probe failed, so a broken probe is not taken for a
    // route change.
    Future<RouteSnapshot?> snapshot() async {
      try {
        final available = await routes.availableInputs();
        final active = await routes.activeInput();
        if (active != null) activeReported = true;
        return RouteSnapshot(available, active);
      } on Object catch (e) {
        log('route_probe_error', {'error': '$e'});
        return null;
      }
    }

    log('permission', {'microphone': await engine.hasPermission()});
    try {
      await interruptions.activate();
      log('audio_session_active');
    } on Object catch (e) {
      log('audio_session_error', {'error': '$e'});
    }
    var last = await snapshot() ?? const RouteSnapshot([], null);
    log('inputs', last.toJson());

    // Compares the inputs now with the last ones seen and, on a change,
    // rolls the segment. [source] says what noticed it: an event or the
    // poll.
    Future<void> check(String source) async {
      final now = await snapshot();
      if (now == null) return;
      if (now == last) {
        if (source != 'poll') {
          eventsWithoutChange++;
          log('event_no_change', {'source': source});
        }
        return;
      }
      final before = last;
      last = now;
      final seen = RouteChangeSeen(offsetMs(), source, before, now);
      changes.add(seen);
      log('route_change_seen', seen.toJson());

      if (service.status.state == RecordingState.userResumeRequired) {
        if (seen.added.isEmpty) return;
        // Stands in for the user tapping resume once a mic is back.
        // RecordingService closes its route_lost row on resume (ADR-021).
        if (await service.resume()) {
          log('resumed', {'why': 'input_available_simulated_tap'});
        } else {
          log('resume_failed', {'error': service.status.errorMessage});
        }
        return;
      }

      final markerStart = _clock().toUtc();
      // Without an active input to compare, any device change may have
      // moved the recording, so cut a boundary to be safe (ADR-016).
      final result = await service.routeChanged(force: now.active == null);
      log('route_change', {
        'outcome': result.outcome.name,
        'from': result.from?.key,
        'to': result.to?.key,
        if (result.reason != null) 'reason': result.reason,
      });
      final lostInput =
          (before.active != null && seen.removed.contains(before.active)) ||
          (before.active == null && seen.removed.isNotEmpty);
      switch (result.outcome) {
        case RouteChangeOutcome.switched when lostInput:
          final row = await media.startInterruption(
            activityId,
            InterruptionReason.routeLost,
            startUtc: markerStart,
          );
          await media.endInterruption(
            row.id,
            autoResumed: true,
            endUtc: _clock().toUtc(),
          );
        // RecordingService opens the route_lost row itself (ADR-021).
        case RouteChangeOutcome.resumeRequired ||
            RouteChangeOutcome.switched ||
            RouteChangeOutcome.unchanged ||
            RouteChangeOutcome.notRecording:
          break;
      }
    }

    final subscriptions = <StreamSubscription<Object?>>[
      service.statusStream.listen(
        (s) => log('state', {
          'state': s.state.name,
          'segment': s.segmentSequence,
          if (s.inputRoute != null) 'input_route': s.inputRoute,
          if (s.errorMessage != null) 'error': s.errorMessage,
        }),
      ),
      interruptions.events.listen((e) {
        log('audio_session', e.toJson());
        switch (e.kind) {
          case AudioInterruptionKind.devicesChanged ||
              AudioInterruptionKind.becomingNoisy:
            then(() => check(e.kind.name));
          case AudioInterruptionKind.began || AudioInterruptionKind.ended:
            break;
        }
      }),
    ];

    final outcome = await service.start(activityId);
    log('start', {'outcome': outcome.name});

    var elapsed = Duration.zero;
    if (outcome == StartOutcome.started) {
      while (elapsed < length) {
        await _wait(sampleInterval);
        elapsed += sampleInterval;
        then(() => check('poll'));
        await _pending;
        final status = service.status;
        if (status.state != RecordingState.recording) continue;
        double? level;
        try {
          level = await engine.levelDbfs();
        } on Object {
          // Logged as a gap in the samples.
        }
        samples.add(
          RouteLevelSample(offsetMs(), level, status.inputRoute ?? 'unknown'),
        );
      }
    }

    await _pending;
    for (final s in subscriptions) {
      await s.cancel();
    }
    final savedId = await service.stop();
    log('stop', {'saved': savedId != null});
    try {
      await interruptions.deactivate();
    } on Object catch (e) {
      log('audio_session_error', {'error': '$e'});
    }

    final segments = await media.segmentsFor(activityId);
    return BluetoothRoutingReport(
      startedAtUtc: startedAt,
      os: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
      startOutcome: outcome,
      requestedLength: length,
      activeInputReported: activeReported,
      eventsWithoutChange: eventsWithoutChange,
      events: events,
      changes: changes,
      samples: samples,
      checks: [for (final s in segments) await _checkLabel(s)],
      interruptions: await media.interruptionsFor(activityId),
    );
  }

  /// Reads the file again and compares it with the row (AT-QUAL-03).
  Future<SegmentLabelCheck> _checkLabel(RecordingSegment segment) async {
    final requested = effectiveCaptureSettings(
      segment.requestedProfile,
      platform,
    );
    if (segment.state != SegmentState.finalised) {
      return SegmentLabelCheck(segment, requested: requested);
    }
    try {
      final info = await inspector.inspect(
        MediaPaths.resolve(mediaRoot, segment.filePath),
      );
      return SegmentLabelCheck(segment, requested: requested, file: info);
    } on Object catch (e) {
      return SegmentLabelCheck(segment, requested: requested, error: '$e');
    }
  }
}

/// The inputs the platform reported at one moment.
class RouteSnapshot {
  const RouteSnapshot(this.available, this.active);

  final List<InputRoute> available;

  /// Null when the platform does not say which input is in use.
  final InputRoute? active;

  @override
  bool operator ==(Object other) =>
      other is RouteSnapshot &&
      other.active == active &&
      other.available.toSet().containsAll(available) &&
      available.toSet().containsAll(other.available);

  @override
  int get hashCode => Object.hash(active, Object.hashAllUnordered(available));

  Map<String, Object?> toJson() => {
    'active': active?.key,
    'available': [for (final r in available) r.key],
  };
}

/// A difference between two snapshots, and what noticed it.
class RouteChangeSeen {
  RouteChangeSeen(this.offsetMs, this.source, this.before, this.after);

  final int offsetMs;

  /// `devicesChanged`, `becomingNoisy` or `poll`.
  final String source;
  final RouteSnapshot before;
  final RouteSnapshot after;

  late final List<InputRoute> added = [
    for (final r in after.available)
      if (!before.available.contains(r)) r,
  ];
  late final List<InputRoute> removed = [
    for (final r in before.available)
      if (!after.available.contains(r)) r,
  ];

  bool get byEvent => source != 'poll';

  Map<String, Object?> toJson() => {
    'offset_ms': offsetMs,
    'source': source,
    'active_before': before.active?.key,
    'active_after': after.active?.key,
    'added': [for (final r in added) r.key],
    'removed': [for (final r in removed) r.key],
  };
}

class RouteLevelSample {
  const RouteLevelSample(this.offsetMs, this.dbfs, this.route);

  final int offsetMs;

  /// Null when the level could not be read.
  final double? dbfs;

  /// The open segment's `input_route`, or `unknown`.
  final String route;
}

/// A segment row against its file (AT-QUAL-03).
class SegmentLabelCheck {
  const SegmentLabelCheck(
    this.segment, {
    required this.requested,
    this.file,
    this.error,
  });

  final RecordingSegment segment;

  /// What the profile asked the encoder for on this platform.
  final EffectiveCaptureSettings requested;

  /// Null when the segment is not finalised or did not parse.
  final AudioFileInfo? file;
  final String? error;

  /// The row's format comes from the file, not the request. Null when
  /// there is no file to compare (damaged rows keep requested values).
  bool? get labelMatchesFile => file == null
      ? null
      : file!.codec == segment.codec &&
            file!.container == segment.container &&
            file!.channelCount == segment.channelCount &&
            file!.sampleRateHz == segment.sampleRateHz;

  /// The platform delivered other channels or sample rate than asked.
  bool get deliveredDiffers =>
      file != null &&
      (file!.channelCount != requested.channelCount ||
          file!.sampleRateHz != requested.sampleRateHz);

  bool get onBluetooth =>
      segment.inputRoute?.startsWith('${InputRouteKind.bluetooth.name}:') ??
      false;

  Map<String, Object?> toJson() => {
    'sequence': segment.sequence,
    'path': segment.filePath,
    'state': segment.state.key,
    'end_reason': segment.endReason?.key,
    'input_route': segment.inputRoute,
    'start_utc': segment.startUtc.toIso8601String(),
    'end_utc': segment.endUtc?.toIso8601String(),
    'duration_ms': segment.durationMs,
    'row': {
      'codec': segment.codec,
      'container': segment.container,
      'channels': segment.channelCount,
      'sample_rate_hz': segment.sampleRateHz,
    },
    'requested': {
      'channels': requested.channelCount,
      'sample_rate_hz': requested.sampleRateHz,
      'bitrate_bps': requested.bitrateBps,
    },
    'file': file == null
        ? null
        : {
            'codec': file!.codec,
            'container': file!.container,
            'channels': file!.channelCount,
            'sample_rate_hz': file!.sampleRateHz,
            'observed_bitrate_bps': file!.observedBitrateBps,
          },
    'label_matches_file': labelMatchesFile,
    'delivered_differs_from_request': deliveredDiffers,
    if (error != null) 'inspection_error': error,
  };
}

class BluetoothRoutingReport {
  BluetoothRoutingReport({
    required this.startedAtUtc,
    required this.os,
    required this.osVersion,
    required this.startOutcome,
    required this.requestedLength,
    required this.activeInputReported,
    required this.eventsWithoutChange,
    required this.events,
    required this.changes,
    required this.samples,
    required this.checks,
    required this.interruptions,
  });

  final DateTime startedAtUtc;
  final String os;
  final String osVersion;
  final StartOutcome startOutcome;
  final Duration requestedLength;
  final bool activeInputReported;

  /// Device events after which the inputs looked the same.
  final int eventsWithoutChange;
  final List<SpikeEvent> events;
  final List<RouteChangeSeen> changes;
  final List<RouteLevelSample> samples;
  final List<SegmentLabelCheck> checks;
  final List<Interruption> interruptions;

  int get changesByEvent => changes.where((c) => c.byEvent).length;
  int get changesByPollOnly => changes.length - changesByEvent;

  /// AT-QUAL-03: rows whose format differs from their file.
  List<SegmentLabelCheck> get mislabelled => [
    for (final c in checks)
      if (c.labelMatchesFile == false) c,
  ];

  int get resumeRequiredCount => events
      .where(
        (e) =>
            e.kind == 'route_change' &&
            e.detail['outcome'] == RouteChangeOutcome.resumeRequired.name,
      )
      .length;

  /// Highest level per input route, from the samples.
  Map<String, double?> get maxLevelByRoute {
    final out = <String, double?>{};
    for (final s in samples) {
      final current = out[s.route];
      final level = s.dbfs;
      out[s.route] = level == null
          ? current
          : (current == null || level > current ? level : current);
    }
    return out;
  }

  /// Plain observations for `PLATFORM_FEASIBILITY.md`. Not a verdict.
  List<String> get observations => [
    'Start: ${startOutcome.name}.',
    if (!activeInputReported)
      'The platform never reported the active input, so segments store no '
          'route and every device change cut a boundary.',
    if (changes.isEmpty)
      'No input change seen: connect and disconnect the headset during '
          'the run.',
    if (changes.isNotEmpty)
      '${changes.length} input change(s) seen: $changesByEvent by a device '
          'event, $changesByPollOnly only by polling.',
    if (eventsWithoutChange > 0)
      '$eventsWithoutChange device event(s) with no change in the inputs.',
    '${checks.length} segment(s), '
        '${checks.where((c) => c.segment.endReason == SegmentEndReason.routeChange).length} '
        'ended by a route change, '
        '${checks.where((c) => c.segment.state == SegmentState.damaged).length} '
        'damaged.',
    'AT-QUAL-03: ${mislabelled.length} segment(s) whose stored codec, '
        'channels or sample rate differ from the file.',
    for (final c in checks.where((c) => c.deliveredDiffers))
      'Segment ${c.segment.sequence} (${c.segment.inputRoute ?? 'route '
                  'unknown'}): asked for ${c.requested.channelCount} ch '
          '${c.requested.sampleRateHz} Hz, file has '
          '${c.file!.channelCount} ch ${c.file!.sampleRateHz} Hz.',
    if (checks.any((c) => c.onBluetooth))
      'Bluetooth segments present. A hands-free mic is often 8 or 16 kHz '
          'even when the file says more: listen for narrowband sound.',
    if (resumeRequiredCount > 0)
      '$resumeRequiredCount time(s) no microphone could take over and the '
          'recorder waited for the user.',
    '${interruptions.where((i) => i.reason == InterruptionReason.routeLost).length} '
        'route-lost marker(s) logged.',
    for (final e in maxLevelByRoute.entries)
      'Max level on ${e.key}: ${e.value ?? '-'} dBFS.',
  ];

  Map<String, Object?> toJson() => {
    'spike': 'P0-07',
    'started_at_utc': startedAtUtc.toIso8601String(),
    'os': os,
    'os_version': osVersion,
    'start_outcome': startOutcome.name,
    'requested_seconds': requestedLength.inSeconds,
    'active_input_reported': activeInputReported,
    'changes_by_event': changesByEvent,
    'changes_by_poll_only': changesByPollOnly,
    'events_without_change': eventsWithoutChange,
    'mislabelled_segments': mislabelled.length,
    'max_level_by_route': maxLevelByRoute,
    'observations': observations,
    'segments': [for (final c in checks) c.toJson()],
    'route_changes': [for (final c in changes) c.toJson()],
    'interruptions': [
      for (final i in interruptions)
        {
          'reason': i.reason.key,
          'start_utc': i.startUtc.toIso8601String(),
          'end_utc': i.endUtc?.toIso8601String(),
          'auto_resumed': i.autoResumed,
        },
    ],
    'events': [for (final e in events) e.toJson()],
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Rows for the P0-07 table in `docs/PLATFORM_FEASIBILITY.md` 2.4.3.
  String toMarkdown() {
    final out = StringBuffer()
      ..writeln('P0-07 run, $os $osVersion, ${startedAtUtc.toIso8601String()}')
      ..writeln();
    for (final o in observations) {
      out.writeln('- $o');
    }
    out
      ..writeln()
      ..writeln(
        '| Seq | State | End reason | Input route | Row ch / Hz '
        '| File ch / Hz | Label matches file |',
      )
      ..writeln('|---:|---|---|---|---|---|---|');
    for (final c in checks) {
      final s = c.segment;
      final file = c.file == null
          ? '-'
          : '${c.file!.channelCount} / ${c.file!.sampleRateHz}';
      final match = switch (c.labelMatchesFile) {
        true => 'yes',
        false => '**no**',
        null => 'no file to compare',
      };
      out.writeln(
        '| ${s.sequence} | ${s.state.key} | ${s.endReason?.key ?? '-'} '
        '| ${s.inputRoute ?? 'unknown'} '
        '| ${s.channelCount} / ${s.sampleRateHz} | $file | $match |',
      );
    }
    return out.toString();
  }
}
