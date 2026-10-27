import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/filesystem/media_paths.dart';
import '../data/repositories/media_asset_repository.dart';
import '../data/repositories/repository_support.dart';
import '../domain/models/enums.dart';
import '../domain/models/media.dart';
import '../domain/services/recording_service.dart';
import '../domain/services/recording_state.dart';
import '../platform/audio_capture/audio_capture_engine.dart';
import '../platform/camera/photo_camera.dart';
import '../platform/interruptions/audio_interruption_source.dart';
import 'background_recording_spike.dart' show SpikeEvent;

/// Spike P0-05: photos taken during a recording on Android, iOS and
/// Windows [P0-05, FR-PHO-07, FR-PHO-01, AT-PHO-01].
///
/// Drives the real [RecordingService], opens the camera while it records
/// (as a tap on Photo would) and takes [PhotoDuringRecordingSpike.run]'s
/// `photoCount` photos (20 for AT-PHO-01). Around each shot it logs the
/// recording state, the open segment and the input level, and every audio
/// session event. Manual steps in `TEST_PLAN.md` MT-21.
///
/// Mitigation under test (FR-PHO-07): if the audio session is interrupted
/// while the camera is busy, or within [cameraWindow] of a shot, it is
/// logged as a `camera` interruption, the segment ends, and recording
/// resumes in a new segment as soon as the shot is done, without waiting
/// for the system. Other interruptions follow P0-04 (resume only when the
/// system allows).
///
/// After the run every gap between segments is matched against the
/// interruption rows. A gap no row explains is lost audio. Observations
/// only, no verdict: the tester also listens around each shot. Spike
/// code, not used by the app. The real coordinator is P1-07, photos P1-14.
class PhotoDuringRecordingSpike {
  PhotoDuringRecordingSpike({
    required this.service,
    required this.engine,
    required this.media,
    required this.camera,
    required this.interruptions,
    required this.mediaRoot,
    this.cameraWindow = const Duration(seconds: 2),
    this.levelDropDb = 20,
    String Function()? newId,
    Future<void> Function(Duration)? wait,
    DateTime Function()? clock,
  }) : _newId = newId ?? uuidV4,
       _wait = wait ?? Future<void>.delayed,
       _clock = clock ?? DateTime.now;

  final RecordingService service;
  final AudioCaptureEngine engine;
  final MediaAssetRepository media;
  final PhotoCamera camera;
  final AudioInterruptionSource interruptions;
  final Directory mediaRoot;

  /// How long after a shot an interruption is still put down to the
  /// camera.
  final Duration cameraWindow;

  /// A level this much lower after a shot than before it is flagged for
  /// listening. A quiet room can do the same, so it is a hint only.
  final double levelDropDb;
  final String Function() _newId;
  final Future<void> Function(Duration) _wait;
  final DateTime Function() _clock;

  Future<void> _pending = Future<void>.value();

  /// Completes when every command queued so far has run. For tests.
  Future<void> settle() => _pending;

  Future<PhotoDuringRecordingReport> run({
    required String conferenceId,
    required String activityId,
    int photoCount = 20,
    Duration interval = const Duration(seconds: 3),
    Duration afterShot = const Duration(seconds: 1),
  }) async {
    final startedAt = _clock().toUtc();
    final events = <SpikeEvent>[];
    final shots = <ShotResult>[];
    var cameraBusy = false;
    DateTime? lastShotEnd;
    var eventsInShots = 0;
    String? openInterruptionId;
    InterruptionReason? openReason;
    var systemOfferedResume = false;

    int offsetMs() => _clock().toUtc().difference(startedAt).inMilliseconds;
    void log(String kind, [Map<String, Object?> detail = const {}]) =>
        events.add(SpikeEvent(offsetMs(), kind, detail));

    void then(Future<void> Function() action) =>
        _pending = _pending.then((_) => action()).catchError((Object e) {
          log('command_error', {'error': '$e'});
        });

    bool nearCamera() =>
        cameraBusy ||
        (lastShotEnd != null &&
            _clock().toUtc().difference(lastShotEnd) <= cameraWindow);

    Future<void> resume(String why, {required bool auto}) async {
      if (!await service.resume()) {
        log('resume_failed', {
          'why': why,
          'state': service.status.state.name,
          'error': service.status.errorMessage,
        });
        return;
      }
      if (openInterruptionId != null) {
        await media.endInterruption(
          openInterruptionId!,
          autoResumed: auto,
          endUtc: _clock().toUtc(),
        );
        openInterruptionId = null;
        openReason = null;
      }
      log('resumed', {'why': why});
    }

    Future<double?> level() async {
      if (service.status.state != RecordingState.recording) return null;
      try {
        return await engine.levelDbfs();
      } on Object {
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

    final subscriptions = <StreamSubscription<Object?>>[
      service.statusStream.listen(
        (s) => log('state', {
          'state': s.state.name,
          'segment': s.segmentSequence,
          if (s.errorMessage != null) 'error': s.errorMessage,
        }),
      ),
      interruptions.events.listen((e) {
        final near = nearCamera();
        if (near) eventsInShots++;
        log('audio_session', {...e.toJson(), 'near_camera': near});
        switch (e.kind) {
          case AudioInterruptionKind.began when !e.mayDuck:
            final reason = near
                ? InterruptionReason.camera
                : InterruptionReason.system;
            final markerStart = _clock().toUtc();
            then(() async {
              if (service.status.state != RecordingState.recording) return;
              await service.pause();
              final row = await media.startInterruption(
                activityId,
                reason,
                startUtc: markerStart,
              );
              openInterruptionId = row.id;
              openReason = reason;
            });
          case AudioInterruptionKind.ended:
            systemOfferedResume = systemOfferedResume || e.shouldResume;
            if (e.shouldResume) {
              then(() async {
                if (openInterruptionId != null) {
                  await resume('system_allowed', auto: true);
                }
              });
            }
          case AudioInterruptionKind.began ||
              AudioInterruptionKind.becomingNoisy ||
              AudioInterruptionKind.devicesChanged:
            break;
        }
      }),
    ];

    // Listing does not open a camera, so it is logged even when the
    // recording cannot start.
    List<CameraLens> lenses = const [];
    String? cameraError;
    try {
      lenses = await camera.listCameras();
      log('cameras', {
        'found': [for (final l in lenses) l.toJson()],
      });
    } on Object catch (e) {
      cameraError = '$e';
      log('camera_error', {'error': cameraError});
    }

    final outcome = await service.start(activityId);
    log('start', {'outcome': outcome.name});

    var cameraOpened = false;
    if (outcome == StartOutcome.started && cameraError == null) {
      try {
        final openStart = _clock().toUtc();
        cameraBusy = true;
        await camera.open();
        cameraOpened = true;
        log('camera_open', {
          'ms': _clock().toUtc().difference(openStart).inMilliseconds,
        });
      } on Object catch (e) {
        cameraError = '$e';
        log('camera_error', {'error': cameraError});
      } finally {
        cameraBusy = false;
        lastShotEnd = _clock().toUtc();
      }
    }

    if (cameraOpened) {
      for (var i = 1; i <= photoCount; i++) {
        await _pending;
        final stateBefore = service.status.state;
        final segmentBefore = service.status.segmentSequence;
        final levelBefore = await level();
        final photoId = _newId();
        final relative = MediaPaths.photo(conferenceId, activityId, photoId);
        final shotStart = _clock().toUtc();
        final shotOffset = offsetMs();
        String? error;
        CapturedPhoto? captured;
        cameraBusy = true;
        try {
          captured = await camera.takePhoto(
            MediaPaths.resolve(mediaRoot, relative).path,
          );
        } on Object catch (e) {
          error = '$e';
        } finally {
          cameraBusy = false;
          lastShotEnd = _clock().toUtc();
        }
        final shotMs = lastShotEnd.difference(shotStart).inMilliseconds;
        if (captured != null) {
          await media.addPhoto(
            id: photoId,
            activityId: activityId,
            filePath: relative,
            takenUtc: shotStart,
            source: PhotoSource.inApp,
            bytes: captured.bytes,
          );
        }
        log('shot', {
          'n': i,
          'ms': shotMs,
          if (captured != null) 'bytes': captured.bytes,
          'error': ?error,
        });

        // Give late audio session events time to arrive, then put the
        // recording back if the camera stopped it (FR-PHO-07).
        await _wait(afterShot);
        await _pending;
        if (openInterruptionId != null &&
            openReason == InterruptionReason.camera) {
          await resume('after_shot', auto: true);
        }

        shots.add(
          ShotResult(
            number: i,
            offsetMs: shotOffset,
            durationMs: shotMs,
            photoBytes: captured?.bytes,
            error: error,
            stateBefore: stateBefore,
            stateAfter: service.status.state,
            segmentBefore: segmentBefore,
            segmentAfter: service.status.segmentSequence,
            levelBeforeDbfs: levelBefore,
            levelAfterDbfs: await level(),
          ),
        );
        if (i < photoCount) await _wait(interval);
      }
    }

    await _pending;
    for (final s in subscriptions) {
      await s.cancel();
    }
    try {
      await camera.close();
    } on Object catch (e) {
      log('camera_error', {'error': '$e'});
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

    return PhotoDuringRecordingReport(
      startedAtUtc: startedAt,
      os: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
      startOutcome: outcome,
      requestedPhotos: photoCount,
      cameras: lenses,
      cameraError: cameraError,
      systemOfferedResume: systemOfferedResume,
      eventsNearCamera: eventsInShots,
      levelDropDb: levelDropDb,
      events: events,
      shots: shots,
      segments: await media.segmentsFor(activityId),
      interruptions: await media.interruptionsFor(activityId),
      photos: await media.photosFor(activityId),
    );
  }
}

/// What happened around one shot.
class ShotResult {
  const ShotResult({
    required this.number,
    required this.offsetMs,
    required this.durationMs,
    required this.stateBefore,
    required this.stateAfter,
    required this.segmentBefore,
    required this.segmentAfter,
    this.photoBytes,
    this.error,
    this.levelBeforeDbfs,
    this.levelAfterDbfs,
  });

  final int number;
  final int offsetMs;

  /// From the call to the camera to the photo on disk.
  final int durationMs;

  /// Null when the shot failed.
  final int? photoBytes;
  final String? error;
  final RecordingState stateBefore;
  final RecordingState stateAfter;
  final int? segmentBefore;
  final int? segmentAfter;

  /// Null when not recording or the level could not be read.
  final double? levelBeforeDbfs;
  final double? levelAfterDbfs;

  bool get saved => photoBytes != null;

  /// The shot ended one segment and started another.
  bool get cutSegment => segmentAfter != segmentBefore;

  bool get recordingAfter => stateAfter == RecordingState.recording;

  /// How far the level fell across the shot, or null without both
  /// readings.
  double? get levelDropDb => levelBeforeDbfs == null || levelAfterDbfs == null
      ? null
      : levelBeforeDbfs! - levelAfterDbfs!;

  Map<String, Object?> toJson() => {
    'n': number,
    'offset_ms': offsetMs,
    'duration_ms': durationMs,
    'saved': saved,
    if (photoBytes != null) 'bytes': photoBytes,
    if (error != null) 'error': error,
    'state_before': stateBefore.name,
    'state_after': stateAfter.name,
    'segment_before': segmentBefore,
    'segment_after': segmentAfter,
    'level_before_dbfs': levelBeforeDbfs,
    'level_after_dbfs': levelAfterDbfs,
  };
}

/// Time between two segments, and whether an interruption row covers it.
class SegmentGap {
  const SegmentGap({
    required this.afterSequence,
    required this.startUtc,
    required this.endUtc,
    required this.explainedBy,
  });

  final int afterSequence;
  final DateTime startUtc;
  final DateTime endUtc;

  /// The interruption that covers the gap, or null when none does.
  final Interruption? explainedBy;

  int get durationMs => endUtc.difference(startUtc).inMilliseconds;
  bool get explained => explainedBy != null;

  Map<String, Object?> toJson() => {
    'after_segment': afterSequence,
    'start_utc': startUtc.toIso8601String(),
    'end_utc': endUtc.toIso8601String(),
    'duration_ms': durationMs,
    'explained_by': explainedBy?.reason.key,
  };
}

/// Gaps between consecutive segments of one activity, each matched with
/// the interruption row that overlaps it [AT-PHO-01].
List<SegmentGap> segmentGaps(
  List<RecordingSegment> segments,
  List<Interruption> interruptions,
) {
  final ordered = [...segments]
    ..sort((a, b) => a.sequence.compareTo(b.sequence));
  final out = <SegmentGap>[];
  for (var i = 1; i < ordered.length; i++) {
    final before = ordered[i - 1];
    final after = ordered[i];
    final start = before.endUtc ?? before.startUtc;
    final end = after.startUtc;
    if (!end.isAfter(start)) continue;
    Interruption? cover;
    for (final x in interruptions) {
      final xEnd = x.endUtc;
      if (!x.startUtc.isAfter(end) && (xEnd == null || !xEnd.isBefore(start))) {
        cover = x;
        break;
      }
    }
    out.add(
      SegmentGap(
        afterSequence: before.sequence,
        startUtc: start,
        endUtc: end,
        explainedBy: cover,
      ),
    );
  }
  return out;
}

class PhotoDuringRecordingReport {
  PhotoDuringRecordingReport({
    required this.startedAtUtc,
    required this.os,
    required this.osVersion,
    required this.startOutcome,
    required this.requestedPhotos,
    required this.cameras,
    required this.cameraError,
    required this.systemOfferedResume,
    required this.eventsNearCamera,
    required this.levelDropDb,
    required this.events,
    required this.shots,
    required this.segments,
    required this.interruptions,
    required this.photos,
  });

  final DateTime startedAtUtc;
  final String os;
  final String osVersion;
  final StartOutcome startOutcome;
  final int requestedPhotos;
  final List<CameraLens> cameras;

  /// Why the camera could not be listed or opened, if it could not.
  final String? cameraError;
  final bool systemOfferedResume;

  /// Audio session events while the camera was busy or just after.
  final int eventsNearCamera;
  final double levelDropDb;
  final List<SpikeEvent> events;
  final List<ShotResult> shots;
  final List<RecordingSegment> segments;
  final List<Interruption> interruptions;
  final List<Photo> photos;

  late final List<SegmentGap> gaps = segmentGaps(segments, interruptions);

  int get savedPhotos => shots.where((s) => s.saved).length;

  List<Interruption> get cameraInterruptions => [
    for (final i in interruptions)
      if (i.reason == InterruptionReason.camera) i,
  ];

  /// AT-PHO-01: gaps between segments that no interruption explains.
  List<SegmentGap> get unexplainedGaps => [
    for (final g in gaps)
      if (!g.explained) g,
  ];

  /// AT-PHO-01: camera interruptions that did not resume on their own.
  List<Interruption> get cameraInterruptionsNotResumed => [
    for (final i in cameraInterruptions)
      if (!i.autoResumed) i,
  ];

  List<ShotResult> get shotsWithLevelDrop => [
    for (final s in shots)
      if ((s.levelDropDb ?? 0) >= levelDropDb) s,
  ];

  /// No unexplained gap and every camera interruption resumed on its own.
  /// Says nothing about the sound itself: listen to the files.
  bool get meetsAtPho01Rows =>
      startOutcome == StartOutcome.started &&
      savedPhotos == requestedPhotos &&
      unexplainedGaps.isEmpty &&
      cameraInterruptionsNotResumed.isEmpty;

  /// Plain observations for `PLATFORM_FEASIBILITY.md`. Not a verdict.
  List<String> get observations => [
    'Start: ${startOutcome.name}.',
    if (cameras.isEmpty && cameraError == null) 'No camera listed.',
    if (cameraError != null) 'Camera could not be used: $cameraError',
    '$savedPhotos of $requestedPhotos photo(s) saved, '
        '${shots.length - savedPhotos} failed.',
    if (shots.isNotEmpty) 'Shot time: ${_ms(shots.map((s) => s.durationMs))}.',
    '${segments.length} segment(s), '
        '${segments.where((s) => s.state == SegmentState.damaged).length} '
        'damaged.',
    '${shots.where((s) => s.cutSegment).length} shot(s) cut a segment '
        'boundary.',
    '$eventsNearCamera audio session event(s) while the camera was busy '
        'or just after.',
    '${cameraInterruptions.length} camera interruption(s), '
        '${cameraInterruptionsNotResumed.length} not resumed on their own.',
    if (interruptions.length > cameraInterruptions.length)
      '${interruptions.length - cameraInterruptions.length} other '
          'interruption(s), away from any shot.',
    'AT-PHO-01: ${unexplainedGaps.length} gap(s) between segments with no '
        'interruption to explain them'
        '${unexplainedGaps.isEmpty ? '' : ' (${unexplainedGaps.map((g) => '${g.durationMs} ms').join(', ')})'}.',
    if (shots.any((s) => !s.recordingAfter))
      'Not recording after shot(s) '
          '${shots.where((s) => !s.recordingAfter).map((s) => s.number).join(', ')}.',
    if (shotsWithLevelDrop.isNotEmpty)
      'Level fell by ${levelDropDb.toStringAsFixed(0)} dB or more across '
          'shot(s) ${shotsWithLevelDrop.map((s) => s.number).join(', ')}: '
          'listen around them.',
    if (systemOfferedResume) 'The system offered to resume at least once.',
  ];

  static String _ms(Iterable<int> values) {
    final sorted = values.toList()..sort();
    return 'min ${sorted.first} ms, median ${sorted[sorted.length ~/ 2]} ms, '
        'max ${sorted.last} ms';
  }

  Map<String, Object?> toJson() => {
    'spike': 'P0-05',
    'started_at_utc': startedAtUtc.toIso8601String(),
    'os': os,
    'os_version': osVersion,
    'start_outcome': startOutcome.name,
    'requested_photos': requestedPhotos,
    'saved_photos': savedPhotos,
    'cameras': [for (final c in cameras) c.toJson()],
    'camera_error': cameraError,
    'events_near_camera': eventsNearCamera,
    'unexplained_gaps': unexplainedGaps.length,
    'camera_interruptions_not_resumed': cameraInterruptionsNotResumed.length,
    'meets_at_pho_01_rows': meetsAtPho01Rows,
    'observations': observations,
    'shots': [for (final s in shots) s.toJson()],
    'segments': [
      for (final s in segments)
        {
          'sequence': s.sequence,
          'path': s.filePath,
          'state': s.state.key,
          'end_reason': s.endReason?.key,
          'start_utc': s.startUtc.toIso8601String(),
          'end_utc': s.endUtc?.toIso8601String(),
          'duration_ms': s.durationMs,
          'bytes': s.bytes,
        },
    ],
    'gaps': [for (final g in gaps) g.toJson()],
    'interruptions': [
      for (final i in interruptions)
        {
          'reason': i.reason.key,
          'start_utc': i.startUtc.toIso8601String(),
          'end_utc': i.endUtc?.toIso8601String(),
          'auto_resumed': i.autoResumed,
        },
    ],
    'photos': [
      for (final p in photos)
        {'path': p.filePath, 'offset_ms': p.offsetMs, 'bytes': p.bytes},
    ],
    'events': [for (final e in events) e.toJson()],
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Rows for the P0-05 table in `docs/PLATFORM_FEASIBILITY.md` 2.7.
  String toMarkdown() {
    final out = StringBuffer()
      ..writeln('P0-05 run, $os $osVersion, ${startedAtUtc.toIso8601String()}')
      ..writeln();
    for (final o in observations) {
      out.writeln('- $o');
    }
    out
      ..writeln()
      ..writeln(
        '| Shot | Offset s | Shot ms | Saved | State after '
        '| Segment before / after | Level before / after dBFS |',
      )
      ..writeln('|---:|---:|---:|---|---|---|---|');
    String level(double? v) => v == null ? '-' : v.toStringAsFixed(1);
    for (final s in shots) {
      out.writeln(
        '| ${s.number} | ${(s.offsetMs / 1000).toStringAsFixed(1)} '
        '| ${s.durationMs} | ${s.saved ? 'yes' : '**no**'} '
        '| ${s.stateAfter.name} '
        '| ${s.segmentBefore ?? '-'} / ${s.segmentAfter ?? '-'} '
        '| ${level(s.levelBeforeDbfs)} / ${level(s.levelAfterDbfs)} |',
      );
    }
    return out.toString();
  }
}
