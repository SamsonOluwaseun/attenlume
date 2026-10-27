import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/filesystem/media_paths.dart';
import '../data/repositories/media_asset_repository.dart';
import '../domain/models/enums.dart';
import '../domain/models/media.dart';
import '../domain/services/recording_service.dart';
import '../domain/services/recording_state.dart';
import '../platform/audio_capture/audio_capture_engine.dart';
import '../platform/diagnostics/battery_probe.dart';
import '../platform/diagnostics/memory_probe.dart';

/// Spike P0-10: a 90-minute recording on a low-spec device, with memory
/// trend, file size and battery [P0-10, AT-REC-01, AT-MEM-01, FR-REC-02].
///
/// Drives the real [RecordingService] for a fixed time and, once per
/// [sampleInterval], logs the process RSS, the size of the file being
/// written, the input level and the battery. The tester locks the phone
/// and uses other apps as in MT-19 (`TEST_PLAN.md`).
///
/// The report states what was measured. It does not decide pass or fail:
/// there is no agreed memory budget yet (BUILD_GUIDE 12.6), so the tester
/// reads the trend and records the result with the device and OS. Spike
/// code, not used by the app. Interruption handling is P0-04's job; here
/// a state other than recording is only logged and counted.
class LongRunSpike {
  LongRunSpike({
    required this.service,
    required this.engine,
    required this.media,
    required this.mediaRoot,
    this.memory = const ProcessMemoryProbe(),
    this.battery = const UnknownBatteryProbe(),
    this.sampleInterval = const Duration(minutes: 1),
    this.warmUp = const Duration(minutes: 5),
    Future<void> Function(Duration)? wait,
    DateTime Function()? clock,
    this._onSample,
  }) : _wait = wait ?? Future<void>.delayed,
       _clock = clock ?? DateTime.now;

  final RecordingService service;
  final AudioCaptureEngine engine;
  final MediaAssetRepository media;
  final Directory mediaRoot;
  final MemoryProbe memory;
  final BatteryProbe battery;
  final Duration sampleInterval;

  /// Samples before this offset are left out of the memory trend, so
  /// start-up allocation does not read as growth.
  final Duration warmUp;
  final Future<void> Function(Duration) _wait;
  final DateTime Function() _clock;
  final void Function(LongRunSample)? _onSample;

  Future<LongRunReport> run({
    required String activityId,
    required Duration length,
  }) async {
    final startedAt = _clock().toUtc();
    final events = <LongRunEvent>[];
    final samples = <LongRunSample>[];

    int offsetMs() => _clock().toUtc().difference(startedAt).inMilliseconds;
    void log(String kind, [Map<String, Object?> detail = const {}]) =>
        events.add(LongRunEvent(offsetMs(), kind, detail));

    Future<BatteryReading?> readBattery() async {
      try {
        return await battery.read();
      } on Object catch (e) {
        log('battery_error', {'error': '$e'});
        return null;
      }
    }

    Future<LongRunSample> sample() async {
      final status = service.status;
      int? fileBytes;
      double? level;
      if (status.state == RecordingState.recording) {
        fileBytes = await _openFileBytes(activityId, status.segmentId);
        try {
          level = await engine.levelDbfs();
        } on Object {
          // Logged as a gap in the levels.
        }
      }
      return LongRunSample(
        offsetMs: offsetMs(),
        state: status.state,
        segmentSequence: status.segmentSequence,
        rssBytes: memory.currentRssBytes(),
        openFileBytes: fileBytes,
        dbfs: level,
        battery: await readBattery(),
      );
    }

    log('permission', {'microphone': await engine.hasPermission()});
    final subscription = service.statusStream.listen(
      (s) => log('state', {
        'state': s.state.name,
        'segment': s.segmentSequence,
        if (s.errorMessage != null) 'error': s.errorMessage,
      }),
    );

    final rssBefore = memory.currentRssBytes();
    final batteryBefore = await readBattery();
    final outcome = await service.start(activityId);
    log('start', {'outcome': outcome.name});

    if (outcome == StartOutcome.started) {
      var elapsed = Duration.zero;
      while (elapsed < length) {
        final step = length - elapsed < sampleInterval
            ? length - elapsed
            : sampleInterval;
        await _wait(step);
        elapsed += step;
        final s = await sample();
        samples.add(s);
        _onSample?.call(s);
      }
    }

    final savedId = await service.stop();
    log('stop', {'saved': savedId != null});
    await subscription.cancel();

    return LongRunReport(
      startedAtUtc: startedAt,
      os: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
      processors: Platform.numberOfProcessors,
      startOutcome: outcome,
      requestedLength: length,
      sampleInterval: sampleInterval,
      warmUp: warmUp,
      rssBeforeBytes: rssBefore,
      peakRssBytes: memory.peakRssBytes(),
      batteryBefore: batteryBefore,
      batteryAfter: await readBattery(),
      events: events,
      samples: samples,
      segments: await media.segmentsFor(activityId),
    );
  }

  /// Size of the file the encoder is writing, or null if it cannot be
  /// read. Read from disk, so it shows whether audio really reaches it.
  Future<int?> _openFileBytes(String activityId, String? segmentId) async {
    if (segmentId == null) return null;
    final segments = await media.segmentsFor(activityId);
    for (final s in segments) {
      if (s.id != segmentId) continue;
      final file = MediaPaths.resolve(mediaRoot, s.filePath);
      try {
        return file.lengthSync();
      } on FileSystemException {
        return null;
      }
    }
    return null;
  }
}

class LongRunEvent {
  const LongRunEvent(this.offsetMs, this.kind, this.detail);

  final int offsetMs;
  final String kind;
  final Map<String, Object?> detail;

  Map<String, Object?> toJson() => {
    'offset_ms': offsetMs,
    'kind': kind,
    ...detail,
  };
}

class LongRunSample {
  const LongRunSample({
    required this.offsetMs,
    required this.state,
    required this.segmentSequence,
    required this.rssBytes,
    required this.openFileBytes,
    required this.dbfs,
    required this.battery,
  });

  final int offsetMs;
  final RecordingState state;
  final int? segmentSequence;
  final int rssBytes;

  /// Null when not recording or the file could not be read.
  final int? openFileBytes;

  /// Null when not recording or the level could not be read.
  final double? dbfs;
  final BatteryReading? battery;

  static const csvHeader =
      'offset_s,state,segment,rss_mb,open_file_bytes,dbfs,battery_percent,'
      'charging';

  String toCsvRow() => [
    (offsetMs / 1000).toStringAsFixed(0),
    state.name,
    segmentSequence ?? '',
    _mb(rssBytes).toStringAsFixed(1),
    openFileBytes ?? '',
    dbfs?.toStringAsFixed(1) ?? '',
    battery?.percent ?? '',
    battery?.charging ?? '',
  ].join(',');

  Map<String, Object?> toJson() => {
    'offset_ms': offsetMs,
    'state': state.name,
    'segment': segmentSequence,
    'rss_bytes': rssBytes,
    'open_file_bytes': openFileBytes,
    'dbfs': dbfs,
    'battery': battery?.toJson(),
  };
}

double _mb(int bytes) => bytes / (1024 * 1024);

/// Least-squares slope of [ys] against [xs], or null with under three
/// points or no spread in [xs].
double? leastSquaresSlope(List<double> xs, List<double> ys) {
  final n = xs.length;
  if (n < 3) return null;
  final meanX = xs.reduce((a, b) => a + b) / n;
  final meanY = ys.reduce((a, b) => a + b) / n;
  var num = 0.0;
  var den = 0.0;
  for (var i = 0; i < n; i++) {
    num += (xs[i] - meanX) * (ys[i] - meanY);
    den += (xs[i] - meanX) * (xs[i] - meanX);
  }
  return den == 0 ? null : num / den;
}

class LongRunReport {
  LongRunReport({
    required this.startedAtUtc,
    required this.os,
    required this.osVersion,
    required this.processors,
    required this.startOutcome,
    required this.requestedLength,
    required this.sampleInterval,
    required this.warmUp,
    required this.rssBeforeBytes,
    required this.peakRssBytes,
    required this.batteryBefore,
    required this.batteryAfter,
    required this.events,
    required this.samples,
    required this.segments,
  });

  /// Signals at or below this level count as silence or a blocked mic.
  static const flatSignalDbfs = -90.0;

  final DateTime startedAtUtc;
  final String os;
  final String osVersion;
  final int processors;
  final StartOutcome startOutcome;
  final Duration requestedLength;
  final Duration sampleInterval;
  final Duration warmUp;
  final int rssBeforeBytes;
  final int peakRssBytes;
  final BatteryReading? batteryBefore;
  final BatteryReading? batteryAfter;
  final List<LongRunEvent> events;
  final List<LongRunSample> samples;
  final List<RecordingSegment> segments;

  /// RSS growth in MB per hour over the samples after [warmUp]. Null with
  /// too few samples.
  late final double? rssSlopeMbPerHour = () {
    final kept = samples.where((s) => s.offsetMs >= warmUp.inMilliseconds);
    return leastSquaresSlope(
      [for (final s in kept) s.offsetMs / Duration.millisecondsPerHour],
      [for (final s in kept) _mb(s.rssBytes)],
    );
  }();

  int? get rssFirstBytes => samples.isEmpty ? null : samples.first.rssBytes;
  int? get rssLastBytes => samples.isEmpty ? null : samples.last.rssBytes;

  /// Mean RSS of the first and last third of the samples, in MB. A
  /// steady recorder keeps them close.
  (double, double)? get rssThirdsMb {
    if (samples.length < 3) return null;
    final third = samples.length ~/ 3;
    double mean(Iterable<LongRunSample> xs) =>
        xs.fold(0.0, (sum, s) => sum + _mb(s.rssBytes)) / xs.length;
    return (
      mean(samples.take(third)),
      mean(samples.skip(samples.length - third)),
    );
  }

  /// Samples taken while the recorder was not recording.
  int get notRecordingSamples =>
      samples.where((s) => s.state != RecordingState.recording).length;

  /// Consecutive samples on the same segment where the file did not grow.
  /// An encoder that buffers in memory, or a mic the OS cut off, shows
  /// here before the run ends.
  int get stalledIntervals {
    var count = 0;
    for (var i = 1; i < samples.length; i++) {
      final a = samples[i - 1];
      final b = samples[i];
      if (a.openFileBytes == null || b.openFileBytes == null) continue;
      if (a.segmentSequence != b.segmentSequence) continue;
      if (b.openFileBytes! <= a.openFileBytes!) count++;
    }
    return count;
  }

  int get flatSamples =>
      samples.where((s) => s.dbfs != null && s.dbfs! <= flatSignalDbfs).length;

  int get damagedSegments =>
      segments.where((s) => s.state == SegmentState.damaged).length;

  int get recordedMs => segments.fold(0, (sum, s) => sum + (s.durationMs ?? 0));

  int get recordedBytes => segments.fold(0, (sum, s) => sum + (s.bytes ?? 0));

  int? get requestedBitrateBps =>
      segments.isEmpty ? null : segments.first.requestedBitrateBps;

  /// Whole-file rate over the recorded time, container overhead included.
  double? get fileKbps =>
      recordedMs == 0 ? null : recordedBytes * 8 / recordedMs;

  /// Disk use per hour at the measured rate, in MB (10^6 bytes, as the
  /// BUILD_GUIDE 12.7 estimate is).
  double? get mbPerHour =>
      fileKbps == null ? null : fileKbps! * 1000 / 8 * 3600 / 1e6;

  /// Battery drop per hour, when both readings exist and the device was on
  /// battery for both.
  double? get batteryDrainPercentPerHour {
    final a = batteryBefore;
    final b = batteryAfter;
    if (a == null || b == null || a.charging || b.charging) return null;
    final hours = requestedLength.inMilliseconds / Duration.millisecondsPerHour;
    return hours == 0 ? null : (a.percent - b.percent) / hours;
  }

  String _f(double? x, [int digits = 1]) =>
      x == null ? 'unknown' : x.toStringAsFixed(digits);

  /// Plain observations for `PLATFORM_FEASIBILITY.md`. Not a verdict.
  List<String> get observations {
    final thirds = rssThirdsMb;
    return [
      'Start: ${startOutcome.name}.',
      '${segments.length} segment(s), $damagedSegments damaged, '
          '${(recordedMs / 60000).toStringAsFixed(1)} min recorded of '
          '${(requestedLength.inMilliseconds / 60000).toStringAsFixed(1)} '
          'min requested.',
      if (notRecordingSamples > 0)
        '$notRecordingSamples of ${samples.length} samples were taken while '
            'not recording. See the state events.',
      if (samples.isNotEmpty)
        'RSS ${_f(_mb(rssBeforeBytes))} MB before start, '
            '${_f(_mb(rssFirstBytes!))} MB at the first sample, '
            '${_f(_mb(rssLastBytes!))} MB at the last, '
            '${_f(_mb(peakRssBytes))} MB peak.',
      'RSS trend after ${warmUp.inMinutes} min warm-up: '
          '${_f(rssSlopeMbPerHour, 2)} MB per hour.',
      if (thirds != null)
        'Mean RSS first third ${_f(thirds.$1)} MB, last third '
            '${_f(thirds.$2)} MB.',
      'Files: $recordedBytes bytes, ${_f(fileKbps)} kbps whole-file against '
          '${requestedBitrateBps == null ? 'unknown' : requestedBitrateBps! ~/ 1000} '
          'kbps requested, ${_f(mbPerHour)} MB per hour, '
          '${_f(mbPerHour == null ? null : mbPerHour! * 8)} MB per 8 hours.',
      if (stalledIntervals > 0)
        'The open file did not grow in $stalledIntervals sample '
            'interval(s): the encoder may buffer, or capture stopped.',
      if (flatSamples > 0)
        '$flatSamples sample(s) at or below $flatSignalDbfs dBFS: listen '
            'for silence.',
      if (batteryDrainPercentPerHour != null)
        'Battery ${batteryBefore!.percent}% to ${batteryAfter!.percent}%, '
            '${_f(batteryDrainPercentPerHour)}% per hour.'
      else if (batteryBefore == null || batteryAfter == null)
        'Battery not readable (no battery, or no probe on this platform yet): '
            'note it by hand.'
      else
        'Battery was charging: no drain figure.',
    ];
  }

  Map<String, Object?> toJson() => {
    'spike': 'P0-10',
    'started_at_utc': startedAtUtc.toIso8601String(),
    'os': os,
    'os_version': osVersion,
    'processors': processors,
    'start_outcome': startOutcome.name,
    'requested_seconds': requestedLength.inSeconds,
    'sample_interval_seconds': sampleInterval.inSeconds,
    'warm_up_seconds': warmUp.inSeconds,
    'memory': {
      'rss_before_bytes': rssBeforeBytes,
      'rss_first_bytes': rssFirstBytes,
      'rss_last_bytes': rssLastBytes,
      'peak_rss_bytes': peakRssBytes,
      'rss_slope_mb_per_hour': rssSlopeMbPerHour,
      'rss_first_third_mb': rssThirdsMb?.$1,
      'rss_last_third_mb': rssThirdsMb?.$2,
    },
    'files': {
      'recorded_ms': recordedMs,
      'recorded_bytes': recordedBytes,
      'requested_bitrate_bps': requestedBitrateBps,
      'file_kbps': fileKbps,
      'mb_per_hour': mbPerHour,
      'stalled_intervals': stalledIntervals,
    },
    'battery': {
      'before': batteryBefore?.toJson(),
      'after': batteryAfter?.toJson(),
      'drain_percent_per_hour': batteryDrainPercentPerHour,
    },
    'not_recording_samples': notRecordingSamples,
    'flat_samples': flatSamples,
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
    'samples': [for (final s in samples) s.toJson()],
    'events': [for (final e in events) e.toJson()],
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// One row per sample, for a spreadsheet chart of the trend.
  String toCsv() => [
    LongRunSample.csvHeader,
    for (final s in samples) s.toCsvRow(),
  ].join('\n');

  /// Rows for the P0-10 table in `docs/PLATFORM_FEASIBILITY.md` 2.8.
  String toMarkdown() {
    final out = StringBuffer()
      ..writeln(
        'P0-10 run, $os $osVersion, $processors cores, '
        '${startedAtUtc.toIso8601String()}',
      )
      ..writeln();
    for (final o in observations) {
      out.writeln('- $o');
    }
    out
      ..writeln()
      ..writeln('| Seq | State | End reason | Duration ms | Bytes |')
      ..writeln('|---:|---|---|---:|---:|');
    for (final s in segments) {
      out.writeln(
        '| ${s.sequence} | ${s.state.key} | ${s.endReason?.key ?? '-'} '
        '| ${s.durationMs ?? '-'} | ${s.bytes ?? '-'} |',
      );
    }
    return out.toString();
  }
}
