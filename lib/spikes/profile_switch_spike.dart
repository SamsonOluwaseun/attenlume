import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;

import '../data/filesystem/m4a_inspector.dart';
import '../data/filesystem/media_paths.dart';
import '../data/local_database/app_database.dart';
import '../data/repositories/activity_repository.dart';
import '../data/repositories/media_asset_repository.dart';
import '../domain/models/enums.dart';
import '../domain/models/media.dart';
import '../domain/services/capture_settings.dart';
import '../domain/services/recording_service.dart';

/// Spike P0-12: per-segment profile switching and observed bitrate
/// reporting [P0-12, FR-QUAL-01, FR-QUAL-04, FR-QUAL-05, FR-QUAL-06].
///
/// Drives the real [RecordingService]: starts with the first profile, then
/// calls [RecordingService.changeProfile] for each of the others after
/// [ProfileSwitchSpike.run]'s segment length, then stops. Every finished
/// file is inspected again, so the report shows the requested bitrate
/// next to what the encoder declared, the audio payload rate and the
/// whole-file rate, plus the gap each switch left between segments.
///
/// The report states what was observed. It does not decide pass or fail:
/// the tester listens to each switch and records the result (MT-18).
/// Spike code, not used by the app.
class ProfileSwitchSpike {
  ProfileSwitchSpike({
    required this.service,
    required this.activities,
    required this.media,
    required this.mediaRoot,
    required this.platform,
    this.inspector = const M4aInspector(),
    Future<void> Function(Duration)? wait,
    DateTime Function()? clock,
  }) : _wait = wait ?? Future<void>.delayed,
       _clock = clock ?? DateTime.now;

  final RecordingService service;
  final ActivityRepository activities;
  final MediaAssetRepository media;
  final Directory mediaRoot;
  final CapturePlatform platform;
  final M4aInspector inspector;
  final Future<void> Function(Duration) _wait;
  final DateTime Function() _clock;

  static const defaultProfiles = [
    RecordingProfile.economy,
    RecordingProfile.balanced,
    RecordingProfile.enhanced,
    RecordingProfile.economy,
  ];

  Future<ProfileSwitchReport> run({
    required String activityId,
    List<RecordingProfile> profiles = defaultProfiles,
    Duration segmentLength = const Duration(seconds: 20),
  }) async {
    if (profiles.isEmpty) {
      throw ArgumentError.value(profiles, 'profiles', 'Give at least one');
    }
    final startedAt = _clock().toUtc();
    await activities.update(
      activityId,
      ActivitiesCompanion(recordingProfileOverride: Value(profiles.first)),
    );
    final startOutcome = await service.start(activityId);
    final startError = service.status.errorMessage;
    final switches = <ProfileSwitchStep>[];
    if (startOutcome == StartOutcome.started) {
      await _wait(segmentLength);
      for (final next in profiles.skip(1)) {
        final from = service.status.profile;
        final before = _clock();
        final result = await service.changeProfile(next);
        switches.add(
          ProfileSwitchStep(
            from: from,
            to: next,
            result: result,
            commandMs: _clock().difference(before).inMilliseconds,
          ),
        );
        if (result.outcome == ProfileChangeOutcome.failed) break;
        await _wait(segmentLength);
      }
      await service.stop();
    }

    final rows = <ProfileSegmentResult>[];
    RecordingSegment? previous;
    for (final segment in await media.segmentsFor(activityId)) {
      AudioFileInfo? info;
      String? error;
      final file = MediaPaths.resolve(mediaRoot, segment.filePath);
      if (segment.state == SegmentState.damaged) {
        error = 'damaged';
      } else {
        try {
          info = await inspector.inspect(file);
        } on Object catch (e) {
          error = '$e';
        }
      }
      final previousEnd = previous?.endUtc;
      rows.add(
        ProfileSegmentResult(
          segment: segment,
          info: info,
          error: error,
          gapBefore: previousEnd == null
              ? null
              : segment.startUtc.difference(previousEnd),
        ),
      );
      previous = segment;
    }

    return ProfileSwitchReport(
      startedAtUtc: startedAt,
      os: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
      platform: platform,
      startOutcome: startOutcome,
      startError: startError,
      segmentLength: segmentLength,
      switches: switches,
      segments: rows,
    );
  }
}

/// One [RecordingService.changeProfile] call.
class ProfileSwitchStep {
  const ProfileSwitchStep({
    required this.from,
    required this.to,
    required this.result,
    required this.commandMs,
  });

  final RecordingProfile? from;
  final RecordingProfile to;
  final ProfileChangeResult result;

  /// How long the command took: finalise, inspect, hash and restart.
  final int commandMs;

  Map<String, Object?> toJson() => {
    'from': from?.key,
    'to': to.key,
    'outcome': result.outcome.name,
    'reason': result.reason,
    'command_ms': commandMs,
  };
}

/// One segment as stored, and as its file reads back.
class ProfileSegmentResult {
  const ProfileSegmentResult({
    required this.segment,
    this.info,
    this.error,
    this.gapBefore,
  });

  final RecordingSegment segment;
  final AudioFileInfo? info;
  final String? error;

  /// From the previous segment's end to this one's start.
  final Duration? gapBefore;

  /// Audio payload rate against the requested rate, in percent. Positive
  /// means the encoder wrote more than asked.
  double? get payloadDeviationPercent {
    final i = info;
    if (i == null || i.payloadBitrateBps == 0) return null;
    final requested = segment.requestedBitrateBps;
    return (i.payloadBitrateBps - requested) * 100 / requested;
  }

  /// Measured megabytes (10^6 bytes) per hour of this file, container
  /// included. Compare with the nominal figure shown in the selector
  /// (FR-UI-08, FR-STO-01).
  double? get observedMegabytesPerHour {
    final i = info;
    if (i == null || i.durationMs <= 0) return null;
    return i.bytes * 3600000 / i.durationMs / 1e6;
  }

  double get requestedMegabytesPerHour =>
      segment.requestedBitrateBps * 3600 / 8 / 1e6;

  Map<String, Object?> toJson() => {
    'sequence': segment.sequence,
    'file': segment.filePath,
    'state': segment.state.key,
    'end_reason': segment.endReason?.key,
    'requested_profile': segment.requestedProfile.key,
    'requested_bitrate_bps': segment.requestedBitrateBps,
    'stored_observed_bitrate_bps': segment.observedBitrateBps,
    'gap_before_ms': gapBefore?.inMilliseconds,
    'info': info?.toJson(),
    'error': error,
    'payload_deviation_percent': payloadDeviationPercent,
    'observed_mb_per_hour': observedMegabytesPerHour,
    'requested_mb_per_hour': requestedMegabytesPerHour,
  };
}

class ProfileSwitchReport {
  const ProfileSwitchReport({
    required this.startedAtUtc,
    required this.os,
    required this.osVersion,
    required this.platform,
    required this.startOutcome,
    this.startError,
    required this.segmentLength,
    required this.switches,
    required this.segments,
  });

  final DateTime startedAtUtc;
  final String os;
  final String osVersion;
  final CapturePlatform platform;
  final StartOutcome startOutcome;

  /// Why capture could not start, when it failed.
  final String? startError;
  final Duration segmentLength;
  final List<ProfileSwitchStep> switches;
  final List<ProfileSegmentResult> segments;

  /// Payload rates further than this from the request are called out.
  static const notableDeviationPercent = 10.0;

  /// Plain observations for `PLATFORM_FEASIBILITY.md`. Not a verdict.
  List<String> get observations {
    final gaps = [
      for (final s in segments)
        if (s.gapBefore != null) s.gapBefore!.inMilliseconds,
    ];
    final notChanged = [
      for (final s in switches)
        if (s.result.outcome != ProfileChangeOutcome.changed)
          '${s.to.key} ${s.result.outcome.name}',
    ];
    return [
      'Start: ${startOutcome.name}'
          '${startError == null ? '' : ' ($startError)'}.',
      if (switches.isEmpty)
        'No switches ran.'
      else if (notChanged.isEmpty)
        '${switches.length} switch(es), all changed.'
      else
        '${switches.length} switch(es), not changed: '
            '${notChanged.join(', ')}.',
      if (gaps.isNotEmpty)
        'Gap between segments: ${gaps.reduce((a, b) => a < b ? a : b)} to '
            '${gaps.reduce((a, b) => a > b ? a : b)} ms (database '
            'timestamps). Listen at each switch for lost words.',
      for (final s in segments)
        if (s.error != null)
          'Segment ${s.segment.sequence}: ${s.error}.'
        else if (s.payloadDeviationPercent case final d?
            when d.abs() > notableDeviationPercent)
          'Segment ${s.segment.sequence} '
              '(${s.segment.requestedProfile.key}): payload '
              '${(s.info!.payloadBitrateBps / 1000).toStringAsFixed(1)} kbps '
              'against ${s.segment.requestedBitrateBps ~/ 1000} kbps '
              'requested (${d.toStringAsFixed(0)}%).',
    ];
  }

  Map<String, Object?> toJson() => {
    'spike': 'P0-12',
    'started_at_utc': startedAtUtc.toIso8601String(),
    'os': os,
    'os_version': osVersion,
    'platform': platform.name,
    'start_outcome': startOutcome.name,
    'start_error': startError,
    'segment_seconds': segmentLength.inSeconds,
    'observations': observations,
    'switches': [for (final s in switches) s.toJson()],
    'segments': [for (final s in segments) s.toJson()],
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Table for `docs/PLATFORM_FEASIBILITY.md` 2.3.1.
  String toMarkdown() {
    final out = StringBuffer()
      ..writeln('P0-12 run, $os $osVersion, ${startedAtUtc.toIso8601String()}')
      ..writeln();
    for (final o in observations) {
      out.writeln('- $o');
    }
    out
      ..writeln()
      ..writeln(
        '| Seq | Profile | Requested kbps | Codec | Channels | Sample rate '
        '| Duration ms | Declared kbps | Payload kbps | File kbps '
        '| Deviation % | MB/h observed | MB/h requested | Gap ms '
        '| End reason |',
      )
      ..writeln(
        '|---:|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:'
        '|---:|---|',
      );
    String kbps(int bps) => (bps / 1000).toStringAsFixed(1);
    for (final s in segments) {
      final seg = s.segment;
      final i = s.info;
      final lead =
          '| ${seg.sequence} | ${seg.requestedProfile.key} '
          '| ${seg.requestedBitrateBps ~/ 1000} ';
      final tail =
          '| ${s.requestedMegabytesPerHour.toStringAsFixed(1)} '
          '| ${s.gapBefore?.inMilliseconds ?? '-'} '
          '| ${seg.endReason?.key ?? '-'} |';
      if (i == null) {
        out.writeln('$lead| error: ${s.error} | | | | | | | | $tail');
        continue;
      }
      out.writeln(
        '$lead| ${i.codec} | ${i.channelCount} | ${i.sampleRateHz} '
        '| ${i.durationMs} | ${kbps(i.declaredAvgBitrateBps)} '
        '| ${kbps(i.payloadBitrateBps)} | ${kbps(i.observedBitrateBps)} '
        '| ${s.payloadDeviationPercent?.toStringAsFixed(1) ?? '-'} '
        '| ${s.observedMegabytesPerHour?.toStringAsFixed(1) ?? '-'} $tail',
      );
    }
    return out.toString();
  }
}
