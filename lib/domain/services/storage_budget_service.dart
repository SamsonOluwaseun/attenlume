import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../data/filesystem/media_paths.dart';
import '../../data/repositories/activity_repository.dart';
import '../../data/repositories/media_asset_repository.dart';
import '../../platform/storage/free_space_probe.dart';
import '../../shared/utilities/serial_lock.dart';
import '../models/enums.dart';
import 'capture_settings.dart';
import 'recording_service.dart';
import 'recording_state.dart';
import 'storage_thresholds.dart';

/// One snapshot of the device storage budget for recording (FR-STO-01, FR-UI-07) [P1-12].
class StorageBudgetSnapshot {
  const StorageBudgetSnapshot({
    required this.freeBytes,
    required this.totalBytes,
    required this.level,
    required this.minutesLeft,
    required this.bytesPerSecond,
    required this.isMeasuredRate,
    this.conferenceBytes,
    required this.timestamp,
  });

  /// Bytes free on the storage volume, or null when unknown.
  final int? freeBytes;

  /// Total capacity of the storage volume in bytes, or null when unknown.
  final int? totalBytes;

  /// The current storage level (ok, warning, urgent, hardStop).
  final StorageLevel level;

  /// Estimated whole minutes left before hitting the hard reserve.
  /// Null if free space is unknown or rate is unknown.
  final int? minutesLeft;

  /// The byte rate used for the estimate (bytes per second).
  final double? bytesPerSecond;

  /// True if [bytesPerSecond] was computed from actual file growth on disk;
  /// false if it fell back to the nominal profile target (FR-STO-01).
  final bool isMeasuredRate;

  /// Total bytes used by this conference's media folder, if computed (FR-UI-07).
  final int? conferenceBytes;

  /// When this assessment was made.
  final DateTime timestamp;

  /// True if storage is running low (below 1 GB or under 60 minutes left).
  bool get isWarning => level == StorageLevel.warning;

  /// True if storage is critical (near 300 MB).
  bool get isUrgent => level == StorageLevel.urgent;

  /// True if storage has reached the hard reserve (100 MB).
  bool get isHardStop => level == StorageLevel.hardStop;

  static final unknown = StorageBudgetSnapshot(
    freeBytes: null,
    totalBytes: null,
    level: StorageLevel.ok,
    minutesLeft: null,
    bytesPerSecond: null,
    isMeasuredRate: false,
    conferenceBytes: null,
    timestamp: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

/// Tracks free space and rolling minutes-left estimates from measured file
/// growth, rechecks every 30 seconds while recording, and enforces the hard
/// stop reserve (FR-STO-01 to 04, FR-UI-07) [P1-12].
class StorageBudgetService {
  StorageBudgetService({
    required this.recorder,
    required this.activities,
    required this.media,
    required this.mediaRoot,
    required this.freeSpaceProbe,
    required this.platform,
    this.thresholds = const StorageThresholds(),
    this.tickInterval = const Duration(seconds: 30),
    Timer Function(Duration, void Function(Timer))? createTimer,
    this.clock = DateTime.now,
  }) : _createTimer = createTimer ?? Timer.periodic;

  final RecordingService recorder;
  final ActivityRepository activities;
  final MediaAssetRepository media;
  final Future<Directory> Function() mediaRoot;
  final FreeSpaceProbe freeSpaceProbe;
  final CapturePlatform platform;
  final StorageThresholds thresholds;
  final Duration tickInterval;
  final Timer Function(Duration, void Function(Timer)) _createTimer;
  final DateTime Function() clock;

  final _snapshotController =
      StreamController<StorageBudgetSnapshot>.broadcast();
  final _hardStopNoticeController = StreamController<String>.broadcast();
  final _lock = SerialLock();

  StorageBudgetSnapshot _currentSnapshot = StorageBudgetSnapshot.unknown;
  StreamSubscription<RecordingStatus>? _statusSub;
  Timer? _periodicTimer;
  bool _disposed = false;

  /// The most recently computed storage budget snapshot.
  StorageBudgetSnapshot get currentSnapshot => _currentSnapshot;

  /// Stream of storage budget snapshot updates.
  Stream<StorageBudgetSnapshot> get snapshotStream =>
      _snapshotController.stream;

  /// Stream emitting clear notifications when recording was stopped
  /// due to hitting the hard storage reserve (FR-STO-04).
  Stream<String> get hardStopNoticeStream => _hardStopNoticeController.stream;

  /// Starts listening to recording state transitions.
  void start() {
    _statusSub ??= recorder.statusStream.listen(_onRecordingStatusChanged);
    if (recorder.status.state == RecordingState.recording) {
      _startPeriodicCheck();
    }
  }

  void _onRecordingStatusChanged(RecordingStatus status) {
    if (_disposed) return;
    if (status.state == RecordingState.recording) {
      _startPeriodicCheck();
    } else {
      _stopPeriodicCheck();
    }
  }

  void _startPeriodicCheck() {
    _stopPeriodicCheck();
    unawaited(checkNow());
    _periodicTimer = _createTimer(tickInterval, (_) {
      unawaited(checkNow());
    });
  }

  void _stopPeriodicCheck() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// Checks disk space and computes budget immediately (FR-STO-03).
  ///
  /// Rechecks before recording, every 30 seconds while recording, after each
  /// photo, before trim/export, and on OS low-space signals.
  Future<StorageBudgetSnapshot> checkNow({
    String? activityId,
    RecordingProfile? profile,
  }) => _lock.run(
    () => _checkNowLocked(activityId: activityId, profile: profile),
  );

  Future<StorageBudgetSnapshot> _checkNowLocked({
    String? activityId,
    RecordingProfile? profile,
  }) async {
    final status = recorder.status;
    final actId = activityId ?? status.activityId;
    var prof = profile ?? status.profile;

    if (prof == null && actId != null) {
      try {
        prof = await activities.effectiveProfile(actId);
      } catch (_) {
        prof = RecordingProfile.balanced;
      }
    }
    prof ??= RecordingProfile.balanced;

    int? freeBytes;
    int? totalBytes;
    try {
      final root = await mediaRoot();
      final space = await freeSpaceProbe.query(root.path);
      freeBytes = space?.availableBytes;
      totalBytes = space?.totalBytes;
    } catch (_) {
      // Free space stays null when probe fails or throws.
    }

    // Determine bytes per second: measured file growth vs nominal (FR-STO-01).
    final (bytesPerSecond, isMeasured) = await _calculateBytesPerSecond(
      actId,
      prof,
    );

    // Calculate space used by this conference (FR-UI-07).
    int? conferenceBytes;
    if (actId != null) {
      try {
        final act = await activities.get(actId);
        if (act != null) {
          final root = await mediaRoot();
          final confFolder = Directory(
            p.join(root.path, MediaPaths.conferenceFolder(act.conferenceId)),
          );
          conferenceBytes = _calculateDirectorySize(confFolder);
        }
      } catch (_) {}
    }

    // Assess storage against thresholds (FR-STO-02, FR-STO-04).
    final StorageLevel level;
    final int? minutesLeft;
    if (freeBytes == null) {
      level = StorageLevel.ok;
      minutesLeft = null;
    } else {
      final assessment = assessStorage(
        freeBytes: freeBytes,
        bytesPerSecond: bytesPerSecond,
        thresholds: thresholds,
      );
      level = assessment.level;
      minutesLeft = assessment.minutesLeft;
    }

    final snapshot = StorageBudgetSnapshot(
      freeBytes: freeBytes,
      totalBytes: totalBytes,
      level: level,
      minutesLeft: minutesLeft,
      bytesPerSecond: bytesPerSecond,
      isMeasuredRate: isMeasured,
      conferenceBytes: conferenceBytes,
      timestamp: clock(),
    );

    _currentSnapshot = snapshot;
    if (!_snapshotController.isClosed) {
      _snapshotController.add(snapshot);
    }

    // Hard stop limit enforcement (FR-STO-04).
    if (level == StorageLevel.hardStop &&
        recorder.status.state == RecordingState.recording) {
      await recorder.stop(reason: SegmentEndReason.storageLow);
      const notice = 'Storage nearly full. Recording stopped and saved.';
      if (!_hardStopNoticeController.isClosed) {
        _hardStopNoticeController.add(notice);
      }
    }

    return snapshot;
  }

  /// Calculates write rate: attempts measured file growth first,
  /// falling back to nominal bitrate (FR-STO-01).
  Future<(double?, bool)> _calculateBytesPerSecond(
    String? activityId,
    RecordingProfile profile,
  ) async {
    // 1. Current active segment file growth
    final openFile = recorder.currentSegmentFile;
    final openStart = recorder.currentSegmentStartUtc;
    if (openFile != null && openStart != null) {
      try {
        if (openFile.existsSync()) {
          final bytes = openFile.lengthSync();
          final elapsedSec =
              clock().difference(openStart).inMilliseconds / 1000.0;
          if (elapsedSec >= 5.0 && bytes > 0) {
            return (bytes / elapsedSec, true);
          }
        }
      } catch (_) {}
    }

    // 2. Previously completed segments in this activity
    if (activityId != null) {
      try {
        final segments = await media.segmentsFor(activityId);
        if (segments.isNotEmpty) {
          var sumBytes = 0;
          var sumMs = 0;
          for (final seg in segments) {
            if (seg.bytes != null && seg.bytes! > 0) {
              sumBytes += seg.bytes!;
            }
            if (seg.durationMs != null && seg.durationMs! > 0) {
              sumMs += seg.durationMs!;
            } else if (seg.endUtc != null) {
              sumMs += seg.endUtc!.difference(seg.startUtc).inMilliseconds;
            }
          }
          final sumSec = sumMs / 1000.0;
          if (sumSec >= 5.0 && sumBytes > 0) {
            return (sumBytes / sumSec, true);
          }
        }
      } catch (_) {}
    }

    // 3. Fallback: Nominal profile bitrate
    final settings = effectiveCaptureSettings(profile, platform);
    final nominalBps = settings.bitrateBps / 8.0;
    return (nominalBps, false);
  }

  /// Signal received when the OS announces low storage space (FR-STO-03).
  Future<void> onOsLowSpaceSignal() => checkNow();

  int _calculateDirectorySize(Directory dir) {
    if (!dir.existsSync()) return 0;
    var total = 0;
    try {
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += entity.lengthSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _stopPeriodicCheck();
    await _statusSub?.cancel();
    _statusSub = null;
    await _snapshotController.close();
    await _hardStopNoticeController.close();
  }
}
