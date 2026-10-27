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
import '../platform/interruptions/audio_interruption_source.dart';

/// Spike P0-04: background recording with the screen locked, and call
/// interruption and resume, on Android and iOS [P0-04, NFR-05, NFR-06,
/// FR-REC-05].
///
/// Drives the real [RecordingService] for a fixed time while the tester
/// locks the phone and calls it (manual steps in `TEST_PLAN.md` MT-17).
/// Logs app lifecycle, audio session events, recorder states and the
/// input level once per [sampleInterval], so silent background capture
/// (the OS cutting the mic off) shows up as a flat signal. On an
/// interruption it pauses (ends the segment), logs an interruption row,
/// and resumes when the system allows or when the app is visible again.
///
/// The report states what was observed. It does not decide pass or fail:
/// the tester listens to the files and records the result. Spike code,
/// not used by the app. The real coordinator is P1-07.
class BackgroundRecordingSpike {
  BackgroundRecordingSpike({
    required this.service,
    required this.engine,
    required this.media,
    required this.interruptions,
    required this.lifecycle,
    this.sampleInterval = const Duration(seconds: 1),
    Future<void> Function(Duration)? wait,
    DateTime Function()? clock,
  }) : _wait = wait ?? Future<void>.delayed,
       _clock = clock ?? DateTime.now;

  final RecordingService service;
  final AudioCaptureEngine engine;
  final MediaAssetRepository media;
  final AudioInterruptionSource interruptions;
  final Stream<AppLifecycleState> lifecycle;
  final Duration sampleInterval;
  final Future<void> Function(Duration) _wait;
  final DateTime Function() _clock;

  /// Signals at or below this level count as silence or a blocked mic.
  static const flatSignalDbfs = -90.0;

  Future<void> _pending = Future<void>.value();

  /// Completes when every command queued so far has run. For tests.
  Future<void> settle() => _pending;

  Future<BackgroundRecordingReport> run({
    required String activityId,
    required Duration length,
  }) async {
    final startedAt = _clock().toUtc();
    final events = <SpikeEvent>[];
    final samples = <LevelSample>[];
    var appState = AppLifecycleState.resumed;
    var interruptedByOs = false;
    var resumeOffered = false;
    String? openInterruptionId;

    int offsetMs() => _clock().toUtc().difference(startedAt).inMilliseconds;
    void log(String kind, [Map<String, Object?> detail = const {}]) =>
        events.add(SpikeEvent(offsetMs(), kind, detail));

    // Commands run one after another, after the event that caused them.
    void then(Future<void> Function() action) =>
        _pending = _pending.then((_) => action()).catchError((Object e) {
          log('command_error', {'error': '$e'});
        });

    Future<void> resume(String why) async {
      if (!await service.resume()) {
        log('resume_failed', {
          'why': why,
          'state': service.status.state.name,
          'error': service.status.errorMessage,
        });
        return;
      }
      interruptedByOs = false;
      if (openInterruptionId != null) {
        await media.endInterruption(
          openInterruptionId!,
          autoResumed: why == 'system_allowed',
          endUtc: _clock().toUtc(),
        );
        openInterruptionId = null;
      }
      log('resumed', {'why': why});
    }

    log('permission', {'microphone': await engine.hasPermission()});
    try {
      await interruptions.activate();
      log('audio_session_active');
    } on Object catch (e) {
      log('audio_session_error', {'error': '$e'});
    }

    final subscriptions = <StreamSubscription<Object?>>[
      service.statusStream.listen(
        (s) => log('state', {
          'state': s.state.name,
          'segment': s.segmentSequence,
          if (s.errorMessage != null) 'error': s.errorMessage,
        }),
      ),
      lifecycle.listen((state) {
        appState = state;
        log('lifecycle', {'state': state.name});
        if (state == AppLifecycleState.resumed) {
          then(() async {
            if (interruptedByOs) await resume('app_visible');
          });
        }
      }),
      interruptions.events.listen((e) {
        log('audio_session', e.toJson());
        switch (e.kind) {
          case AudioInterruptionKind.began when !e.mayDuck:
            then(() async {
              if (service.status.state != RecordingState.recording) return;
              await service.pause();
              interruptedByOs = true;
              final row = await media.startInterruption(
                activityId,
                InterruptionReason.system,
                startUtc: _clock().toUtc(),
              );
              openInterruptionId = row.id;
            });
          case AudioInterruptionKind.ended:
            resumeOffered = resumeOffered || e.shouldResume;
            if (e.shouldResume) {
              then(() async {
                if (interruptedByOs) await resume('system_allowed');
              });
            }
          case AudioInterruptionKind.began ||
              AudioInterruptionKind.becomingNoisy ||
              AudioInterruptionKind.devicesChanged:
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
        if (service.status.state != RecordingState.recording) continue;
        double? level;
        try {
          level = await engine.levelDbfs();
        } on Object {
          // Logged as a gap in the samples.
        }
        samples.add(LevelSample(offsetMs(), level, appState));
      }
    }

    await _pending;
    for (final s in subscriptions) {
      await s.cancel();
    }
    final savedId = await service.stop();
    log('stop', {'saved': savedId != null});
    if (openInterruptionId != null) {
      await media.endInterruption(
        openInterruptionId!,
        autoResumed: false,
        endUtc: _clock().toUtc(),
      );
    }
    try {
      await interruptions.deactivate();
    } on Object catch (e) {
      log('audio_session_error', {'error': '$e'});
    }

    return BackgroundRecordingReport(
      startedAtUtc: startedAt,
      os: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
      startOutcome: outcome,
      requestedLength: length,
      systemOfferedResume: resumeOffered,
      events: events,
      samples: samples,
      segments: await media.segmentsFor(activityId),
      interruptions: await media.interruptionsFor(activityId),
    );
  }
}

class SpikeEvent {
  const SpikeEvent(this.offsetMs, this.kind, this.detail);

  final int offsetMs;
  final String kind;
  final Map<String, Object?> detail;

  Map<String, Object?> toJson() => {
    'offset_ms': offsetMs,
    'kind': kind,
    ...detail,
  };
}

class LevelSample {
  const LevelSample(this.offsetMs, this.dbfs, this.appState);

  final int offsetMs;

  /// Null when the level could not be read.
  final double? dbfs;
  final AppLifecycleState appState;

  bool get inBackground => appState != AppLifecycleState.resumed;
}

/// Level figures for the samples taken in one app state.
class LevelSummary {
  LevelSummary(Iterable<LevelSample> samples)
    : count = samples.length,
      _levels = [
        for (final s in samples)
          if (s.dbfs != null) s.dbfs!,
      ];

  final int count;
  final List<double> _levels;

  double? get maxDbfs => _levels.isEmpty ? null : _levels.reduce(_max);

  /// Every readable sample at or below [BackgroundRecordingSpike.flatSignalDbfs].
  bool get flat =>
      _levels.isNotEmpty &&
      _levels.every((l) => l <= BackgroundRecordingSpike.flatSignalDbfs);

  Map<String, Object?> toJson() => {
    'samples': count,
    'readable': _levels.length,
    'max_dbfs': maxDbfs,
    'flat_signal': flat,
  };
}

double _max(double a, double b) => a > b ? a : b;

class BackgroundRecordingReport {
  BackgroundRecordingReport({
    required this.startedAtUtc,
    required this.os,
    required this.osVersion,
    required this.startOutcome,
    required this.requestedLength,
    required this.systemOfferedResume,
    required this.events,
    required this.samples,
    required this.segments,
    required this.interruptions,
  });

  final DateTime startedAtUtc;
  final String os;
  final String osVersion;
  final StartOutcome startOutcome;
  final Duration requestedLength;
  final bool systemOfferedResume;
  final List<SpikeEvent> events;
  final List<LevelSample> samples;
  final List<RecordingSegment> segments;
  final List<Interruption> interruptions;

  late final foreground = LevelSummary(samples.where((s) => !s.inBackground));
  late final background = LevelSummary(samples.where((s) => s.inBackground));

  bool get wentToBackground => events.any(
    (e) =>
        e.kind == 'lifecycle' &&
        e.detail['state'] != AppLifecycleState.resumed.name,
  );

  int get damagedSegments =>
      segments.where((s) => s.state == SegmentState.damaged).length;

  int get recordedMs => segments.fold(0, (sum, s) => sum + (s.durationMs ?? 0));

  /// Plain observations for `PLATFORM_FEASIBILITY.md`. Not a verdict.
  List<String> get observations => [
    'Start: ${startOutcome.name}.',
    if (!wentToBackground)
      'The app never left the foreground: lock the screen during the run.',
    if (wentToBackground && background.count == 0)
      'No level samples while in the background (recorder was not '
          'recording).',
    if (background.flat)
      'Background signal was flat (max ${background.maxDbfs} dBFS): the OS '
          'probably cut the microphone off. Listen to confirm.',
    if (background.count > 0 && !background.flat)
      'Background signal present (max ${background.maxDbfs} dBFS) over '
          '${background.count} samples. Listen to confirm.',
    '${interruptions.length} interruption(s) logged, '
        '${interruptions.where((i) => i.autoResumed).length} resumed on '
        'the system signal.',
    if (interruptions.isNotEmpty && !systemOfferedResume)
      'The system never allowed a resume: user-resume path needed.',
    '${segments.length} segment(s), $damagedSegments damaged, '
        '${(recordedMs / 1000).toStringAsFixed(1)} s recorded of '
        '${requestedLength.inSeconds} s requested.',
  ];

  Map<String, Object?> toJson() => {
    'spike': 'P0-04',
    'started_at_utc': startedAtUtc.toIso8601String(),
    'os': os,
    'os_version': osVersion,
    'start_outcome': startOutcome.name,
    'requested_seconds': requestedLength.inSeconds,
    'system_offered_resume': systemOfferedResume,
    'foreground_levels': foreground.toJson(),
    'background_levels': background.toJson(),
    'observations': observations,
    'segments': [
      for (final s in segments)
        {
          'sequence': s.sequence,
          'file': s.filePath,
          'state': s.state.key,
          'end_reason': s.endReason?.key,
          'start_utc': s.startUtc.toIso8601String(),
          'end_utc': s.endUtc?.toIso8601String(),
          'duration_ms': s.durationMs,
          'bytes': s.bytes,
          'observed_bitrate_bps': s.observedBitrateBps,
          'sha256': s.sha256,
        },
    ],
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

  /// Rows for the P0-04 matrix in `docs/PLATFORM_FEASIBILITY.md` 2.7.
  String toMarkdown() {
    final out = StringBuffer()
      ..writeln('P0-04 run, $os $osVersion, ${startedAtUtc.toIso8601String()}')
      ..writeln();
    for (final o in observations) {
      out.writeln('- $o');
    }
    out
      ..writeln()
      ..writeln(
        '| Seq | State | End reason | Duration ms | Bytes | Observed kbps |',
      )
      ..writeln('|---:|---|---|---:|---:|---:|');
    for (final s in segments) {
      final kbps = s.observedBitrateBps == null
          ? '-'
          : (s.observedBitrateBps! / 1000).toStringAsFixed(1);
      out.writeln(
        '| ${s.sequence} | ${s.state.key} | ${s.endReason?.key ?? '-'} '
        '| ${s.durationMs ?? '-'} | ${s.bytes ?? '-'} | $kbps |',
      );
    }
    return out.toString();
  }
}
