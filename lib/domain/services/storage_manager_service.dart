import 'dart:io';

import 'package:path/path.dart' as p;

import '../../data/filesystem/media_paths.dart';
import '../../data/repositories/activity_repository.dart';
import '../../data/repositories/conference_repository.dart';
import '../../data/repositories/export_job_repository.dart';
import '../../data/repositories/media_asset_repository.dart';
import '../../platform/storage/free_space_probe.dart';
import '../models/enums.dart';
import '../models/export_job.dart';
import '../models/storage_breakdown.dart';

/// Service that analyzes storage breakdown, provides preview and execution
/// of local media deletion gated by verified export, and cleans safe temporary files
/// (FR-STO-05, FR-STO-06, FR-STO-07, ADR-036, ADR-037) [P1-20].
class StorageManagerService {
  StorageManagerService({
    required this.conferences,
    required this.activities,
    required this.media,
    required this.exports,
    required this.mediaRoot,
    required this.freeSpaceProbe,
  });

  final ConferenceRepository conferences;
  final ActivityRepository activities;
  final MediaAssetRepository media;
  final ExportJobRepository exports;
  final Future<Directory> Function() mediaRoot;
  final FreeSpaceProbe freeSpaceProbe;

  /// Analyzes storage breakdown per conference and per activity across all
  /// storage kinds, calculating export statuses and deduplicating shared files
  /// (FR-STO-05, ADR-036, ADR-037).
  Future<AppStorageBreakdown> analyzeStorage() async {
    final root = await mediaRoot();
    final space = await _safeQuerySpace(root.path);

    final allConfs = await conferences.getAll(includeArchived: true);
    final allTypes = {for (final t in await activities.types()) t.id: t};
    final confBreakdowns = <ConferenceStorageBreakdown>[];

    // Global trackers to deduplicate shared audio files across the app (ADR-036).
    final globalTrackedAudioPaths = <String>{};
    var globalUniqueAudioBytes = 0;
    var globalPhotoBytes = 0;
    var globalThumbnailBytes = 0;
    var globalTranscriptBytes = 0;
    var globalTemporaryExportBytes = 0;
    const globalModelBytes = 0;
    var globalKeptOriginalBytes = 0;
    var globalDerivedBytes = 0;
    var globalKeptOriginalsCount = 0;

    for (final conf in allConfs) {
      final acts = await activities.listForConference(conf.id);
      final jobs = await exports.forConference(conf.id);
      final completedJobs = jobs
          .where((j) => j.state == ExportJobState.completed)
          .toList();

      final confExportStatus = _determineConferenceExportStatus(completedJobs);

      final actBreakdowns = <ActivityStorageBreakdown>[];
      final confTrackedAudioPaths = <String>{};
      var confUniqueAudioBytes = 0;
      var confPhotoBytes = 0;
      var confThumbnailBytes = 0;
      var confTranscriptBytes = 0;
      var confKeptOriginalBytes = 0;
      var confDerivedBytes = 0;

      for (final act in acts) {
        final actExportStatus = _determineActivityExportStatus(
          completedJobs,
          act.id,
        );

        // Audio segments.
        final segs = await media.segmentsFor(act.id);
        var actAudioBytes = 0;
        for (final s in segs) {
          final sBytes = s.bytes ?? 0;
          actAudioBytes += sBytes;
          if (!confTrackedAudioPaths.contains(s.filePath)) {
            confTrackedAudioPaths.add(s.filePath);
            confUniqueAudioBytes += sBytes;
          }
          if (!globalTrackedAudioPaths.contains(s.filePath)) {
            globalTrackedAudioPaths.add(s.filePath);
            globalUniqueAudioBytes += sBytes;
          }
        }

        // Photos.
        final photos = await media.photosFor(act.id);
        var actPhotoBytes = 0;
        for (final pRow in photos) {
          final b = pRow.bytes ?? 0;
          actPhotoBytes += b;
        }
        confPhotoBytes += actPhotoBytes;
        globalPhotoBytes += actPhotoBytes;

        // On-disk files inside the activity folder.
        final actDir = Directory(
          p.join(root.path, MediaPaths.activityFolder(conf.id, act.id)),
        );

        final actThumbnailBytes = _directoryFileSize(
          Directory(p.join(actDir.path, 'thumbs')),
        );
        confThumbnailBytes += actThumbnailBytes;
        globalThumbnailBytes += actThumbnailBytes;

        final originalsDir = Directory(
          p.join(actDir.path, 'audio', 'originals'),
        );
        final originalsCount = _directoryFileCount(originalsDir);
        final actKeptOriginalBytes = _directoryFileSize(originalsDir);
        confKeptOriginalBytes += actKeptOriginalBytes;
        globalKeptOriginalBytes += actKeptOriginalBytes;
        globalKeptOriginalsCount += originalsCount;

        final actDerivedBytes = _directoryFileSize(
          Directory(p.join(actDir.path, 'waveforms')),
        );
        confDerivedBytes += actDerivedBytes;
        globalDerivedBytes += actDerivedBytes;

        // Transcripts (Phase 2 check).
        var actTranscriptBytes = 0;
        final transcriptFile = File(p.join(actDir.path, 'transcript.md'));
        if (transcriptFile.existsSync()) {
          actTranscriptBytes += transcriptFile.lengthSync();
        }
        actTranscriptBytes += _directoryFileSize(
          Directory(p.join(actDir.path, 'transcripts')),
        );
        confTranscriptBytes += actTranscriptBytes;
        globalTranscriptBytes += actTranscriptBytes;

        final actType = allTypes[act.typeId];
        final actSizes = StorageKindSizes(
          audioBytes: actAudioBytes,
          photoBytes: actPhotoBytes,
          thumbnailBytes: actThumbnailBytes,
          transcriptBytes: actTranscriptBytes,
          temporaryExportBytes: 0,
          modelBytes: 0,
          keptOriginalBytes: actKeptOriginalBytes,
          derivedBytes: actDerivedBytes,
        );

        actBreakdowns.add(
          ActivityStorageBreakdown(
            activityId: act.id,
            activityTitle: act.title,
            activityTypeLabel: actType?.label ?? 'Activity',
            exportStatus: actExportStatus,
            sizes: actSizes,
            segmentCount: segs.length,
            photoCount: photos.length,
            keptOriginalsCount: originalsCount,
          ),
        );
      }

      // Check for conference-level temporary exports or files.
      final confExportsDir = Directory(
        p.join(root.path, MediaPaths.conferenceFolder(conf.id), 'exports'),
      );
      final confTempExportBytes = _directoryFileSize(confExportsDir);
      globalTemporaryExportBytes += confTempExportBytes;

      final confSizes = StorageKindSizes(
        audioBytes: confUniqueAudioBytes,
        photoBytes: confPhotoBytes,
        thumbnailBytes: confThumbnailBytes,
        transcriptBytes: confTranscriptBytes,
        temporaryExportBytes: confTempExportBytes,
        modelBytes: 0,
        keptOriginalBytes: confKeptOriginalBytes,
        derivedBytes: confDerivedBytes,
      );

      confBreakdowns.add(
        ConferenceStorageBreakdown(
          conferenceId: conf.id,
          conferenceName: conf.name,
          isArchived: conf.isArchived,
          exportStatus: confExportStatus,
          sizes: confSizes,
          activities: actBreakdowns,
        ),
      );
    }

    // App-level temporary export staging or partial files.
    final rootExportsDir = Directory(p.join(root.path, 'exports'));
    final rootExportBytes = _directoryFileSize(rootExportsDir);
    globalTemporaryExportBytes += rootExportBytes;

    final safeTemporaryBytes = globalDerivedBytes + globalTemporaryExportBytes;

    final overallSizes = StorageKindSizes(
      audioBytes: globalUniqueAudioBytes,
      photoBytes: globalPhotoBytes,
      thumbnailBytes: globalThumbnailBytes,
      transcriptBytes: globalTranscriptBytes,
      temporaryExportBytes: globalTemporaryExportBytes,
      modelBytes: globalModelBytes,
      keptOriginalBytes: globalKeptOriginalBytes,
      derivedBytes: globalDerivedBytes,
    );

    return AppStorageBreakdown(
      totalDeviceFreeBytes: space?.availableBytes,
      totalDeviceCapacityBytes: space?.totalBytes,
      appTotalBytes: overallSizes.totalBytes,
      overallSizes: overallSizes,
      conferences: confBreakdowns,
      safeTemporaryBytes: safeTemporaryBytes,
      keptOriginalsTotalBytes: globalKeptOriginalBytes,
      keptOriginalsCount: globalKeptOriginalsCount,
    );
  }

  /// Clears safe temporary files: waveform summaries
  /// and temporary export staging files (FR-STO-06). If [includeKeptOriginals]
  /// is true, also removes unlinked originals kept after permanent trimming (ADR-037).
  Future<SafeCleanupResult> clearSafeTemporaryFiles({
    bool includeKeptOriginals = false,
  }) async {
    final root = await mediaRoot();
    var filesDeleted = 0;
    var bytesFreed = 0;

    // 1. Waveform summaries across all activity waveforms/ directories.
    if (root.existsSync()) {
      try {
        final entities = root.listSync(recursive: true, followLinks: false);
        for (final entity in entities) {
          if (entity is! File) continue;
          final path = entity.path;

          // Waveform summaries.
          if (path.endsWith('.wave')) {
            final len = entity.lengthSync();
            try {
              entity.deleteSync();
              filesDeleted++;
              bytesFreed += len;
            } on FileSystemException {
              // Ignore locked files.
            }
          }
          // Partial recordings are recovery candidates, even without a row.
          // Never treat them as disposable cache (FR-REC-08, NFR-07).
        }
      } on FileSystemException {
        // Continue if listing encounters inaccessible paths.
      }
    }

    // 2. Staging / temporary export files.
    final rootExportsDir = Directory(p.join(root.path, 'exports'));
    if (rootExportsDir.existsSync()) {
      try {
        for (final f in rootExportsDir.listSync(recursive: true)) {
          if (f is File) {
            final len = f.lengthSync();
            try {
              f.deleteSync();
              filesDeleted++;
              bytesFreed += len;
            } on FileSystemException {
              // Ignore locked files.
            }
          }
        }
      } on FileSystemException {
        // Ignored.
      }
    }

    // 3. Kept originals if explicitly requested.
    if (includeKeptOriginals) {
      final originalsResult = await removeKeptOriginals();
      filesDeleted += originalsResult.filesDeleted;
      bytesFreed += originalsResult.bytesFreed;
    }

    return SafeCleanupResult(
      filesDeleted: filesDeleted,
      bytesFreed: bytesFreed,
    );
  }

  /// Removes recordings kept in `audio/originals/` after permanent trimming
  /// (ADR-037, FR-REV-06, FR-STO-06). Never touches any file named by a segment row.
  Future<SafeCleanupResult> removeKeptOriginals({
    String? conferenceId,
    String? activityId,
  }) async {
    final root = await mediaRoot();
    final namedPaths = await media.segmentPaths();
    var filesDeleted = 0;
    var bytesFreed = 0;

    if (!root.existsSync()) {
      return const SafeCleanupResult(filesDeleted: 0, bytesFreed: 0);
    }

    try {
      final entities = root.listSync(recursive: true, followLinks: false);
      for (final entity in entities) {
        if (entity is! File) continue;
        final relPath = p.posix.joinAll(
          p.split(p.relative(entity.path, from: root.path)),
        );

        if (!MediaPaths.isKeptOriginal(relPath)) continue;
        if (namedPaths.contains(relPath)) continue;

        // Scope filter if requested.
        final parts = p.posix.split(relPath);
        if (conferenceId != null && parts[1] != conferenceId) continue;
        if (activityId != null && parts[3] != activityId) continue;

        final len = entity.lengthSync();
        try {
          entity.deleteSync();
          filesDeleted++;
          bytesFreed += len;
        } on FileSystemException {
          // Ignored.
        }
      }
    } on FileSystemException {
      // Ignored.
    }

    return SafeCleanupResult(
      filesDeleted: filesDeleted,
      bytesFreed: bytesFreed,
    );
  }

  /// Generates a preview for the "Delete local copies" action (FR-STO-06, FR-STO-07).
  /// Throws [StorageManagerException] if the target does not have a verified export.
  Future<DeleteLocalPreview> previewDeleteLocalCopies({
    required String conferenceId,
    String? activityId,
    required bool keepLightweightIndex,
  }) async {
    final conf = await conferences.get(conferenceId);
    if (conf == null) {
      throw const StorageManagerException('Conference not found.');
    }

    final jobs = await exports.forConference(conferenceId);
    final completedJobs = jobs
        .where((j) => j.state == ExportJobState.completed)
        .toList();

    // Verify integrity gate (FR-STO-06, NFR-11).
    if (activityId == null) {
      final status = _determineConferenceExportStatus(completedJobs);
      if (!status.isVerified) {
        throw const StorageManagerException(
          'Deleting local copies requires a verified export with checksum verification.',
        );
      }
    } else {
      final status = _determineActivityExportStatus(completedJobs, activityId);
      if (!status.isVerified) {
        throw const StorageManagerException(
          'Deleting local copies requires a verified export with checksum verification.',
        );
      }
    }

    final targetActivityIds = activityId != null
        ? [activityId]
        : (await activities.listForConference(conferenceId))
              .map((a) => a.id)
              .toList();

    final remainingNamedPaths = await media.segmentPathsExcludingActivities(
      targetActivityIds,
    );

    var audioFilesCount = 0;
    var audioBytes = 0;
    var photoFilesCount = 0;
    var photoBytes = 0;
    var keptOriginalsCount = 0;
    var keptOriginalsBytes = 0;
    var derivedFilesCount = 0;
    var derivedBytes = 0;
    var sharedFilesPreservedCount = 0;

    final root = await mediaRoot();
    final inspectedAudioPaths = <String>{};

    for (final actId in targetActivityIds) {
      final segs = await media.segmentsFor(actId);
      for (final s in segs) {
        if (inspectedAudioPaths.contains(s.filePath)) continue;
        inspectedAudioPaths.add(s.filePath);

        if (remainingNamedPaths.contains(s.filePath)) {
          // File is shared with another activity not being deleted (ADR-036).
          sharedFilesPreservedCount++;
        } else {
          audioFilesCount++;
          audioBytes += s.bytes ?? 0;
        }
      }

      final photos = await media.photosFor(actId);
      photoFilesCount += photos.length;
      for (final pRow in photos) {
        photoBytes += pRow.bytes ?? 0;
      }

      final actDir = Directory(
        p.join(root.path, MediaPaths.activityFolder(conferenceId, actId)),
      );

      final originalsDir = Directory(p.join(actDir.path, 'audio', 'originals'));
      if (originalsDir.existsSync()) {
        final files = originalsDir.listSync().whereType<File>().toList();
        keptOriginalsCount += files.length;
        for (final f in files) {
          keptOriginalsBytes += f.lengthSync();
        }
      }

      final waveformsDir = Directory(p.join(actDir.path, 'waveforms'));
      if (waveformsDir.existsSync()) {
        final files = waveformsDir.listSync().whereType<File>().toList();
        derivedFilesCount += files.length;
        for (final f in files) {
          derivedBytes += f.lengthSync();
        }
      }
    }

    final totalFilesToDelete =
        audioFilesCount +
        photoFilesCount +
        keptOriginalsCount +
        derivedFilesCount;
    final totalBytesToFree =
        audioBytes + photoBytes + keptOriginalsBytes + derivedBytes;

    String? actTitle;
    if (activityId != null) {
      final act = await activities.get(activityId);
      actTitle = act?.title;
    }

    return DeleteLocalPreview(
      conferenceId: conferenceId,
      conferenceName: conf.name,
      activityId: activityId,
      activityTitle: actTitle,
      keepLightweightIndex: keepLightweightIndex,
      audioFilesCount: audioFilesCount,
      audioBytes: audioBytes,
      photoFilesCount: photoFilesCount,
      photoBytes: photoBytes,
      keptOriginalsCount: keptOriginalsCount,
      keptOriginalsBytes: keptOriginalsBytes,
      derivedFilesCount: derivedFilesCount,
      derivedBytes: derivedBytes,
      sharedFilesPreservedCount: sharedFilesPreservedCount,
      totalFilesToDelete: totalFilesToDelete,
      totalBytesToFree: totalBytesToFree,
    );
  }

  /// Executes "Delete local copies" after verified export (FR-STO-06, FR-STO-07).
  /// Preserves shared files (ADR-036) and supports lightweight archived index mode
  /// (FR-STO-07).
  Future<DeleteLocalResult> deleteLocalCopies({
    required String conferenceId,
    String? activityId,
    required bool keepLightweightIndex,
  }) async {
    // 1. Run preview validation first to verify gate and gather deletion targets.
    final preview = await previewDeleteLocalCopies(
      conferenceId: conferenceId,
      activityId: activityId,
      keepLightweightIndex: keepLightweightIndex,
    );

    final root = await mediaRoot();
    final targetActivityIds = activityId != null
        ? [activityId]
        : (await activities.listForConference(conferenceId))
              .map((a) => a.id)
              .toList();

    final remainingNamedPaths = await media.segmentPathsExcludingActivities(
      targetActivityIds,
    );

    var filesDeleted = 0;
    var bytesFreed = 0;
    final processedAudioPaths = <String>{};

    for (final actId in targetActivityIds) {
      // 2. Audio segments: delete physical files if not shared elsewhere.
      final segs = await media.segmentsFor(actId);
      for (final s in segs) {
        if (processedAudioPaths.contains(s.filePath)) continue;
        processedAudioPaths.add(s.filePath);

        if (!remainingNamedPaths.contains(s.filePath)) {
          final file = MediaPaths.resolve(root, s.filePath);
          if (file.existsSync()) {
            final len = file.lengthSync();
            try {
              file.deleteSync();
              filesDeleted++;
              bytesFreed += len;
            } on FileSystemException {
              // Ignored.
            }
          }
        }
      }

      // 3. Audio originals.
      final originalsDir = Directory(
        p.join(root.path, MediaPaths.originalsFolder(conferenceId, actId)),
      );
      if (originalsDir.existsSync()) {
        try {
          for (final f in originalsDir.listSync().whereType<File>()) {
            final len = f.lengthSync();
            try {
              f.deleteSync();
              filesDeleted++;
              bytesFreed += len;
            } on FileSystemException {
              // Ignored.
            }
          }
        } on FileSystemException {
          // Ignored.
        }
      }

      // 4. Derived waveform summaries.
      final waveformsDir = Directory(
        p.join(
          root.path,
          MediaPaths.activityFolder(conferenceId, actId),
          'waveforms',
        ),
      );
      if (waveformsDir.existsSync()) {
        try {
          for (final f in waveformsDir.listSync().whereType<File>()) {
            final len = f.lengthSync();
            try {
              f.deleteSync();
              filesDeleted++;
              bytesFreed += len;
            } on FileSystemException {
              // Ignored.
            }
          }
        } on FileSystemException {
          // Ignored.
        }
      }

      // 5. Photos:
      final photos = await media.photosFor(actId);
      for (final pRow in photos) {
        final photoFile = MediaPaths.resolve(root, pRow.filePath);
        if (photoFile.existsSync()) {
          final len = photoFile.lengthSync();
          try {
            photoFile.deleteSync();
            filesDeleted++;
            bytesFreed += len;
          } on FileSystemException {
            // Ignored.
          }
        }

        // Thumbnails: delete only if NOT keeping lightweight index (FR-STO-07).
        if (!keepLightweightIndex && pRow.thumbnailPath != null) {
          final thumbFile = MediaPaths.resolve(root, pRow.thumbnailPath!);
          if (thumbFile.existsSync()) {
            final len = thumbFile.lengthSync();
            try {
              thumbFile.deleteSync();
              filesDeleted++;
              bytesFreed += len;
            } on FileSystemException {
              // Ignored.
            }
          }
        }
      }

      // 6. Database rows update:
      if (keepLightweightIndex) {
        // Keep lightweight index: delete segment rows only, keeping notes,
        // bookmarks, metadata and photo rows (with thumbnails intact).
        await media.deleteSegments(segs.map((s) => s.id));
      } else {
        // "Delete means delete": delete the activity entirely.
        await activities.delete(actId);
      }
    }

    // 7. If conference-wide and not keeping index, remove the conference entirely.
    if (activityId == null && !keepLightweightIndex) {
      await conferences.delete(conferenceId);
      final confDir = Directory(
        p.join(root.path, MediaPaths.conferenceFolder(conferenceId)),
      );
      if (confDir.existsSync()) {
        try {
          confDir.deleteSync(recursive: true);
        } on FileSystemException {
          // Ignored.
        }
      }
    }

    return DeleteLocalResult(
      filesDeleted: filesDeleted,
      bytesFreed: bytesFreed,
      sharedFilesPreserved: preview.sharedFilesPreservedCount,
      keptIndex: keepLightweightIndex,
    );
  }

  // --- Helpers ---

  Future<FreeSpace?> _safeQuerySpace(String path) async {
    try {
      return await freeSpaceProbe.query(path);
    } on Object {
      return null;
    }
  }

  ExportStatus _determineConferenceExportStatus(List<ExportJob> completedJobs) {
    if (completedJobs.isEmpty) return ExportStatus.notExported;

    final confJobs = completedJobs.where((j) {
      final kind = j.scope['kind'];
      return kind == 'conference' || kind == null;
    }).toList();

    return _rankExportJobs(confJobs);
  }

  ExportStatus _determineActivityExportStatus(
    List<ExportJob> completedJobs,
    String activityId,
  ) {
    if (completedJobs.isEmpty) return ExportStatus.notExported;

    final relevantJobs = completedJobs.where((j) {
      final kind = j.scope['kind'];
      if (kind == 'conference' || kind == null) return true;
      if (kind == 'activities') {
        final ids = j.scope['activity_ids'] as List?;
        return ids?.contains(activityId) == true;
      }
      return false;
    }).toList();

    return _rankExportJobs(relevantJobs);
  }

  ExportStatus _rankExportJobs(List<ExportJob> jobs) {
    if (jobs.isEmpty) return ExportStatus.notExported;

    var hasChecksum = false;
    var hasCloud = false;
    var hasLocal = false;

    for (final j in jobs) {
      if (j.verificationLevel == VerificationLevel.checksum) {
        hasChecksum = true;
      } else if (j.destination == ExportDestination.googleDrive ||
          j.destination == ExportDestination.onedrive) {
        hasCloud = true;
      } else if (j.destination == ExportDestination.local) {
        hasLocal = true;
      }
    }

    if (hasChecksum) return ExportStatus.verified;
    if (hasCloud) return ExportStatus.uploaded;
    if (hasLocal) return ExportStatus.exportedLocally;
    return ExportStatus.notExported;
  }

  int _directoryFileSize(Directory dir) {
    if (!dir.existsSync()) return 0;
    var total = 0;
    try {
      for (final f in dir.listSync(recursive: true, followLinks: false)) {
        if (f is File) {
          total += f.lengthSync();
        }
      }
    } on FileSystemException {
      // Ignored.
    }
    return total;
  }

  int _directoryFileCount(Directory dir) {
    if (!dir.existsSync()) return 0;
    var count = 0;
    try {
      for (final f in dir.listSync(recursive: true, followLinks: false)) {
        if (f is File) count++;
      }
    } on FileSystemException {
      // Ignored.
    }
    return count;
  }
}
