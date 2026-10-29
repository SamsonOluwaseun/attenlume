import 'enums.dart';

/// Bytes on disk by kind (FR-STO-05) [P1-20].
class StorageKindSizes {
  const StorageKindSizes({
    this.audioBytes = 0,
    this.photoBytes = 0,
    this.thumbnailBytes = 0,
    this.waveformBytes = 0,
    this.keptOriginalBytes = 0,
    this.recoveryBytes = 0,
  });

  /// Recordings named by segment rows. A file two rows share (ADR-036) is
  /// counted once per conference and once for the app.
  final int audioBytes;

  /// Photos named by photo rows.
  final int photoBytes;

  /// Photo thumbnails in `thumbs/`.
  final int thumbnailBytes;

  /// Waveform summaries in `waveforms/` (ADR-034). They are made while
  /// recording and cannot be rebuilt, so only orphans are temporary.
  final int waveformBytes;

  /// Recordings a permanent trim replaced, in `audio/originals/` (ADR-037).
  final int keptOriginalBytes;

  /// `.partial` recordings and audio no row names, left for crash recovery
  /// (FR-REC-08, ADR-038). Never cleared here.
  final int recoveryBytes;

  int get totalBytes =>
      audioBytes +
      photoBytes +
      thumbnailBytes +
      waveformBytes +
      keptOriginalBytes +
      recoveryBytes;

  StorageKindSizes operator +(StorageKindSizes other) => StorageKindSizes(
    audioBytes: audioBytes + other.audioBytes,
    photoBytes: photoBytes + other.photoBytes,
    thumbnailBytes: thumbnailBytes + other.thumbnailBytes,
    waveformBytes: waveformBytes + other.waveformBytes,
    keptOriginalBytes: keptOriginalBytes + other.keptOriginalBytes,
    recoveryBytes: recoveryBytes + other.recoveryBytes,
  );

  static const zero = StorageKindSizes();
}

/// Export state of a conference or activity, from `export_jobs`
/// (FR-STO-05) [P1-20]. Ordered from least to most.
enum ExportStatus implements KeyedEnum {
  notExported('not_exported', 'Not exported'),
  exportedLocally('exported_locally', 'Exported locally'),
  uploaded('uploaded', 'Uploaded'),
  verified('verified', 'Verified');

  const ExportStatus(this.key, this.label);

  @override
  final String key;
  final String label;

  /// A completed export whose files were checked against
  /// `checksums.sha256` (ADR-040).
  bool get isVerified => this == ExportStatus.verified;
}

/// One activity (FR-STO-05) [P1-20].
class ActivityStorageBreakdown {
  const ActivityStorageBreakdown({
    required this.activityId,
    required this.activityTitle,
    required this.activityTypeLabel,
    required this.exportStatus,
    required this.sizes,
    this.segmentCount = 0,
    this.photoCount = 0,
    this.keptOriginalsCount = 0,
    this.deleteBlockedReason,
  });

  final String activityId;
  final String activityTitle;
  final String activityTypeLabel;
  final ExportStatus exportStatus;

  /// Every file this activity's rows name, so a shared file shows in both
  /// parts of a split.
  final StorageKindSizes sizes;
  final int segmentCount;
  final int photoCount;
  final int keptOriginalsCount;

  /// Why "Delete local copies" is not offered, or null when it is
  /// (FR-STO-06, ADR-047).
  final String? deleteBlockedReason;

  bool get canDeleteLocalCopies => deleteBlockedReason == null;

  int get totalBytes => sizes.totalBytes;
}

/// One conference with its activities (FR-STO-05) [P1-20].
class ConferenceStorageBreakdown {
  const ConferenceStorageBreakdown({
    required this.conferenceId,
    required this.conferenceName,
    required this.isArchived,
    required this.exportStatus,
    required this.sizes,
    required this.activities,
    this.deleteBlockedReason,
  });

  final String conferenceId;
  final String conferenceName;
  final bool isArchived;
  final ExportStatus exportStatus;

  /// Files counted once, including files no row names.
  final StorageKindSizes sizes;
  final List<ActivityStorageBreakdown> activities;
  final String? deleteBlockedReason;

  bool get canDeleteLocalCopies => deleteBlockedReason == null;

  int get totalBytes => sizes.totalBytes;
}

/// The whole app (FR-STO-05) [P1-20].
class AppStorageBreakdown {
  const AppStorageBreakdown({
    required this.freeBytes,
    required this.capacityBytes,
    required this.sizes,
    required this.conferences,
    required this.temporaryExportBytes,
    required this.orphanWaveformBytes,
    required this.keptOriginals,
  });

  final int? freeBytes;
  final int? capacityBytes;

  /// Every conference, counted once.
  final StorageKindSizes sizes;
  final List<ConferenceStorageBreakdown> conferences;

  /// Leftover export staging in `exports-temp/` (ADR-040).
  final int temporaryExportBytes;

  /// Waveform summaries for segments that no longer exist.
  final int orphanWaveformBytes;

  /// Files in `audio/originals/` that no row names (ADR-037).
  final List<KeptOriginalFile> keptOriginals;

  /// What "Clear safe temporary files" would free.
  int get safeTemporaryBytes => temporaryExportBytes + orphanWaveformBytes;

  int get keptOriginalBytes => keptOriginals.fold(0, (n, o) => n + o.bytes);

  int get totalBytes => sizes.totalBytes + temporaryExportBytes;
}

/// A recording kept after a permanent trim (ADR-037) [P1-20].
class KeptOriginalFile {
  const KeptOriginalFile({
    required this.relativePath,
    required this.bytes,
    required this.conferenceName,
    required this.activityTitle,
  });

  final String relativePath;
  final int bytes;
  final String conferenceName;

  /// Null when the activity no longer exists.
  final String? activityTitle;
}

/// Result of a cleanup (FR-STO-06) [P1-20].
class SafeCleanupResult {
  const SafeCleanupResult({
    required this.filesDeleted,
    required this.bytesFreed,
  });

  final int filesDeleted;
  final int bytesFreed;
}

/// What "Delete local copies" would remove (FR-STO-06) [P1-20].
class DeleteLocalPreview {
  const DeleteLocalPreview({
    required this.conferenceId,
    required this.conferenceName,
    required this.activityId,
    required this.activityTitles,
    required this.audioFiles,
    required this.audioBytes,
    required this.photoFiles,
    required this.photoBytes,
    required this.otherFiles,
    required this.otherBytes,
    required this.sharedFilesKept,
    required this.recoveryFilesKept,
    required this.bookmarkCount,
  });

  final String conferenceId;
  final String conferenceName;

  /// Null when the whole conference is deleted.
  final String? activityId;
  final List<String> activityTitles;
  final int audioFiles;
  final int audioBytes;

  /// Photos and their thumbnails.
  final int photoFiles;
  final int photoBytes;

  /// Kept originals and waveform summaries.
  final int otherFiles;
  final int otherBytes;

  /// Files another activity still names (ADR-036); left in place.
  final int sharedFilesKept;

  /// `.partial` and unlinked recordings left for crash recovery (ADR-038).
  final int recoveryFilesKept;

  /// Bookmarks and notes removed with the activities.
  final int bookmarkCount;

  int get totalFiles => audioFiles + photoFiles + otherFiles;
  int get totalBytes => audioBytes + photoBytes + otherBytes;
}

/// Result of "Delete local copies" (FR-STO-06) [P1-20].
class DeleteLocalResult {
  const DeleteLocalResult({
    required this.filesDeleted,
    required this.bytesFreed,
    required this.activitiesDeleted,
    required this.failedFiles,
  });

  final int filesDeleted;
  final int bytesFreed;
  final int activitiesDeleted;

  /// Files that could not be deleted (for example open in another app).
  /// Their activities and rows are kept so nothing is left unnamed.
  final int failedFiles;
}

/// A refusal; nothing changed. The message is plain UK English.
class StorageManagerException implements Exception {
  const StorageManagerException(this.message);

  final String message;

  @override
  String toString() => 'StorageManagerException: $message';
}
