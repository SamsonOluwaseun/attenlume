import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/filesystem/cuts_manifest.dart';
import '../data/filesystem/m4a_inspector.dart';
import '../domain/models/activity.dart';
import '../domain/models/enums.dart';
import '../domain/models/media.dart';
import '../domain/services/activity_split_service.dart';
import '../domain/services/cut_range_math.dart';
import '../platform/audio_trimmer/audio_trimmer.dart';
import '../platform/audio_trimmer/m4a_container_trimmer.dart';

/// Report from executing [TrimmingSpike].
class TrimmingSpikeReport {
  const TrimmingSpikeReport({
    required this.mathPassed,
    required this.splitLogicPassed,
    required this.cutsManifestPassed,
    required this.trimExecutionMs,
    required this.trimPeakRssBytes,
    required this.trimDeltaRssBytes,
    required this.trimmedDurationMs,
    required this.trimmedFileBytes,
    required this.trimmedFileInspectedValid,
    required this.failureRecoveryVerified,
  });

  final bool mathPassed;
  final bool splitLogicPassed;
  final bool cutsManifestPassed;
  final int trimExecutionMs;
  final int trimPeakRssBytes;
  final int trimDeltaRssBytes;
  final int trimmedDurationMs;
  final int trimmedFileBytes;
  final bool trimmedFileInspectedValid;
  final bool failureRecoveryVerified;

  Map<String, Object?> toJson() => {
    'math_passed': mathPassed,
    'split_logic_passed': splitLogicPassed,
    'cuts_manifest_passed': cutsManifestPassed,
    'trim_execution_ms': trimExecutionMs,
    'trim_peak_rss_mb': (trimPeakRssBytes / (1024 * 1024)).toStringAsFixed(1),
    'trim_delta_rss_mb': (trimDeltaRssBytes / (1024 * 1024)).toStringAsFixed(1),
    'trimmed_duration_ms': trimmedDurationMs,
    'trimmed_file_bytes': trimmedFileBytes,
    'trimmed_file_inspected_valid': trimmedFileInspectedValid,
    'failure_recovery_verified': failureRecoveryVerified,
  };
}

/// Spike P0-14: Trimming approach per platform and non-destructive cut maths
/// [P0-14, FR-REV-04, FR-REV-05, FR-REV-06, FR-REV-07, FR-EXP-03, NFR-07].
///
/// Demonstrates cut range consolidation, keep-range calculation, playhead
/// activity splitting, `cuts.json` instruction manifest generation, and
/// atomic passthrough file trimming with failure recovery.
class TrimmingSpike {
  TrimmingSpike({
    required this.workDir,
    AudioTrimmer? trimmer,
    this.inspector = const M4aInspector(),
  }) : trimmer = trimmer ?? const M4aContainerTrimmer();

  final Directory workDir;
  final AudioTrimmer trimmer;
  final M4aInspector inspector;

  Future<TrimmingSpikeReport> run() async {
    await workDir.create(recursive: true);

    // 1. Verify Cut-Range Maths
    final testCuts = [
      _dummyCut('1', 5000, 15000),
      _dummyCut('2', 12000, 20000), // overlaps with cut 1 -> 5000..20000
      _dummyCut('3', 45000, 50000),
    ];
    final merged = CutRangeMath.mergeOverlappingCutRanges(testCuts);
    final mathPassed =
        merged.length == 2 &&
        merged[0].startMs == 5000 &&
        merged[0].endMs == 20000 &&
        merged[1].startMs == 45000 &&
        merged[1].endMs == 50000;

    // 2. Verify Activity Split Logic
    final now = DateTime.utc(2026, 11, 4, 10, 0);
    final dummyActivity = Activity(
      id: 'act-001',
      conferenceId: 'conf-001',
      typeId: 'type-001',
      title: 'Double Session',
      speakerNames: const [],
      tags: const [],
      status: ActivityStatus.completed,
      recordingPermissionStatus: RecordingPermissionStatus.permitted,
      isPrivate: false,
      actualStart: now,
      actualEnd: now.add(const Duration(minutes: 60)),
      createdAt: now,
      updatedAt: now,
    );
    final dummySegments = [
      _dummySegment(
        'seg-001',
        dummyActivity.id,
        1,
        now,
        const Duration(minutes: 25),
      ),
      // 5 min gap (minutes 25..30)
      _dummySegment(
        'seg-002',
        dummyActivity.id,
        2,
        now.add(const Duration(minutes: 30)),
        const Duration(minutes: 30),
      ),
    ];
    final dummyBookmarks = [
      Bookmark(
        id: 'bmk-1',
        activityId: dummyActivity.id,
        atUtc: now.add(const Duration(minutes: 10)),
        offsetMs: 10 * 60 * 1000,
        source: BookmarkSource.ui,
        createdAt: now,
        updatedAt: now,
      ),
      Bookmark(
        id: 'bmk-2',
        activityId: dummyActivity.id,
        atUtc: now.add(const Duration(minutes: 40)),
        offsetMs: 40 * 60 * 1000,
        source: BookmarkSource.ui,
        createdAt: now,
        updatedAt: now,
      ),
    ];
    // Split at minute 28 (inside the gap)
    final splitPlan = ActivitySplitService.planSplit(
      activity: dummyActivity,
      splitOffsetMs: 28 * 60 * 1000,
      totalDurationMs: 60 * 60 * 1000,
      newActivityId: 'act-002',
      segments: dummySegments,
      bookmarks: dummyBookmarks,
      photos: const [],
      cutRanges: const [],
    );
    final splitLogicPassed =
        splitPlan.splitOccurredInGap &&
        splitPlan.activity1Segments.length == 1 &&
        splitPlan.activity2Segments.length == 1 &&
        splitPlan.bookmarks[0].targetActivityId == 'act-001' &&
        splitPlan.bookmarks[1].targetActivityId == 'act-002' &&
        splitPlan.bookmarks[1].newOffsetMs == (40 - 28) * 60 * 1000;

    // 3. Verify cuts.json manifest generation
    final manifest = CutsManifest.fromDomain(
      activityId: dummyActivity.id,
      totalDurationMs: 60 * 60 * 1000,
      cutRanges: testCuts,
    );
    final manifestFile = File(p.join(workDir.path, 'cuts.json'));
    await manifest.writeToFile(manifestFile);
    final jsonStr = await manifestFile.readAsString();
    final parsedManifest = CutsManifest.fromJson(
      Map<String, Object?>.from(jsonDecode(jsonStr) as Map),
    );
    final cutsManifestPassed =
        parsedManifest.cuts.length == 3 &&
        parsedManifest.keepRanges.isNotEmpty &&
        manifest.toFfmpegFilterComplex().contains('atrim');

    // 4. Run Trimming & Measure RSS Delta
    final sourceAudioFile = File(p.join(workDir.path, 'source_recording.m4a'));
    final targetAudioFile = File(p.join(workDir.path, 'trimmed_recording.m4a'));

    // Create initial 10-second synthetic M4A via container trimmer
    final initTrim = await const M4aContainerTrimmer().trim(
      sourceFile: await _createSeedFile(sourceAudioFile),
      targetFile: sourceAudioFile,
      keepRanges: const [TimeRange(0, 10000)],
    );

    final rssBefore = ProcessInfo.currentRss;
    var maxRss = rssBefore;
    final sw = Stopwatch()..start();

    // Trim start 2s and end 1s: keep [2000, 9000] (7 seconds)
    final trimResult = await trimmer.trim(
      sourceFile: initTrim.targetFile,
      targetFile: targetAudioFile,
      keepRanges: const [TimeRange(2000, 9000)],
    );
    sw.stop();

    final currentRss = ProcessInfo.currentRss;
    if (currentRss > maxRss) maxRss = currentRss;

    // Verify output file validity with inspector
    final inspected = await inspector.inspect(trimResult.targetFile);
    final trimmedFileInspectedValid =
        inspected.durationMs == 7000 && inspected.codec == 'aac_lc';

    // 5. Test Failure Recovery (injected error)
    var failureRecoveryVerified = false;
    const failingTrimmer = M4aContainerTrimmer(failBeforeRename: true);
    final failureTarget = File(p.join(workDir.path, 'failed_trim.m4a'));
    final partialFailureTarget = File('${failureTarget.path}.partial');
    final originalBytesBefore = sourceAudioFile.lengthSync();

    try {
      await failingTrimmer.trim(
        sourceFile: sourceAudioFile,
        targetFile: failureTarget,
        keepRanges: const [TimeRange(1000, 5000)],
      );
    } catch (_) {
      // Expect failure: verify partial file was deleted and source was untouched
      failureRecoveryVerified =
          !failureTarget.existsSync() &&
          !partialFailureTarget.existsSync() &&
          sourceAudioFile.existsSync() &&
          sourceAudioFile.lengthSync() == originalBytesBefore;
    }

    return TrimmingSpikeReport(
      mathPassed: mathPassed,
      splitLogicPassed: splitLogicPassed,
      cutsManifestPassed: cutsManifestPassed,
      trimExecutionMs: sw.elapsedMilliseconds,
      trimPeakRssBytes: maxRss,
      trimDeltaRssBytes: maxRss - rssBefore,
      trimmedDurationMs: trimResult.durationMs,
      trimmedFileBytes: trimResult.bytes,
      trimmedFileInspectedValid: trimmedFileInspectedValid,
      failureRecoveryVerified: failureRecoveryVerified,
    );
  }

  Future<File> _createSeedFile(File file) async {
    if (!file.parent.existsSync()) {
      await file.parent.create(recursive: true);
    }
    final tempPartial = File('${file.path}.seed.partial');
    final sink = tempPartial.openWrite();
    sink.add(
      M4aContainerTrimmer.buildM4aContainer(
        channels: 1,
        sampleRateHz: 48000,
        durationMs: 10000,
        avgBitrateBps: 96000,
        maxBitrateBps: 96000,
        mediaDataBytes: 120000,
      ),
    );
    await sink.flush();
    await sink.close();
    return tempPartial.rename(file.path);
  }

  CutRange _dummyCut(String id, int start, int end) => CutRange(
    id: id,
    activityId: 'dummy',
    startOffsetMs: start,
    endOffsetMs: end,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  RecordingSegment _dummySegment(
    String id,
    String actId,
    int seq,
    DateTime start,
    Duration length,
  ) => RecordingSegment(
    id: id,
    activityId: actId,
    sequence: seq,
    filePath: 'audio/seg-$seq.m4a',
    state: SegmentState.finalised,
    requestedProfile: RecordingProfile.balanced,
    codec: 'aac_lc',
    container: 'm4a',
    channelCount: 1,
    sampleRateHz: 48000,
    requestedBitrateBps: 96000,
    startUtc: start,
    endUtc: start.add(length),
    durationMs: length.inMilliseconds,
    bytes: length.inSeconds * 12000,
    createdAt: start,
    updatedAt: start.add(length),
  );
}
